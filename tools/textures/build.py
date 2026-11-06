"""Turns the design canvas into game textures for the add-on.

It renders two layouts in Microsoft Edge, one piece at a time, with the
canvas's own stylesheet (design/canvas-source/ministry.css):

  tools/textures/layout.html   the add-on window (Throne Room board)
  tools/textures/extras.html   the herald pop-up and the settings page (Extras board)

then crops each piece, packs them into textures and writes:

  addon/MinistryOfTheAllied/Media/*.tga   the textures the game loads
  addon/MinistryOfTheAllied/Media.lua     where each piece sits

The live design canvas is the source of truth: refresh design/canvas-source/
from it first, then run   python tools/textures/build.py
Needs Microsoft Edge and Python 3 with Pillow. Add --preview to also save
pictures of the assembled window and herald (in the system temp folder).
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
SEALS = ["official", "crown", "exchange", "silverhand"]

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

# Herald buttons drawn ready-made: the label and the style ("blue" is .btn, "quiet" is .btn.quiet).
HERALD_BUTTONS = ["Vote now", "Read it", "Open", "Dismiss", "Stop", "Restart"]

# Slots: places where the add-on draws live text or buttons, by root.
SLOTS = {
    "win": [f"tab{i}" for i in range(1, 8)] + [
        "title", "subtitle", "knob-settings", "knob-close", "page", "parch", "eyebrow", "heading",
        "divider", "note", "note2", "railfoot", "portrait", "initials", "who", "who-small",
        "foot", "foot-left", "foot-right", "pip", "crest", "seal", "sheen"],
    "kit": ["kit"],
    "herald": ["herald", "hseal", "htext", "heyebrow", "htitle", "hbody", "hbutton"],
    "settings": ["settings", "sparch", "sseal", "seyebrow", "stitle", "seg", "seg-modest", "seg-royal"]
    + [f"row{i}" for i in range(1, 6)] + [f"slabel{i}" for i in range(1, 6)]
    + [f"ssmall{i}" for i in range(1, 6)] + [f"sw{i}" for i in range(1, 5)],
}


def find_edge():
    for p in EDGE_PATHS:
        if p.exists():
            return p
    sys.exit("Microsoft Edge wasn't found.")


def local_css(css):
    for blob, rel in BLOBS.items():
        css = css.replace(f"/_blob/{blob}", (DESIGN / rel).as_uri())
    return css.replace(":hover", ".hover")  # so a hover look can be switched on for rendering


def stylesheet(board=None):
    """The canvas stylesheet, the fonts, and optionally one board's own styles."""
    css = local_css((DESIGN / "canvas-source" / "ministry.css").read_text(encoding="utf-8"))
    if board:
        text = (DESIGN / "canvas-source" / board).read_text(encoding="utf-8")
        m = re.search(r"<helmet>.*?<style>(.*?)</style>", text, re.S)
        css += "\n" + local_css(m.group(1))
    faces = "\n".join(
        f"@font-face{{font-family:'{fam}';font-weight:{w};font-style:{st};src:url({(FONTS / f).as_uri()})}}"
        for fam, w, st, f in FONT_FACES)
    base = ("html,body{margin:0;background:transparent!important}"
            "*{animation:none!important;transition:none!important}"
            ".tab.on::before{display:none!important}")
    return faces + "\n" + css + "\n" + base


def board_styles(board):
    """One more board's own styles, for parts drawn alongside another board's."""
    text = (DESIGN / "canvas-source" / board).read_text(encoding="utf-8")
    return "\n" + local_css(re.search(r"<helmet>.*?<style>(.*?)</style>", text, re.S).group(1))


def fill(template, subs):
    text = (HERE / template).read_text(encoding="utf-8")
    return re.sub(r"\{\{(\w+)\}\}", lambda m: subs[m.group(1)], text)


def window_html(pages, css, piece_css="", page=0, hover_tab=None):
    tabs = []
    for i, p in enumerate(pages, 1):
        cls = "tab" + (" on" if i == 1 else "") + (" hover" if i == hover_tab else "")
        tabs.append(
            f'      <a class="{cls}" id="tab{i}"><svg id="icon{i}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{ICONS[p["id"]]}</svg>'
            f'<span id="label{i}">{html.escape(p["label"], quote=False)}'
            f'<small id="small{i}">{html.escape(p["small"], quote=False)}</small></span></a>')
    p = pages[page]
    return fill("layout.html", {
        "css": css + "\n" + piece_css,
        "tabs": "\n".join(tabs),
        "crest": (DESIGN / "textures" / "alliance-crest.png").as_uri(),
        "seal": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
        "subtitle": html.escape(p["subtitle"], quote=False),
        "eyebrow": html.escape(p["eyebrow"], quote=False),
        "heading": html.escape(p["heading"], quote=False),
        "note": html.escape(p["note"], quote=False),
    })


