"""Drawing primitives, palette and marker art for Self-Expanding Blueprints'
graphics. tools/gen_graphics.py writes the files; see its docstring for the
list and the style rules every picture follows.

Style follows the other mods in the family: flat colours, crisp dark
outlines, no gradients, no text. Shapes are drawn at SS times the final size
and downscaled with an area-average filter, which anti-aliases every
diagonal in a single pixel and leaves no halo. Nothing is random and nothing
is timestamped, so a rerun rewrites identical bytes.

The marker sprites are drawn at scale 0.5 on a 1x1 tile, which is 32 px on
screen at zoom 1, and half that when zoomed out. So they are built bold:
wide heads, thick shafts, outlines 3 units wide (1.5 px at 32 px). The
overlay shapes are tinted at draw time. They stay pure white inside with a
dark outline, because tint multiplies: white takes the colour and the dark
rim stays dark.

Art coordinates are 0..64, y down. Outlines are drawn OUTSIDE the nominal
shape edge, so a polygon keeps the size it was designed at and its outline
adds OUTLINE units around it.
"""

import math

from PIL import Image, ImageDraw

SIZE = 64  # every output file is SIZE x SIZE
# Supersampling factor: art is drawn at SIZE*SS, then downscaled. PIL fills one
# pixel past the right and bottom edge of every polygon, so each shape drifts by
# half a supersample pixel. At 32x that is a few percent of one edge pixel, below
# anything the eye can pick out; at 8x it showed as a grey strip along the inner
# edge of the rim on white shapes. The whole set still builds in well under a second.
SS = 32

# Pillow 9.1-9.3 warn on the old Image.BOX / Image.ROTATE_* spellings and
# older Pillow lacks the enums; this picks whichever exists.
_RESAMPLING = getattr(Image, "Resampling", Image)
_TRANSPOSE = getattr(Image, "Transpose", Image)
# Box filter on the premultiplied image is exact area coverage. Lanczos is
# sharper in theory, but its ripples leave faint alpha specks around every
# shape and nudge colours next to the outline, which a clean transparent
# background should not have. At this supersampling the box edge is already a
# single pixel wide.
DOWNSCALE = _RESAMPLING.BOX

# Palette. One near-black ink for every outline, so the whole set shares a rim.
INK = (28, 30, 34, 255)
WHITE = (255, 255, 255, 255)
SOCKET_GREEN = (76, 175, 80, 255)  # #4CAF50
SOCKET_PLUG = (46, 125, 50, 255)  # #2E7D32, the plug reads as a separate part
ENTRY_BLUE = (33, 150, 243, 255)  # #2196F3
ENTRY_BRACKET = (21, 101, 192, 255)  # #1565C0
ANCHOR_GREY = (158, 158, 158, 255)  # #9E9E9E
PAPER_BLUE = (43, 95, 158, 255)  # #2B5F9E blueprint paper
PAPER_GRID = (96, 146, 204, 255)  # #6092CC lighter grid lines
PAPER_NIGHT = (14, 34, 66, 255)  # #0E2242 the thumbnail's night paper: a dark tile for markers
MACHINE_GREY = (122, 128, 136, 255)  # #7A8088 duller than ANCHOR_GREY, never outshouts an arrow
HIGHLIGHT = (255, 224, 130, 255)  # #FFE082 the ring that marks a tile in the help diagram
SENSOR_AMBER = (242, 179, 61, 255)  # #F2B33D, the overlay's colour for copies waiting on ore
ORE_ROCK = (141, 110, 99, 255)  # #8D6E63
ORE_GLINT = (176, 190, 197, 255)  # #B0BEC5
PROBE_VIOLET = (171, 71, 188, 255)  # #AB47BC
PORT_TEAL = (38, 166, 154, 255)  # #26A69A
DECON_RED = (229, 57, 53, 255)  # #E53935: Keep clear's brackets and cross, the deconstruction planner's red

OUTLINE = 3  # marker and card outline width, art units
THIN = 2  # overlay glyph outline width, art units


# ---------------------------------------------------------------- drawing --


