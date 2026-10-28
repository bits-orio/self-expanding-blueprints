"""Help diagram for the probe tab, help-probe.png (400x112), no text.

Top row, read left to right:

  design  a copy as blueprint paper with the probe, a violet pin, on one of
          its tiles, ringed in yellow so the eye finds it.
  arrow   the design goes down on the ground.
  ground  one strip of dirt with an ore patch on its left part and room for
          two copies. On the patch the copy is built: its ringed tile shows
          the pin standing on ore, and a green check sits on its corner.
          Past the patch's edge there is no copy: a red dashed footprint
          marks where it would have gone, the pin stands on bare dirt, and a
          red X sits on its corner. Both spots are on the same strip, so ore
          is close by; what differs is the ground under the pin.

Bottom row, the "deny" signal: the same probe with Factorio's red deny
signal in a slot beside it, an arrow, then that probe on the same two tiles
of ground, cut from the strip right above them, each followed by its
verdict. On ore an X, on bare dirt a check: the top row's verdicts, flipped.

The picture is 112 tall, not 80 like help-growth.png, to make room for the
deny row; DENY_ROW = False draws the top row alone at 80.

Built from help-growth.png's parts (seb_help.py) at one pixel per art unit,
with every sprite placed on whole pixels, so grid lines and rims stay crisp.
Run from the tools folder:  python3 help_probe.py <out.png>
"""

import math
import sys

from PIL import Image

from seb_art import (
    DOWNSCALE, INK, ORE_GLINT, ORE_ROCK, PAPER_NIGHT, SOCKET_GREEN, WHITE, Art, arrow, cross, facing, probe,
)
from seb_help import (
    BLOCK_H, BLOCK_W, OP_BAR, OP_RIM, OP_SIZE, PAD, RIM, RING, TILE, block_sprite, marker_cell, ring_sprite,
)

DIRT = (70, 58, 44, 255)  # #463A2C dark soil: warmer than the window's grey, darker than the ore on it
BLOCKED_RED = (242, 64, 51, 255)  # the overlay's blocked tint (0.95, 0.25, 0.20), and near enough the deny signal's red

DENY_ROW = True  # False: the top row alone, 80 tall like help-growth.png
TOP_ROW_H, DENY_ROW_H = 80, 32  # the top row is laid out in help-growth.png's 80 rows; the deny row below it
SIZE = (400, TOP_ROW_H + (DENY_ROW_H if DENY_ROW else 0))

PROBE_TILE = (2, 1)  # the probe's tile in a copy: middle row, clear of both machines and of the badge corner
STRIP_MX, STRIP_MY = 12, 8  # dirt showing left and right of a copy, and above and below it
SPOT_GAP = 72  # dirt between the two spots, room for the ore patch to thin out
STRIP_W = 2 * STRIP_MX + 2 * BLOCK_W + SPOT_GAP
STRIP_H = 2 * STRIP_MY + BLOCK_H
STRIP_X = SIZE[0] - PAD - STRIP_W  # the strip ends PAD from the right edge, as help-growth.png's last copy does
STRIP_Y = (TOP_ROW_H - STRIP_H) // 2
COPY_Y = STRIP_Y + STRIP_MY  # the top of every copy in the top row, the design's too
SPOTS = (STRIP_X + STRIP_MX, STRIP_X + STRIP_MX + BLOCK_W + SPOT_GAP)  # left edges: built, skipped
DENY_Y = TOP_ROW_H + 8  # the deny row's tiles: rings end 6 rows above the bottom, as the badges start below the top

ORE_PITCH = 10  # the ore patch's scatter grid: about one lump and a gap
ORE_DENSE_TO = 80  # strip x where the patch starts to thin out: just past the built copy
ORE_GONE_AT = 146  # strip x where it has thinned out to nothing: just short of the skipped copy's footprint

BADGE, SMALL_BADGE = 20, 16  # check and X: on a copy's corner, and after a single tile
SLOT = 14  # the deny signal's slot, a little smaller than a tile so the pin stays the main thing
ARROW = (36, OP_SIZE, 14, 10)  # the top row's arrow: canvas width and height, head width and length, as help_sensor's
SMALL_ARROW = (24, 14, 10, 7)  # the deny row's, smaller as the row is
DASH, DASH_GAP, DASH_CORNER = 4, 4, 6  # the footprint's dashes, RIM wide, pixels along an edge

