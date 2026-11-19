#!/usr/bin/env python3
"""Reads one run of dev/mp-drag.sh and reports on the area tool's drag preview.

usage: dev/mp-drag-report.py <run dir> <round-trip ticks>

The world mod (dev/mods/seb-drag-world) logs "SEB_DRAG t=<tick> ..." lines on
the server and on the client: every selection event of the area tool and every
change of the preview. marks.txt holds the wall time of each mouse action.
Exit status 1 when a check fails: the preview outlives a drag, somebody else
would see it, the two simulations logged different lines, or a log holds an
error or a desync.
"""
import re
import statistics
import sys
from pathlib import Path

run, latency = Path(sys.argv[1]), int(sys.argv[2])
TICK_MS = 1000 / 60
LINE = re.compile(r"^\s*([\d.]+) Script @__seb-drag-world__/control\.lua:\d+: SEB_DRAG t=(\d+) (.*)$")
ENDS = {"on_player_selected_area", "on_player_alt_selected_area", "on_player_reverse_selected_area",
        "on_player_alt_reverse_selected_area", "on_player_cancel_selected_area"}
failures = []


def lines_of(path):
    """(log seconds, tick, text) of every SEB_DRAG line."""
    out = []
    for raw in path.read_text(errors="replace").splitlines():
        m = LINE.match(raw)
        if m:
            out.append((float(m.group(1)), int(m.group(2)), m.group(3)))
    return out


def fields(text):
    return dict(re.findall(r"(\w+)=(\S+)", text))


client_log = run / "client/userdata/factorio-current.log"
opened = float((run / "log-opened").read_text())
client = lines_of(client_log)
server = lines_of(run / "server.log")

# The mouse actions, grouped by drag.
drags, current = [], None
for raw in (run / "marks.txt").read_text().splitlines():
    stamp, what = raw.split(" ", 1)
    if what.startswith("drag "):
        current = {"name": what[5:], "start": float(stamp), "marks": []}
        drags.append(current)
    elif what == "end":
        current["end"] = float(stamp)
    else:
        current["marks"].append((float(stamp), what))

events = [(opened + at, tick, fields(text)) for at, tick, text in client if text.startswith("ev=on_player")]
previews = [(opened + at, tick, text) for at, tick, text in client if text.startswith("preview ")]


def within(rows, drag):
    return [row for row in rows if drag["start"] <= row[0] <= drag["end"]]


def ms(seconds):
    return f"{seconds * 1000:.0f} ms ({seconds * 1000 / TICK_MS:.1f} ticks)"


def preview_at(tick):
    """What the preview showed once `tick` was done."""
    shown = "none"
    for _, at, text in previews:
        if at > tick:
            break
        shown = text.split(" ", 2)[2]
    return shown


