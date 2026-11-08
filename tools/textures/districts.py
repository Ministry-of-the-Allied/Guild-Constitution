"""The Districts page's pictures (Batch D3), drawn straight from Max's Stormwind City
screenshot with Pillow: no Edge needed. Called by build.py, which packs and writes them.

  districts_map      the screenshot, cropped to the city as the Districts board shows it
  districts          each district's outline in three looks (rest: dashed in its colour with
                     a pale halo; lit: gold edge, glow and a thin line in its colour inside;
                     fill: the shape filled, which the add-on shows faintly), the meeting-spot
                     diamond, the pin and its pulse ring
  districts_wm       the world map's heavier outlines (D4b, Max 8 Nov): wmrest, the same
                     dashes about 1.6 times as thick on a thin dark casing so they stand off
                     yellow and green map art alike; wmlit, the lit look on the same casing.
                     Their own texture, so the page's atlas stays 1024 x 1024.

The shapes and the board's crop come from design/canvas-source/Districts.dc.html (the
Map view), so the canvas stays the source: move an edge there, run the build again.
Positions are in the screenshot's own pixels, from the crop's top-left (the board's
viewBox), so the add-on scales them to whatever size it draws the chart.
"""
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
DESIGN = HERE.parents[1] / "design"
BOARD = DESIGN / "canvas-source" / "Districts.dc.html"
SCREENSHOT = DESIGN / "reference" / "stormwind-city-map.webp"

KEYS = {"harb": "HARB", "cath": "CATH", "iron": "IRON", "old": "OLD", "arc": "ARC"}
COLOURS = {"HARB": "#1F7A70", "CATH": "#3D86C6", "IRON": "#B0621C", "OLD": "#8E2B22", "ARC": "#6B44A8"}
# Meeting spots, as the board draws them (its diamonds and pin), in screenshot pixels.
SPOTS = {"OLD": (1194, 646), "ARC": (720, 878), "IRON": (1030, 430), "HARB": (470, 420), "CATH": (846, 561)}
GOLD, HALO = (243, 217, 138), (255, 248, 220)
CASING = (40, 26, 12)  # the world map lines' dark edge: dark brown
CASING_ALPHA = 140     # about 55%
WM_HEAVY = 1.6         # the world map's dashes against the page's
MAP_TEX = 1024        # the map picture's width in the texture
LINE_SCALE = 0.6      # outline pixels per screenshot pixel (the chart shows about 0.41 of one)
SS = 3                # drawn this many times larger, then shrunk: smooth edges


def board():
    """The crop (x, y, w, h) and {code: [(x, y), ...]} from the board's Map view."""
    text = BOARD.read_text(encoding="utf-8")
    box = tuple(int(v) for v in re.search(r'<svg viewBox="(\d+) (\d+) (\d+) (\d+)" preserveAspectRatio', text).groups())
    shapes = {}
    for key, d in re.findall(r'class="\{\{cls\.(\w+)\}\}"[^>]*\sd="([^"]+)"', text):
        shapes[KEYS[key]] = [(int(x), int(y)) for x, y in re.findall(r"[ML](-?\d+) (-?\d+)", d)]
    if set(shapes) != set(KEYS.values()):
        raise RuntimeError(f"the Districts board has {sorted(shapes)}, not the five districts")
    return box, shapes


def rgb(hex_):
    return tuple(int(hex_[i:i + 2], 16) for i in (1, 3, 5))


def dashed(points, on, off):
    """The polygon's edge as dashes: a list of line strips."""
    pts = points + [points[0]]
    strips, cur, left, drawing = [], [pts[0]], on, True
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
        pos = 0.0
        while seg - pos > 1e-6:
            step = min(left, seg - pos)
            pos += step
            left -= step
            p = (x0 + (x1 - x0) * pos / seg, y0 + (y1 - y0) * pos / seg)
            if drawing:
                cur.append(p)
            if left <= 1e-6:
                if drawing:
                    strips.append(cur)
                drawing = not drawing
                left = on if drawing else off
                cur = [p]
    if drawing and len(cur) > 1:
        strips.append(cur)
    return strips


