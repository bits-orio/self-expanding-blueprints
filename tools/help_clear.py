"""help-clear.png: the Keep clear marker's help picture, 400x80, no text.

Left to right:

  design  a copy as blueprint paper with Keep clear markers in both places
          the text names: on one tile inside it, and on every tile of the
          column past its right edge. Each is ringed in yellow so the eye
          finds it.
  arrow   the design grows.
  ground  a strip of dirt with trees and rocks along both edges, and the
          copies grown on it. Each copy's outline takes in the column past
          it, as the map's overlay draws a copy, since those tiles count in
          its footprint; and wherever a marker stood there is bare ground:
          markers are never built, and no tree or rock stands on those tiles.
          So the column is a free lane between one copy and the next, and
          the tile inside is a hole in each copy. The third copy is not
          built: a wooden chest stands on its lane, ringed in red. A red
          dashed outline marks where the copy and its lane would have gone,
          with a red X in it.

The chest is no part of any copy, so it looks like nothing in one: brown
wood, not the copies' grey machines. Only the refused spot is red, its
outline, its X and the ring on the chest, so the eye goes from the X to its
cause. The refused spot is drawn as help-probe.png draws a copy that was not
built (the dashes, the X and the arrow are help_probe.py's own), on that
picture's dirt, so the pictures read as one family.

Built from help-growth.png's parts (seb_help.py) at one pixel per art unit,
every sprite placed on whole pixels, so grid lines and rims stay crisp.
Run from tools/:  python3 help_clear.py <out.png>
"""

import math
import sys

from PIL import Image, ImageDraw

from help_probe import ARROW, BADGE, BLOCKED_RED, DIRT, _dashes, arrow_sprite, cross_sprite
from seb_art import HIGHLIGHT, INK, Art, clear, facing
from seb_help import BLOCK_H, BLOCK_W, PAD, RIM, RING, RING_RADIUS, TILE, block_sprite, marker_cell, ring_sprite

# New colours.
TREE = (74, 124, 52, 255)  # #4A7C34 a tree's crown, seen from above
TREE_LIGHT = (122, 168, 76, 255)  # #7AA84C the sunlit side of the crown
ROCK = (134, 128, 120, 255)  # #868078 a rock's lit face: warmer than MACHINE_GREY, and round, not square
ROCK_SHADE = (100, 95, 89, 255)  # #645F59 its shaded side
ROCK_LIGHT = (176, 171, 162, 255)  # #B0ABA2 its top
WOOD = (184, 128, 68, 255)  # #B88044 the wooden chest, bright enough to stand out on DIRT
WOOD_DARK = (122, 80, 40, 255)  # #7A5028 its frame and lid seam

SIZE = (400, 2 * PAD + BLOCK_H)  # 400 x 80, as help-growth.png
TOP = PAD  # every copy's top edge, the design's too, as in help-growth.png
STEP = BLOCK_W + TILE  # one copy and its lane: its footprint, five tiles wide
COPIES = 3  # two built, then the refused one
INSIDE = (2, 1)  # the tile kept clear inside the copy: middle row, clear of both machines
LANE_TILE = 1  # the lane tile the chest stands on: the middle one

STRIP_MX, STRIP_MY = 4, 12  # dirt left and right of the row, and above and below it, rim included
STRIP_W = 2 * STRIP_MX + COPIES * STEP
STRIP_H = 2 * STRIP_MY + BLOCK_H
STRIP_X = SIZE[0] - PAD - STRIP_W  # the strip ends PAD from the right edge, as help-probe.png's does
STRIP_Y = TOP - STRIP_MY
X_ROW = STRIP_X + STRIP_MX  # the first copy's left edge
X_DESIGN = PAD
ARROW_W = 32  # help-probe.png's arrow, 4 pixels shorter: the room here is 38

TREE_SIZES = {"tree": 11, "small": 9}  # pixels across a crown: the room above and below the row is 10
ROCK_SIZE, CHEST = (11, 9), 12  # a chest is a little smaller than its tile

# What stands along the strip's two edges: (x of its centre in the strip,
# what it is, pixels it sits nearer the strip's rim). Trees of two sizes in
# loose clumps, a rock between clumps: one size evenly spaced read as a
# hedge, as one size of ore read as polka dots in help-sensor.png.
TOP_EDGE = (
    (7, "tree", 0), (17, "small", 1), (28, "tree", 0), (43, "rock", 0), (57, "tree", 1), (68, "tree", 0),
    (79, "small", 1), (95, "rock", 0), (109, "small", 0), (120, "tree", 1), (131, "tree", 0), (147, "rock", 1),
    (162, "tree", 0), (173, "small", 1), (188, "tree", 0), (199, "tree", 1), (214, "rock", 0), (228, "small", 1),
    (239, "tree", 0),
)
BOTTOM_EDGE = (
    (9, "small", 1), (21, "tree", 0), (36, "rock", 1), (50, "tree", 0), (61, "small", 1), (72, "tree", 0),
    (88, "tree", 1), (103, "rock", 0), (118, "tree", 0), (129, "small", 1), (143, "tree", 0), (155, "tree", 1),
    (170, "rock", 0), (185, "small", 0), (196, "tree", 1), (207, "tree", 0), (222, "rock", 1), (237, "tree", 0),
)


