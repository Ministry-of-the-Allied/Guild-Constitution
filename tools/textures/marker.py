"""Builds Media/marker.tga: the art for the NPC marker (ADDON_SPEC.md 10.18).

The marker is drawn like the game's own quest marker: a tall tapered "!" with a
round dot under it (a quest to pick up) or a "?" (one to hand in), each with a
vertical gradient, light at the top and strong at the bottom, lit as a rounded
solid (lighter on the upper left, a soft gloss), with no outline. Instead of Blizzard's gold, each look takes
its party's colours: the Ministry and Silverhand the blue of the Ministry
skin's page leather, the Exchange and the Crown their skin tokens (UI/Skin.lua,
Skin.accents; 9.3).

The colours are baked in (a gradient through three colours can't be made by
tinting white), so the sheet holds every look. One 512 x 256 sheet:

    row 0 (y 0..127)     eight cells of 64 x 128: the "!" in the four looks
                         (x 0, 64, 128, 192), then the "?" (x 256 .. 448)
    row 1 (y 128..255)   four cells of 128 x 128: the far arrow in the four looks

The look order is LOOKS below: Ministry, Silverhand, Exchange, Crown. The cells'
places are in UI/NPCMarkers.lua (Cell). Run from the repo root:

    python tools/textures/marker.py [preview.png]

Needs Pillow and numpy. The optional preview shows the four looks large, and at about the
size they are on screen over a name.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MEDIA = os.path.join(ROOT, "addon", "MinistryOfTheAllied", "Media") + os.sep
GW, GH = 64, 128  # a glyph cell
AW = 128          # an arrow cell
SS = 4            # drawn at 4x and shrunk, for smooth edges


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# The skin tokens (UI/Skin.lua, Skin.accents).
SH = {"PALE": "C9D6F5", "GEM": "2F5FD0", "TOP": "3460B4", "INK": "1B3570"}
EX = {"PALE": "F0C9BC", "TOP": "B8343C", "INK": "7A1219"}
CR = {"PALE": "E8C6DC", "TOP": "86296A", "INK": "58143F"}

# Each look: gradient stops (position 0 at the top, 1 at the bottom, colour).
# The Ministry's (and Silverhand's, the same design: Max, 12 Nov) is the blue of the
# Ministry skin's page leather (design/canvas-source/ministry.css, .win-leather): its
# brightest blue just under a lit top (as the others have their pale accent at the
# top), going down to its darkest blues.
LEATHER = ["3360B4", "1E3B7C", "142B5E"]
LIT_BLUE = "7FA6F0"  # the leather's blue, lit: the top of the marker
BLUE = [(0.0, LIT_BLUE), (0.42, LEATHER[0]), (0.8, LEATHER[1]), (1.0, LEATHER[2])]
LOOKS = [
    ("Ministry", BLUE),
    ("Silverhand", BLUE),
    ("Exchange", [(0.0, EX["PALE"]), (0.55, EX["TOP"]), (1.0, EX["INK"])]),
    ("Crown", [(0.0, CR["PALE"]), (0.55, CR["TOP"]), (1.0, CR["INK"])]),
]


def ramp_at(stops, t):
    t = max(0.0, min(1.0, t))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            f = (t - p0) / (p1 - p0) if p1 > p0 else 0
            a, b = hexrgb(c0), hexrgb(c1)
            return tuple(round(a[i] + (b[i] - a[i]) * f) for i in range(3))
    return hexrgb(stops[-1][1])


def gradient(size, stops, y0, y1):
    """A vertical gradient image: stops run from row y0 to row y1."""
    w, h = size
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        px[0, y] = ramp_at(stops, (y - y0) / max(1, y1 - y0))
    return col.resize((w, h))


# ---------------------------------------------------------------------------
# Shapes (masks at SS x size)
# ---------------------------------------------------------------------------

def bang_masks():
    """The "!": its bar and its dot, as two masks (each gets its own gradient)."""
    w, h = GW * SS, GH * SS
    cx = w / 2
    r0 = 15.5 * SS   # half the bar's width at the top
    rb = 4.2 * SS    # the rounded tip's radius
    top, tip = 5 * SS, 82 * SS  # the bar's top and the centre of its tip
    cap = r0 * 0.95  # the height of the top's rounded cap
    pts = []
    # down the left side: the body, near-parallel at first, then tapering
    n = 80
    for i in range(n + 1):
        s = i / n
        y = top + cap + (tip - top - cap) * s
        hw = rb + (r0 - rb) * math.cos(s * math.pi / 2) ** 0.85
        pts.append((cx - hw, y))
    # round the tip
    for i in range(1, 30):
        a = math.pi + i / 30 * math.pi
        pts.append((cx + rb * math.cos(a), tip - rb * math.sin(a)))
    # up the right side
    for i in range(n, -1, -1):
        s = i / n
        y = top + cap + (tip - top - cap) * s
        hw = rb + (r0 - rb) * math.cos(s * math.pi / 2) ** 0.85
        pts.append((cx + hw, y))
    # over the top: a flattened half superellipse
    e = 2.6
    for i in range(1, 60):
        a = i / 60 * math.pi
        c, sn = math.cos(a), math.sin(a)
        x = cx + r0 * math.copysign(abs(c) ** (2 / e), c)
        y = top + cap - cap * abs(sn) ** (2 / e)
        pts.append((x, y))
    bar = Image.new("L", (w, h), 0)
    ImageDraw.Draw(bar).polygon(pts, fill=255)
    dot = Image.new("L", (w, h), 0)
    dr, dy = 11.5 * SS, 107 * SS
    ImageDraw.Draw(dot).ellipse((cx - dr, dy - dr, cx + dr, dy + dr), fill=255)
    return bar, dot, (top, tip + rb), (dy - dr, dy + dr)


# The "?" hook's outline in cell units (64 x 128), and its dot (x, y, radius).
# Matched to the game's own "?" by laying ours over it (Max's Marshal McBride
# picture, 12 Nov): its edge traced from the picture enlarged 16 times, then
# smoothed (the lowest 16 harmonics of the outline) so the curve is clean at any
# size. The hook starts on a slant at the left, not facing down.
QUERY_HOOK = [
    (27.15, 10.30), (28.44, 10.06), (29.78, 9.91), (31.37, 9.83), (32.75, 9.84), (34.35, 9.95),
    (35.70, 10.09), (37.00, 10.29), (38.47, 10.57), (39.68, 10.86), (41.06, 11.28), (42.21, 11.72),
    (43.35, 12.24), (44.67, 12.96), (45.77, 13.67), (47.02, 14.60), (48.05, 15.46), (49.03, 16.37),
    (50.11, 17.48), (50.97, 18.47), (51.93, 19.65), (52.71, 20.69), (53.47, 21.75), (54.31, 23.00),
    (55.00, 24.09), (55.74, 25.38), (56.30, 26.51), (56.79, 27.65), (57.24, 29.03), (57.54, 30.26),
    (57.78, 31.75), (57.91, 33.08), (57.98, 34.45), (58.00, 36.07), (57.96, 37.46), (57.85, 39.05),
    (57.67, 40.36), (57.40, 41.62), (56.96, 43.00), (56.45, 44.13), (55.73, 45.40), (55.02, 46.46),
    (54.23, 47.50), (53.24, 48.70), (52.35, 49.71), (51.29, 50.86), (50.36, 51.82), (49.41, 52.75),
    (48.26, 53.81), (47.27, 54.72), (46.10, 55.79), (45.12, 56.74), (44.19, 57.73), (43.22, 58.95),
    (42.50, 60.04), (41.83, 61.37), (41.39, 62.55), (41.05, 63.75), (40.75, 65.18), (40.53, 66.43),
    (40.26, 67.90), (39.97, 69.17), (39.61, 70.42), (39.05, 71.84), (38.45, 72.98), (37.59, 74.17),
    (36.72, 75.03), (35.73, 75.72), (34.43, 76.29), (33.20, 76.57), (31.67, 76.64), (30.30, 76.50),
    (28.94, 76.19), (27.41, 75.61), (26.21, 74.95), (25.01, 73.99), (24.19, 73.03), (23.56, 71.96),
    (23.06, 70.57), (22.81, 69.30), (22.66, 67.75), (22.60, 66.39), (22.58, 65.00), (22.57, 63.39),
    (22.57, 62.01), (22.60, 60.43), (22.68, 59.10), (22.85, 57.81), (23.19, 56.36), (23.62, 55.18),
    (24.30, 53.87), (25.01, 52.82), (25.83, 51.81), (26.86, 50.69), (27.77, 49.74), (28.86, 48.64),
    (29.79, 47.70), (30.72, 46.74), (31.80, 45.62), (32.74, 44.65), (33.85, 43.51), (34.80, 42.53),
    (35.71, 41.54), (36.69, 40.33), (37.40, 39.26), (37.99, 37.93), (38.24, 36.75), (38.24, 35.54),
    (37.88, 34.14), (37.29, 33.01), (36.31, 31.83), (35.27, 30.99), (34.10, 30.35), (32.65, 29.86),
    (31.38, 29.68), (29.92, 29.73), (28.70, 29.97), (27.54, 30.38), (26.23, 31.04), (25.15, 31.73),
    (23.93, 32.66), (22.90, 33.53), (21.87, 34.43), (20.68, 35.47), (19.64, 36.31), (18.41, 37.15),
    (17.32, 37.72), (16.19, 38.11), (14.82, 38.33), (13.60, 38.31), (12.16, 38.05), (10.94, 37.63),
    (9.76, 37.04), (8.50, 36.16), (7.57, 35.25), (6.73, 34.02), (6.23, 32.86), (5.97, 31.63),
    (5.95, 30.14), (6.17, 28.86), (6.64, 27.40), (7.19, 26.21), (7.85, 25.09), (8.69, 23.84),
    (9.45, 22.81), (10.36, 21.64), (11.17, 20.63), (12.00, 19.61), (13.01, 18.42), (13.93, 17.41),
    (15.06, 16.29), (16.08, 15.39), (17.14, 14.57), (18.42, 13.73), (19.54, 13.10), (20.85, 12.45),
    (21.98, 11.95), (23.13, 11.50), (24.49, 11.02), (25.69, 10.65),
]
QUERY_DOT = (31.08, 105.26, 10.94)


def query_masks():
    """The "?": its hook (the outline above) and its dot, as two masks."""
    w, h = GW * SS, GH * SS
    hook = Image.new("L", (w, h), 0)
    ImageDraw.Draw(hook).polygon([(x * SS, y * SS) for x, y in QUERY_HOOK], fill=255)
    ys = [y for _, y in QUERY_HOOK]
    top, bottom = min(ys) * SS, max(ys) * SS
    cx, dy, dr = (v * SS for v in QUERY_DOT)
    dot = Image.new("L", (w, h), 0)
    ImageDraw.Draw(dot).ellipse((cx - dr, dy - dr, cx + dr, dy + dr), fill=255)
    return hook, dot, (top, bottom), (dy - dr, dy + dr)


def arrow_mask():
    n = AW * SS
    cx = n / 2
    tip = (cx, n * 0.10)
    left = (n * 0.18, n * 0.84)
    notch = (cx, n * 0.64)
    right = (n * 0.82, n * 0.84)
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).polygon([tip, right, notch, left], fill=255)
    return m, (n * 0.10, n * 0.84)


# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

# The light falls from the upper left and the front, as on the game's markers.
LIGHT = np.array([-0.42, -0.55, 0.72])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


def body(mask, stops, span, round_=4.0):
    """One piece: its gradient, lit as a rounded solid, cut to the mask. No outline
    (Max, 12 Nov: the dark outline made them look flat): the shape reads by its light.

    The piece's height is its mask blurred (a dome, highest in the middle), its slope
    gives each pixel a facing, and the light gives the shading: lighter on the upper
    left, darker round the lower right edge, with a soft gloss highlight."""
    size = mask.size
    g = np.asarray(gradient(size, stops, span[0], span[1]), dtype=np.float64)
    h = np.asarray(mask.filter(ImageFilter.GaussianBlur(SS * round_)), dtype=np.float64) / 255.0
    h = np.sqrt(h)
    gy, gx = np.gradient(h)
    k = SS * 7.0
    n = np.stack([-gx * k, -gy * k, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    diffuse = np.clip(n @ LIGHT, 0, 1)
    flat = LIGHT[2]
    shade = 0.62 + 0.5 * (diffuse - flat) / (1 - flat) * (1 - flat) + 0.38 * diffuse / 1.0
    shade = np.clip(shade, 0.45, 1.35)
    gloss = np.clip(n @ HALF, 0, 1) ** 36 * 0.55
    col = g * shade[..., None] + 255.0 * gloss[..., None]
    col = np.clip(col, 0, 255).astype(np.uint8)
    out = Image.fromarray(col, "RGB").convert("RGBA")
    out.putalpha(mask)
    return out


def laid(pieces, size):
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    for img in pieces:
        out = Image.alpha_composite(out, img)
    return out


def glyph(masks, stops):
    a, dot, span_a, span_dot = masks
    img = laid([body(a, stops, span_a), body(dot, stops, span_dot, 3.0)], a.size)
    return img.resize((GW, GH), Image.LANCZOS)


def arrow(stops):
    m, span = arrow_mask()
    img = laid([body(m, stops, span, 6.0)], m.size)
    return img.resize((AW, AW), Image.LANCZOS)


def sheet():
    out = Image.new("RGBA", (GW * 8, GH * 2), (0, 0, 0, 0))
    bm, qm = bang_masks(), query_masks()
    for i, (_, stops) in enumerate(LOOKS):
        out.paste(glyph(bm, stops), (i * GW, 0))
        out.paste(glyph(qm, stops), (GW * 4 + i * GW, 0))
        out.paste(arrow(stops), (i * AW, GH))
    return out


def preview(sh, path):
    font = None
    for f in ("C:/Windows/Fonts/frizqt__.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(f):
            font = f
            break
    col = 300
    W, H = col * len(LOOKS), 470
    img = Image.new("RGBA", (W, H), (46, 44, 38, 255))
    # a little grain, like ground in the game
    noise = Image.effect_noise((W, H), 18).convert("L")
    img = Image.composite(Image.new("RGBA", (W, H), (60, 58, 48, 255)), img, noise.point(lambda v: v // 3))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(font, 22) if font else None
    small = ImageFont.truetype(font, 15) if font else None
    for i, (name, _) in enumerate(LOOKS):
        x = i * col
        bang = sh.crop((i * GW, 0, (i + 1) * GW, GH))
        query = sh.crop((GW * 4 + i * GW, 0, GW * 4 + (i + 1) * GW, GH))
        arr = sh.crop((i * AW, GH, (i + 1) * AW, GH * 2))
        d.text((x + col / 2, 18), name, fill=(235, 225, 200), font=big, anchor="mt")
        # large: the cells at 1.5x
        img.alpha_composite(bang.resize((96, 192), Image.LANCZOS), (x + 40, 52))
        img.alpha_composite(query.resize((96, 192), Image.LANCZOS), (x + 150, 52))
        # on screen: about 40 px tall over a nameplate's name, and the arrow at 36 px
        for j, cell in enumerate((bang, query)):
            sx = x + 30 + j * 120
            g = cell.resize((20, 40), Image.LANCZOS)
            img.alpha_composite(g, (sx + 40, 280))
            d.text((sx + 50, 326), "Farmer Fung", fill=(64, 255, 64), font=small, anchor="mt")
        a = arr.resize((36, 36), Image.LANCZOS)
        img.alpha_composite(a, (x + col // 2 - 18, 380))
        d.text((x + col / 2, 420), "Farmer Fung  ·  340 yd", fill=(220, 220, 220), font=small, anchor="mt")
    img.convert("RGB").save(path)


if __name__ == "__main__":
    s = sheet()
    s.save(MEDIA + "marker.tga")
    print("wrote", MEDIA + "marker.tga", s.size)
    if len(sys.argv) > 1:
        preview(s, sys.argv[1])
        print("preview", sys.argv[1])
