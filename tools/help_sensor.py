"""help-sensor.png: the ore sensor's help picture, two scenes and no text.

1. Waiting. A finished copy of a mining design: a drill with the sensor on
   it, inside an amber square, the drill's mining area, which the sensor
   watches. Inside the square the copy shows the ground under it, and the
   ground is full of ore. Two small machines fill the copy's last column,
   outside the square. The copy's socket, on the first tile past its right
   edge, is grey: not open yet. Past it, a dashed outline over more ore marks
   where the next copy will go, as the map's overlay draws it while a copy
   waits.
2. Grown. The same copy, its square mined down to bare ground, and the next
   copy built where the dashed outline was, standing on that ore. It waits in
   its turn: its own socket is grey.

A white block arrow leads from one scene to the other: once the ore is gone,
the copy grows. The arrow has the gap to itself, well clear of any socket.

Built from help-growth.png's parts (seb_help.py) at one pixel per art unit,
every sprite placed on whole pixels, so grid lines and rims stay crisp. The
dirt, the dashed outline and the arrow are drawn as help-probe.png draws
them, so the pictures read as one family.
Run from tools/:  python3 help_sensor.py <out.png>
"""

import sys

from PIL import Image, ImageDraw

from seb_art import (
    Art, INK, MACHINE_GREY, ORE_GLINT, ORE_ROCK, PAPER_GRID, SENSOR_AMBER, WHITE,
    arrow, sensor, socket,
)
from seb_help import (
    BLOCK_H, BLOCK_W, MACHINE, MACHINES, OP_BAR, OP_RIM, OP_SIZE, PAD, RIM, TILE,
    block_sprite, marker_cell,
)

DIRT = (70, 58, 44, 255)  # #463A2C help-probe.png's soil, so the ground is the same in both pictures
DRILL_HEAD = (84, 89, 96, 255)  # #545960 the drill's round head, a shade under MACHINE_GREY

SIZE = (400, 2 * PAD + BLOCK_H)  # 400 x 80, as help-growth.png
TOP = PAD  # every copy's top edge
ROW = TOP + TILE  # a copy's middle row: the sockets sit in it
SCENES = (2 * BLOCK_W, 2 * BLOCK_W + TILE)  # a copy and the plot past it; two copies and a socket
GAP = SIZE[0] - 2 * PAD - sum(SCENES)  # 96: the room between the scenes, for the arrow alone

AREA = 3 * TILE  # the drill's mining area: the copy's first three columns
AREA_LINE = 2  # the amber line, just inside the copy's dark rim
GROUND = (RIM, RIM, AREA - RIM, AREA - RIM)  # the area inside the copy's rim: ground, edged by the amber line
FREE_TILES = ((3, 0), (3, 2))  # the copy's last column, outside the area: its other machines
DRILL = 26  # the drill's side: well over a tile, so the marker reads as sitting on it
DRILL_HEAD_R = DRILL / 2 - 3  # the round head, filling the drill's body but its rim and corners

ARROW_LEN, ARROW_HEAD_W, ARROW_HEAD_LEN = 36, 14, 10  # help-probe.png's arrow
DASH, DASH_GAP, DASH_CORNER = 4, 4, 6  # help-probe.png's dashed outline, pixels along an edge

# sensor()'s lump of ore and its glint in the 64-unit marker art, and the
# point they turn about: the ore on the ground is the ore the marker shows.
LUMP = ((21, 37), (26, 24), (37, 20), (45, 29), (43, 41), (30, 45))
GLINT = ((28, 28), (35, 24), (39, 30), (32, 33))
LUMP_MID, LUMP_SPAN = (33, 32.5), 25