def extras_html(css, piece_css="", seal="official", button="Vote now", style="blue", seg="full"):
    return fill("extras.html", {
        "css": css + "\n" + piece_css,
        "seal": (DESIGN / "textures" / f"seal-{seal}.svg").as_uri(),
        "crown": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
        "button": html.escape(button, quote=False),
        "button_class": "btn sm" if style == "blue" else "btn quiet sm",
        "modest_class": "on" if seg == "small" else "",
        "royal_class": "on" if seg == "full" else "",
    })


def only(show, hide=(), extra=""):
    """CSS that hides everything except the piece being drawn."""
    css = "body *{visibility:hidden!important}\n"
    css += ",".join(show) + "{visibility:visible!important}\n"
    if hide:
        css += ",".join(hide) + "{visibility:hidden!important}\n"
    return css + extra


def slug(text):
    return re.sub(r"\W+", "", text.title())


def pieces_to_draw(pages):
    """name -> dict(tex, scale, layout, root, args, css)"""
    white = "{color:#fff!important}"
    d = {}

    def win(name, css, tex="atlas", scale=ATLAS_SCALE, **args):
        d[name] = dict(tex=tex, scale=scale, layout="window", root="win", args=args, css=css)

    def herald(name, css, tex="extras", scale=ATLAS_SCALE, **args):
        d[name] = dict(tex=tex, scale=scale, layout="extras", root="herald", args=args, css=css)

    def settings(name, css, tex="extras", scale=ATLAS_SCALE, **args):
        d[name] = dict(tex=tex, scale=scale, layout="extras", root="settings", args=args, css=css)

    # Parts for page contents (UI/Kit.lua)
    for name in ("kitBlue", "kitRibbonOn1", "kitRibbonOn2", "kitRibbonOn3", "kitRibbonOn4", "kitRibbonOff1",
                 "kitRibbonOff2", "kitRibbonOff3", "kitGem", "kitGemHollow", "kitCoinG", "kitCoinS", "kitBand",
                 "kitStepTodo", "kitStepDone", "kitStepNow"):
        d[name] = dict(tex="extras", scale=ATLAS_SCALE, layout="extras", root="kit", args={},
                       css=only(["#" + name, "#" + name + " *"]))
    d["kitTrack"] = dict(tex="extras", scale=ATLAS_SCALE, layout="extras", root="kit", args={}, css=only(["#kitTrack"], ["#kitTrack *"]))

    # The window (Milestone 2)
    win("chrome", only(["#rim", "#rim *", ".corner", "#title", "#page", "#parch"],
                       extra=".win-rim{box-shadow:0 0 0 1px #2a1d06!important}"), tex="chrome", scale=CHROME_SCALE)
    win("tabRest", only(["#tab2"]))
    win("tabHover", only(["#tab2"]), hover_tab=2)
    win("tabOn", only(["#tab1"]))
    win("divider", only(["#divider"]), scale=1.6)  # 600 wide: 1.6x is what fits
    win("knobSettings", only(["#knob-settings", "#knob-settings *"]))
    win("knobClose", only(["#knob-close", "#knob-close *"]))
    win("portrait", only(["#portrait"], ["#initials"]))
    win("railLine", only(["#railfoot"]))
    win("pip", only(["#pip"]))
    win("sheen", only(["#sheen"]))
    win("crest", only(["#crest"]), tex="crest")
    win("seal", only(["#seal"]), tex="seal")
    for i in range(1, len(pages) + 1):
        win(f"icon{i}", only([f"#icon{i}", f"#icon{i} *"], extra=f"#icon{i}{white}"))
        win(f"label{i}", only([f"#label{i}"], [f"#small{i}"], f"#label{i}{white}"))
        win(f"small{i}", only([f"#small{i}"], extra=f"#small{i}{white}"))
        win(f"subtitle{i}", only(["#subtitle"]), page=i - 1)
        win(f"eyebrow{i}", only(["#eyebrow"]), page=i - 1)

    # The herald pop-up (Milestone 3)
    herald("heraldBg", only(["#herald"]), scale=1.15)  # shown at 0.8 (Royal): 1.15x stays sharp
    for s in SEALS:
        herald(f"hseal_{s}", only(["#hseal"]), seal=s)
    for label in HERALD_BUTTONS:
        for style in ("blue", "quiet"):
            herald(f"hbtn_{style}_{slug(label)}", only(["#hbutton"]), button=label, style=style)

    # The settings page (Milestone 3)
    settings("settingsPage", only(["#settings", "#sparch", "#sseal", "#seyebrow", "#stitle"]), scale=1.3)
    settings("rowLine", only(["#row1"]))
    settings("swOn", only(["#sw1", "#sw1 *"]))
    settings("swOff", only(["#sw4", "#sw4 *"]))
    settings("segBox", only(["#seg"]))
    settings("segModestOn", only(["#seg-modest"]), seg="small")
    settings("segModestOff", only(["#seg-modest"]), seg="full")
    settings("segRoyalOn", only(["#seg-royal"]), seg="full")
    settings("segRoyalOff", only(["#seg-royal"]), seg="small")
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

    def rects(self, name, text):
        page = self.workdir / f"{name}-rects.html"
        page.write_text(text, encoding="utf-8")
        out = subprocess.run(self._args(1) + ["--dump-dom", page.as_uri()],
                             capture_output=True, timeout=180, text=True, encoding="utf-8")
        m = re.search(r'<pre id="rects-json"[^>]*>(.*?)</pre>', out.stdout, re.S)
        if not m:
            raise RuntimeError("Edge didn't report the layout (run this from PowerShell, not Git Bash)")
        return json.loads(html.unescape(m.group(1)))


