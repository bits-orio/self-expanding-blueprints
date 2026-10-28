#!/usr/bin/env python3
"""Generate thumbnail.png: the mod-portal card. It keeps the house frame
shared with Land Title Registry, Multi-Team Support and Blueprint Primer
(512x512, a thin square frame inset 14 px, DejaVu Sans Bold, a dark halo
under white text) and lays the name out as a column down the left edge:

    S elf
    E xpanding
    B lueprints

  - night blueprint paper: a darker take on Blueprint Primer's paper, so the
    coloured initials carry,
  - the initials in the overlay's growth-loop colours, read from
    scripts/render/overlay.lua (the single source of truth, as Land Title
    Registry reads its state colours): S an open socket, E a socket waiting
    at a gate, B a copy building. Retinting the overlay retints the card,
  - each initial lit by a soft glow of its own colour, added as light (a
    screen blend): a glow laid over the paper as a veil darkens next to the
    glyph and reads as an outline,
  - small green arrows down the column: S grows into E grows into B.

Drawn at SUPERSAMPLE times the size and box-filtered down: a box filter is
exact coverage and cannot ring around the bright glyph edges the way Lanczos
does.

Run from the repo root:  python3 tools/gen_thumbnail.py
"""

import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from gen_graphics import arrow

ROOT = Path(__file__).resolve().parent.parent

SIZE = 512
SUPERSAMPLE = 4
S = SIZE * SUPERSAMPLE

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

PAPER = (14, 34, 66, 255)
PAPER_MINOR = (28, 60, 104, 255)
PAPER_MAJOR = (46, 92, 150, 255)
FRAME = (70, 130, 200, 255)
FRAME_INSET = 14
FRAME_WIDTH = 8
WORD_FILL = (250, 252, 255)
ARROW_FILL = (76, 200, 90, 230)

# The column: initials' size and left edge, baseline pitch, first baseline,
# the gap between an initial and the rest of its word, and where words end.
INITIAL_SIZE = 150
COLUMN_LEFT = 46
PITCH = 148
FIRST_BASELINE = 162
WORD_GAP = 6
WORD_RIGHT = 476
WORDS = (("S", "elf", "open"), ("E", "xpanding", "waiting"), ("B", "lueprints", "building"))

GLOW_RADIUS = 10
GLOW_STRENGTH = 0.85
HALO_RADIUS = 8
HALO_STRENGTH = 1.5


def px(v):
    return round(v * SUPERSAMPLE)


def overlay_colors():
    """{name: (r, g, b)} from the COLOR table of scripts/render/overlay.lua."""
    text = (ROOT / "scripts/render/overlay.lua").read_text()
    pattern = r"(\w+)\s*=\s*\{\s*r\s*=\s*([\d.]+),\s*g\s*=\s*([\d.]+),\s*b\s*=\s*([\d.]+)"
    return {m[1]: tuple(round(float(v) * 255) for v in m.group(2, 3, 4)) for m in re.finditer(pattern, text)}


def paper(img):
    """32 px cells with a heavier line every fourth, and the house frame."""
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S, S], fill=PAPER)
    for k in range(1, SIZE // 32):
        colour, width = (PAPER_MAJOR, px(2)) if k % 4 == 0 else (PAPER_MINOR, px(1))
        d.line([(px(k * 32), 0), (px(k * 32), S)], fill=colour, width=width)
        d.line([(0, px(k * 32)), (S, px(k * 32))], fill=colour, width=width)
    far = S - 1 - px(FRAME_INSET)
    d.rectangle([px(FRAME_INSET)] * 2 + [far, far], outline=FRAME, width=px(FRAME_WIDTH))


def column_arrows(img, big):
    """An arrow in each gap between initials, centred on the column."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = COLUMN_LEFT + d.textlength("E", font=big) / SUPERSAMPLE / 2
    for row in range(len(WORDS) - 1):
        base = FIRST_BASELINE + row * PITCH
        pts = arrow((cx, base + 4), (cx, base + 36), shaft_w=10, head_w=28, head_len=16)
        d.polygon([(px(x), px(y)) for x, y in pts], fill=ARROW_FILL)
    img.alpha_composite(layer)


def word_font(d, big):
    """The largest size at which every rest-of-word fits before WORD_RIGHT."""
    for size in range(72, 19, -1):
        font = ImageFont.truetype(FONT, px(size))
        if all(px(COLUMN_LEFT) + d.textlength(i, font=big) + px(WORD_GAP) + d.textlength(rest, font=font)
               <= px(WORD_RIGHT) for i, rest, _ in WORDS):
            return font
    return font


def blurred(layer, radius, strength):
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(px(radius)))
    return alpha.point(lambda v: min(255, int(v * strength)))


def light(img, layer, colour):
    """Adds a glow of `colour` around the layer's glyph as light."""
    a = blurred(layer, GLOW_RADIUS, GLOW_STRENGTH)
    glow = Image.merge("RGB", [a.point(lambda v, c=c: v * c // 255) for c in colour])
    img.paste(ImageChops.screen(img.convert("RGB"), glow).convert("RGBA"))


def halo_under(img, layer):
    """The house dark halo: a blur of the layer's coverage, then the layer."""
    halo = Image.new("RGBA", img.size, (0, 0, 0, 0))
    halo.putalpha(blurred(layer, HALO_RADIUS, HALO_STRENGTH))
    img.alpha_composite(halo)
    img.alpha_composite(layer)


def column(img, colours):
    big = ImageFont.truetype(FONT, px(INITIAL_SIZE))
    initials = Image.new("RGBA", img.size, (0, 0, 0, 0))
    words = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dw = ImageDraw.Draw(words)
    small = word_font(dw, big)
    column_arrows(img, big)
    for row, (initial, rest, state) in enumerate(WORDS):
        base = px(FIRST_BASELINE + row * PITCH)
        one = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(one).text((px(COLUMN_LEFT), base), initial, font=big, fill=colours[state], anchor="ls")
        light(img, one, colours[state])
        initials.alpha_composite(one)
        x = px(COLUMN_LEFT) + dw.textlength(initial, font=big) + px(WORD_GAP)
        dw.text((x, base), rest, font=small, fill=WORD_FILL, anchor="ls")
    img.alpha_composite(initials)
    halo_under(img, words)


def build():
    img = Image.new("RGBA", (S, S))
    paper(img)
    column(img, overlay_colors())
    return img.resize((SIZE, SIZE), Image.Resampling.BOX).convert("RGB")


def main():
    out = ROOT / "thumbnail.png"
    build().save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