# An ore field over the whole mining area, in pixels of the area: centre x,
# y, width, quarter turns, mirrored. Big lumps and small chips scattered
# unevenly, with dirt showing between them, so it reads as ore lying on the
# ground; an even grid of one size read as polka dots. The drill covers the
# middle of it, as a drill stands on its ore, and the ore round it shows.
PATCH = (
    (10.5, 11, 8.5, 0, False), (19, 9, 5, 2, True), (27, 10.5, 9, 1, False), (37.5, 11, 8, 3, True),
    (12, 20, 6, 1, True), (20, 18, 4.5, 3, False), (30, 19.5, 7.5, 2, True), (39, 21, 5, 0, False),
    (9.5, 28, 7, 2, False), (20, 26.5, 9, 0, True), (31.5, 29, 6, 3, False), (38, 30, 7.5, 1, True),
    (24, 34, 5, 1, False),
    (10.5, 38, 8, 3, True), (19, 38.5, 6, 0, False), (28.5, 37.5, 8.5, 2, False), (37.5, 39, 6, 1, True),
)


# ------------------------------------------------------------------- parts --


def sensor_cell():
    """The sensor marker with its lump of ore cleared out, leaving the four
    brackets. Ore under a mined-out copy's marker would read as ore left over.
    The lump lies inside the middle half of the 64-unit art and the brackets
    outside it, so clearing that square takes the lump alone: the cell matches
    brackets drawn on their own to within 1 in 255."""
    art = sensor()
    quarter = art.width // 4
    ImageDraw.Draw(art).rectangle([quarter, quarter, 3 * quarter - 1, 3 * quarter - 1], fill=(0, 0, 0, 0))
    return marker_cell(art)


def closed_socket_cell():
    """The socket marker greyed, as a button that cannot be pressed yet is,
    on its dark tile at full strength so it shows on any background."""
    art = socket()
    grey = art.convert("L")
    return marker_cell(Image.merge("RGBA", (grey, grey, grey, art.getchannel("A"))))


def machine_sprite():
    """block_sprite's small grey machine, cut out of it, so the ones added in
    the last column are the same pixels."""
    inset = (TILE - MACHINE) // 2
    tx, ty = MACHINES[0]
    x, y = tx * TILE + inset, ty * TILE + inset
    return block_sprite().crop((x, y, x + MACHINE, y + MACHINE))


def _place(point, cx, cy, scale, turns, mirror):
    """Move one point of sensor()'s lump onto a lump of the ore field."""
    x, y = point[0] - LUMP_MID[0], point[1] - LUMP_MID[1]
    if mirror:
        x = -x
    for _ in range(turns):  # quarter turns and the mirror give one lump eight looks
        x, y = -y, x
    return cx + x * scale, cy + y * scale


def ore_sprite():
    """The ore field over a mining area. Every lump, outline included, keeps
    a pixel clear of the amber line, so the line stays one clean stroke."""
    a = Art(AREA, AREA)
    lo = RIM + AREA_LINE + 2  # the line's inner edge, one clear pixel, then the lump's one-pixel outline
    for cx, cy, width, turns, mirror in PATCH:
        k = width / LUMP_SPAN
        rock = [_place(p, cx, cy, k, turns, mirror) for p in LUMP]
        assert all(lo <= v <= AREA - lo for p in rock for v in p), "lump too close to the amber line"
        a.shapes([rock], ORE_ROCK, outline=1)
        a.d.polygon(a._px([_place(p, cx, cy, k, turns, mirror) for p in GLINT]), fill=ORE_GLINT)
    return a.done()


def area_sprite():
    """The amber square the map draws round the area a waiting copy watches."""
    a = Art(AREA, AREA)
    inner = RIM + AREA_LINE
    a.rect(GROUND, SENSOR_AMBER)
    a.rect((inner, inner, AREA - inner, AREA - inner), (0, 0, 0, 0))
    return a.done()


def drill_sprite():
    """A mining drill seen from above: a grey machine, ringed in ink like the
    copy's small machines but much bigger, with a round head in its body."""
    a = Art(DRILL, DRILL)
    a.rect((0, 0, DRILL, DRILL), INK)
    a.rect((1, 1, DRILL - 1, DRILL - 1), MACHINE_GREY)
    a.disc(DRILL / 2, DRILL / 2, DRILL_HEAD_R, DRILL_HEAD, outline=1)
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