class Art:
    """A transparent canvas drawn at SS times the scale: SIZE x SIZE unless
    asked otherwise, one pixel per art unit in the result.

    Every method takes art units (0..64 on the default canvas), not
    supersampled pixels.
    """

    def __init__(self, width=SIZE, height=SIZE):
        self.size = (width, height)
        self.im = Image.new("RGBA", (width * SS, height * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def _px(self, pts):
        return [(round(x * SS), round(y * SS)) for x, y in pts]

    def _stroke(self, pts, width, color):
        """Closed outline of the given width, centred on the edges, round joins."""
        pts = self._px(pts)
        w = round(width * SS)
        r = w / 2
        for i, a in enumerate(pts):
            b = pts[(i + 1) % len(pts)]
            self.d.line([a, b], fill=color, width=w)
            self.d.ellipse([a[0] - r, a[1] - r, a[0] + r, a[1] + r], fill=color)

    def shapes(self, polys, fill, outline=OUTLINE, ink=INK):
        """Fill polygons and wrap them in a dark outline.

        All strokes go down before any fill, so shapes passed together fuse
        into one silhouette with a single rim and no seams between them.
        The stroke is twice the outline width and centred on the edge; the
        fill then covers its inner half, leaving the outer half as the rim.
        """
        for pts in polys:
            self._stroke(pts, outline * 2, ink)
        for pts in polys:
            self.d.polygon(self._px(pts), fill=fill)

    def disc(self, cx, cy, r, fill, outline=OUTLINE, ink=INK):
        for rad, color in ((r + outline, ink), (r, fill)):
            box = [(cx - rad) * SS, (cy - rad) * SS, (cx + rad) * SS, (cy + rad) * SS]
            self.d.ellipse(box, fill=color)

    def rounded(self, box, radius, fill):
        x0, y0, x1, y1 = (round(v * SS) for v in box)
        self.d.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=round(radius * SS), fill=fill)

    def rect(self, box, fill):
        x0, y0, x1, y1 = (round(v * SS) for v in box)
        self.d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=fill)

    def done(self):
        """Downscale to the final size."""
        return self.im.resize(self.size, DOWNSCALE)


def arrow(tail, tip, shaft_w, head_w, head_len):
    """Block arrow polygon from tail centre to tip, as 7 vertices tip first."""
    (tx, ty), (px, py) = tail, tip
    length = math.hypot(px - tx, py - ty)
    ux, uy = (px - tx) / length, (py - ty) / length  # along the arrow
    vx, vy = -uy, ux  # across it
    bx, by = px - ux * head_len, py - uy * head_len  # centre of the head's base
    s, h = shaft_w / 2, head_w / 2
    return [
        (px, py),
        (bx + vx * h, by + vy * h),
        (bx + vx * s, by + vy * s),
        (tx + vx * s, ty + vy * s),
        (tx - vx * s, ty - vy * s),
        (bx - vx * s, by - vy * s),
        (bx - vx * h, by - vy * h),
    ]


def cross(cx, cy, reach, half_w):
    """X polygon as 12 vertices: four flat-ended arms at 45 degrees.

    reach is the distance from the centre to the middle of each arm's end,
    half_w is half the thickness of a bar.
    """
    k = math.sqrt(0.5)
    n = half_w * math.sqrt(2)  # where two bars' edges cross, on an axis
    arms = ((k, -k), (k, k), (-k, k), (-k, -k))  # NE, SE, SW, NW, clockwise
    notches = ((cx + n, cy), (cx, cy + n), (cx - n, cy), (cx, cy - n))  # after each arm
    pts = []
    for (ux, uy), notch in zip(arms, notches):
        vx, vy = -uy, ux
        ex, ey = cx + ux * reach, cy + uy * reach
        pts += [(ex - vx * half_w, ey - vy * half_w), (ex + vx * half_w, ey + vy * half_w), notch]
    return pts


def clip(poly, box):
    """The part of a convex polygon inside box (x0, y0, x1, y1), cut against
    one side of the box at a time (Sutherland-Hodgman). Empty if none is."""
    x0, y0, x1, y1 = box
    for axis, limit, side in ((0, x0, 1), (0, x1, -1), (1, y0, 1), (1, y1, -1)):
        inside = [side * (p[axis] - limit) >= 0 for p in poly]
        cut = []
        for i, p in enumerate(poly):
            j = (i + 1) % len(poly)
            if inside[i]:
                cut.append(p)
            if inside[i] != inside[j]:  # the edge crosses this side: keep the crossing
                q = poly[j]
                t = (limit - p[axis]) / (q[axis] - p[axis])
                cut.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
        poly = cut
    return poly


