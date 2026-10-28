#!/usr/bin/env python3
"""Verify every locale key the Lua references exists in the right section.

Exact keys ("seb-gui.title") must exist in their section. Dynamic keys built
by concatenation ("seb-reason." .. reason) are checked against the values that
can reach them: every REASON in scripts/const.lua plus the gate reasons for
seb-reason, the refusal reasons in DYNAMIC for the other sections.

Every .cfg file in locale/en is read and their sections are merged, as the
engine does. A key defined twice in one file is an error: the engine refuses
to load the mod. A key defined in two files is only a warning: the engine
loads it silently and the file that sorts last wins (measured on 2.1.23).

Run from the repo root:  python3 tools/check_locale.py
Exit status is non-zero when something is missing, so it can gate a release.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALE = ROOT / "locale/en"

# Values that dynamic keys are built from, besides scripts/const.lua REASON.
DYNAMIC = {
    "seb-reason": ["capacity", "chunks", "unknown-force", "unknown-surface"],
    "seb-error": [
        "invalid-design", "empty-blueprint", "book-not-blueprint", "not-a-blueprint",
        "many-entries", "calibration-failed", "unknown",
    ],
    "seb-gui": [
        "direction-north", "direction-east", "direction-south", "direction-west",
        # help_view.lua's tabs: captions and lines
        "help-tab-sockets", "help-tab-sensor", "help-tab-probe", "help-tab-port",
        "help-plain", "help-socket", "help-plug", "help-target",
        "help-sensor-what", "help-sensor-where", "help-sensor-radius", "help-sensor-retire",
        "help-probe-what", "help-probe-rules", "help-probe-examples", "help-probe-pools",
        "help-port-what", "help-port-how", "help-port-numbers",
        "help-tab-clear", "help-clear-what", "help-clear-how", "help-clear-footprint", "help-clear-negative-space",
    ],
    "seb-status": ["growing", "waiting", "stalled", "paused", "finished", "stopped", "planned", "planning"],
}


def parse_file(path):
    """One .cfg file: its {section: {key, ...}} and the (section, key) pairs it defines twice."""
    sections, twice, current = {}, [], None
    for line in path.read_text(encoding="utf-8").split("\n"):
        header = re.match(r"^\[(.+)\]$", line.strip())
        if header:
            current = header.group(1)
            sections.setdefault(current, set())
            continue
        if current and "=" in line and not line.strip().startswith("#"):
            key = line.split("=", 1)[0].strip()
            if key in sections[current]:
                twice.append((current, key))
            sections[current].add(key)
    return sections, twice


def parse_locale():
    """Every .cfg file in locale/en, sections merged.

    Returns (sections, duplicates, shared). duplicates: (file, section, key)
    defined twice in one file, which the engine refuses to load. shared:
    (section, key, first file, other file) defined in more than one file.
    """
    sections, duplicates, shared, owner = {}, [], [], {}
    for path in sorted(LOCALE.glob("*.cfg")):
        found, twice = parse_file(path)
        duplicates += [(path.name, section, key) for section, key in twice]
        for section, keys in found.items():
            sections.setdefault(section, set()).update(keys)
            for key in sorted(keys):
                first = owner.setdefault((section, key), path.name)
                if first != path.name:
                    shared.append((section, key, first, path.name))
    return sections, duplicates, shared


def lua_sources():
    yield from ROOT.glob("scripts/**/*.lua")
    yield from ROOT.glob("prototypes/*.lua")
    yield from ROOT.glob("prototypes/tips/*.lua")
    yield ROOT / "control.lua"


def reasons():
    text = (ROOT / "scripts/const.lua").read_text()
    block = re.search(r"const\.REASON = \{(.*?)\n\}", text, re.S).group(1)
    return re.findall(r'= "([a-z-]+)"', block)


def main():
    sections, duplicates, shared = parse_locale()
    missing = []
    for path in lua_sources():
        text = path.read_text()
        # A key ending in "-" is a dynamic prefix ("seb-gui.direction-" .. key).
        for section, key in re.findall(r'"(seb-[a-z-]+)\.([a-z0-9-]*[a-z0-9])"', text):
            if key not in sections.get(section, set()):
                missing.append(f"{section}.{key}  ({path.relative_to(ROOT)})")
    wanted = dict(DYNAMIC)
    wanted["seb-reason"] = wanted["seb-reason"] + reasons()
    for section, keys in wanted.items():
        for key in keys:
            if key not in sections.get(section, set()):
                missing.append(f"{section}.{key}  (dynamic)")
    for line in sorted(set(missing)):
        print("MISSING", line)
    for name, section, key in duplicates:
        print("DUPLICATE", f"{section}.{key}  ({name})")
    for section, key, first, other in shared:
        print("WARNING", f"{section}.{key} is defined in {first} and in {other}, which wins")
    files = len(list(LOCALE.glob("*.cfg")))
    print(f"checked {sum(len(v) for v in sections.values())} keys in {len(sections)} sections of {files} files")
    return 1 if missing or duplicates else 0


if __name__ == "__main__":
    sys.exit(main())
