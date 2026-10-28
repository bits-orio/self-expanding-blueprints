"""The help diagrams' shared parts (a copy as blueprint paper, plus and
equals signs, a marker on its dark tile, the highlight ring) and the socket
and plug diagram, help-growth.png. The other help pictures (help_sensor.py,
help_probe.py, help_port.py) build on the same parts.
"""

from PIL import Image

from seb_art import (
    Art, DOWNSCALE, INK, PAPER_BLUE, PAPER_GRID, PAPER_NIGHT, MACHINE_GREY, HIGHLIGHT, WHITE,
    entry, facing, socket,
)

# ----------------------------------------------------------- help diagram --

# help-growth.png is a picture of three panels with no text, shown in the
# window under "How growing works": a copy and its socket, a copy and its
# plug, and the two copies joined. It is drawn at one pixel per art unit and
# built from small supersampled sprites placed on whole pixels, so every grid
# line, rim and bar lands on a pixel edge and stays crisp. The copy is one
# sprite pasted four times, which is what makes the copies identical.
TILE = 16  # pixels per tile
BLOCK_W, BLOCK_H = 4 * TILE, 3 * TILE  # a copy, 4 x 3 tiles
PAD = 16  # margin round the whole picture
GAP = 48  # the room between two panels, holding a plus or an equals sign
HELP_W = 2 * PAD + (5 + 4 + 8) * TILE + 2 * GAP  # panels are 5, 4 and 8 tiles wide
HELP_H = 2 * PAD + BLOCK_H

RIM = 2  # a copy's dark outline, drawn inside its 4 x 3 tiles
MACHINES = ((1, 0), (2, 2))  # tiles of a copy that hold a small grey machine
MACHINE = 10  # a machine's side, outline included, centred in its tile
OP_SIZE, OP_ARM, OP_BAR, OP_RIM = 18, 16, 4, 1  # plus and equals: canvas, length, bar, outline
RING, RING_RADIUS = 2, 4  # the ring's thickness; it sits just outside the tile it marks


def block_sprite():
    """One copy as blueprint paper, BLOCK_W x BLOCK_H: a dark rim, a grid line
    on every tile boundary, and a couple of small grey machines."""
    a = Art(BLOCK_W, BLOCK_H)
    a.rect((0, 0, BLOCK_W, BLOCK_H), INK)
    a.rect((RIM, RIM, BLOCK_W - RIM, BLOCK_H - RIM), PAPER_BLUE)
    for x in range(TILE, BLOCK_W, TILE):
        a.rect((x, RIM, x + 1, BLOCK_H - RIM), PAPER_GRID)
    for y in range(TILE, BLOCK_H, TILE):
        a.rect((RIM, y, BLOCK_W - RIM, y + 1), PAPER_GRID)
    inset = (TILE - MACHINE) // 2
    for tx, ty in MACHINES:
        x, y = tx * TILE + inset, ty * TILE + inset
        a.rect((x, y, x + MACHINE, y + MACHINE), INK)
        a.rect((x + 1, y + 1, x + MACHINE - 1, y + MACHINE - 1), MACHINE_GREY)
    return a.done()


def plus_sprite():
    """White plus built from two bars, so there is no font in it."""
    c, r, t = OP_SIZE / 2, OP_ARM / 2, OP_BAR / 2
    shape = [  # clockwise from the top arm, three corners per arm
        (c - t, c - r), (c + t, c - r), (c + t, c - t),
        (c + r, c - t), (c + r, c + t), (c + t, c + t),
        (c + t, c + r), (c - t, c + r), (c - t, c + t),
        (c - r, c + t), (c - r, c - t), (c - t, c - t),
    ]
    a = Art(OP_SIZE, OP_SIZE)
    a.shapes([shape], WHITE, outline=OP_RIM)
    return a.done()


def equals_sprite():
    """White equals sign: two bars one bar-width apart."""
    c, r, t = OP_SIZE / 2, OP_ARM / 2, OP_BAR
    top = c - t * 3 / 2  # bar, gap and bar are all t tall, centred on c
    bars = [[(c - r, y), (c + r, y), (c + r, y + t), (c - r, y + t)] for y in (top, top + 2 * t)]
    a = Art(OP_SIZE, OP_SIZE)
    a.shapes(bars, WHITE, outline=OP_RIM)
    return a.done()


def marker_cell(north):
    """A marker as the diagram draws it: one TILE square, facing east, on a dark
    tile. The dark tile is what lets the plug's blue show up on blue paper.
    The art is the same 64 px image the files hold, box-filtered down 4 to 1."""
    cell = Image.new("RGBA", (TILE, TILE), PAPER_NIGHT)
    cell.alpha_composite(facing(north, "east").resize((TILE, TILE), DOWNSCALE))
    return cell


def ring_sprite():
    """A flat rounded ring that wraps one tile: its hole is exactly a tile and
    the sprite is RING pixels bigger on every side."""
    n = TILE + 2 * RING
    a = Art(n, n)
    a.rounded((0, 0, n, n), RING_RADIUS, HIGHLIGHT)
    a.rounded((RING, RING, n - RING, n - RING), RING_RADIUS - RING, (0, 0, 0, 0))
    return a.done()


def help_growth():
    """Help diagram, no text: a copy and its socket, plus a copy and its plug,
    equals the two copies joined.

    The socket (socket.png) is on the first tile outside the copy's right edge,
    facing east, away from the copy. The plug (entry.png) is on the copy's own
    left edge tile, facing east, into the copy. Build the second copy so its
    plug tile lands on the socket tile and the copies sit edge to edge: in the
    third panel copy 2 starts at the tile the socket stood on, and its plug is
    on it. The same ring marks the socket tile, the plug tile and the joint, so
    the eye can follow one tile through all three panels.
    """
    block, ring = block_sprite(), ring_sprite()
    socket_cell, plug_cell = marker_cell(socket()), marker_cell(entry())
    sheet = Image.new("RGBA", (HELP_W, HELP_H), (0, 0, 0, 0))
    top = PAD
    row = top + TILE  # the middle row of a copy: every marker sits in it

    def ringed(cell, x):
        sheet.alpha_composite(cell, (x, row))
        sheet.alpha_composite(ring, (x - RING, row - RING))

    x1 = PAD  # panel 1: a copy, and its socket on the first tile outside its right edge
    sheet.alpha_composite(block, (x1, top))
    ringed(socket_cell, x1 + BLOCK_W)

    x2 = x1 + BLOCK_W + TILE + GAP  # panel 2: a copy, and its plug on its own left edge tile
    sheet.alpha_composite(block, (x2, top))
    ringed(plug_cell, x2)

    x3 = x2 + BLOCK_W + GAP  # panel 3: copy 2 starts on the tile the socket stood on
    joint = x3 + BLOCK_W
    sheet.alpha_composite(block, (x3, top))
    sheet.alpha_composite(block, (joint, top))
    ringed(plug_cell, joint)

    mid = (HELP_H - OP_SIZE) // 2
    for sign, gap_left in ((plus_sprite(), x1 + BLOCK_W + TILE), (equals_sprite(), x2 + BLOCK_W)):
        sheet.alpha_composite(sign, (gap_left + (GAP - OP_SIZE) // 2, mid))
    return sheet
