"""The Chronicle book on the Throne Room (Max, 10 Nov 2026), for tools/textures/build.py.

Under What's on sits a closed, leatherbound tome. Hovering lifts its cover a little;
a click flips it open, its pages turning fast in a holy light with golden motes rising, and
it comes to rest open; a click on the open book opens the Charter (UI/ChronicleBook.lua).

The book is drawn in 3D with CSS in tools/textures/chronicle.html, so the cover and the pages
turn with real perspective. Edge renders it once per piece and angle, and the game steps
through the pictures (frame-stepping with SetTexCoord: no FlipBook, no texture rotation).

Per skin (file name as build.SKINS), in chronicle_<file>.tga: the closed book without its
front cover ("base"), the front cover at each angle ("cover000" ... "cover180"), the open
book's covers ("open") and its ribbons ("ribbons"). The leather, metal, jewels and ribbons
are the window's own for that skin, and the cover carries the skin's emblem.
Shared, in chronicle.tga: the open book's pages ("pages"), one page at each angle as it
turns ("page006" ... "page174"), the glows ("leak", "glowOpen", "halo", "beam"), a mote and
the book's shadow.

Pieces are named "chronicle_<file>:<part>" and "chronicle:<part>", root "book": canvas units
from the top-left of the book's scene. Media.chronicle has the angles, the boxes of the closed
and open book, where the live line goes on the open book's left page, and the timings
(the game and the preview below use the same numbers).

Still pictures are drawn at 2x for sharpness (ADDON_SPEC.md 19.1); the in-between angles,
on screen for a few hundredths of a second each, at 1.5x.

Run on its own to draw only the book and save previews (no game files written):
    python tools/textures/chronicle.py [folder]
"""
import concurrent.futures
import json
import math
import re
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DESIGN = ROOT / "design"
ADDON = ROOT / "addon" / "MinistryOfTheAllied"

ORIGIN = (20, 20)       # #scene's top-left on the page (chronicle.html)
VIEW = (340, 330)       # the page Edge renders
SCENE = (300, 290)      # the scene box
STILL, MOTION = 2, 1.5  # drawing scales: pictures that rest on screen, and the in-between angles

COVER_REST = [0, 4, 8, 12]     # the hover lift (it rests at the last), drawn at 2x
COVER_TURN = [25, 40, 55, 70, 85, 100, 115, 130, 145, 160, 172, 180]
PAGE_TURN = list(range(6, 175, 6))   # 6 ... 174: fine steps, as the pages hang and fall slowly

# Seconds from the click. The game (UI/ChronicleBook.lua) reads these from Media.chronicle.timing.
TIMING = {
    "lift": 0.07,                 # hover: the cover follows the mouse with this time constant
    # Fast, as an explosion (Max: "speed up the page flicking to make it seem more explosive"); then the
    # pages hang in the light for a moment and fall slowly (Max, 10 Nov)
    "cover": [0.0, 0.3],          # the cover is flung from its lift to lying open on the left
    "slide": [0.0, 0.5],          # the book slides from the closed book's place to the open book's
    # pages: n flung up one after another (every) from start, each in rise seconds (fast, slowing as it
    # rises) to its place in a fan (fan: the first page's angle to the last's), drifting on by drift degrees
    # as they hang; from hold they fall one after another (fallEvery), slowly, each taking
    # fall[0] + fall[1] * (degrees to go) / 180 seconds
    "pages": {"n": 9, "start": 0.12, "every": 0.035, "rise": 0.16, "fan": [144, 36], "drift": 6,
              "hold": 0.75, "fallEvery": 0.06, "fall": [0.35, 0.6]},
    "swap": [0.3, 0.6, 0.75],     # the open book fades in over the closed one, then the closed one goes
    # The holy light (Max, 10 Nov: "a very grand and regal holy light that engulfs the book, as if blessed
    # by the heavens ... aggressive almost ... explosive"). On cream pages light only whitens them, so it
    # floods the dark plate round the book: rays bursting out and turning slowly behind it, a shaft from
    # above, a golden aura, a shockwave ring, one great swell that engulfs the book, motes flung out and
    # twinkling stars. It bursts once and settles to a steady blessed light; it never flickers. The burst
    # may break out over the page round the plate (Max, 10 Nov: "3D and alive"); the steady light keeps
    # inside the plate (place: rest).
    "glow": [0.05, 0.45, 2.0],    # the light bursts to its peak, then settles by the third time
    # the light on the pages (glowOpen, beam, shaftFront) settles sooner, so the pages show as they hang
    "front": [0.05, 0.3, 0.75],
    "done": 2.05,                 # the last page has landed (build() checks it)
    "peak": {"glowOpen": 0.6, "halo": 1.0, "beam": 1.0, "leak": 0.8, "rays": 1.0, "shaft": 1.0,
             "shaftFront": 0.45, "bloom": 1.0, "bloomClosed": 1.0, "haloFront": 0.75},  # the light at its height
    "settle": {"glowOpen": 0.32, "halo": 0.5, "beam": 0.32, "rays": 0.6, "shaft": 0.45,
               "shaftFront": 0.1, "bloom": 0.7, "haloFront": 0.12},                     # the open book's steady light
    "hover": {"leak": 0.35, "bloomClosed": 0.4, "openRays": 0.2},   # hovering: the closed book's aura; more rays when open
    # the swell of light over the book: up to its height, then down to its steady light (gone low before
    # the pages hang, so they show against the light)
    "engulf": [0.1, 0.3, 0.8],
    "flare": [0.1, 0.28, 0.75],   # the burst's bright heart and streak: grows from nothing to its height, then fades
    "ring": [0.15, 0.7],          # the shockwave: a ring of light flung out, fading as it goes
    "turn": 2.4,                  # the rays turn by one drawn step (10 degrees) in this many seconds
    "motes": {"burst": 48, "burstFor": 0.6, "ambient": 3.2, "life": [1.4, 2.6], "rise": [40, 90], "size": [5, 11],
              "fling": [50, 130], "stars": 0.3, "spread": 120},   # fling: how far the burst's motes are thrown out
    # Where the lights sit: their middle at the book's middle across and at y (a share of its height down
    # from its top), the book's box going from the closed book's to the open book's as it slides; sizes in
    # canvas units; grow: from and to, over the burst; rest: the size it
    # settles to with the light (the steady light keeps inside the plate).
    "place": {"halo": {"y": 0.42, "w": 330, "h": 300, "rest": 0.8},
              "rays": {"y": 0.4, "w": 460, "h": 460, "grow": [0.25, 1.2], "rest": 0.55},
              "shaft": {"y": 0.05, "w": 300, "h": 330, "rest": 0.45}, "beam": {"y": 0.2, "w": 150, "h": 240, "rest": 0.85},
              "haloFront": {"y": 0.45, "w": 330, "h": 260, "rest": 0.8},
              "ring": {"y": 0.42, "w": 200, "h": 170, "grow": [0.4, 2.6]},
              "flare": {"y": 0.34, "w": 320, "h": 150, "grow": [0.5, 2.0]}},
}
RAY_STEPS = [0, 10, 20]   # the rays drawn turned by these degrees: their pattern repeats every 30