# ------------------------------------------------------------------ parts --


def clear_cell():
    """The Keep clear marker on its dark tile, as the design shows it.
    marker_cell turns art to face east, as sockets and plugs are drawn; the
    game never turns this marker, so the art is turned west first and the two
    turns cancel, as help_probe.py does for the probe."""
    return marker_cell(facing(clear(), "west"))


def ring(w, h, color=HIGHLIGHT):
    """help-growth.png's ring, made to wrap a w x h area rather than one tile:
    RING pixels thick, just outside it."""
    a = Art(w + 2 * RING, h + 2 * RING)
    a.rounded((0, 0, w + 2 * RING, h + 2 * RING), RING_RADIUS, color)
    a.rounded((RING, RING, w + RING, h + RING), RING_RADIUS - RING, (0, 0, 0, 0))
    return a.done()


def grown_copy():
    """A copy as it stands once grown: its paper, then its lane, the column
    it keeps clear, one tile of bare ground. One ink rim goes round both, as
    the map's overlay outlines a copy's whole footprint, so between two
    copies the joint shows both rims, as in help-growth.png. The tile kept
    clear inside it is bare ground too, framed by the paper's grid lines."""
    a = Art(STEP, BLOCK_H)
    a.rect((0, 0, STEP, BLOCK_H), INK)
    a.rect((BLOCK_W, RIM, STEP - RIM, BLOCK_H - RIM), DIRT)
    sheet = a.done()
    paper = block_sprite()
    x, y = INSIDE[0] * TILE, INSIDE[1] * TILE
    ImageDraw.Draw(paper).rectangle([x + 1, y + 1, x + TILE - 1, y + TILE - 1], fill=DIRT)  # inside the grid lines
    sheet.alpha_composite(paper)
    return sheet


def tree_sprite(n):
    """A tree seen from above, n pixels across: a round crown with a lumpy
    edge, eight bumps round a disc, all rimmed as one, and its sunlit side."""
    a = Art(n, n)
    c = n / 2
    reach, bump = c - 0.2 * n, 0.14 * n  # from the centre to each bump's, and a bump's radius
    turns = [t * math.pi / 4 + 0.3 for t in range(8)]  # a little off square, so no bump points straight up
    bumps = [(c + reach * math.cos(angle), c + reach * math.sin(angle)) for angle in turns]
    parts = bumps + [(c, c)]
    radii = [bump] * 8 + [reach]
    for (x, y), r in zip(parts, radii):  # every rim before any fill, so the crown has one outline
        a.disc(x, y, r, INK, outline=1)
    for (x, y), r in zip(parts, radii):
        a.disc(x, y, r, TREE, outline=0)
    a.disc(c - 0.11 * n, c - 0.11 * n, 0.155 * n, TREE_LIGHT, outline=0)
    return a.done()


def rock_sprite():
    """A grey boulder: an ink rim, a shaded side, a lit face and a pale top."""
    w, h = ROCK_SIZE
    a = Art(w, h)
    a.shapes([[(1.2, h * 0.66), (2.0, h * 0.30), (w * 0.40, 1.2), (w - 2.2, 1.6), (w - 1.2, h * 0.55),
               (w * 0.66, h - 1.2), (2.4, h - 1.3)]], ROCK_SHADE, outline=1)
    a.d.polygon(a._px([(2.0, h * 0.30), (w * 0.40, 1.2), (w - 2.2, 1.6), (w - 1.2, h * 0.55), (w * 0.5, h * 0.62),
                       (1.6, h * 0.55)]), fill=ROCK)
    a.d.polygon(a._px([(2.6, h * 0.34), (w * 0.42, 2.0), (w - 3.0, 2.3), (w * 0.5, h * 0.45)]), fill=ROCK_LIGHT)
    return a.done()


def chest_sprite():
    """A wooden chest from above: an ink rim, a darker frame, the lid's seam
    across it and a dark latch."""
    n, mid = CHEST, CHEST // 2
    a = Art(n, n)
    a.rect((0, 0, n, n), INK)
    a.rect((1, 1, n - 1, n - 1), WOOD_DARK)
    a.rect((2, 2, n - 2, n - 2), WOOD)
    a.rect((2, mid - 1, n - 2, mid), WOOD_DARK)
    a.rect((mid - 1, mid - 2, mid + 1, mid + 1), INK)
    return a.done()


