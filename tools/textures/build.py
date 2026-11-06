"""Turns the design canvas into game textures for the add-on.

It renders tools/textures/layout.html (the add-on window, laid out with the
canvas's own stylesheet, design/canvas-source/ministry.css) in Microsoft Edge,
one piece at a time, crops each piece, packs them into textures and writes:

  addon/MinistryOfTheAllied/Media/*.tga   the textures the game loads
  addon/MinistryOfTheAllied/Media.lua     where each piece sits in the window

Run it again whenever the design changes:   python tools/textures/build.py
Needs Microsoft Edge and Python 3 with Pillow. Add --preview to also save a
picture of the assembled window (in the system temp folder) for checking.
"""
import concurrent.futures
import html
import json
import re
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DESIGN = ROOT / "design"
ADDON = ROOT / "addon" / "MinistryOfTheAllied"
MEDIA = ADDON / "Media"
FONTS = MEDIA / "Fonts"

EDGE_PATHS = [
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]

WIN_X, WIN_Y = 140, 140      # the window's top-left corner in layout.html
WIN_W, WIN_H = 1000, 680
VIEW_W, VIEW_H = 1400, 960   # the page size Edge renders
ATLAS_SCALE = 2              # small pieces are drawn at twice their size, for sharpness
CHROME_SCALE = 1.46          # the big window background: as sharp as fits in 2048 x 1024
ATLAS_WIDTH = 1024
PAD = 2

# The canvas stores its textures under /_blob/ names; these are the same files in the repo.
BLOBS = {
    "c2d86e49cc4f265a0371294274387bd7": "textures/leather-grain.svg",
    "6d5fbe8d4c5384d8cf626886038701ac": "textures/filigree-corner.svg",
    "d4a81ff364cfd13a95212c60a73bd187": "textures/parchment-grain.svg",
    "83dde6b367275cb6d4d9550c6c74c5ac": "textures/tab-frame.svg",
    "e91083b63eec292d284b54d9d2ba82db": "textures/divider-ink.svg",
}

FONT_FACES = [
    ("Cinzel", 600, "normal", "Cinzel-SemiBold.ttf"),
    ("Cinzel", 700, "normal", "Cinzel-Bold.ttf"),
    ("Cinzel Decorative", 700, "normal", "CinzelDecorative-Bold.ttf"),
    ("Cinzel Decorative", 900, "normal", "CinzelDecorative-Black.ttf"),
    ("EB Garamond", 400, "normal", "EBGaramond-Regular.ttf"),
    ("EB Garamond", 500, "normal", "EBGaramond-Medium.ttf"),
    ("EB Garamond", 400, "italic", "EBGaramond-Italic.ttf"),
]

# Tab icons, from the canvas boards.
ICONS = {
    "throne": '<path d="M3 19h18M4.5 19 3.5 8l5 4 3.5-7 3.5 7 5-4-1 11"></path>',
    "ballot": '<path d="M4 11h16v9H4zM8 11V4h8v7M10 7.5h4M9 15.5h6"></path>',
    "statute": '<path d="M7 4h11a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H7a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3zM4 7h3M9.5 9h7M9.5 12.5h7M9.5 16h4.5"></path>',
    "parties": '<path d="M5 21V3.5M5 4h8.5l-2 3 2 3H5M13 21V9M13 9.5h7l-2 3 2 3h-7"></path>',
    "treasury": '<ellipse cx="12" cy="6" rx="7" ry="2.6"></ellipse><path d="M5 6v4c0 1.4 3.1 2.6 7 2.6s7-1.2 7-2.6V6M5 10v4c0 1.4 3.1 2.6 7 2.6s7-1.2 7-2.6v-4M5 14v4c0 1.4 3.1 2.6 7 2.6s7-1.2 7-2.6v-4"></path>',
    "districts": '<path d="M3 6.5 9 4l6 2.5L21 4v13.5L15 20l-6-2.5L3 20zM9 4v13.5M15 6.5V20"></path>',
    "ring": '<path d="M4 4l10.5 10.5M4 4h3.5l9 9M4 4v3.5l9 9M13 17.5l4.5-4.5M15.5 15.5l4 4M20 4l-10.5 10.5M20 4h-3.5l-9 9M20 4v3.5l-9 9M11 17.5 6.5 13M8.5 15.5l-4 4"></path>',
}

# Slots: places in the window where the add-on draws live text or buttons.
SLOTS = [f"tab{i}" for i in range(1, 8)] + [
    "title", "subtitle", "knob-settings", "knob-close", "page", "parch", "eyebrow", "heading",
    "divider", "note", "note2", "railfoot", "portrait", "initials", "who", "who-small",
    "foot", "foot-left", "foot-right", "pip", "crest", "seal", "sheen",
]