def crop(im, scale, origin):
    alpha = im.getchannel("A").point(lambda v: 255 if v > 3 else 0)
    box = alpha.getbbox()
    if not box:
        raise RuntimeError("a piece came out empty")
    l, t, r, b = box
    l, t = max(0, l - 1), max(0, t - 1)
    r, b = min(im.width, r + 1), min(im.height, b + 1)
    ox, oy = origin
    return im.crop((l, t, r, b)), {
        "x": l / scale - ox, "y": t / scale - oy, "w": (r - l) / scale, "h": (b - t) / scale}


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def pack(items):
    """Packs (name, image) pairs into one atlas, guillotine style. Returns the image and positions."""
    items = sorted(items, key=lambda it: (-it[1].height, -it[1].width, it[0]))
    free = [(0, 0, ATLAS_WIDTH, 4096)]
    spots = {}
    for name, im in items:
        w, h = im.width + 2 * PAD, im.height + 2 * PAD
        fits = [f for f in free if w <= f[2] and h <= f[3]]
        if not fits:
            raise RuntimeError(f"{name} doesn't fit in the atlas")
        fx, fy, fw, fh = min(fits, key=lambda f: (f[1], f[0]))
        free.remove((fx, fy, fw, fh))
        free.append((fx + w, fy, fw - w, h))       # beside it, as tall as it
        free.append((fx, fy + h, fw, fh - h))      # below it, the full width
        spots[name] = (fx + PAD, fy + PAD)
    height = pow2(max(spots[n][1] + im.height + PAD for n, im in items))
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
    css = {"window": stylesheet(), "extras": stylesheet("Extras.dc.html") + board_styles("GladiatorsRing.dc.html")}
    render = {
        "window": lambda c, args: window_html(pages, css["window"], c, **args),
        "extras": lambda c, args: extras_html(css["extras"], c, **args),
    }
    MEDIA.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="mota-textures-"))
    edge = Edge(work)
    print("Reading the layouts...")
    rects = {}
    rects.update(edge.rects("window", render["window"]("", {})))
    rects.update(edge.rects("extras", render["extras"]("", {})))
    origin = {root: (rects[root]["x"], rects[root]["y"]) for root in SLOTS}
    slots = {}
    for root, names in SLOTS.items():
        ox, oy = origin[root]
        for n in names:
            r = rects[n]
            slots[n] = {"x": r["x"] - ox, "y": r["y"] - oy, "w": r["w"], "h": r["h"], "root": root}

    todo = pieces_to_draw(pages)
    print(f"Drawing {len(todo)} pieces in Edge...")
    drawn = {}

    def draw(name):
        p = todo[name]
        im = edge.screenshot(name, render[p["layout"]](p["css"], p["args"]), p["scale"])
        return name, crop(im, p["scale"], origin[p["root"]])

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name, result in pool.map(draw, todo):
            drawn[name] = result

    pieces, textures = {}, {}

    def place(name, tex, size, spot):
        im, pos = drawn[name]
        x, y = spot
        pieces[name] = dict(pos, tex=tex, root=todo[name]["root"], l=x / size[0], r=(x + im.width) / size[0],
                            t=y / size[1], b=(y + im.height) / size[1])

    for tex in ("atlas", "extras"):
        items = [(n, drawn[n][0]) for n, p in todo.items() if p["tex"] == tex]
        image, spots = pack(items)
        for name, _ in items:
            place(name, tex, image.size, spots[name])
        textures[tex] = image
    for name, size in (("chrome", (2048, 1024)), ("crest", None), ("seal", None)):
        canvas = on_canvas(drawn[name][0], size)
        place(name, name, canvas.size, (0, 0))
        textures[name] = canvas
    textures["shadow"] = shadow_texture()

    for name, im in sorted(textures.items()):
        im.save(MEDIA / f"{name}.tga")
        print(f"  Media/{name}.tga  {im.width} x {im.height}")

    media = {
        "dir": "Interface\\AddOns\\MinistryOfTheAllied\\Media\\",
        "window": {"w": WIN_W, "h": WIN_H},
        "textures": {name: f"{name}.tga" for name in textures},
        "shadow": {"inset": 96, "corner": 112, "size": 256},
        "heraldButtons": HERALD_BUTTONS,
        "pieces": pieces,
        "slots": slots,
        "pages": pages,
    }
    lua = ("-- Generated by tools/textures/build.py from the design canvas. Don't edit by hand:\n"
           "-- change the design or the layouts, then run the script again.\n"
           "-- Positions are in canvas units from the top-left corner of the piece's root\n"
           "-- (win: the window, herald: the herald pop-up, settings: the settings page;\n"
           "-- y goes down). l, r, t, b are the piece's texture coordinates.\n\n"
           "local _, MOTA = ...\n\nMOTA.Media = " + lua_value(media) + "\n")
    (ADDON / "Media.lua").write_text(lua, encoding="utf-8", newline="\n")
    print("  Media.lua")

    if "--preview" in sys.argv:
        out = Path(tempfile.gettempdir())
        preview_window(pieces, textures, out / "mota-window-preview.png")
        preview_extras(pieces, textures, out / "mota-extras-preview.png")
        print(f"Previews: {out / 'mota-window-preview.png'}, {out / 'mota-extras-preview.png'}")