def layer(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def stroke(im, strips, colour, width, alpha=255):
    d = ImageDraw.Draw(im)
    for s in strips:
        d.line([(x, y) for x, y in s], fill=colour + (alpha,), width=round(width), joint="curve")
        r = width / 2
        for x, y in (s[0], s[-1]):
            d.ellipse((x - r, y - r, x + r, y + r), fill=colour + (alpha,))


def glow(im, radius, strength=1):
    out = im.filter(ImageFilter.GaussianBlur(radius))
    for _ in range(strength - 1):
        out.alpha_composite(out)
    return out


def draw_shape(code, pts, look):
    """One look of a district, cropped. Returns (image, (x, y) of its top-left in screenshot px)."""
    pad = 24
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = min(xs) - pad, min(ys) - pad
    w, h = max(xs) - x0 + pad, max(ys) - y0 + pad
    k = LINE_SCALE * SS
    local = [((x - x0) * k, (y - y0) * k) for x, y in pts]
    size = (round(w * k), round(h * k))
    col = rgb(COLOURS[code])
    im = layer(size)
    if look == "fill":
        ImageDraw.Draw(im).polygon(local, fill=col + (255,))
    elif look == "wmrest":
        line = 6 * WM_HEAVY * k
        strips = dashed(local, 28 * k, 12 * k)
        casing = layer(size)
        stroke(casing, strips, CASING, line + 4 * k)
        im.alpha_composite(glow(casing, 0.6 * k))
        im.putalpha(im.getchannel("A").point(lambda v: v * CASING_ALPHA // 255))
        stroke(im, strips, col, line)
    elif look == "wmlit":
        closed = [local + [local[0]]]
        g = layer(size)
        stroke(g, closed, GOLD, 13 * k)
        im.alpha_composite(glow(g, 6 * k, 2))
        casing = layer(size)
        stroke(casing, closed, CASING, 13 * k + 5 * k, CASING_ALPHA + 40)
        im.alpha_composite(glow(casing, 0.8 * k))
        stroke(im, closed, GOLD, 13 * k)
        stroke(im, closed, col, 5.5 * k)
    elif look == "rest":
        strips = dashed(local, 20 * k, 10 * k)
        halo = layer(size)
        stroke(halo, strips, HALO, 6 * k + 3 * k)
        im.alpha_composite(glow(halo, 1.5 * k))
        stroke(im, strips, col, 6 * k, 230)
    else:  # lit
        closed = [local + [local[0]]]
        g = layer(size)
        stroke(g, closed, GOLD, 11 * k)
        im.alpha_composite(glow(g, 6 * k, 2))
        shadow = layer(size)
        stroke(shadow, closed, (0, 0, 0), 11 * k, 150)
        im.alpha_composite(glow(shadow, 2 * k))
        stroke(im, closed, GOLD, 11 * k)
        stroke(im, closed, col, 4.5 * k)
    im = im.resize((round(size[0] / SS), round(size[1] / SS)), Image.LANCZOS)
    return im, (x0, y0)


def draw_marks():
    """The meeting-spot diamond, the pin and its pulse ring, each centred on its spot.
    Returns {name: (image, (dx, dy) from the spot to the image's top-left)}."""
    k = LINE_SCALE * SS
    out = {}
    # diamond: 28 across, dark with a gold edge (the board's legend diamonds)
    s = round(36 * k)
    im = layer((s, s))
    c = s / 2
    r = 14 * k
    ImageDraw.Draw(im).polygon([(c, c - r), (c + r, c), (c, c + r), (c - r, c)], fill=(42, 31, 20, 235),
                               outline=GOLD + (255,), width=round(2 * k))
    out["spot"] = im
    # pin: the board's teardrop (72 wide, 90 tall, its point on the spot)
    w, h = round(84 * k), round(102 * k)
    im = layer((w, h))
    d = ImageDraw.Draw(im)
    cx, top = w / 2, 6 * k
    head = 36 * k
    # head circle and a triangle to the point
    d.ellipse((cx - head, top, cx + head, top + 2 * head), fill=GOLD + (255,))
    d.polygon([(cx - head * 0.82, top + head * 1.55), (cx + head * 0.82, top + head * 1.55), (cx, top + 90 * k)],
              fill=GOLD + (255,))
    inner = head - 4.5 * k
    d.ellipse((cx - inner, top + 4.5 * k, cx + inner, top + 4.5 * k + 2 * inner), fill=(27, 53, 112, 255))
    d.polygon([(cx - inner * 0.8, top + head * 1.5), (cx + inner * 0.8, top + head * 1.5), (cx, top + 82 * k)],
              fill=(27, 53, 112, 255))
    d.ellipse((cx - 10 * k, top + head - 10 * k, cx + 10 * k, top + head + 10 * k), fill=GOLD + (255,))
    shadow = layer((w, h))
    shadow.paste((0, 0, 0, 120), mask=im.getchannel("A"))
    pin = layer((w, h))
    pin.alpha_composite(glow(shadow, 3 * k), (round(2 * k), round(3 * k)))
    pin.alpha_composite(im)
    out["pin"] = pin
    # pulse ring: radius 26, 8 wide (the add-on grows and fades it)
    s = round(72 * k)
    im = layer((s, s))
    c = s / 2
    ImageDraw.Draw(im).ellipse((c - 26 * k, c - 26 * k, c + 26 * k, c + 26 * k), outline=GOLD + (255,), width=round(8 * k))
    out["ring"] = im
    shrunk = {}
    for name, im in out.items():
        small = im.resize((round(im.width / SS), round(im.height / SS)), Image.LANCZOS)
        if name == "pin":  # its point sits on the spot
            anchor = (-small.width / 2 / LINE_SCALE, -(6 + 90) / 1)
        else:
            anchor = (-small.width / 2 / LINE_SCALE, -small.height / 2 / LINE_SCALE)
        shrunk[name] = (small, anchor)
    return shrunk


def build(pack, pow2):
    """Returns (textures {name: image}, pieces {name: dict}, media dict for Media.lua).
    pack and pow2 are build.py's own."""
    box, shapes = board()
    bx, by, bw, bh = box
    shot = Image.open(SCREENSHOT).convert("RGBA").crop((bx, by, bx + bw, by + bh))
    mh = round(bh * MAP_TEX / bw)
    shot = shot.resize((MAP_TEX, mh), Image.LANCZOS)
    map_tex = Image.new("RGBA", (MAP_TEX, pow2(mh)), (0, 0, 0, 255))
    map_tex.paste(shot, (0, 0))
    textures = {"districts_map": map_tex}
    pieces = {"districts_map": dict(tex="districts_map", root="map", x=0, y=0, w=bw, h=bh,
                                    l=0, r=1, t=0, b=mh / map_tex.height)}

    drawn = {}
    for code, pts in shapes.items():
        for look in ("rest", "lit", "fill"):
            im, (x0, y0) = draw_shape(code, pts, look)
            drawn[f"dz_{code}_{look}"] = (im, x0 - bx, y0 - by)
    for name, (im, (dx, dy)) in draw_marks().items():
        drawn["dz_" + name] = (im, dx, dy)  # marks: x, y are from the spot, not the map
    atlas, spots = pack([(n, im) for n, (im, _, _) in drawn.items()])
    textures["districts"] = atlas
    W, H = atlas.size
    for n, (im, x, y) in drawn.items():
        sx, sy = spots[n]
        pieces[n] = dict(tex="districts", root="map", x=x, y=y, w=im.width / LINE_SCALE, h=im.height / LINE_SCALE,
                         l=sx / W, r=(sx + im.width) / W, t=sy / H, b=(sy + im.height) / H)

    # The world map's heavier outlines, in their own texture.
    wm = {}
    for code, pts in shapes.items():
        for look in ("wmrest", "wmlit"):
            im, (x0, y0) = draw_shape(code, pts, look)
            wm[f"dz_{code}_{look}"] = (im, x0 - bx, y0 - by)
    atlas, spots = pack([(n, im) for n, (im, _, _) in wm.items()])
    textures["districts_wm"] = atlas
    W, H = atlas.size
    for n, (im, x, y) in wm.items():
        sx, sy = spots[n]
        pieces[n] = dict(tex="districts_wm", root="map", x=x, y=y, w=im.width / LINE_SCALE, h=im.height / LINE_SCALE,
                         l=sx / W, r=(sx + im.width) / W, t=sy / H, b=(sy + im.height) / H)

    media = {
        "w": bw, "h": bh,  # the chart, in screenshot pixels
        "crop": {"x": bx, "y": by},  # where the chart sits in the whole screenshot
        "shot": {"w": Image.open(SCREENSHOT).width, "h": Image.open(SCREENSHOT).height},
        "shapes": {code: [v for x, y in pts for v in (x - bx, y - by)] for code, pts in shapes.items()},
        "spots": {code: {"x": x - bx, "y": y - by} for code, (x, y) in SPOTS.items()},
    }
    return textures, pieces, media


if __name__ == "__main__":  # a quick look: python tools/textures/districts.py <out.png>
    import sys

    def _pow2(n):
        p = 1
        while p < n:
            p *= 2
        return p

    sys.path.insert(0, str(HERE))
    from build import pack as _pack  # noqa: E402
    tex, pcs, med = build(_pack, _pow2)
    m = tex["districts_map"].crop((0, 0, MAP_TEX, round(med["h"] * MAP_TEX / med["w"])))
    k = MAP_TEX / med["w"]
    for code in med["shapes"]:
        p = pcs[f"dz_{code}_{'lit' if code == 'CATH' else 'rest'}"]
        a = tex["districts"]
        W, H = a.size
        part = a.crop((round(p["l"] * W), round(p["t"] * H), round(p["r"] * W), round(p["b"] * H)))
        part = part.resize((round(p["w"] * k), round(p["h"] * k)), Image.LANCZOS)
        m.paste(part, (round(p["x"] * k), round(p["y"] * k)), part)
    for code, s in med["spots"].items():
        p = pcs["dz_pin" if code == "CATH" else "dz_spot"]
        a = tex["districts"]
        W, H = a.size
        part = a.crop((round(p["l"] * W), round(p["t"] * H), round(p["r"] * W), round(p["b"] * H)))
        part = part.resize((max(1, round(p["w"] * k)), max(1, round(p["h"] * k))), Image.LANCZOS)
        m.paste(part, (round((s["x"] + p["x"]) * k), round((s["y"] + p["y"]) * k)), part)
    m.save(sys.argv[1] if len(sys.argv) > 1 else "districts-preview.png")