def ground_strip():
    """The dirt the copies grow on, with trees and rocks along its two edges
    and none in the row between them. They go down before the rim, so the
    ones on the edge run under it as if the ground went on."""
    a = Art(STRIP_W, STRIP_H)
    a.rect((0, 0, STRIP_W, STRIP_H), DIRT)
    strip = a.done()
    things = {kind: tree_sprite(n) for kind, n in TREE_SIZES.items()}
    things["rock"] = rock_sprite()
    room = (RIM + STRIP_MY) / 2  # the middle of the dirt between the rim and the row
    row_top, row_bottom = STRIP_MY, STRIP_MY + BLOCK_H
    for edge, y_mid, outward in ((TOP_EDGE, room, -1), (BOTTOM_EDGE, STRIP_H - room, 1)):
        for x, kind, nudge in edge:
            thing = things[kind]
            y = y_mid - thing.height / 2  # centred in the room; the spare half pixel and the nudge go toward the rim
            top = (math.floor(y) if outward < 0 else math.ceil(y)) + outward * nudge
            assert top + thing.height <= row_top or top >= row_bottom, "a tree or rock in the copies' row"
            strip.alpha_composite(thing, (math.floor(x - thing.width / 2), top))
    paint = ImageDraw.Draw(strip)
    for x0, y0, x1, y1 in ((0, 0, STRIP_W, RIM), (0, STRIP_H - RIM, STRIP_W, STRIP_H),
                           (0, 0, RIM, STRIP_H), (STRIP_W - RIM, 0, STRIP_W, STRIP_H)):
        paint.rectangle([x0, y0, x1 - 1, y1 - 1], fill=INK)
    return strip


def refused_outline():
    """Where a copy and its lane would have gone: help-probe.png's red dashed
    footprint, five tiles wide here as the footprint now is, RIM wide where
    the copy's rim would be."""
    a = Art(STEP, BLOCK_H)
    for x0, x1 in _dashes(STEP):
        a.rect((x0, 0, x1, RIM), BLOCKED_RED)
        a.rect((x0, BLOCK_H - RIM, x1, BLOCK_H), BLOCKED_RED)
    for y0, y1 in _dashes(BLOCK_H):
        a.rect((0, y0, RIM, y1), BLOCKED_RED)
        a.rect((STEP - RIM, y0, STEP, y1), BLOCKED_RED)
    return a.done()


# ---------------------------------------------------------------- picture --


def draw():
    """The design and its Keep clear tiles, then the copies it grows into:
    two built with those tiles left bare, and a spot refused for a chest."""
    sheet = Image.new("RGBA", SIZE, (0, 0, 0, 0))

    # The design, as the player draws it: a marker inside, and one on every
    # tile of the column past the right edge.
    column = X_DESIGN + BLOCK_W
    inside_x, inside_y = X_DESIGN + INSIDE[0] * TILE, TOP + INSIDE[1] * TILE
    sheet.alpha_composite(block_sprite(), (X_DESIGN, TOP))
    sheet.alpha_composite(clear_cell(), (inside_x, inside_y))
    sheet.alpha_composite(ring_sprite(), (inside_x - RING, inside_y - RING))
    for row in range(BLOCK_H // TILE):
        sheet.alpha_composite(clear_cell(), (column, TOP + row * TILE))
    sheet.alpha_composite(ring(TILE, BLOCK_H), (column - RING, TOP - RING))

    # The ground, then the copies on it.
    sheet.alpha_composite(ground_strip(), (STRIP_X, STRIP_Y))
    lefts = [X_ROW + i * STEP for i in range(COPIES)]
    copy = grown_copy()
    for x in lefts[:-1]:
        sheet.alpha_composite(copy, (x, TOP))

    # The refused spot: the chest on its lane, then the footprint, the red
    # ring hugging the chest (a pixel of ground between them, its right side
    # on the footprint's dashed edge), and the X on the copy's part of it.
    spot, lane = lefts[-1], lefts[-1] + BLOCK_W
    chest_x = lane + (TILE - RIM - CHEST) // 2  # centred in the lane's ground, inside the footprint's rim
    chest_y = TOP + LANE_TILE * TILE + (TILE - CHEST) // 2
    sheet.alpha_composite(chest_sprite(), (chest_x, chest_y))
    sheet.alpha_composite(refused_outline(), (spot, TOP))
    sheet.alpha_composite(ring(CHEST + 2, CHEST + 2, BLOCKED_RED), (chest_x - 1 - RING, chest_y - 1 - RING))
    sheet.alpha_composite(cross_sprite(BADGE), (spot + (BLOCK_W - BADGE) // 2, TOP + (BLOCK_H - BADGE) // 2))

    # The arrow, centred in the room between the design's ring and the ground.
    room_x = column + TILE + RING
    h = ARROW[1]
    arrow = arrow_sprite(ARROW_W, *ARROW[1:])
    sheet.alpha_composite(arrow, (room_x + (STRIP_X - room_x - ARROW_W) // 2, TOP + (BLOCK_H - h) // 2))
    return sheet


if __name__ == "__main__":
    draw().save(sys.argv[1])