def find_edge():
    for p in EDGE_PATHS:
        if p.exists():
            return p
    sys.exit("Microsoft Edge wasn't found.")


def stylesheet():
    css = (DESIGN / "canvas-source" / "ministry.css").read_text(encoding="utf-8")
    for blob, rel in BLOBS.items():
        css = css.replace(f"/_blob/{blob}", (DESIGN / rel).as_uri())
    css = css.replace(":hover", ".hover")  # so a hover look can be switched on for rendering
    faces = "\n".join(
        f"@font-face{{font-family:'{fam}';font-weight:{w};font-style:{st};src:url({(FONTS / f).as_uri()})}}"
        for fam, w, st, f in FONT_FACES)
    base = ("html,body{margin:0;background:transparent!important}"
            "*{animation:none!important;transition:none!important}"
            ".tab.on::before{display:none!important}")
    return faces + "\n" + css + "\n" + base


def page_html(pages, css, *, page=0, hover_tab=None, piece_css=""):
    tabs = []
    for i, p in enumerate(pages, 1):
        cls = "tab" + (" on" if i == 1 else "") + (" hover" if i == hover_tab else "")
        tabs.append(
            f'      <a class="{cls}" id="tab{i}"><svg id="icon{i}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{ICONS[p["id"]]}</svg>'
            f'<span id="label{i}">{html.escape(p["label"], quote=False)}'
            f'<small id="small{i}">{html.escape(p["small"], quote=False)}</small></span></a>')
    p = pages[page]
    text = (HERE / "layout.html").read_text(encoding="utf-8")
    subs = {
        "css": css + "\n" + piece_css,
        "tabs": "\n".join(tabs),
        "crest": (DESIGN / "textures" / "alliance-crest.png").as_uri(),
        "seal": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
        "subtitle": html.escape(p["subtitle"], quote=False),
        "eyebrow": html.escape(p["eyebrow"], quote=False),
        "heading": html.escape(p["heading"], quote=False),
        "note": html.escape(p["note"], quote=False),
    }
    return re.sub(r"\{\{(\w+)\}\}", lambda m: subs[m.group(1)], text)


def only(show, hide=(), extra=""):
    """CSS that hides everything except the piece being drawn."""
    css = "body *{visibility:hidden!important}\n"
    css += ",".join(show) + "{visibility:visible!important}\n"
    if hide:
        css += ",".join(hide) + "{visibility:hidden!important}\n"
    return css + extra


def pieces_to_draw(pages):
    """name -> (texture, scale, page index, hover tab, css)"""
    white = "{color:#fff!important}"
    d = {
        "chrome": ("chrome", CHROME_SCALE, 0, None, only(
            ["#rim", "#rim *", ".corner", "#title", "#page", "#parch"],
            extra=".win-rim{box-shadow:0 0 0 1px #2a1d06!important}")),
        "tabRest": ("atlas", ATLAS_SCALE, 0, None, only(["#tab2"])),
        "tabHover": ("atlas", ATLAS_SCALE, 0, 2, only(["#tab2"])),
        "tabOn": ("atlas", ATLAS_SCALE, 0, None, only(["#tab1"])),
        "divider": ("atlas", 1.6, 0, None, only(["#divider"])),  # 600 wide: 1.6x is what fits
        "knobSettings": ("atlas", ATLAS_SCALE, 0, None, only(["#knob-settings", "#knob-settings *"])),
        "knobClose": ("atlas", ATLAS_SCALE, 0, None, only(["#knob-close", "#knob-close *"])),
        "portrait": ("atlas", ATLAS_SCALE, 0, None, only(["#portrait"], ["#initials"])),
        "railLine": ("atlas", ATLAS_SCALE, 0, None, only(["#railfoot"])),
        "pip": ("atlas", ATLAS_SCALE, 0, None, only(["#pip"])),
        "sheen": ("atlas", ATLAS_SCALE, 0, None, only(["#sheen"])),
        "crest": ("crest", ATLAS_SCALE, 0, None, only(["#crest"])),
        "seal": ("seal", ATLAS_SCALE, 0, None, only(["#seal"])),
    }
    for i in range(1, len(pages) + 1):
        d[f"icon{i}"] = ("atlas", ATLAS_SCALE, 0, None, only([f"#icon{i}", f"#icon{i} *"], extra=f"#icon{i}{white}"))
        d[f"label{i}"] = ("atlas", ATLAS_SCALE, 0, None, only([f"#label{i}"], [f"#small{i}"], f"#label{i}{white}"))
        d[f"small{i}"] = ("atlas", ATLAS_SCALE, 0, None, only([f"#small{i}"], extra=f"#small{i}{white}"))
        d[f"subtitle{i}"] = ("atlas", ATLAS_SCALE, i - 1, None, only(["#subtitle"]))
        d[f"eyebrow{i}"] = ("atlas", ATLAS_SCALE, i - 1, None, only(["#eyebrow"]))
    return d