GOLD = dict(
    metal="linear-gradient(180deg,#FFF3C4 0%,#EBCB7A 18%,#C9A24A 42%,#8A6420 58%,#C9A24A 76%,#F3D98A 100%)",
    metalH="linear-gradient(90deg,#8A6420 0%,#E9C877 22%,#FFF3C4 50%,#E9C877 78%,#8A6420 100%)",
    metalMid="#C9A24A", metalDk="#5A3F10", metalStops=["#FFF1BF", "#E6C36C", "#A97E2C", "#EBCB7A", "#7A5719"],
    ribbon2=["#F3D98A", "#C9A24A", "#8A6420"], dot="rgba(243,217,138,.55)")
SILVER = dict(
    metal="linear-gradient(180deg,#FFFFFF 0%,#E3E8EE 18%,#AEB8C6 42%,#6B7483 58%,#AEB8C6 76%,#EEF2F6 100%)",
    metalH="linear-gradient(90deg,#6B7483 0%,#D5DCE5 22%,#FFFFFF 50%,#D5DCE5 78%,#6B7483 100%)",
    metalMid="#AEB8C6", metalDk="#1B1F27", metalStops=["#FFFFFF", "#E3E8EE", "#8C96A5", "#EEF2F6", "#4F5866"],
    ribbon2=["#FFFFFF", "#C9D0DA", "#8C96A5"], dot="rgba(230,236,244,.5)")


def leather(stops):
    return "radial-gradient(ellipse 90% 70% at 40% 0%," + stops + ")"


# The window's leather for each skin (WindowSkins board), its jewels (UI/Skin.lua GEM) and emblem (build.SKINS).
SKINS = {
    "ministry": dict(GOLD, leather=leather("#3360B4 0%,#1E3B7C 34%,#142B5E 62%,#0B1838 100%"),
                     edge="#0B1838", edgeHi="#1E3B7C", endpaper="#1B3570", well="#0E1F45", wellHi="#24468F",
                     gem="#2F5FD0", ribbon=["#2E58AA", "#1B3570", "#12285A"], emblem="alliance-crest.png"),
    "silverhand": dict(SILVER, leather=leather("#3A5DAE 0%,#1F4290 34%,#173470 62%,#0C1C44 100%"),
                       edge="#0C1C44", edgeHi="#1F4290", endpaper="#1F4290", well="#0C1C44", wellHi="#2A55A8",
                       gem="#2F5FD0", ribbon=["#3460B4", "#1F4290", "#12285A"], emblem="seal-silverhand.svg"),
    "exchange": dict(GOLD, leather=leather("#B8343C 0%,#8E1A21 34%,#661118 62%,#2E0609 100%"),
                     edge="#2E0609", edgeHi="#661118", endpaper="#7A1219", well="#3A0A0E", wellHi="#8E1A21",
                     gem="#9B5BD6", ribbon=["#B8343C", "#8E1A21", "#661118"], emblem="seal-exchange.svg"),
    "crown": dict(GOLD, leather=leather("#86296A 0%,#58143F 10%,#3D0B2D 26%,#2A0720 52%,#140210 100%"),
                  edge="#140210", edgeHi="#3D0B2D", endpaper="#58143F", well="#2A0720", wellHi="#58143F",
                  gem="#0B7A38", ribbon=["#86296A", "#58143F", "#3D0B2D"], emblem="crest-crown.png"),
}


def cover_name(a):
    return f"cover{a:03d}"


def page_name(a):
    return f"page{a:03d}"


def page_html(fonts, piece, skin="ministry", angle=0):
    s = dict(SKINS[skin])
    params = {"piece": piece, "angle": angle, "skin": {k: v for k, v in s.items() if k != "emblem"},
              "grain": (DESIGN / "textures" / "leather-grain.svg").as_uri(),
              "parch": (DESIGN / "textures" / "parchment-grain.svg").as_uri(),
              "emblem": (DESIGN / "textures" / s["emblem"]).as_uri(),
              "crest": (DESIGN / "textures" / "crest-crown.png").as_uri()}
    text = (HERE / "chronicle.html").read_text(encoding="utf-8")
    return text.replace("{{fonts}}", fonts).replace("{{params}}", json.dumps(params))


def crop(im, scale):
    box = im.getchannel("A").point(lambda v: 255 if v > 3 else 0).getbbox()
    if not box:
        raise RuntimeError("a piece of the book came out empty")
    l, t, r, b = box
    l, t, r, b = max(0, l - 1), max(0, t - 1), min(im.width, r + 1), min(im.height, b + 1)
    ox, oy = ORIGIN
    return im.crop((l, t, r, b)), {"x": l / scale - ox, "y": t / scale - oy, "w": (r - l) / scale, "h": (b - t) / scale}