print(f"network round trip {latency} ticks ({latency * TICK_MS:.0f} ms), client log {client_log}")
print(f"client lines {len(client)}, server lines {len(server)}")
trails, stale = [], []
for drag in drags:
    seen = within(events, drag)
    names = [e[2]["ev"].replace("on_player_", "").replace("_selected_area", "") for e in seen]
    print(f"\n== {drag['name']}: events {' '.join(names) or 'none'}")
    moves = [m for m in drag["marks"] if m[1].startswith("move")][1:]   # the first move is before the press
    changes = [e for e in seen if e[2]["ev"] == "on_player_change_selected_area"]
    ends = [e for e in seen if e[2]["ev"] in ENDS]
    if drag["name"] == "stepped":
        if len(changes) != len(moves):
            failures.append(f"stepped: {len(moves)} moves but {len(changes)} change events")
        for (sent, what), (at, tick, f) in zip(moves, changes):
            trails.append(at - sent)
            print(f"  {what:<16} shown at t={tick} cursor {f['cur']:<14} trail {ms(at - sent)}: {preview_at(tick)}")
    # The release, the Q or the flick against the event that ended the drag.
    done = [m for m in drag["marks"] if m[1] in ("up", "key q", "flicked")]
    if done and ends:
        sent, what = done[0]
        at, tick, f = ends[0]
        print(f"  {what}: {f['ev']} at t={tick}, {ms(at - sent)} later; preview then: {preview_at(tick)}")
        if preview_at(tick) != "none":
            failures.append(f"{drag['name']}: the preview stayed after {f['ev']} (t={tick})")
    elif done:
        print(f"  {done[0][1]}: no event ended this drag")
    # The rectangle the last preview was drawn for against the one released.
    grown = [e for e in ends if e[2]["ev"] != "on_player_cancel_selected_area"]
    before = [e for e in seen if e[2]["ev"] in ("on_player_start_selected_area", "on_player_change_selected_area")]
    if grown and before:
        last, final = before[-1], grown[0]
        was, verdict = preview_at(last[1]), "the one that preview was drawn for"
        if was == "none":
            verdict = "no preview was on screen for it"
        elif last[2]["area"] != final[2]["area"]:
            verdict = f"NOT the one that preview was drawn for ({last[2]['area']})"
            stale.append(drag["name"])
        print(f"  last preview t={last[1]} {was}")
        print(f"  released rectangle {final[2]['area']}: {verdict}")
    shown = [p for p in within(previews, drag) if not p[2].endswith(" none")]
    if shown:
        cleared = [p for p in within(previews, drag) if p[2].endswith(" none")]
        last_clear = cleared[-1][1] if cleared else None
        print(f"  preview on screen from t={shown[0][1]}, changed {len(shown)} times, gone at t={last_clear}")
    else:
        print("  the preview never showed")

# The same tick on both machines: how far the client runs behind the server.
server_opened = run / "server-log-opened"
if server_opened.exists():
    at_server = {(tick, text): float(server_opened.read_text()) + at for at, tick, text in server}
    behind = [opened + at - at_server[(tick, text)] for at, tick, text in client
              if text.startswith("ev=on_player") and (tick, text) in at_server]
    if behind:
        print(f"\nthe client runs a selection event {ms(statistics.median(behind))} after the server ran it (median of {len(behind)})")
if previews and not previews[-1][2].endswith(" none"):
    failures.append("a preview is still drawn at the end of the run")
if trails:
    print(f"\nstepped drag: the preview trails the pointer by min {ms(min(trails))}, "
          f"median {ms(statistics.median(trails))}, max {ms(max(trails))}")

print("drags released on a rectangle the last preview was not drawn for: " + (", ".join(stale) or "none"))

# Who sees it: every preview line names the dragging player alone.
drawn = [text for _, _, text in previews if not text.endswith(" none")]
others = [text for text in drawn if "box_players={1}" not in text or "text_players={1}" not in text]
fails = [text for _, _, text in client + server if text.startswith("FAIL")]
print(f"\npreview states logged: {len(drawn)}, drawn for player 1 alone: {len(drawn) - len(others)}")
if others or fails:
    failures.append(f"{len(others)} preview states and {len(fails)} FAIL lines name other players")

# The same simulation twice: from the tick the client joined, the server
# logged what the client logged.
if client:
    joined = client[0][1]
    ours = [(tick, text) for _, tick, text in client]
    theirs = [(tick, text) for _, tick, text in server if tick >= joined]
    print(f"server and client lines from t={joined}: {len(theirs)} and {len(ours)}, "
          f"{'identical' if ours == theirs else 'DIFFERENT'}")
    if ours != theirs:
        failures.append("the server and the client logged different SEB_DRAG lines")
else:
    failures.append("the client logged no SEB_DRAG line")

bad = re.compile(r"desync|mod event handlers are not identical|non-recoverable|stack traceback|Error (?!InterruptibleStdioStream)", re.I)
for path in (run / "server.log", run / "client.log"):
    hits = [raw for raw in path.read_text(errors="replace").splitlines() if bad.search(raw) and "SEB_DRAG" not in raw]
    for raw in hits[:5]:
        print(f"  {path.name}: {raw.strip()[:200]}")
    if hits:
        failures.append(f"{path.name}: {len(hits)} error or desync lines")
if not failures:
    print("no error, no desync")

print()
for failure in failures:
    print(f"FAIL {failure}")
print("MP DRAG " + ("FAILED" if failures else "OK"))
sys.exit(1 if failures else 0)