def plot_sprite():
    """Where the next copy will go: the ground there, its ore in the same
    place as in a copy, and a copy's outline dashed in the paper's grid blue,
    RIM wide, on the copy's own edge."""
    a = Art(BLOCK_W, BLOCK_H)
    a.rect((0, 0, BLOCK_W, BLOCK_H), DIRT)
    for x0, x1 in _dashes(BLOCK_W):
        a.rect((x0, 0, x1, RIM), PAPER_GRID)
        a.rect((x0, BLOCK_H - RIM, x1, BLOCK_H), PAPER_GRID)
    for y0, y1 in _dashes(BLOCK_H):
        a.rect((0, y0, RIM, y1), PAPER_GRID)
        a.rect((BLOCK_W - RIM, y0, BLOCK_W, y1), PAPER_GRID)
    plot = a.done()
    plot.alpha_composite(ore_sprite())
    return plot


def arrow_sprite():
    """White block arrow pointing right, help-probe.png's "becomes" arrow."""
    a = Art(ARROW_LEN, OP_SIZE)
    mid = OP_SIZE / 2
    tail, tip = (OP_RIM + 1, mid), (ARROW_LEN - OP_RIM - 1, mid)
    a.shapes([arrow(tail, tip, OP_BAR, ARROW_HEAD_W, ARROW_HEAD_LEN)], WHITE, outline=OP_RIM)
    return a.done()


def mining_copy(ore):
    """One copy of the mining design, with its ore still there or mined out.

    Inside the amber line the copy shows the ground under it: the sensor
    looks at the ground, not at the copy. block_sprite's own two machines lie
    inside the area, so the ground covers them; the copy's other machines
    stand in its last column, which makes that column read as part of it."""
    assert all(tx < AREA // TILE for tx, _ in MACHINES), "the ground must cover the paper's machines"
    sheet = block_sprite()
    x0, y0, x1, y1 = GROUND
    ImageDraw.Draw(sheet).rectangle([x0, y0, x1 - 1, y1 - 1], fill=DIRT)
    if ore:
        sheet.alpha_composite(ore_sprite())
    sheet.alpha_composite(area_sprite())
    inset = (TILE - MACHINE) // 2
    for tx, ty in FREE_TILES:
        sheet.alpha_composite(machine_sprite(), (tx * TILE + inset, ty * TILE + inset))
    corner = (AREA - DRILL) // 2  # the drill in the middle of its area, the sensor in the middle of it
    sheet.alpha_composite(drill_sprite(), (corner, corner))
    sheet.alpha_composite(sensor_cell(), (TILE, TILE))
    return sheet


# ----------------------------------------------------------------- picture --


def draw():
    """The two scenes: waiting on ore, then mined out and grown."""
    sheet = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    full, mined, closed = mining_copy(ore=True), mining_copy(ore=False), closed_socket_cell()

    x1 = PAD  # scene 1: ore left, so the socket stays shut and the next copy is only a plan
    sheet.alpha_composite(full, (x1, TOP))
    sheet.alpha_composite(plot_sprite(), (x1 + BLOCK_W, TOP))  # it starts on the socket's tile
    sheet.alpha_composite(closed, (x1 + BLOCK_W, ROW))

    x2 = x1 + SCENES[0] + GAP  # scene 2: mined out, and the next copy stands on the plot
    sheet.alpha_composite(mined, (x2, TOP))
    sheet.alpha_composite(full, (x2 + BLOCK_W, TOP))
    sheet.alpha_composite(closed, (x2 + 2 * BLOCK_W, ROW))

    gap_left, mid = x1 + SCENES[0], (SIZE[1] - OP_SIZE) // 2  # the arrow centred in the gap, on the middle row
    sheet.alpha_composite(arrow_sprite(), (gap_left + (GAP - ARROW_LEN) // 2, mid))
    return sheet


if __name__ == "__main__":
    draw().save(sys.argv[1])
