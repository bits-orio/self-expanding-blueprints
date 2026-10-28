#!/usr/bin/env python3
"""Generate every PNG in graphics/ for Self-Expanding Blueprints.

    socket.png, socket-<dir>.png   green arrow on a square plug: the next copy attaches here
    entry.png,  entry-<dir>.png    blue arrow entering a U bracket: this design attaches here
    sensor.png                     amber corner brackets around a lump of ore: watch the ore here
    probe.png                      violet map pin: something must be true on this tile
    port.png                       teal box with an arrow each way: a copy's circuit mailbox
    clear.png                      red corner brackets round a red cross: keep this tile empty
    frame.png, frame-<dir>.png     the dashed frame round the design in hand while growing
    anchor.png                    small grey dot (internal entity, almost never visible)
    grow-tool.png                  tool and shortcut icon: blueprint paper, block, two arrows
    overlay-arrow.png              white up arrow, tinted and rotated by the renderer
    overlay-blocked.png            white X, tinted red by the renderer
    help-growth.png                help diagram, no text: a copy and its socket, plus a copy
                                   and its plug, equals the two copies joined (400x80)
    help-sensor.png                help diagram: a copy waits on its ore, then grows (help_sensor.py)
    help-probe.png                 help diagram: a copy goes only where its probe holds, and
                                   "deny" flips it (400x112, help_probe.py)
    help-port.png                  help diagram: a builder writes into one copy's port (help_port.py)
    help-clear.png                 help diagram: every copy leaves its Keep clear tiles bare, a lane
                                   between copies among trees and rocks, and a chest on one
                                   refuses the copy (help_clear.py)

<dir> is north, east, south, west. Every file is 64x64 RGBA on a transparent
background, except the help-*.png diagrams. North is the art as drawn; the other three
are lossless 90 degree turns of it, so socket.png and socket-north.png are the
same pixels.

The drawing primitives, palette and marker art are in tools/seb_art.py (with
the style rules); the help diagrams in tools/seb_help.py and help_*.py.

Run from the repo root:  python3 tools/gen_graphics.py
"""

from pathlib import Path

from PIL import Image

import help_clear
import help_port
import help_probe
import help_sensor
import seb_help
from seb_art import (
    SIZE, TURNS, anchor, clear, entry, facing, frame_dash, frame_icon, grow_tool, overlay_arrow, overlay_blocked, port,
    probe, sensor, socket,
)

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "graphics"
HELP_PICTURES = {"help-sensor": help_sensor, "help-probe": help_probe, "help-port": help_port, "help-clear": help_clear}
SIZES = {"help-growth": (seb_help.HELP_W, seb_help.HELP_H)}  # every other file is SIZE x SIZE
SIZES.update({stem: module.SIZE for stem, module in HELP_PICTURES.items()})


# -------------------------------------------------------------------- main --

def build():
    """Return {file stem: image} for every PNG this script owns, in write order."""
    images = {}
    for stem, make in (("socket", socket), ("entry", entry)):
        north = make()
        images[stem] = north
        for direction in TURNS:
            images[f"{stem}-{direction}"] = facing(north, direction)
    images["sensor"] = sensor()
    images["probe"] = probe()
    images["port"] = port()
    images["clear"] = clear()
    images["frame"] = frame_icon()
    for direction in TURNS:
        images[f"frame-{direction}"] = facing(frame_dash(), direction)
    images["anchor"] = anchor()
    images["grow-tool"] = grow_tool()
    images["overlay-arrow"] = overlay_arrow()
    images["overlay-blocked"] = overlay_blocked()
    images["help-growth"] = seb_help.help_growth()
    for stem, module in HELP_PICTURES.items():
        images[stem] = module.draw()
    return images


def check(path, size):
    """Read a written file back: (size text, mode, bytes, is RGBA at `size` with clear corners)."""
    with Image.open(path) as img:
        right, bottom = img.width - 1, img.height - 1
        corners = [img.getpixel(c)[3] for c in ((0, 0), (right, 0), (0, bottom), (right, bottom))]
        ok = img.size == size and img.mode == "RGBA" and not any(corners)
        return f"{img.width}x{img.height}", img.mode, path.stat().st_size, ok


def main():
    OUT_DIR.mkdir(exist_ok=True)
    rows = []
    for stem, img in build().items():
        path = OUT_DIR / f"{stem}.png"
        img.save(path, optimize=True)
        rows.append((path.name, *check(path, SIZES.get(stem, (SIZE, SIZE)))))

    width = max(len(r[0]) for r in rows)
    print(f"{'file':<{width}}  {'size':<7} {'mode':<5} {'bytes':>6}  ok")
    for name, size, mode, nbytes, ok in rows:
        print(f"{name:<{width}}  {size:<7} {mode:<5} {nbytes:>6}  {'yes' if ok else 'NO'}")
    if not all(r[4] for r in rows):
        raise SystemExit("a file is not RGBA at its intended size with transparent corners")


if __name__ == "__main__":
    main()
