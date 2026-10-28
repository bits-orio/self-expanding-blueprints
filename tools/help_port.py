"""Help diagram for the port, help-port.png (400x80), no text. Left to right:

1. The blueprint builder: a light blue combinator with red and green wire
   terminals on each end. Its screen shows a Write request: a copy number
   (two pips on a dark plate) and one signal, an iron gear.
2. Write and Read: two matching white arrows, one out to the copies and one
   back, like the two arrows on the port marker itself.
3. Three copies of one build: a constant combinator with the port marker on
   it, wired in green to an assembler. A plate under each copy numbers it
   with one, two and three pips, in the same style as the builder's plate.
   Only copy two changes: its port is ringed, the gear sits on the ring
   (what the port now holds), and its assembler shows the gear (what it now
   makes). The other two assemblers have no recipe.

The gear is the one thing the eye can follow from the builder to the port to
the assembler. It is one signal on purpose: three signals would echo copy
three's three pips and suggest that the count of signals picks the copy.

Built like help-growth.png (tools/seb_help.py): one pixel per art unit, small
supersampled sprites pasted on whole pixels so every rim and grid line stays
crisp, and one copy sprite pasted three times so the copies are identical.
Run from the tools folder:  python3 help_port.py <out.png>
"""

import math
import sys

from PIL import Image, ImageDraw

from seb_art import (
    HIGHLIGHT, INK, MACHINE_GREY, PAPER_BLUE, PAPER_NIGHT, WHITE, Art, arrow, facing, port,
)
from seb_help import (
    BLOCK_H, BLOCK_W, MACHINE, MACHINES, OP_RIM, PAD, RIM, RING, RING_RADIUS, TILE, block_sprite, marker_cell,
)

SIZE = (400, 80)

# New colours.
BUILDER_BLUE = (158, 204, 255, 255)  # #9ECCFF the builder's tint (r=0.62 g=0.80 b=1.00) applied to white
WIRE_RED = (228, 62, 30, 255)  # #E43E1E Factorio's red circuit wire
WIRE_GREEN = (120, 200, 70, 255)  # #78C846 Factorio's green circuit wire, lifted so 2 px show on blue paper
GEAR_STEEL = (196, 202, 210, 255)  # #C4CAD2 the iron gear: pale steel, so it shows on a dark slot

TOP = PAD  # the copies' band, where help-growth.png has its copies; everything else centres on it
TARGET = 2  # the copy the builder writes to and reads from

# Values as Factorio's windows show them: on dark slots.
PIP, PIP_GAP = 8, 1  # a copy number's round white pips, rim included, and the space between two
SCREEN = 14  # the builder's slots, and the gear on the target's port: a gear 12 px across
PLATE = 12  # the plates under the copies, as tall as the room under the copies allows
PLATE_GAP = 2  # between a copy and its plate
GEAR_TEETH = 8  # few enough that each tooth still shows at 12 px

# The builder, lying the way a left-to-right circuit is laid out. It is 2 x 1
# tiles in the game, drawn bigger so its screen reads.
BUILDER_W, BUILDER_H = 70, 32  # terminal to terminal
KNOB_W, KNOB_H = 6, 18  # a wire terminal on each end, red over green, centred on it
SCREEN_GAP = 2  # between the copy number and the signal on its screen

OP_W, OP_H = 36, 26  # the Write and Read arrows' canvas
WRITE_Y, READ_Y = 7, 19  # their centre lines, leaving room for each head and its rim
COPY_GAP = 12  # room between two copies, so each reads as a copy of its own

# Inside a copy: the port's combinator in the top left corner, so the gear it
# holds can sit on its ring above the copy, and the assembler on the right.
BODY_RIM = 2  # the combinator's grey body showing round the marker on it
BODY = TILE + 2 * BODY_RIM
TERM_W, TERM_H = 3, 12  # the combinator's wire terminals on its right side, red over green
PORT_X = PORT_Y = RIM + 1  # the combinator's corner: one pixel of paper inside the copy's rim
ASSEMBLER = 24  # schematic like every machine here; the game's is 3 x 3 tiles
ASSEMBLER_X = BLOCK_W - RIM - 2 - ASSEMBLER  # two pixels of paper before the rim
ASSEMBLER_Y = (BLOCK_H - ASSEMBLER) // 2
RECIPE = SCREEN  # the assembler's recipe slot, the same size as the gear's other slots
WIRE = 2  # the wire's width
WIRE_Y = PORT_Y + BODY // 2 + 2  # level with the middle of the green terminal

COPIES_W = 3 * BLOCK_W + 2 * COPY_GAP
X_BUILDER = PAD
X_COPIES = SIZE[0] - PAD - COPIES_W
X_OP = (X_BUILDER + BUILDER_W + X_COPIES - OP_W) // 2  # centred in the room between