def stripes(box, width, first, period=None):
    """Stripes over box (x0, y0, x1, y1), rising to the right: bands of x + y
    `width` wide, one every `period` (every other band by default), the first
    starting at x + y = first. Returns the stripes as polygons clipped to the
    box."""
    x0, y0, x1, y1 = box
    bands = []
    u = first
    while u < x1 + y1:  # a band is the strip between the lines x + y = u and x + y = u + width
        band = clip([(u - y0, y0), (u + width - y0, y0), (u + width - y1, y1), (u - y1, y1)], box)
        if len(band) >= 3:
            bands.append(band)
        u += period or 2 * width
    return bands


# ------------------------------------------------------------------ images --


def socket():
    """Green arrow pointing north, its tail set on a small square plug.

    The tip reaches the top edge. The plug is a separate darker square, a
    little wider than the shaft and split from it by one outline width, so
    it reads as "plugs in here" even at 24 px.
    """
    a = Art()
    cx = 32
    tail = 40
    head = arrow((cx, tail), (cx, 5), shaft_w=12, head_w=46, head_len=25)
    plug_top = tail + OUTLINE
    plug = [(cx - 8, plug_top), (cx + 8, plug_top), (cx + 8, plug_top + 16), (cx - 8, plug_top + 16)]
    a.shapes([head], SOCKET_GREEN)
    a.shapes([plug], SOCKET_PLUG)
    return a.done()


def entry():
    """Blue arrow pointing north, its tip inside a U bracket open at the bottom.

    The bracket sits at the top, which is what separates this at a glance
    from the socket: a flat bar across the top instead of a point.
    """
    a = Art()
    cx = 32
    bracket = [
        (7, 5), (57, 5), (57, 29), (49, 29), (49, 13), (15, 13), (15, 29), (7, 29),
    ]
    shaft = arrow((cx, 59), (cx, 22), shaft_w=16, head_w=36, head_len=20)
    a.shapes([bracket], ENTRY_BRACKET)
    a.shapes([shaft], ENTRY_BLUE)
    return a.done()


def brackets(lo=6, hi=58, t=7, arm=19):
    """Four corner brackets on a tile's edge (square edges, thickness, arm
    length), as polygons: the ore sensor's, and Keep clear's."""
    shapes = []
    for x, y, dx, dy in ((lo, lo, 1, 1), (hi, lo, -1, 1), (lo, hi, 1, -1), (hi, hi, -1, -1)):
        shapes.append([
            (x, y), (x + dx * arm, y), (x + dx * arm, y + dy * t),
            (x + dx * t, y + dy * t), (x + dx * t, y + dy * arm), (x, y + dy * arm),
        ])
    return shapes


def bar(start, end, width):
    """A straight band from start to end, `width` across, as a polygon."""
    (ax, ay), (bx, by) = start, end
    length = math.hypot(bx - ax, by - ay)
    nx, ny = -(by - ay) / length * width / 2, (bx - ax) / length * width / 2
    return [(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)]


def sensor():
    """Four amber corner brackets around a lump of ore: "watch the ore in here".

    A sensor watches a square, not a way, so one file serves every facing.
    The brackets sit on the tile's edge and leave its middle open, so the
    ore reads even at 16 px.
    """
    a = Art()
    a.shapes(brackets(), SENSOR_AMBER)
    a.shapes([[(21, 37), (26, 24), (37, 20), (45, 29), (43, 41), (30, 45)]], ORE_ROCK)
    a.d.polygon(a._px([(28, 28), (35, 24), (39, 30), (32, 33)]), fill=ORE_GLINT)
    return a.done()


def probe():
    """A violet map pin standing on its tile, a white dot in its head.

    A probe states a fact about the tile under its point, so the point
    reaches the tile's middle-bottom and the head fills the top.
    """
    a = Art()
    head_r, cx, cy = 17, 32, 24
    k = math.sqrt(0.5)
    head = [(cx + head_r * math.cos(t * math.pi / 24), cy + head_r * math.sin(t * math.pi / 24)) for t in range(48)]
    pin = [(cx - head_r * k, cy + head_r * k), (cx, 58), (cx + head_r * k, cy + head_r * k)]
    a.shapes([head, pin], PROBE_VIOLET)  # passed together, they share one rim
    a.disc(cx, cy, 6, WHITE, outline=0)
    return a.done()