class Edge:
    def __init__(self, workdir):
        self.exe = str(find_edge())
        self.workdir = workdir
        self.local = threading.local()
        self.count = 0
        self.lock = threading.Lock()

    def _profile(self):
        if not hasattr(self.local, "profile"):
            with self.lock:
                self.count += 1
                self.local.profile = self.workdir / f"profile{self.count}"
        return self.local.profile

    def _args(self, scale):
        return [self.exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                "--no-default-browser-check", "--disable-extensions", f"--user-data-dir={self._profile()}",
                f"--force-device-scale-factor={scale}", "--default-background-color=00000000",
                f"--window-size={VIEW_W},{VIEW_H}", "--virtual-time-budget=5000"]

    def screenshot(self, name, text, scale):
        page = self.workdir / f"{name}.html"
        png = self.workdir / f"{name}.png"
        page.write_text(text, encoding="utf-8")
        subprocess.run(self._args(scale) + [f"--screenshot={png}", page.as_uri()],
                       capture_output=True, timeout=180)
        if not png.exists():
            raise RuntimeError(f"Edge didn't draw {name}")
        return Image.open(png).convert("RGBA")

    def rects(self, text):
        page = self.workdir / "rects.html"
        page.write_text(text, encoding="utf-8")
        out = subprocess.run(self._args(1) + ["--dump-dom", page.as_uri()],
                             capture_output=True, timeout=180, text=True, encoding="utf-8")
        m = re.search(r'<pre id="rects-json"[^>]*>(.*?)</pre>', out.stdout, re.S)
        if not m:
            raise RuntimeError("Edge didn't report the layout")
        return json.loads(html.unescape(m.group(1)))


def crop(im, scale):
    alpha = im.getchannel("A").point(lambda v: 255 if v > 3 else 0)
    box = alpha.getbbox()
    if not box:
        raise RuntimeError("a piece came out empty")
    l, t, r, b = box
    l, t = max(0, l - 1), max(0, t - 1)
    r, b = min(im.width, r + 1), min(im.height, b + 1)
    return im.crop((l, t, r, b)), {
        "x": l / scale - WIN_X, "y": t / scale - WIN_Y, "w": (r - l) / scale, "h": (b - t) / scale}


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def pack(items):
    """Shelf-packs (name, image) pairs into one atlas. Returns the image and positions."""
    items = sorted(items, key=lambda it: (-it[1].height, it[0]))
    x = y = shelf = 0
    spots = {}
    for name, im in items:
        if im.width + 2 * PAD > ATLAS_WIDTH:
            raise RuntimeError(f"{name} is too wide for the atlas")
        if x + im.width + 2 * PAD > ATLAS_WIDTH:
            x, y, shelf = 0, y + shelf, 0
        spots[name] = (x + PAD, y + PAD)
        x += im.width + 2 * PAD
        shelf = max(shelf, im.height + 2 * PAD)
    height = pow2(y + shelf)
    atlas = Image.new("RGBA", (ATLAS_WIDTH, height), (0, 0, 0, 0))
    for name, im in items:
        atlas.paste(im, spots[name])
    return atlas, spots


def on_canvas(im, size=None):
    """Places an image at the top-left of a power-of-two canvas."""
    w, h = size or (pow2(im.width), pow2(im.height))
    if im.width > w or im.height > h:
        raise RuntimeError(f"{im.size} doesn't fit in {w} x {h}")
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.paste(im, (0, 0))
    return canvas


def shadow_texture():
    """The window's soft drop shadow, drawn as a nine-slice: corners 112, centre 32."""
    im = Image.new("L", (256, 256), 0)
    ImageDraw.Draw(im).rounded_rectangle((96, 96, 160, 160), radius=9, fill=255)
    im = im.filter(ImageFilter.GaussianBlur(30))
    rgba = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    rgba.putalpha(im.point(lambda v: int(v * 0.85)))
    return rgba


def lua_value(v, indent=""):
    if isinstance(v, dict):
        inner = indent + "  "
        parts = []
        for k in sorted(v, key=str):
            key = k if re.fullmatch(r"[A-Za-z_]\w*", str(k)) else "[" + json.dumps(k) + "]"
            parts.append(f"{inner}{key} = {lua_value(v[k], inner)},")
        return "{\n" + "\n".join(parts) + "\n" + indent + "}"
    if isinstance(v, list):
        inner = indent + "  "
        return "{\n" + "\n".join(f"{inner}{lua_value(x, inner)}," for x in v) + "\n" + indent + "}"
    if isinstance(v, float):
        return f"{v:.5f}".rstrip("0").rstrip(".")
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    return str(v)