# sensor()'s lump of ore and its glint in seb_art's 64-unit art, and the point
# they turn about: the help pictures all draw ore as the sensor marker does.
LUMP = ((21, 37), (26, 24), (37, 20), (45, 29), (43, 41), (30, 45))
GLINT = ((28, 28), (35, 24), (39, 30), (32, 33))
LUMP_MID, LUMP_SPAN = (33, 32.5), 25


# ------------------------------------------------------------------ parts --


def probe_cell():
    """The probe on its dark tile, upright, as the design shows it. marker_cell
    turns art to face east, as sockets and plugs are drawn; the game never
    turns a probe, so the art is turned west first and the two turns cancel."""
    return marker_cell(facing(probe(), "west"))


def pin_sprite():
    """The probe alone, one tile, to stand on ground: no dark tile behind it."""
    return probe().resize((TILE, TILE), DOWNSCALE)


def _lump_points(points, cx, cy, width, turns, mirror):
    """sensor()'s lump moved to (cx, cy), scaled to width, turned and mirrored."""
    k = width / LUMP_SPAN
    out = []
    for px, py in points:
        x, y = px - LUMP_MID[0], py - LUMP_MID[1]
        if mirror:
            x = -x
        for _ in range(turns):  # quarter turns keep the facets crisp
            x, y = -y, x
        out.append((cx + x * k, cy + y * k))
    return out


def _scatter(i, j):
    """A fixed stand-in for a random number, 0..96, for grid point (i, j): the
    patch looks scattered but every run draws the same lumps."""
    return (i * 73 + j * 151 + i * j * 37) % 97