# ------------------------------------------------------------------ values --


def slot(w, h):
    """A dark rounded slot, the way Factorio's windows frame a value."""
    a = Art(w, h)
    a.rounded((0, 0, w, h), 3, INK)
    a.rounded((1, 1, w - 1, h - 1), 2, PAPER_NIGHT)
    return a.done()


def gear_outline(c, r_out, r_root):
    """An iron gear's outline round (c, c): GEAR_TEETH flat-topped teeth,
    each a trapezoid from the root circle out to the tip circle."""
    step = 2 * math.pi / GEAR_TEETH
    base, tip = step * 0.31, step * 0.225  # half a tooth's width at its root and at its tip
    pts = []
    for i in range(GEAR_TEETH):
        a = i * step - math.pi / 2  # a tooth straight up, so the gear sits square
        for r, da in ((r_root, -base), (r_out, -tip), (r_out, tip), (r_root, base)):
            pts.append((c + r * math.cos(a + da), c + r * math.sin(a + da)))
    return pts


def gear_slot(n):
    """The iron gear signal on its slot, n pixels square. The hole is the
    slot's own dark showing through, which is what makes it read as a gear
    and not a flower."""
    a = Art(n, n)
    a.rounded((0, 0, n, n), 3, INK)
    a.rounded((1, 1, n - 1, n - 1), 2, PAPER_NIGHT)
    c, r = n / 2, n / 2 - 2  # one pixel of slot, then the gear's own rim
    a.shapes([gear_outline(c, r, r * 0.72)], GEAR_STEEL, outline=1)
    a.disc(c, c, r * 0.3, PAPER_NIGHT, outline=0)
    return a.done()


def pips_sprite(n):
    """A copy's number as n round white pips in a row, each with a dark rim.
    Round, so they are never taken for a signal."""
    a = Art(n * PIP + (n - 1) * PIP_GAP, PIP)
    r = PIP / 2
    for i in range(n):
        a.disc(i * (PIP + PIP_GAP) + r, r, r - OP_RIM, WHITE, outline=OP_RIM)
    return a.done()


def number_plate(n, h):
    """A copy's number on a dark plate h tall: the builder shows its request's
    copy number on one, and every copy carries its own under it."""
    pips = pips_sprite(n)
    pad = (h - PIP) // 2
    plate = slot(pips.width + 2 * pad, h)
    plate.alpha_composite(pips, (pad, pad))
    return plate


# ------------------------------------------------------------- the builder --


def builder_sprite():
    """The blueprint builder: a light blue box with a wire terminal on each
    end, capped red over green, and a screen showing its request: the copy's
    number and the signal to put in that copy's port."""
    a = Art(BUILDER_W, BUILDER_H)
    k, mid = KNOB_W, BUILDER_H // 2
    top, bottom = mid - KNOB_H // 2, mid + KNOB_H // 2
    for x in (0, BUILDER_W - k):  # input on the left, output on the right
        a.rect((x, top, x + k, bottom), INK)  # the rim, and a dark seam between the caps
        a.rect((x + 1, top + 1, x + k - 1, mid - 1), WIRE_RED)
        a.rect((x + 1, mid + 1, x + k - 1, bottom - 1), WIRE_GREEN)
    a.rounded((k - 1, 0, BUILDER_W - k + 1, BUILDER_H), 4, INK)
    a.rounded((k + 1, 2, BUILDER_W - k - 1, BUILDER_H - 2), 2, BUILDER_BLUE)
    body = a.done()

    number, signal = number_plate(TARGET, SCREEN), gear_slot(SCREEN)
    x = (BUILDER_W - (number.width + SCREEN_GAP + signal.width)) // 2
    y = (BUILDER_H - SCREEN) // 2
    body.alpha_composite(number, (x, y))
    body.alpha_composite(signal, (x + number.width + SCREEN_GAP, y))
    return body


def arrows_sprite():
    """Write over Read: a white arrow out to the copies and one back, the same
    size, so they read as two directions and not as more and less."""
    a = Art(OP_W, OP_H)
    head = dict(shaft_w=4, head_w=12, head_len=7)
    a.shapes([arrow((OP_RIM, WRITE_Y), (OP_W - OP_RIM, WRITE_Y), **head)], WHITE, outline=OP_RIM)
    a.shapes([arrow((OP_W - OP_RIM, READ_Y), (OP_RIM, READ_Y), **head)], WHITE, outline=OP_RIM)
    return a.done()


# --------------------------------------------------------------- the copies --


def plain_copy():
    """block_sprite with its two small machines painted out: this build holds
    a combinator and an assembler instead. Each machine sits inside one tile
    on flat paper, clear of the grid lines, so filling its box with paper
    restores the sheet exactly."""
    sheet = block_sprite()
    paint = ImageDraw.Draw(sheet)
    inset = (TILE - MACHINE) // 2
    for tx, ty in MACHINES:
        x, y = tx * TILE + inset, ty * TILE + inset
        paint.rectangle([x, y, x + MACHINE - 1, y + MACHINE - 1], fill=PAPER_BLUE)
    return sheet