def main():
    pages = json.loads((HERE / "pages.json").read_text(encoding="utf-8"))
    css = stylesheet()
    MEDIA.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="mota-textures-"))
    edge = Edge(work)
    print("Reading the layout...")
    rects = edge.rects(page_html(pages, css))
    slots = {k: rects[k] for k in SLOTS}

    todo = pieces_to_draw(pages)
    print(f"Drawing {len(todo)} pieces in Edge...")
    drawn = {}

    def draw(name):
        tex, scale, page, hover, piece_css = todo[name]
        im = edge.screenshot(name, page_html(pages, css, page=page, hover_tab=hover, piece_css=piece_css), scale)
        return name, crop(im, scale)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name, result in pool.map(draw, todo):
            drawn[name] = result

    pieces = {}
    textures = {}

    def place(name, tex, size, spot):
        im, pos = drawn[name]
        x, y = spot
        pieces[name] = dict(pos, tex=tex, l=x / size[0], r=(x + im.width) / size[0],
                            t=y / size[1], b=(y + im.height) / size[1])

    atlas_items = [(n, drawn[n][0]) for n, v in todo.items() if v[0] == "atlas"]
    atlas, spots = pack(atlas_items)
    for name, _ in atlas_items:
        place(name, "atlas", atlas.size, spots[name])
    textures["atlas"] = atlas

    for name, size in (("chrome", (2048, 1024)), ("crest", None), ("seal", None)):
        canvas = on_canvas(drawn[name][0], size)
        place(name, name, canvas.size, (0, 0))
        textures[name] = canvas
    textures["shadow"] = shadow_texture()

    for name, im in textures.items():
        im.save(MEDIA / f"{name}.tga")
        print(f"  Media/{name}.tga  {im.width} x {im.height}")

    media = {
        "dir": "Interface\\AddOns\\MinistryOfTheAllied\\Media\\",
        "window": {"w": WIN_W, "h": WIN_H},
        "textures": {name: f"{name}.tga" for name in textures},
        "shadow": {"inset": 96, "corner": 112, "size": 256},
        "pieces": pieces,
        "slots": slots,
        "pages": pages,
    }
    lua = ("-- Generated by tools/textures/build.py from the design canvas. Don't edit by hand:\n"
           "-- change the design or layout.html, then run the script again.\n"
           "-- Positions are in window units from the window's top-left corner (y goes down);\n"
           "-- l, r, t, b are the piece's texture coordinates.\n\n"
           "local _, MotA = ...\n\nMotA.Media = " + lua_value(media) + "\n")
    (ADDON / "Media.lua").write_text(lua, encoding="utf-8", newline="\n")
    print("  Media.lua")

    if "--preview" in sys.argv:
        out = Path(tempfile.gettempdir()) / "mota-window-preview.png"
        preview(pieces, textures, out)
        print(f"Preview: {out}")


def preview(pieces, textures, out):
    """Assembles the window roughly the way the add-on does, for checking."""
    s = 1.0
    ox, oy = 120, 120
    img = Image.new("RGBA", (WIN_W + 240, WIN_H + 240), (17, 19, 27, 255))

    def put(name, dx=0, dy=0, tint=None):
        p = pieces[name]
        tex = textures[p["tex"]]
        W, H = tex.size
        part = tex.crop((round(p["l"] * W), round(p["t"] * H), round(p["r"] * W), round(p["b"] * H)))
        part = part.resize((max(1, round(p["w"] * s)), max(1, round(p["h"] * s))), Image.LANCZOS)
        if tint:
            r, g, b = (int(tint[i:i + 2], 16) for i in (0, 2, 4))
            solid = Image.new("RGBA", part.size, (r, g, b, 255))
            solid.putalpha(part.getchannel("A"))
            part = solid
        img.alpha_composite(part, (round(ox + (p["x"] + dx) * s), round(oy + (p["y"] + dy) * s)))

    put("chrome")
    tab1y = 0
    for i in range(1, 8):
        dy = (i - 1) * 57
        if i == 1:
            put("tabOn")
        else:
            put("tabRest", 0, dy - 57)
        put(f"icon{i}", tint="0E1F45" if i == 1 else "E5CF92")
        put(f"label{i}", tint="0E1F45" if i == 1 else "E5CF92")
        put(f"small{i}", tint="3A2A0A" if i == 1 else "EBC3B2")
    for name in ("subtitle1", "eyebrow1", "divider", "knobSettings", "knobClose", "portrait", "railLine", "pip", "crest"):
        put(name)
    img.save(out)


if __name__ == "__main__":
    main()