def put(img, pieces, textures, name, ox, oy, dx=0, dy=0, tint=None):
    p = pieces[name]
    tex = textures[p["tex"]]
    W, H = tex.size
    part = tex.crop((round(p["l"] * W), round(p["t"] * H), round(p["r"] * W), round(p["b"] * H)))
    part = part.resize((max(1, round(p["w"])), max(1, round(p["h"]))), Image.LANCZOS)
    if tint:
        r, g, b = (int(tint[i:i + 2], 16) for i in (0, 2, 4))
        solid = Image.new("RGBA", part.size, (r, g, b, 255))
        solid.putalpha(part.getchannel("A"))
        part = solid
    img.alpha_composite(part, (round(ox + p["x"] + dx), round(oy + p["y"] + dy)))


def preview_window(pieces, textures, out):
    """Assembles the window roughly the way the add-on does, for checking."""
    img = Image.new("RGBA", (WIN_W + 240, WIN_H + 240), (17, 19, 27, 255))
    P = lambda name, **kw: put(img, pieces, textures, name, 120, 120, **kw)
    P("chrome")
    for i in range(1, 8):
        if i == 1:
            P("tabOn")
        else:
            P("tabRest", dy=(i - 2) * 57)
        P(f"icon{i}", tint="0E1F45" if i == 1 else "E5CF92")
        P(f"label{i}", tint="0E1F45" if i == 1 else "E5CF92")
        P(f"small{i}", tint="3A2A0A" if i == 1 else "EBC3B2")
    for name in ("subtitle1", "eyebrow1", "divider", "knobSettings", "knobClose", "portrait", "railLine", "pip", "crest"):
        P(name)
    img.save(out)


def preview_extras(pieces, textures, out):
    img = Image.new("RGBA", (900, 760), (17, 19, 27, 255))
    H = lambda name, **kw: put(img, pieces, textures, name, 80, 40, **kw)
    H("heraldBg")
    H("hseal_official")
    H("hbtn_blue_VoteNow")
    S = lambda name, **kw: put(img, pieces, textures, name, 200, 220, **kw)
    S("settingsPage")
    for i in range(1, 5):
        S("rowLine", dy=(i - 1) * 58)
    S("segBox")
    S("segModestOff")
    S("segRoyalOn")
    img.save(out)


if __name__ == "__main__":
    main()