# Sprites drawn here rather than in Edge: soft lights, a mote, the shadow (sizes in canvas units).
def radial(size, stops):
    """A soft round light: stops are (radius 0..1, (r, g, b, a)) from the middle out."""
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((x + .5 - w / 2) / (w / 2)) ** 2 + ((y + .5 - h / 2) / (h / 2)) ** 2)
    out = np.zeros((h, w, 4), np.float32)
    rs = [s[0] for s in stops]
    for c in range(4):
        out[..., c] = np.interp(d, rs, [s[1][c] for s in stops])
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def coloured(alpha, rgb):
    """An RGBA picture of one colour from an alpha array (0..1)."""
    h, w = alpha.shape
    out = np.zeros((h, w, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = rgb
    out[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def smooth(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def beam_image(w, h):
    """The bright core of light rising from the pages: strongest at the foot, fading upward, with streaks."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (x + .5 - w / 2) / (w / 2)
    across = np.exp(-(u / 0.42) ** 2) * (0.75 + 0.25 * np.cos(u * 9.0) ** 2)
    up = np.clip((y + .5) / h, 0, 1) ** 1.4
    foot = 1 - smooth(0.88, 1.0, (y + .5) / h)
    return coloured(across * up * foot, (255, 230, 165))


def shaft_image(w, h):
    """A shaft of light from the heavens: narrower at the top, streaked, soft at both ends."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    v = (y + .5) / h
    u = (x + .5 - w / 2) / (w * (0.26 + 0.2 * v))
    across = np.exp(-1.4 * u ** 2)
    streaks = 0.55 + sum(s * np.exp(-((u - c) / 0.09) ** 2) for c, s in
                         ((-0.75, 0.35), (-0.4, 0.5), (-0.08, 0.45), (0.22, 0.55), (0.55, 0.4), (0.85, 0.3)))
    along = smooth(0.0, 0.4, v) * (1 - smooth(0.8, 1.0, v))
    return coloured(across * np.clip(streaks, 0, 1.2) * along * 0.85, (255, 236, 185))


def rays_image(n, turn):
    """Golden rays round the middle, their pattern repeating every 30 degrees, turned by `turn` degrees
    (so pictures turned 0, 10 and 20 laid one after another turn without end)."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = (x + .5 - n / 2) / (n / 2), (y + .5 - n / 2) / (n / 2)
    r = np.sqrt(dx * dx + dy * dy)
    ang = (np.degrees(np.arctan2(dy, dx)) - turn) % 30

    def ray(centre, width, length, strength):
        d = np.abs(ang - centre)
        d = np.minimum(d, 30 - d)
        return strength * np.exp(-(d / width) ** 2) * np.clip(1 - r / length, 0, 1) ** 1.3

    i = ray(0, 2.4, 1.0, 1.0) + ray(15, 1.3, 0.82, 0.8) + ray(7.5, 0.7, 0.6, 0.55) + ray(22.5, 0.7, 0.66, 0.55)
    core = np.clip(1 - r / 0.4, 0, 1) ** 2 * 0.55
    return coloured(i * smooth(0.05, 0.22, r) + core, (255, 220, 135))


def flare_image(w, h):
    """The swell of light at the height of the flip: a long level streak, a shorter upright one, a bright heart."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dx, dy = (x + .5 - w / 2) / (w / 2), (y + .5 - h / 2) / (h / 2)
    level = np.exp(-(dy / 0.07) ** 2) * np.clip(1 - np.abs(dx), 0, 1) ** 1.6
    sx = dx * w / h   # across in the same units as up
    upright = np.exp(-(sx / 0.05) ** 2) * np.clip(1 - np.abs(dy), 0, 1) ** 2 * 0.8
    heart = np.exp(-(sx * sx + dy * dy) / 0.07) + 0.5 * np.exp(-(sx * sx + dy * dy) / 0.4)
    return coloured(level + upright + heart, (255, 242, 205))


def star_image(n):
    """A twinkling four-pointed star."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = (x + .5 - n / 2) / (n / 2), (y + .5 - n / 2) / (n / 2)
    a = (np.exp(-(dy / 0.08) ** 2) * np.clip(1 - np.abs(dx), 0, 1) ** 2.5
         + np.exp(-(dx / 0.08) ** 2) * np.clip(1 - np.abs(dy), 0, 1) ** 2.5
         + np.exp(-(dx * dx + dy * dy) / 0.03))
    return coloured(a, (255, 246, 214))


def sprites():
    """name -> (image, size in canvas units). The lights are sized again in the game (TIMING["place"])."""
    out = {
        "halo": (radial((256, 256), [(0, (255, 226, 150, 235)), (.3, (255, 214, 130, 175)), (.6, (255, 200, 110, 70)),
                                     (1, (255, 190, 100, 0))]), (330, 300)),
        "mote": (radial((32, 32), [(0, (255, 255, 235, 255)), (.18, (255, 240, 190, 235)), (.45, (255, 214, 120, 90)),
                                   (1, (255, 200, 100, 0))]), (8, 8)),
        "star": (star_image(48), (14, 14)),
        "beam": (beam_image(96, 256), (150, 240)),
        "shaft": (shaft_image(160, 256), (300, 330)),
        "flare": (flare_image(256, 128), (260, 130)),
        "ring": (radial((256, 256), [(0, (255, 236, 180, 0)), (.5, (255, 236, 180, 40)), (.76, (255, 240, 195, 255)),
                                     (.86, (255, 226, 160, 120)), (1, (255, 214, 140, 0))]), (200, 170)),
        "shadow": (radial((128, 64), [(0, (0, 0, 0, 150)), (.55, (0, 0, 0, 95)), (1, (0, 0, 0, 0))]), (100, 50)),
    }
    for turn in RAY_STEPS:
        out[f"rays{turn:02d}"] = (rays_image(256, turn), (440, 440))
    return out


def bloom(drawn, keys, scale=0.5, spread=10, blur=13, gain=1.35):
    """A golden aura round the book: its outline from the drawn pieces, widened and blurred. Placed like a
    piece (its x, y from the scene's top-left); drawn at half size, being soft."""
    m = 50
    W, H = round((SCENE[0] + 2 * m) * scale), round((SCENE[1] + 2 * m) * scale)
    sil = Image.new("L", (W, H), 0)
    for key in keys:
        im, pos = drawn[key]
        a = im.getchannel("A").resize((max(1, round(pos["w"] * scale)), max(1, round(pos["h"] * scale))), Image.LANCZOS)
        sil.paste(255, (round((pos["x"] + m) * scale), round((pos["y"] + m) * scale)), a)
    k = int(spread * scale) * 2 + 1
    sil = sil.filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.GaussianBlur(blur * scale))
    alpha = np.asarray(sil, np.float32) / 255 * gain
    im = coloured(alpha, (255, 208, 105))
    l, t, r, b = im.getchannel("A").point(lambda v: 255 if v > 2 else 0).getbbox()
    return im.crop((l, t, r, b)), {"x": l / scale - m, "y": t / scale - m, "w": (r - l) / scale, "h": (b - t) / scale}


def build(edge, pack, fonts):
    """Returns (textures, pieces, media) for build.py."""
    p = TIMING["pages"]
    if p["hold"] < p["start"] + (p["n"] - 1) * p["every"] + p["rise"]:
        raise RuntimeError("the pages must all be up before the first falls (TIMING pages hold)")
    if max(page_lands(i, p) for i in range(p["n"])) > TIMING["done"]:
        raise RuntimeError("a page lands after the book is done (TIMING done)")
    jobs = []   # (texture, part, piece, skin, angle, scale)
    for skin in SKINS:
        tex = "chronicle_" + skin
        # the open book's covers are mostly under its pages, and the lift's middle angles pass in a moment
        jobs += [(tex, "base", "base", skin, 0, STILL), (tex, "open", "open", skin, 0, MOTION),
                 (tex, "ribbons", "ribbons", skin, 0, STILL)]
        jobs += [(tex, cover_name(a), "cover", skin, a, STILL if a in (COVER_REST[0], COVER_REST[-1]) else MOTION)
                 for a in COVER_REST]
        jobs += [(tex, cover_name(a), "cover", skin, a, MOTION) for a in COVER_TURN]
    jobs += [("chronicle", "pages", "pages", "ministry", 0, STILL), ("chronicle", "glowOpen", "glowOpen", "ministry", 0, 1),
             ("chronicle", "leak", "leak", "ministry", 0, 1)]
    jobs += [("chronicle", page_name(a), "page", "ministry", a, MOTION) for a in PAGE_TURN]

    def draw(job):
        tex, part, piece, skin, angle, scale = job
        im = edge.screenshot(f"{tex}_{part}", page_html(fonts, piece, skin, angle), scale, VIEW)
        return job, crop(im, scale)

    print(f"  drawing the Chronicle book: {len(jobs)} pictures...")
    drawn = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for job, result in pool.map(draw, jobs):
            drawn[(job[0], job[1])] = result
    for name, (im, size) in sprites().items():
        drawn[("chronicle", name)] = (im, {"x": 0, "y": 0, "w": size[0], "h": size[1]})
    # the auras: round the open book, and round the closed one (its hover and the moment it opens)
    drawn[("chronicle", "bloom")] = bloom(drawn, [("chronicle_ministry", "open"), ("chronicle", "pages"),
                                                  ("chronicle_ministry", "ribbons")])
    drawn[("chronicle", "bloomClosed")] = bloom(drawn, [("chronicle_ministry", "base"),
                                                        ("chronicle_ministry", cover_name(0))], spread=6, blur=10)

    rects = edge.rects("chronicle-live", page_html(fonts, "pages"), VIEW)
    live = {k: round(v, 2) for k, v in rects["liveLine"].items()}

    textures, pieces = {}, {}
    for tex in ["chronicle"] + ["chronicle_" + s for s in SKINS]:
        items = [(part, im) for (t, part), (im, _) in drawn.items() if t == tex]
        image, spots = pack(items)
        for part, im in items:
            x, y = spots[part]
            pos = drawn[(tex, part)][1]
            pieces[f"{tex}:{part}"] = dict({k: round(v, 3) for k, v in pos.items()}, tex=tex, root="book",
                                           l=x / image.width, r=(x + im.width) / image.width,
                                           t=y / image.height, b=(y + im.height) / image.height)
        textures[tex] = image

    def box(names):
        rs = [pieces[n] for n in names]
        x0, y0 = min(r["x"] for r in rs), min(r["y"] for r in rs)
        x1, y1 = max(r["x"] + r["w"] for r in rs), max(r["y"] + r["h"] for r in rs)
        return {"x": round(x0, 2), "y": round(y0, 2), "w": round(x1 - x0, 2), "h": round(y1 - y0, 2)}

    s = "chronicle_ministry:"
    media = {
        "scene": {"w": SCENE[0], "h": SCENE[1]},
        "cover": COVER_REST + COVER_TURN, "rest": COVER_REST[-1], "page": PAGE_TURN, "rays": RAY_STEPS,
        "closed": box([s + "base", s + cover_name(0)]),
        "open": box([s + "open", "chronicle:pages", s + "ribbons"]),
        "liveLine": live,
        "timing": TIMING,
    }
    return textures, pieces, media


###########################################################################
# The preview: the book on its plate in the right column, as the game lays it out
###########################################################################

LIVE = "212 entries since 3 September"
PLATE_W, PLATE_H = 315, 228     # the Throne Room's right column, and the Chronicle's plate (UI/ThroneRoom.lua)
BOOK_FOOT = 14                  # the closed book's foot sits this far above the plate's foot
K = 2                           # preview pixels per canvas unit
# Round the plate in the preview, what the Throne Room has there (UI/ThroneRoom.lua): to the left the page
# (Who holds power ends 10 above the plate, 20 to its left), above it the last of Recent decrees, to the
# right the scroll bar. The page's scroll area ends at the plate's right edge and its foot, so the game
# cuts the light there; the preview does too.
LEFT_M, TOP_M, RIGHT_M, BOT_M = 76, 112, 30, 8
DECREES = [("Bram won his Ring bout against Tor", "5d"), ("Elara was sworn in as High Justice", "3d"),
           ("The Silverhand Party carried the Treasury Act", "2d"), ("The Crown opened the polls", "1h")]


def ease(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def ramp(t, a, b):
    return ease((t - a) / (b - a)) if b > a else float(t >= a)


def frames_for(angle, angles):
    """The two drawn angles either side of an angle, and how far between them (0..1). On a drawn angle, just it."""
    if angle <= angles[0]:
        return angles[0], angles[0], 0.0
    for a, b in zip(angles, angles[1:]):
        if angle < b:
            return a, b, (angle - a) / (b - a)
    return angles[-1], angles[-1], 0.0


def stepped(name, angle, angles, blend=True):
    """The drawn angle(s) for an angle: the two either side, the nearer laid over the other as it
    comes closer (blend), or just the nearest (while turning fast: two angles far apart would show double)."""
    a, b, f = frames_for(angle, angles)
    if not blend:
        return [(name(b if f >= 0.5 else a), 1, "BLEND")]
    return [(name(a), 1, "BLEND")] + ([(name(b), f, "BLEND")] if f > 0 else [])


def rays_now(spin, strength, tm, media):
    """The turning rays: two drawn turns either side of now, faded across (their light adds up to one)."""
    steps = media["rays"]
    at = spin / tm["turn"]
    k, f = int(math.floor(at)) % len(steps), at - math.floor(at)
    a, b = steps[k], steps[(k + 1) % len(steps)]
    return [(f"rays{a:02d}", strength * (1 - f), "ADD"), (f"rays{b:02d}", strength * f, "ADD")]


def page_angle(i, t, p):
    """Page i's angle t seconds after the click, or None while it lies flat (not flung yet, or landed).
    Flung up fast, slowing as it rises, to its place in a fan; hanging there a moment, drifting on a
    little; then falling slowly to the left (Max, 10 Nov). UI/ChronicleBook.lua: pageAngle."""
    s = p["start"] + i * p["every"]
    if t <= s:
        return None
    h = p["fan"][0] + (p["fan"][1] - p["fan"][0]) * i / (p["n"] - 1)
    u = (t - s) / p["rise"]
    if u < 1:
        return h * (1 - (1 - u) ** 3)
    up, f0 = s + p["rise"], p["hold"] + i * p["fallEvery"]
    if t < f0:
        return h + p["drift"] * (t - up) / (f0 - up)
    a = h + p["drift"]
    v = (t - f0) / (p["fall"][0] + p["fall"][1] * (180 - a) / 180)
    return a + (180 - a) * ease(v) if v < 1 else None


def page_lands(i, p):
    """When page i lies flat on the left again."""
    a = p["fan"][0] + (p["fan"][1] - p["fan"][0]) * i / (p["n"] - 1) + p["drift"]
    return p["hold"] + i * p["fallEvery"] + p["fall"][0] + p["fall"][1] * (180 - a) / 180


def state(t, lift, tm, media, spin=0.0, hover=False):
    """What the book shows t seconds after the click (t < 0: closed, with the hover lift 0..1); spin:
    seconds the rays have been turning; hover: the mouse is on the open book. Returns the slide (0: the
    closed book's place .. 1: the open book's) and the layers, bottom to top: (part, alpha, blend[, size
    scale]). UI/ChronicleBook.lua does the same."""
    hv = tm["hover"]
    if t < 0:
        return 0.0, [("shadow", 1, "BLEND"), ("bloomClosed", hv["bloomClosed"] * lift, "ADD"), ("base", 1, "BLEND"),
                     ("leak", hv["leak"] * lift, "ADD")] + stepped(cover_name, media["rest"] * lift, media["cover"])
    c0, c1 = tm["cover"]
    s0, s1, s2 = tm["swap"]
    g0, g1, g2 = tm["glow"]
    pk, st, pl = tm["peak"], tm["settle"], tm["place"]
    full, settle = ramp(t, g0, g1), ramp(t, g1, g2)
    f0_, f1_, f2_ = tm["front"]
    front = (ramp(t, f0_, f1_), ramp(t, f1_, f2_))

    def lit(name, on=None):   # on: the front lights' own burst and settle
        a, s = on or (full, settle)
        return pk[name] * a * (1 - s) + st[name] * s

    def size(name):   # a light's size: grown over the burst, settling to its rest size with the light
        p = pl[name]
        g = p["grow"][0] + (p["grow"][1] - p["grow"][0]) * full if "grow" in p else 1
        return g * (1 - settle) + p.get("rest", 1) * settle

    rays = lit("rays") + (hv["openRays"] if hover and t >= tm["done"] else 0)
    layers = [("halo", lit("halo"), "ADD", size("halo"))]
    layers += [r + (size("rays"),) for r in rays_now(spin, rays, tm, media)]
    layers += [("shaft", lit("shaft") * ramp(t, 0.25, 0.9), "ADD", size("shaft")), ("shadow", 1, "BLEND")]
    layers.append(("bloomClosed", (hv["bloomClosed"] + (pk["bloomClosed"] - hv["bloomClosed"]) * ramp(t, 0, 0.15))
                   * (1 - ramp(t, 0.45, 0.9)), "ADD"))
    layers.append(("bloom", lit("bloom") * ramp(t, 0.35, 0.9), "ADD"))
    base = 1 - ramp(t, s1, s2)
    if base > 0:
        layers.append(("base", base, "BLEND"))
    leak = 1 - ramp(t, 0.3, 0.7)
    if leak > 0:
        layers.append(("leak", (hv["leak"] + (pk["leak"] - hv["leak"]) * ramp(t, 0, 0.18)) * leak, "ADD"))
    opened = ramp(t, s0, s1)
    if opened > 0:
        layers += [("open", opened, "BLEND"), ("pages", opened, "BLEND"), ("ribbons", opened, "BLEND")]
    turning = []   # (how upright, layers): the most upright is nearest the eye, so drawn last
    cover = media["rest"] + (180 - media["rest"]) * ease((t - c0) / (c1 - c0))
    if t < s1:
        turning.append((math.sin(math.radians(cover)), stepped(cover_name, cover, media["cover"], False)))
    p, pa = tm["pages"], media["page"]
    for i in range(p["n"]):
        ang = page_angle(i, t, p)
        if ang is None:
            continue
        if ang < pa[0]:
            parts = [(page_name(pa[0]), ang / pa[0], "BLEND")]
        elif ang > pa[-1]:
            parts = [(page_name(pa[-1]), (180 - ang) / (180 - pa[-1]), "BLEND")]
        else:
            parts = stepped(page_name, ang, pa, False)
        turning.append((math.sin(math.radians(ang)) + (i + 1) * 1e-4, parts))   # (a page never ties the cover)
    for _, parts in sorted(turning, key=lambda x: x[0]):
        layers += parts
    layers.append(("glowOpen", lit("glowOpen", front) * ramp(t, 0.2, 0.45), "ADD"))
    layers.append(("beam", lit("beam", front) * ramp(t, 0.15, 0.4), "ADD", size("beam")))
    layers.append(("shaftFront", lit("shaftFront", front) * ramp(t, 0.1, 0.4), "ADD", size("shaft")))
    e0, e1, e2 = tm["engulf"]
    layers.append(("haloFront", pk["haloFront"] * ramp(t, e0, e1) * (1 - ramp(t, e1, e2)) + st["haloFront"] * ramp(t, e1, e2),
                   "ADD", size("haloFront")))
    r0, r1 = tm["ring"]
    if r0 < t < r1:   # flung out fast at first, slowing (an ease out), fading as it goes
        u = (t - r0) / (r1 - r0)
        rg = pl["ring"]["grow"]
        layers.append(("ring", (1 - u) ** 1.5, "ADD", rg[0] + (rg[1] - rg[0]) * (1 - (1 - u) ** 2)))
    f0, f1, f2 = tm["flare"]
    fg = pl["flare"]["grow"]
    layers.append(("flare", ramp(t, f0, f1) * (1 - ramp(t, f1, f2)), "ADD", fg[0] + (fg[1] - fg[0]) * ramp(t, f0, f2)))
    return ramp(t, *tm["slide"]), layers


class Motes:
    """Golden motes rising from the pages, some of them twinkling stars: a burst flung out as the light
    bursts (burst motes over burstFor seconds from just after the pages start), then a few now and then.
    UI/ChronicleBook.lua (StepMotes, DrawMotes) does the same."""

    def __init__(self, tm, seed=3):
        self.tm, self.m = tm, tm["motes"]
        self.rng = np.random.default_rng(seed)
        self.list = []
        self.owed = 0.0

    def step(self, t, dt):
        """t: seconds since the click (the open book: any time after done)."""
        m = self.m
        start = self.tm["pages"]["start"] + 0.1
        if t >= start:
            burst = t < start + m["burstFor"]
            self.owed += (m["burst"] / m["burstFor"] if burst else m["ambient"]) * dt
            while self.owed >= 1:
                self.owed -= 1
                r = self.rng.random
                mote = dict(x=(r() - 0.5) * m["spread"], y=-(r() * 30), age=0.0,
                            life=m["life"][0] + r() * (m["life"][1] - m["life"][0]),
                            rise=m["rise"][0] + r() * (m["rise"][1] - m["rise"][0]),
                            size=m["size"][0] + r() * (m["size"][1] - m["size"][0]),
                            sway=(r() - 0.5) * 16, phase=r() * 6.28, star=r() < m["stars"], fx=0.0, fy=0.0)
                if burst:   # flung out in an upward fan, fast at first, then rising like the rest
                    far = m["fling"][0] + r() * (m["fling"][1] - m["fling"][0])
                    ang = math.radians(200 + r() * 140)
                    mote["fx"], mote["fy"] = far * math.cos(ang), far * math.sin(ang)
                self.list.append(mote)
        for m in self.list:
            m["age"] += dt
        self.list = [m for m in self.list if m["age"] < m["life"]]

    def drawn(self):
        """(x, y, size, alpha, part) for each: x, y from the book's light (UI/ChronicleBook.lua: DrawMotes)."""
        out = []
        for m in self.list:
            u = m["age"] / m["life"]
            a = min(1, u / 0.15) * (1 - max(0, (u - 0.6) / 0.4))
            size = m["size"]
            if m["star"]:   # a star twinkles, gently, and is drawn larger (its points are thin)
                a *= 0.6 + 0.4 * math.sin(m["phase"] + m["age"] * 7)
                size *= 1.7
            flung = 1 - math.exp(-5 * m["age"])
            out.append((m["x"] + m["fx"] * flung + m["sway"] * math.sin(m["phase"] + u * 4),
                        m["y"] + m["fy"] * flung - m["rise"] * u, size, a, "star" if m["star"] else "mote"))
        return out


def media_pieces(names):
    """A few pieces from the add-on's current Media.lua (the plate and the parchment, for the preview)."""
    text = (ADDON / "Media.lua").read_text(encoding="utf-8")
    out = {}
    for name in names:
        key = name if re.fullmatch(r"\w+", name) else '["' + name + '"]'
        for m in re.finditer(r"\n    " + re.escape(key) + r" = \{\n(.*?)\n    \}", text, re.S):
            body = dict(re.findall(r"(\w+) = ([^,\n]+),", m.group(1)))
            if "tex" in body:
                out[name] = {k: (v.strip('"') if v.startswith('"') else float(v)) for k, v in body.items()}
                break
    return out


def piece_image(textures, p):
    tex = textures[p["tex"]]
    return tex.crop((round(p["l"] * tex.width), round(p["t"] * tex.height),
                     round(p["r"] * tex.width), round(p["b"] * tex.height)))


def add_blend(dst, src, at, alpha):
    """Additive blend (the game's ADD): dst += src.rgb * src.a * alpha."""
    x, y = at
    w, h = src.size
    x0, y0, x1, y1 = max(0, x), max(0, y), min(dst.width, x + w), min(dst.height, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    d = np.asarray(dst, np.float32).copy()
    s = np.asarray(src, np.float32)[y0 - y:y1 - y, x0 - x:x1 - x]
    d[y0:y1, x0:x1, :3] += s[..., :3] * (s[..., 3:4] / 255) * alpha
    dst.paste(Image.fromarray(np.clip(d, 0, 255).astype(np.uint8), "RGBA"))


def over(dst, src, at, alpha):
    if alpha < 1:
        src = src.copy()
        src.putalpha(src.getchannel("A").point(lambda v: round(v * alpha)))
    x, y = at
    sx, sy = max(0, -x), max(0, -y)
    src = src.crop((sx, sy, min(src.width, dst.width - x), min(src.height, dst.height - y)))
    if src.width > 0 and src.height > 0:
        dst.alpha_composite(src, (max(0, x), max(0, y)))


class Stage:
    """The right column's Chronicle plate, with the book laid on it as the game lays it."""

    def __init__(self, skin, textures, pieces, media, kit):
        self.skin, self.textures, self.pieces, self.media = skin, textures, pieces, media
        self.cache = {}
        self.px, self.py = LEFT_M, TOP_M   # the plate's top-left
        size = ((LEFT_M + PLATE_W + RIGHT_M) * K, (TOP_M + PLATE_H + BOT_M) * K)
        self.bg = Image.new("RGBA", size, (0, 0, 0, 255))
        parch = kit["parch"]   # drawn at build.PARCH_SCALE (1.3) px per unit
        parch = parch.resize((round(parch.width * K / 1.3), round(parch.height * K / 1.3)), Image.LANCZOS)
        self.bg.alpha_composite(parch.crop((0, 0) + size))
        fonts = ADDON / "Media" / "Fonts"

        def u(v):
            return round(v * K)

        def rgba(hexa, a):
            return tuple(int(hexa[i:i + 2], 16) for i in (0, 2, 4)) + (round(a * 255),)

        # Who holds power's foot (Kit:Plate "plain": a pale fill, a dark line, a light band, a fainter line)
        ink = Image.new("RGBA", size, (0, 0, 0, 0))
        d = ImageDraw.Draw(ink)
        x1, y1 = LEFT_M - 20, TOP_M - 10
        d.rectangle((0, 0, u(x1) - 1, u(y1) - 1), fill=rgba("D9C49A", 0.3))
        for inset, width, hexa, a in ((0, 1, "6E4F17", 0.55), (1, 3, "F4EAD0", 0.55), (4, 1, "6E4F17", 0.3)):
            d.rectangle((0, u(y1 - inset - width), u(x1 - inset) - 1, u(y1 - inset) - 1), fill=rgba(hexa, a))
            d.rectangle((u(x1 - inset - width), 0, u(x1 - inset) - 1, u(y1 - inset) - 1), fill=rgba(hexa, a))
        # the last of Recent decrees: rows of 26, a gem, the line, how long ago, a faint rule
        text = ImageFont.truetype(str(fonts / "EBGaramond-Regular.ttf"), u(12.5))
        ital = ImageFont.truetype(str(fonts / "EBGaramond-Italic.ttf"), u(12))
        for k, (line, ago) in enumerate(reversed(DECREES)):
            foot = TOP_M - 18 - k * 26
            mid = foot - 13
            gx = LEFT_M + 6
            d.polygon([(u(gx), u(mid - 4)), (u(gx + 4), u(mid)), (u(gx), u(mid + 4)), (u(gx - 4), u(mid))],
                      fill=rgba("1B3570", 1))
            d.text((u(LEFT_M + 16), u(mid)), line, font=text, fill=rgba("5E4B33", 1), anchor="lm")
            d.text((u(LEFT_M + PLATE_W - 2), u(mid)), ago, font=ital, fill=rgba("5E4B33", 1), anchor="rm")
            d.rectangle((u(LEFT_M), u(foot) - 2, u(LEFT_M + PLATE_W) - 1, u(foot) - 1), fill=rgba("6E4F17", 0.3))
        # the scroll bar
        bx = LEFT_M + PLATE_W + 12
        d.rectangle((u(bx), 0, u(bx + 10) - 1, size[1]), fill=rgba("6E4F17", 0.25))
        d.rectangle((u(bx + 2), u(TOP_M + 40), u(bx + 8) - 1, u(TOP_M + PLATE_H - 10)), fill=rgba("C9A24A", 0.9))
        self.bg.alpha_composite(ink)
        plate, p = kit["plate"]
        # Kit:PlateArt: the drawn plate (206 x 158 box, its shadow round it) stretched to the box
        pw, ph = PLATE_W + (p["w"] - 206), PLATE_H + (p["h"] - 158)
        over(self.bg, plate.resize((u(pw), u(ph)), Image.LANCZOS), (u(self.px + p["x"]), u(self.py + p["y"])), 1)
        draw = ImageDraw.Draw(self.bg)
        font = ImageFont.truetype(str(fonts / "Cinzel-Bold.ttf"), u(11))
        x = (self.px + 16) * K
        for ch in "STATUTE BOOK":
            draw.text((x, (self.py + 11) * K), ch, font=font, fill=(243, 217, 138, 255))
            x += draw.textlength(ch, font=font) + 0.22 * 11 * K
        # where the page's scroll area cuts the light: the plate's right edge and its foot
        self.cut = (u(self.px + PLATE_W), u(self.py + PLATE_H))

    def img(self, part, size=None):
        name = f"chronicle_{self.skin}:{part}"
        if name not in self.pieces:
            name = f"chronicle:{part}"
        key = (name, size)
        if key not in self.cache:
            p = self.pieces[name]
            im = piece_image(self.textures, p)
            w, h = size or (p["w"], p["h"])
            self.cache[key] = (im.resize((max(1, round(w * K)), max(1, round(h * K))), Image.LANCZOS), p)
        return self.cache[key]

    def origin(self, slide):
        """The scene's top-left: the closed book centred on the plate with its foot BOOK_FOOT above the
        plate's foot; the open book centred with its foot at the same height; slide moves between them."""
        cb, ob = self.media["closed"], self.media["open"]
        foot = self.py + PLATE_H - BOOK_FOOT
        cx = self.px + PLATE_W / 2
        closed = (cx - (cb["x"] + cb["w"] / 2), foot - (cb["y"] + cb["h"]))
        opened = (cx - (ob["x"] + ob["w"] / 2), foot - (ob["y"] + ob["h"]))
        s = ease(slide)
        return tuple(a + (b - a) * s for a, b in zip(closed, opened))

    def frame(self, slide, layers, motes=(), live=None, count=None):
        im = self.bg.copy()
        if count:   # the count at the plate's top right (Max, 10 Nov), in the plate's pale ink
            d = ImageDraw.Draw(im)
            f = ImageFont.truetype(str(ADDON / "Media" / "Fonts" / "EBGaramond-Italic.ttf"), round(12.5 * K))
            d.text(((self.px + PLATE_W - 16) * K - d.textlength(count, font=f), (self.py + 11) * K), count,
                   font=f, fill=(201, 214, 245, 255))
        ox, oy = self.origin(slide)
        cb, ob = self.media["closed"], self.media["open"]
        place = self.media["timing"]["place"]
        s = ease(slide)
        here = {k: cb[k] + (ob[k] - cb[k]) * s for k in ("x", "y", "w", "h")}   # the book's box now: the lights' middle
        for layer in layers:
            part, alpha, blend = layer[:3]
            grow = layer[3] if len(layer) > 3 else 1
            if alpha <= 0.003:
                continue
            # the lights' places, and their pictures (the front shaft and the swell are the shaft and the halo again)
            light = "rays" if part.startswith("rays") else "shaft" if part == "shaftFront" else part
            image = {"shaftFront": "shaft", "haloFront": "halo"}.get(part, part)
            if part == "shadow":   # under the book's foot, widening as it opens
                w = cb["w"] + (ob["w"] - cb["w"]) * s
                src, _ = self.img("shadow", (w * 1.04, 30))
                mid = cb["x"] + cb["w"] / 2 + (ob["x"] + ob["w"] / 2 - cb["x"] - cb["w"] / 2) * s
                foot = cb["y"] + cb["h"] + (ob["y"] + ob["h"] - cb["y"] - cb["h"]) * s
                at = (ox + mid - w * 0.52, oy + foot - 22)
            elif light in place:   # a light: its middle on the book's middle, at its share down
                pl = place[light]
                w, h = pl["w"] * grow, pl["h"] * grow
                src, _ = self.img(image, (round(w), round(h)))
                at = (ox + here["x"] + here["w"] / 2 - w / 2, oy + here["y"] + here["h"] * pl["y"] - h / 2)
            else:
                src, p = self.img(part)
                at = (ox + p["x"], oy + p["y"])
            at = (round(at[0] * K), round(at[1] * K))
            (add_blend if blend == "ADD" else over)(im, src, at, min(1, alpha))
        for x, y, size, a, kind in motes:
            src, _ = self.img(kind, (round(size), round(size)))
            add_blend(im, src, (round((ox + here["x"] + here["w"] / 2 + x - size / 2) * K),
                                round((oy + here["y"] + here["h"] * 0.45 + y - size / 2) * K)), a)
        cx, cy = self.cut   # past the scroll area's edges the page shows as it is
        im.paste(self.bg.crop((cx, 0, im.width, im.height)), (cx, 0))
        im.paste(self.bg.crop((0, cy, cx, im.height)), (0, cy))
        if live:
            ll = self.media["liveLine"]
            f = ImageFont.truetype(str(ADDON / "Media" / "Fonts" / "EBGaramond-Italic.ttf"), round(6 * K))
            d = ImageDraw.Draw(im)
            tw = d.textlength(live, font=f)
            d.text((round((ox + ll["x"] + ll["w"] / 2) * K - tw / 2), round((oy + ll["y"] - 1) * K)), live,
                   font=f, fill=(94, 60, 30, 255))
        return im


def kit_images():
    """The plate per skin and the parchment, from the add-on's Media (as the game has them now)."""
    ps = media_pieces(["kitBlue", "kitBlue~cr", "kitBlue~ex", "parch"])
    tex = {}
    for p in ps.values():
        if p["tex"] not in tex:
            tex[p["tex"]] = Image.open(ADDON / "Media" / f"{p['tex']}.tga").convert("RGBA")
    plate_for = {"ministry": "kitBlue", "silverhand": "kitBlue", "exchange": "kitBlue~ex", "crown": "kitBlue~cr"}
    parch = piece_image(tex, ps["parch"])
    return {skin: {"plate": (piece_image(tex, ps[name]), ps[name]), "parch": parch} for skin, name in plate_for.items()}


def opened_frame(stage, tm, media, seed):
    motes = Motes(tm, seed=seed)
    t, dt = 0.0, 1 / 30
    end = tm["done"] + 1.2
    while t < end:
        motes.step(t, dt)
        t += dt
    slide, layers = state(end, 0, tm, media, spin=end)
    return stage.frame(slide, layers, motes.drawn(), live=LIVE)


def book_picture(textures, pieces, media, parts, box, skin="ministry"):
    """The book alone on a clear ground at 2x, cut to its box (for the Throne Room board)."""
    im = Image.new("RGBA", (round(box["w"] * K), round(box["h"] * K)), (0, 0, 0, 0))
    for part in parts:
        name = f"chronicle_{skin}:{part}" if f"chronicle_{skin}:{part}" in pieces else f"chronicle:{part}"
        p = pieces[name]
        src = piece_image(textures, p).resize((round(p["w"] * K), round(p["h"] * K)), Image.LANCZOS)
        over(im, src, (round((p["x"] - box["x"]) * K), round((p["y"] - box["y"]) * K)), 1)
    return im


def preview(textures, pieces, media, out, gif_skins=("ministry",)):
    """Saves stills of every skin (closed, hovered, open), a GIF of the book opening, and the closed
    and open book alone for the Throne Room board (chronicle-closed.png, chronicle-open.png)."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    book_picture(textures, pieces, media, ["base", cover_name(0)], media["closed"]).save(out / "chronicle-closed.png")
    book_picture(textures, pieces, media, ["open", "pages", "ribbons"], media["open"]).save(out / "chronicle-open.png")
    kits = kit_images()
    tm = media["timing"]
    rows = []
    for skin in SKINS:
        stage = Stage(skin, textures, pieces, media, kits[skin])
        shots = [stage.frame(*state(-1, 0, tm, media)), stage.frame(*state(-1, 1, tm, media)),
                 opened_frame(stage, tm, media, 5)]
        row = Image.new("RGBA", (shots[0].width * 3, shots[0].height), (0, 0, 0, 255))
        for i, im in enumerate(shots):
            row.alpha_composite(im, (i * shots[0].width, 0))
        row.save(out / f"chronicle-{skin}.png")
        rows.append(row)
    sheet = Image.new("RGBA", (rows[0].width, sum(r.height for r in rows)), (0, 0, 0, 255))
    for i, r in enumerate(rows):
        sheet.alpha_composite(r, (0, i * r.height))
    sheet.save(out / "chronicle-skins.png")

    for skin in gif_skins:
        stage = Stage(skin, textures, pieces, media, kits[skin])
        motes = Motes(tm, seed=9)
        frames, fps = [], 30
        dt = 1 / fps
        for i in range(int(0.9 * fps)):             # resting, then the mouse arrives and the cover lifts
            lift = 0 if i < 8 else 1 - math.exp(-(i - 8) * dt / tm["lift"])
            frames.append(stage.frame(*state(-1, lift, tm, media)))
        t, steps, keys = 0.0, [], [0.15, 0.32, 0.65, 1.0, 1.45, tm["done"] + 0.5]
        while t < tm["done"] + 1.6:
            motes.step(t, dt)
            slide, layers = state(t, 1, tm, media, spin=t)
            frames.append(stage.frame(slide, layers, motes.drawn(), live=LIVE if t >= tm["done"] else None))
            if keys and t >= keys[0] - 1e-6:
                keys.pop(0)
                steps.append(frames[-1])
            t += dt
        strip = Image.new("RGBA", (steps[0].width * 3, steps[0].height * 2), (0, 0, 0, 255))
        for i, im in enumerate(steps):
            strip.alpha_composite(im, ((i % 3) * im.width, (i // 3) * im.height))
        strip.save(out / f"chronicle-steps-{skin}.png")
        # small enough to send to a phone: 60% of the stills' size
        cut = (0, 0, frames[0].width, frames[0].height)
        size = (round(frames[0].width * 0.6), round((cut[3] - cut[1]) * 0.6))
        flat = [f.crop(cut).resize(size, Image.LANCZOS).convert("RGB")
                .quantize(colors=200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
        durations = [round(1000 / fps)] * len(flat)
        durations[-1] = 1500
        flat[0].save(out / f"chronicle-opening-{skin}.gif", save_all=True, append_images=flat[1:],
                     duration=durations, loop=0)
    return out


if __name__ == "__main__":
    import build as builder  # Edge, the packer and the fonts

    fonts = "\n".join(
        f"@font-face{{font-family:'{fam}';font-weight:{w};font-style:{st};src:url({(builder.FONTS / f).as_uri()})}}"
        for fam, w, st, f in builder.FONT_FACES)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = Path(args[0]) if args else Path(tempfile.gettempdir()) / "mota-chronicle"
    out.mkdir(parents=True, exist_ok=True)
    if "--reuse" in sys.argv:   # the pictures drawn last time; only the preview again (for tuning the timings)
        saved = json.loads((out / "book.json").read_text(encoding="utf-8"))
        pieces, media = saved["pieces"], dict(saved["media"], timing=TIMING)
        textures = {name: Image.open(out / f"{name}.png").convert("RGBA") for name in saved["textures"]}
    else:
        work = Path(tempfile.mkdtemp(prefix="mota-chronicle-"))
        textures, pieces, media = build(builder.Edge(work), builder.pack, fonts)
        for name, im in textures.items():
            im.save(out / f"{name}.png")
            print(f"  {name}: {im.width} x {im.height}")
        (out / "book.json").write_text(json.dumps({"pieces": pieces, "media": media, "textures": list(textures)}),
                                       encoding="utf-8")
    print(json.dumps({k: v for k, v in media.items() if k != "timing"}))
    if "--no-preview" not in sys.argv:
        preview(textures, pieces, media, out)
    print(f"Previews in {out}")