def port_combinator():
    """The port as the player builds it: a constant combinator, grey with its
    red and green wire terminals on the right, and the port marker placed on
    top of it. A port looks the same whichever way it faces, so the marker is
    turned west first and marker_cell's turn to east brings it back upright:
    two lossless quarter turns."""
    a = Art(BODY + TERM_W, BODY)
    mid = BODY // 2
    a.rect((BODY - 1, mid - TERM_H // 2, BODY + TERM_W, mid + TERM_H // 2), INK)
    a.rect((BODY, mid - TERM_H // 2 + 1, BODY + TERM_W - 1, mid - 1), WIRE_RED)
    a.rect((BODY, mid + 1, BODY + TERM_W - 1, mid + TERM_H // 2 - 1), WIRE_GREEN)
    a.rect((0, 0, BODY, BODY), INK)
    a.rect((1, 1, BODY - 1, BODY - 1), MACHINE_GREY)
    combinator = a.done()
    combinator.alpha_composite(marker_cell(facing(port(), "west")), (BODY_RIM, BODY_RIM))
    return combinator


def assembler_sprite(making):
    """An assembler as Factorio's alt mode shows it: a grey machine with its
    recipe on a dark slot in the middle, or the slot empty when it has none."""
    a = Art(ASSEMBLER, ASSEMBLER)
    a.rect((0, 0, ASSEMBLER, ASSEMBLER), INK)
    a.rect((1, 1, ASSEMBLER - 1, ASSEMBLER - 1), MACHINE_GREY)
    machine = a.done()
    recipe = gear_slot(RECIPE) if making else slot(RECIPE, RECIPE)
    machine.alpha_composite(recipe, ((ASSEMBLER - RECIPE) // 2, (ASSEMBLER - RECIPE) // 2))
    return machine


def port_ring():
    """The help-growth ring, made to wrap the port's whole combinator rather
    than one tile: RING pixels thick, just outside the grey body."""
    n = BODY + 2 * RING
    a = Art(n, n)
    a.rounded((0, 0, n, n), RING_RADIUS, HIGHLIGHT)
    a.rounded((RING, RING, n - RING, n - RING), RING_RADIUS - RING, (0, 0, 0, 0))
    return a.done()


def copy_sprite(target):
    """One copy of the build: its port wired in green to its assembler. On
    the target copy the port is ringed and the assembler makes the gear. The
    ring goes down before the combinator, so the terminals cross it and the
    target's port looks like every other copy's."""
    sheet = plain_copy()
    wire_x = PORT_X + BODY + TERM_W  # from the terminal's rim to the assembler's
    wire = Image.new("RGBA", (ASSEMBLER_X - wire_x + 1, WIRE), WIRE_GREEN)
    sheet.alpha_composite(wire, (wire_x, WIRE_Y))
    if target:
        sheet.alpha_composite(port_ring(), (PORT_X - RING, PORT_Y - RING))
    sheet.alpha_composite(port_combinator(), (PORT_X, PORT_Y))
    sheet.alpha_composite(assembler_sprite(making=target), (ASSEMBLER_X, ASSEMBLER_Y))
    return sheet


# ------------------------------------------------------------------ picture --


def draw():
    sheet = Image.new("RGBA", SIZE, (0, 0, 0, 0))

    # The builder, its request on its screen, then Write and Read.
    sheet.alpha_composite(builder_sprite(), (X_BUILDER, TOP + (BLOCK_H - BUILDER_H) // 2))
    sheet.alpha_composite(arrows_sprite(), (X_OP, TOP + (BLOCK_H - OP_H) // 2))

    # Three copies of the same build, each numbered on a plate under it. Only
    # the target's assembler has a recipe: the gear the builder put in its port.
    lefts = [X_COPIES + i * (BLOCK_W + COPY_GAP) for i in range(3)]
    for number, x in enumerate(lefts, start=1):
        sheet.alpha_composite(copy_sprite(target=number == TARGET), (x, TOP))
        plate = number_plate(number, PLATE)
        sheet.alpha_composite(plate, (x + (BLOCK_W - plate.width) // 2, TOP + BLOCK_H + PLATE_GAP))

    # The gear the target's port now holds, sitting on its ring above the copy.
    px, py = lefts[TARGET - 1] + PORT_X, TOP + PORT_Y
    sheet.alpha_composite(gear_slot(SCREEN), (px + (BODY - SCREEN) // 2, py - RING - SCREEN))
    return sheet


if __name__ == "__main__":
    draw().save(sys.argv[1])