def port():
    """A teal box with an arrow each way: the combinator a circuit reads and
    writes through."""
    a = Art()
    a.shapes([[(12, 12), (52, 12), (52, 52), (12, 52)]], PORT_TEAL)
    a.shapes([arrow((14, 26), (34, 26), shaft_w=6, head_w=16, head_len=9)], WHITE, outline=THIN)
    a.shapes([arrow((50, 40), (30, 40), shaft_w=6, head_w=16, head_len=9)], WHITE, outline=THIN)
    return a.done()


def clear():
    """Four red corner brackets around a red cross: "nothing may stand here".

    The brackets are the ore sensor's, as both markers name a tile of the
    design's ground; the red and the cross are the deconstruction planner's,
    as the tile must stay bare. Two thick strokes, no hatching: the first
    plates, hatched in ink and then in thin red stripes, either shouted or
    blurred among the design's buildings. A Keep clear tile is the same
    whichever way a design faces, so one file serves every facing.
    """
    a = Art()
    a.shapes(brackets(), DECON_RED)
    a.shapes([bar((22, 22), (42, 42), 8), bar((42, 22), (22, 42), 8)], DECON_RED)
    return a.done()


def frame_dash():
    """A piece of the frame round the design in hand while growing, facing
    north: a dash on its tile's outer edge, so a row of them is a dashed
    line, as the map draws the next copy's outline. A blueprint preview tints
    what it holds green, or red where blocked, so the dash is white: it takes
    the tint brightest."""
    a = Art()
    a.rect((12, 0, 52, 10), WHITE)
    return a.done()


def frame_icon():
    """The frame piece's item icon, never shown to players: four dashes round
    a tile."""
    a = Art()
    for box in ((12, 0, 52, 10), (12, 54, 52, 64), (0, 12, 10, 52), (54, 12, 64, 52)):
        a.rect(box, WHITE)
    return a.done()


def anchor():
    """Small grey dot. The anchor entity is internal and rarely on screen."""
    a = Art()
    a.disc(32, 32, 9, ANCHOR_GREY)
    return a.done()


def grow_tool():
    """Blueprint paper with a white block and two arrows leading away from it.

    The arrows go right and down: copies spreading out. A strip of paper
    shows between the block and each arrow, so the block stays a clean
    square even at 24 px. The grid pitch is 10 units, which puts a line on a
    whole pixel at 32 px, and the grid is symmetric about the middle.
    """
    a = Art()
    a.rounded((3, 3, 61, 61), 12, INK)
    a.rounded((6, 6, 58, 58), 9, PAPER_BLUE)
    for p in (16, 26, 36, 46):  # 2 units wide each
        a.rect((p, 6, p + 2, 58), PAPER_GRID)
        a.rect((6, p, 58, p + 2), PAPER_GRID)

    block = [(12, 12), (28, 12), (28, 28), (12, 28)]
    right = arrow((34, 20), (53, 20), shaft_w=8, head_w=18, head_len=11)
    down = arrow((20, 34), (20, 53), shaft_w=8, head_w=18, head_len=11)
    a.shapes([block], WHITE, outline=THIN)
    a.shapes([right, down], WHITE, outline=THIN)
    return a.done()


def overlay_arrow():
    """Plain white arrow pointing north, centred so rotating it about the
    middle of the sprite keeps it on its tile."""
    a = Art()
    a.shapes([arrow((32, 58), (32, 6), shaft_w=16, head_w=44, head_len=28)], WHITE, outline=THIN)
    return a.done()


def overlay_blocked():
    """Plain white bold X, centred."""
    a = Art()
    a.shapes([cross(32, 32, reach=29, half_w=7)], WHITE, outline=THIN)
    return a.done()


TURNS = {  # direction -> Pillow transpose that turns a north-facing image to it
    "north": None,
    "east": _TRANSPOSE.ROTATE_270,  # Pillow turns counter-clockwise
    "south": _TRANSPOSE.ROTATE_180,
    "west": _TRANSPOSE.ROTATE_90,
}


def facing(img, direction):
    turn = TURNS[direction]
    return img if turn is None else img.transpose(turn)