def ore_lumps():
    """The ore patch, as (x, y, width, quarter turns, mirrored) in the strip's
    pixels. Lumps sit on a staggered grid, each nudged, sized and turned by
    _scatter. The patch is dense up to ORE_DENSE_TO, then thins out and its
    lumps shrink until ORE_GONE_AT, so it ends near the skipped copy but not
    in its footprint. The built copy hides the patch under it but for its
    probe's tile, which gets four lumps of its own, one in each corner round
    the pin, so it reads as ore even at 16 pixels, and no stray lump at its
    edges."""
    win_x = STRIP_MX + PROBE_TILE[0] * TILE  # the built copy's probe tile, in the strip
    win_y = STRIP_MY + PROBE_TILE[1] * TILE
    row_pitch = ORE_PITCH * 0.87  # rows of a staggered grid are closer than its columns
    lumps = []
    for j in range(int((STRIP_H - 4) / row_pitch) + 1):
        y = 3 + j * row_pitch
        for i in range(int(ORE_GONE_AT / ORE_PITCH) + 1):
            x = 3 + i * ORE_PITCH + (ORE_PITCH / 2 if j % 2 else 0)
            density = min(1.0, max(0.0, (ORE_GONE_AT - x) / (ORE_GONE_AT - ORE_DENSE_TO)))
            h = _scatter(i, j)
            if h >= 93 * density:  # a few gaps even where dense, more as it thins
                continue
            cx, cy = x + (h % 5 - 2) * 0.6, y + (h // 5 % 5 - 2) * 0.6
            if win_x - 3 < cx < win_x + TILE + 3 and win_y - 3 < cy < win_y + TILE + 3:
                continue
            width = 5 + 4 * density * (0.6 + 0.4 * (h // 25 % 4) / 3)  # up to 9 where dense, 5 at the edge
            lumps.append((cx, cy, round(width * 2) / 2, h % 4, h % 2 == 1))
    corners = ((3, 3.5, 5, 0, True), (13, 4, 5, 2, False), (3.5, 12.5, 6.5, 1, False), (12.5, 12, 6.5, 3, True))
    lumps += [(win_x + x, win_y + y, width, turns, mirror) for x, y, width, turns, mirror in corners]
    return lumps


def ground_strip():
    """The dirt the copies go down on, its ore drawn first and its rim last, so
    lumps on the edge run under the rim as if the ground went on."""
    a = Art(STRIP_W, STRIP_H)
    a.rect((0, 0, STRIP_W, STRIP_H), DIRT)
    for x, y, width, turns, mirror in ore_lumps():
        a.shapes([_lump_points(LUMP, x, y, width, turns, mirror)], ORE_ROCK, outline=1)
        a.d.polygon(a._px(_lump_points(GLINT, x, y, width, turns, mirror)), fill=ORE_GLINT)  # a facet: no rim
    for box in ((0, 0, STRIP_W, RIM), (0, STRIP_H - RIM, STRIP_W, STRIP_H),
                (0, 0, RIM, STRIP_H), (STRIP_W - RIM, 0, STRIP_W, STRIP_H)):
        a.rect(box, INK)
    return a.done()


def _dashes(length):
    """(start, end) pixel spans of the dashes along one edge: a longer dash on
    each corner, so the outline keeps its corners, and even dashes between."""
    spans = [(0, DASH_CORNER)]
    x = DASH_CORNER + DASH_GAP
    while x + DASH + DASH_GAP <= length - DASH_CORNER:
        spans.append((x, x + DASH))
        x += DASH + DASH_GAP
    assert x == length - DASH_CORNER, "dashes must close evenly on the far corner"
    return spans + [(length - DASH_CORNER, length)]


def footprint():
    """Where a copy would have gone and was not built: a red dashed outline,
    RIM wide, where its rim would be. Red, as the map shows a blocked spot
    and as Factorio shows a blueprint that cannot be placed; a dashed blue
    frame read as a copy still to come."""
    a = Art(BLOCK_W, BLOCK_H)
    for x0, x1 in _dashes(BLOCK_W):
        a.rect((x0, 0, x1, RIM), BLOCKED_RED)
        a.rect((x0, BLOCK_H - RIM, x1, BLOCK_H), BLOCKED_RED)
    for y0, y1 in _dashes(BLOCK_H):
        a.rect((0, y0, RIM, y1), BLOCKED_RED)
        a.rect((BLOCK_W - RIM, y0, BLOCK_W, y1), BLOCKED_RED)
    return a.done()


def _offset(p, q, d):
    """The segment p-q moved sideways by d (positive is to its right, y down)."""
    length = math.hypot(q[0] - p[0], q[1] - p[1])
    nx, ny = -(q[1] - p[1]) / length, (q[0] - p[0]) / length
    return (p[0] + nx * d, p[1] + ny * d), (q[0] + nx * d, q[1] + ny * d)


def _meet(a, b):
    """Where the lines through segments a and b cross."""
    (x1, y1), (x2, y2) = a
    (x3, y3), (x4, y4) = b
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    u = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return x1 + u * (x2 - x1), y1 + u * (y2 - y1)


def check_mark(cx, cy, size, thickness):
    """Check mark polygon, 6 vertices: a short stroke down to the elbow and a
    long one up to the right, of even thickness, mitred at the elbow."""
    start = (cx - 0.50 * size, cy + 0.02 * size)
    elbow = (cx - 0.15 * size, cy + 0.38 * size)
    end = (cx + 0.52 * size, cy - 0.38 * size)
    h = thickness / 2
    short_up, short_down = _offset(start, elbow, -h), _offset(start, elbow, h)
    long_up, long_down = _offset(elbow, end, -h), _offset(elbow, end, h)
    return [short_up[0], _meet(short_up, long_up), long_up[1],
            long_down[1], _meet(short_down, long_down), short_down[0]]


def check_sprite(n):
    """Green check, n pixels square, outlined like plus and equals: built."""
    a = Art(n, n)
    a.shapes([check_mark(n / 2, n / 2 + 0.5, n * 0.8, n / 4)], SOCKET_GREEN, outline=OP_RIM)
    return a.done()


def cross_sprite(n):
    """Red X, n pixels square, outlined like plus and equals: not built."""
    a = Art(n, n)
    a.shapes([cross(n / 2, n / 2, n * 0.36, n * 0.12)], BLOCKED_RED, outline=OP_RIM)
    return a.done()


def deny_slot():
    """Factorio's deny signal, a red X, on a dark slot like the port picture's
    signal slots: a signal set on the probe, not a verdict, which is bare."""
    a = Art(SLOT, SLOT)
    a.rounded((0, 0, SLOT, SLOT), 3, INK)
    a.rounded((1, 1, SLOT - 1, SLOT - 1), 2, PAPER_NIGHT)
    a.shapes([cross(SLOT / 2, SLOT / 2, SLOT * 0.3, SLOT * 0.09)], BLOCKED_RED, outline=0.75)
    return a.done()


def arrow_sprite(width, height, head_w, head_len):
    """White block arrow pointing right, shaft OP_BAR, outlined like the plus
    and equals signs. The tip stops one outline short of the canvas edge."""
    a = Art(width, height)
    mid = height / 2
    a.shapes([arrow((OP_RIM + 1, mid), (width - OP_RIM - 1, mid), OP_BAR, head_w, head_len)], WHITE, outline=OP_RIM)
    return a.done()


# ---------------------------------------------------------------- picture --


def draw():
    """The probe diagram: the design, its copy built over ore and skipped over
    bare dirt; then, with the deny signal, the same two spots flipped."""
    sheet = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    ground, ring, pin = ground_strip(), ring_sprite(), pin_sprite()
    tx, ty = PROBE_TILE[0] * TILE, PROBE_TILE[1] * TILE  # the probe tile's corner inside a copy

    def under_probe(spot):
        """The strip's ground under the probe of the copy whose left edge is spot."""
        x, y = spot + tx - STRIP_X, COPY_Y + ty - STRIP_Y
        return ground.crop((x, y, x + TILE, y + TILE))

    def pin_on(tile, x, y, slot=False):
        """The pin standing on a tile of ground at (x, y), ringed; with slot,
        the deny signal set on it, beside the ring."""
        sheet.alpha_composite(tile, (x, y))
        sheet.alpha_composite(pin, (x, y))
        sheet.alpha_composite(ring, (x - RING, y - RING))
        if slot:
            sheet.alpha_composite(deny_slot(), (x - RING - 1 - SLOT, y + (TILE - SLOT) // 2))

    # Top row. The design, as the player draws it: the probe on its dark tile.
    sheet.alpha_composite(block_sprite(), (PAD, COPY_Y))
    sheet.alpha_composite(probe_cell(), (PAD + tx, COPY_Y + ty))
    sheet.alpha_composite(ring, (PAD + tx - RING, COPY_Y + ty - RING))

    room_x, room_w = PAD + BLOCK_W, STRIP_X - PAD - BLOCK_W  # between the design and the strip
    w, h = ARROW[:2]
    sheet.alpha_composite(arrow_sprite(*ARROW), (room_x + (room_w - w) // 2, COPY_Y + (BLOCK_H - h) // 2))

    built, skipped = SPOTS
    sheet.alpha_composite(ground, (STRIP_X, STRIP_Y))
    sheet.alpha_composite(block_sprite(), (built, COPY_Y))  # on ore: built, and the pin on the ore under it
    pin_on(under_probe(built), built + tx, COPY_Y + ty)
    sheet.alpha_composite(check_sprite(BADGE), (built + BLOCK_W - BADGE // 2, COPY_Y - BADGE // 2))
    sheet.alpha_composite(footprint(), (skipped, COPY_Y))  # past the ore: no copy, and the pin on bare dirt
    pin_on(under_probe(skipped), skipped + tx, COPY_Y + ty)
    sheet.alpha_composite(cross_sprite(BADGE), (skipped + BLOCK_W - BADGE // 2, COPY_Y - BADGE // 2))

    if not DENY_ROW:
        return sheet

    # Deny row: the same probe with the deny signal set, under the design's probe,
    # then the same two tiles of ground with that probe on them, each one right
    # under the spot it comes from, and its verdict after it.
    sheet.alpha_composite(probe_cell(), (PAD + tx, DENY_Y))
    sheet.alpha_composite(ring, (PAD + tx - RING, DENY_Y - RING))
    sheet.alpha_composite(deny_slot(), (PAD + tx - RING - 1 - SLOT, DENY_Y + (TILE - SLOT) // 2))
    w, h = SMALL_ARROW[:2]
    sheet.alpha_composite(arrow_sprite(*SMALL_ARROW), (room_x + (room_w - w) // 2, DENY_Y + (TILE - h) // 2))
    for spot, verdict in ((built, cross_sprite(SMALL_BADGE)), (skipped, check_sprite(SMALL_BADGE))):
        pin_on(under_probe(spot), spot + tx, DENY_Y, slot=True)
        sheet.alpha_composite(verdict, (spot + tx + TILE + RING + 3, DENY_Y + (TILE - SMALL_BADGE) // 2))
    return sheet


if __name__ == "__main__":
    draw().save(sys.argv[1])
