"""Turns the design canvas into game textures for the add-on.

It renders three layouts in Microsoft Edge, one piece at a time, with the
canvas's own stylesheet (design/canvas-source/ministry.css):

  tools/textures/layout.html   the add-on window (Throne Room board), once per window skin
                               with the Window skins board's styles (ADDON_SPEC.md 9.7)
  tools/textures/extras.html   the herald pop-up and the settings page (Extras board)
  tools/textures/ballot.html   the Ballot Hall's ribbons, seals, buttons and papers (Ballot Hall board)

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
BALLOT_VIEW = (1400, 1560)   # the Ballot Hall layout is taller: its papers sit below the pieces
PAPER_SCALE = 0.9            # the papers are soft parchment: 0.9x keeps all three in one 1024 texture
ATLAS_SCALE = 2              # small pieces are drawn at twice their size, for sharpness
ATLAS_WIDTH = 1024
PAD = 2

# Window skins (Milestone 5, ADDON_SPEC.md 9.7). The window is drawn in layers so each
# part is drawn only as often as it differs: the parchment once, the metal frame once
# per metal, and the leather, wax tabs, knobs and emblem once per skin.
# key, file name, class on .win (Window skins board), emblem, emblem class, metal
SKINS = [
    ("UNREGISTERED", "ministry", "", "alliance-crest.png", "", "gold"),
    ("SILVERHAND", "silverhand", "ws-sh", "seal-silverhand.svg", "seal", "silver"),
    ("AZEROTH_EXCHANGE", "exchange", "ws-ex", "seal-exchange.svg", "seal", "gold"),
    ("CROWN", "crown", "ws-cr", "crest-crown.png", "", "gold"),
]
METALS = {"gold": "", "silver": "ws-sh"}  # the skin class each metal is drawn with
METAL_DARK = {"gold": "#2a1d06", "silver": "#1B1F27"}  # the hairline round the rim
PARCH_SCALE = 1.3     # the parchment page: soft vellum, so a little below the old 1.46 is fine
LEATHER_SCALE = 0.4   # the leather is a soft gradient, drawn small and stretched (0.4 fits beside a shield crest in 1024 x 512)
FRAME_SCALE = 1.0     # the rim, rules and page rim: thin lines, drawn at their own size
TITLE_SCALE = 1.3     # "Ministry of the Allied" (about 700 wide: 1.3x fits the 1024 atlas)
CREST_SCALE = 1.6     # the corner emblem: shown about 130 px wide, so 1.6x stays sharp and each skin fits 1024 x 512
FRAME_BAND = 18       # the rim, double rule and stitching: canvas units in from the window's edge
PAGE_RIM = 3          # the metal rim round the parchment
GRAIN_TILE = 400      # leather-grain.svg repeats every 400 canvas units
GRAIN_SIZE = 256      # ...and is drawn at 256 x 256, tiled over the stretched leather
BAND_MAX = 330        # taller bands are cut in two, so every metal set fits 1024 x 512

# The canvas stores its textures under /_blob/ names; these are the same files in the repo.
BLOBS = {
    "c2d86e49cc4f265a0371294274387bd7": "textures/leather-grain.svg",
    "6d5fbe8d4c5384d8cf626886038701ac": "../tools/textures/corner-nogem.svg",  # the gem is its own layer, tinted per skin
    "d4a81ff364cfd13a95212c60a73bd187": "textures/parchment-grain.svg",
    "83dde6b367275cb6d4d9550c6c74c5ac": "../tools/textures/tab-frame-gold.svg",  # small gold gems, the same in every skin
    "e91083b63eec292d284b54d9d2ba82db": "textures/divider-ink.svg",
    "19c005d5f1860452928780ca70041223": "textures/seal-official.svg",
    "539190bbac866c98462ae1069c2f22b6": "textures/seal-crown.svg",
    "dd8568019d0ff8be3c87935987cf352a": "textures/seal-silverhand.svg",
    "2548a4e779105c6802c9276a14f27592": "textures/seal-exchange.svg",
    "95cd0584f50217d5706a3ab342656520": "textures/crest-crown.png",
    "7c545901b08ed0754c9e9eaf3000577b": "textures/alliance-crest.png",
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

# Accent colours (the pieces that are blue in the canvas, drawn again for the Crown and the Exchange).
# suffix -> (top, middle, bottom, dark edge, ink, plate top, plate bottom, plate pale text, ink as rgb)
ACCENTS = {
    "~cr": dict(top="#86296A", mid="#58143F", bot="#3D0B2D", dark="#2A0720", ink="#58143F", rgb="88,20,63",
                plate_top="#6E2058", plate_bot="#3D0B2D", pale="#E8C6DC"),
    "~ex": dict(top="#B8343C", mid="#8E1A21", bot="#661118", dark="#2E0609", ink="#7A1219", rgb="122,18,25",
                plate_top="#8E1A21", plate_bot="#4A0A0F", pale="#F0C9BC"),
}
# Pieces with blue in them, by layout: each is drawn once more per accent in the "accent" texture.
ACCENT_PIECES = (
    ["kitBlue", "kitStepTodo"] + [f"kitRibbonOn{i}" for i in range(1, 8)]
    + ["b_" + n for n in ("rb-ballot-on", "rb-ballot-on-dot", "rb-results-on", "rb-crown-on", "btn-seal", "btn-open",
                          "btn-close", "btn-runoff", "btn-last", "btn-add", "pill-general-on", "pill-snap-on",
                          "pill-runoff-on")]
    + [f"hbtn_{style}_{{}}" for style in ("blue", "quiet")]  # filled in per herald label below
    + ["segModestOn", "segRoyalOn", "segPartyOn", "segMinistryOn"]
)


def accent_css(a):
    """CSS that turns the canvas's blue parts into the accent."""
    grain = (DESIGN / "textures" / "leather-grain.svg").resolve().as_uri()
    rules = [
        ".ribbon.on,.pill.on{background:linear-gradient(180deg,TOP 0%,MID 58%,BOT 100%)!important}",
        ".btn:not(.gold):not(.quiet){background:linear-gradient(180deg,TOP,MID 55%,BOT)!important;"
        "box-shadow:0 0 0 1px DARK,0 0 0 3px #D2AE5C,0 0 0 4px #4A330C,0 5px 12px rgba(40,25,5,.45),"
        "inset 0 1px 0 rgba(255,255,255,.28)!important}",
        ".btn.quiet{color:INK!important;box-shadow:inset 0 0 0 1px rgba(RGB,.65),"
        "inset 0 0 0 3px rgba(255,250,235,.4)!important}",
        ".seg button.on{background:linear-gradient(180deg,TOP,MID)!important}",
        ".plate.blue{background:url(GRAIN),linear-gradient(180deg,PLATETOP,PLATEBOT)!important;"
        "box-shadow:inset 0 0 0 1px #F3D98A,inset 0 0 0 3px DARK,inset 0 0 0 4px rgba(201,162,74,.55),"
        "0 4px 10px rgba(60,40,10,.35)!important}",
        ".plate.blue .eyebrow{color:PALE!important}",
        ".step:not(.done):not(.now){background:DARK!important}",
    ]
    css = "\n".join(rules)
    for token, value in (("PLATETOP", a["plate_top"]), ("PLATEBOT", a["plate_bot"]), ("TOP", a["top"]),
                         ("MID", a["mid"]), ("BOT", a["bot"]), ("DARK", a["dark"]), ("INK", a["ink"]),
                         ("RGB", a["rgb"]), ("PALE", a["pale"]), ("GRAIN", grain)):
        css = css.replace(token, value)
    return css


# Herald buttons drawn ready-made: the label and the style ("blue" is .btn, "quiet" is .btn.quiet).
HERALD_BUTTONS = ["Vote now", "Read it", "Open", "Dismiss", "Stop", "Restart"]

# Slots: places where the add-on draws live text or buttons, by root.
SLOTS = {
    "win": [f"tab{i}" for i in range(1, 8)] + [
        "title", "subtitle", "knob-settings", "knob-close", "page", "parch", "eyebrow", "heading",
        "divider", "note", "note2", "railfoot", "portrait", "initials", "who", "who-small",
        "foot", "foot-left", "foot-right", "pip", "crest", "seal", "sheen",
        "rim", "leather", "corner-tr", "corner-bl", "corner-br"],
    "kit": ["kit"],
    "herald": ["herald", "hseal", "htext", "heyebrow", "htitle", "hbody", "hbutton"],
    "settings": ["settings", "sparch", "sseal", "seyebrow", "stitle", "seg", "seg-modest", "seg-royal",
                 "segskin", "seg-party", "seg-ministry"]
    + [f"row{i}" for i in range(1, 7)] + [f"slabel{i}" for i in range(1, 7)]
    + [f"ssmall{i}" for i in range(1, 7)] + [f"sw{i}" for i in range(1, 5)],
    # The Ballot Hall's pieces, so the add-on knows each one's own box (without its shadow).
    "ballot": ["ballot", "rb-ballot", "rb-ballot-dot", "rb-ballot-on", "rb-ballot-on-dot", "rb-results",
               "rb-results-on", "rb-crown", "rb-crown-on", "seal-off", "seal-crown", "seal-tilt", "stamp", "held",
               "ring", "kdot-on", "kdot-off", "diamond", "portrait-king", "btn-seal", "btn-open", "btn-close",
               "btn-declare", "btn-runoff", "btn-last", "btn-add", "pill-general", "pill-general-on", "pill-snap",
               "pill-snap-on", "pill-runoff", "pill-runoff-on", "xbtn", "paper-ballot", "paper-half", "paper-wide"],
}


def find_edge():
    for p in EDGE_PATHS:
        if p.exists():
            return p
    sys.exit("Microsoft Edge wasn't found.")


def local_css(css):
    for blob, rel in BLOBS.items():
        css = css.replace(f"/_blob/{blob}", (DESIGN / rel).resolve().as_uri())
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


def window_html(pages, css, piece_css="", page=0, hover_tab=None, skin="UNREGISTERED"):
    tabs = []
    for i, p in enumerate(pages, 1):
        cls = "tab" + (" on" if i == 1 else "") + (" hover" if i == hover_tab else "")
        tabs.append(
            f'      <a class="{cls}" id="tab{i}"><svg id="icon{i}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{ICONS[p["id"]]}</svg>'
            f'<span id="label{i}">{html.escape(p["label"], quote=False)}'
            f'<small id="small{i}">{html.escape(p["small"], quote=False)}</small></span></a>')
    p = pages[page]
    _, _, cls, emblem, emblem_cls, _ = next(s for s in SKINS if s[0] == skin)
    return fill("layout.html", {
        "css": css + "\n" + piece_css,
        "tabs": "\n".join(tabs),
        "skin": cls,
        "crest_class": emblem_cls,
        "crest": (DESIGN / "textures" / emblem).as_uri(),
        "seal": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
        "subtitle": html.escape(p["subtitle"], quote=False),
        "eyebrow": html.escape(p["eyebrow"], quote=False),
        "heading": html.escape(p["heading"], quote=False),
        "note": html.escape(p["note"], quote=False),
    })


def extras_html(css, piece_css="", seal="official", button="Vote now", style="blue", seg="full", skin_seg="party"):
    return fill("extras.html", {
        "party_class": "on" if skin_seg == "party" else "",
        "ministry_class": "on" if skin_seg == "ministry" else "",
        "css": css + "\n" + piece_css,
        "seal": (DESIGN / "textures" / f"seal-{seal}.svg").as_uri(),
        "crown": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
        "seal_sh": (DESIGN / "textures" / "seal-silverhand.svg").as_uri(),
        "seal_ex": (DESIGN / "textures" / "seal-exchange.svg").as_uri(),
        "button": html.escape(button, quote=False),
        "button_class": "btn sm" if style == "blue" else "btn quiet sm",
        "modest_class": "on" if seg == "small" else "",
        "royal_class": "on" if seg == "full" else "",
    })


def ballot_html(css, piece_css=""):
    return fill("ballot.html", {
        "css": css + "\n" + piece_css,
        "official": (DESIGN / "textures" / "seal-official.svg").as_uri(),
        "crown": (DESIGN / "textures" / "seal-crown.svg").as_uri(),
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


RAW = {"rim", "rules", "pagerim"}  # metal pieces cut up after drawing (see frame_bands)


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

    def ballot(name, css, tex="ballot", scale=ATLAS_SCALE):
        d[name] = dict(tex=tex, scale=scale, layout="ballot", root="ballot", args={}, css=css)

    # Parts for page contents (UI/Kit.lua)
    for name in ("kitBlue", "kitRibbonOn1", "kitRibbonOn2", "kitRibbonOn3", "kitRibbonOn4", "kitRibbonOff1",
                 "kitRibbonOff2", "kitRibbonOff3", "kitGem", "kitGemHollow", "kitCoinG", "kitCoinS", "kitBand",
                 "kitStepTodo", "kitStepDone", "kitStepNow", "kitRibbonOn5", "kitRibbonOn6", "kitRibbonOn7",
                 "kitRibbonOff5", "kitRibbonOff6", "kitRibbonOff7", "kitPortraitSh", "kitPortraitEx"):
        d[name] = dict(tex="extras", scale=ATLAS_SCALE, layout="extras", root="kit", args={},
                       css=only(["#" + name, "#" + name + " *"]))
    # Wide parts are drawn smaller, to fit the atlas.
    for name in ("kitBannerSh", "kitBannerEx", "kitEnvelope"):
        d[name] = dict(tex="extras", scale=1.3, layout="extras", root="kit", args={},
                       css=only(["#" + name, "#" + name + " *"]))
    d["kitTrack"] = dict(tex="extras", scale=ATLAS_SCALE, layout="extras", root="kit", args={}, css=only(["#kitTrack"], ["#kitTrack *"]))

    # The window (Milestone 2), in layers for the skins (Milestone 5, ADDON_SPEC.md 9.7).
    # Shared by every skin: the parchment, the leather grain and the parts on the page.
    win("parch", only(["#parch"]), tex="parch", scale=PARCH_SCALE)
    d["grain"] = dict(tex="grain", scale=GRAIN_SIZE / GRAIN_TILE, layout="grain", root="win", args={}, css="", raw=True)
    win("divider", only(["#divider"]), scale=1.6)  # 600 wide: 1.6x is what fits
    win("portrait", only(["#portrait"], ["#initials"]))  # the Ring page's portrait ring
    win("sheen", only(["#sheen"]))
    win("seal", only(["#seal"]), tex="seal")
    no_rules = "#subtitle::before,#subtitle::after{visibility:hidden!important}"
    for i in range(1, len(pages) + 1):
        win(f"icon{i}", only([f"#icon{i}", f"#icon{i} *"], extra=f"#icon{i}{white}"))
        win(f"label{i}", only([f"#label{i}"], [f"#small{i}"], f"#label{i}{white}"))
        win(f"small{i}", only([f"#small{i}"], extra=f"#small{i}{white}"))
        # the page's name in white, coloured in the game with the skin's pale ink; its rules come per metal
        win(f"subtitle{i}", only(["#subtitle"], extra=f"#subtitle{white}" + no_rules), page=i - 1)
        win(f"eyebrow{i}", only(["#eyebrow"]), page=i - 1)

    # Once per metal: the rim, rules and stitching, the filigree corner, the title, the lit tab,
    # the page's metal rim and the small metal parts. Drawn with the skin that wears that metal.
    for metal, cls in METALS.items():
        skin = next(s[0] for s in SKINS if s[2] == cls)
        tex = "frame_" + metal

        def m(name, css, scale=ATLAS_SCALE, **args):
            d[f"{metal}:{name}"] = dict(tex=tex, scale=scale, layout="window", root="win",
                                        args=dict(args, skin=skin), css=css, **({"raw": True} if name in RAW else {}))
        rim_line = f".win-rim{{box-shadow:0 0 0 1px {METAL_DARK[metal]}!important}}"
        m("rim", only(["#rim"], extra=rim_line), scale=FRAME_SCALE)
        m("rules", only(["#leather"], extra=".win-leather{background:none!important;box-shadow:none!important}"),
          scale=FRAME_SCALE)
        m("pagerim", only(["#page"]), scale=FRAME_SCALE)
        m("corner", only(["#corner-tr"]))
        # the corner's jewel, alone and untinted: the game colours it for the skin
        gem_url = (HERE / "corner-gem.svg").resolve().as_uri()
        m("cornerGem", only(["#corner-tr"], extra=f".corner{{background-image:url({gem_url})!important;filter:none!important}}"))
        m("title", only(["#title"]), scale=TITLE_SCALE)
        m("tabOn", only(["#tab1"]))
        m("subRule", only(["#subtitle"], extra="#subtitle{color:transparent!important}"))
        m("railLine", only(["#railfoot"]))
        m("pip", only(["#pip"]))
        m("portrait", only(["#portrait"], ["#initials"]))

    # The portrait bubble (initials) and the divider's jewel are blue in the canvas: drawn again for the
    # Crown and the Exchange, named "<piece>~cr" / "<piece>~ex" (gold metal only: silver is Silverhand's blue).
    bubble = {"~cr": ("#8E2E6E", "#1C0415", "cr"), "~ex": ("#C23A42", "#3A070B", "ex")}
    for suffix, (light, dark, short) in bubble.items():
        d["gold:portrait" + suffix] = dict(d["gold:portrait"], css=d["gold:portrait"]["css"]
            + f"\n#portrait{{background:radial-gradient(circle at 40% 35%,{light},{dark} 85%)!important}}")
        url = (HERE / f"divider-ink-{short}.svg").resolve().as_uri()
        d["divider" + suffix] = dict(d["divider"], css=d["divider"]["css"]
            + f"\n.divider{{background-image:url({url})!important}}")

    # Once per skin: the leather (with the Crown's glow behind the title), the wax tabs,
    # the knobs and the corner emblem.
    leather_only = (".win-leather::before,.win-leather::after{display:none!important}"
                    ".win-leather{background-size:0 0,auto!important}")  # the grain is its own layer
    for key, file, _, _, _, _ in SKINS:
        tex = "skin_" + file

        def s(name, css, scale=ATLAS_SCALE, **args):
            d[f"{file}:{name}"] = dict(tex=tex, scale=scale, layout="window", root="win",
                                       args=dict(args, skin=key), css=css)
        s("leather", only([".win-head", "#leather"], extra=leather_only), scale=LEATHER_SCALE)
        s("tabRest", only(["#tab2"]))
        s("tabHover", only(["#tab2"]), hover_tab=2)
        s("knobSettings", only(["#knob-settings", "#knob-settings *"]))
        s("knobClose", only(["#knob-close", "#knob-close *"]))
        s("crest", only(["#crest"]), scale=CREST_SCALE)

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
    # The window skin switch (Milestone 5)
    settings("segSkinBox", only(["#segskin"]))
    settings("segPartyOn", only(["#seg-party"]), skin_seg="party")
    settings("segPartyOff", only(["#seg-party"]), skin_seg="ministry")
    settings("segMinistryOn", only(["#seg-ministry"]), skin_seg="ministry")
    settings("segMinistryOff", only(["#seg-ministry"]), skin_seg="party")

    # The Ballot Hall (Milestone 4). Piece names are the layout's ids, prefixed "b_".
    for el in SLOTS["ballot"][1:]:
        if el.startswith("paper-"):
            ballot("b_" + el, only([f"#{el}"]), tex="papers", scale=PAPER_SCALE)
        else:
            ballot("b_" + el, only([f"#{el}", f"#{el} *"]))

    # The blue parts again in each accent (the Crown's plum, the Exchange's crimson), named "<piece>~cr".
    bases = []
    for n in ACCENT_PIECES:
        if "{}" in n:
            bases += [n.format(slug(label)) for label in HERALD_BUTTONS]
        else:
            bases.append(n)
    for suffix, a in ACCENTS.items():
        for base in bases:
            d[base + suffix] = dict(d[base], tex="accent", css=d[base]["css"] + "\n" + accent_css(a))
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

    def _args(self, scale, size=None):
        w, h = size or (VIEW_W, VIEW_H)
        return [self.exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                "--no-default-browser-check", "--disable-extensions", f"--user-data-dir={self._profile()}",
                f"--force-device-scale-factor={scale}", "--default-background-color=00000000",
                f"--window-size={w},{h}", "--virtual-time-budget=5000"]

    def screenshot(self, name, text, scale, size=None):
        page = self.workdir / f"{name}.html"
        png = self.workdir / f"{name}.png"
        page.write_text(text, encoding="utf-8")
        subprocess.run(self._args(scale, size) + [f"--screenshot={png}", page.as_uri()],
                       capture_output=True, timeout=180)
        if not png.exists():
            raise RuntimeError(f"Edge didn't draw {name}")
        return Image.open(png).convert("RGBA")

    def rects(self, name, text, size=None):
        page = self.workdir / f"{name}-rects.html"
        page.write_text(text, encoding="utf-8")
        out = subprocess.run(self._args(1, size) + ["--dump-dom", page.as_uri()],
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


def trim(im, pos, scale, dx=0):
    """Crops a piece (or part of one, starting dx pixels in) to what's drawn, keeping its place."""
    box = im.getchannel("A").point(lambda v: 255 if v > 3 else 0).getbbox()
    if not box:
        raise RuntimeError("a piece came out empty")
    l, t, r, b = box
    return im.crop(box), {"x": pos["x"] + (dx + l) / scale, "y": pos["y"] + t / scale,
                          "w": (r - l) / scale, "h": (b - t) / scale}


def clear_inside(im, scale, rect, inset):
    """Makes the inside of a layout rect (page units), inset by some canvas units, transparent."""
    x, y, w, h = rect["x"], rect["y"], rect["w"], rect["h"]
    im.paste((0, 0, 0, 0), tuple(round(v * scale) for v in (x + inset, y + inset, x + w - inset, y + h - inset)))


def bands(im, scale, origin, rect, inset, prefix):
    """Cuts a frame drawn round an empty middle into bands: top and bottom the full width,
    the sides between them, tall sides in pieces. Returns {name: (image, pos)}."""
    l, t, r, b = im.getchannel("A").point(lambda v: 255 if v > 3 else 0).getbbox()
    il, it = round((rect["x"] + inset) * scale), round((rect["y"] + inset) * scale)
    ir, ib = round((rect["x"] + rect["w"] - inset) * scale), round((rect["y"] + rect["h"] - inset) * scale)
    parts = {"Top": (l, t, r, it), "Bottom": (l, ib, r, b)}
    n = max(1, -(-(ib - it) // round(BAND_MAX * scale)))
    for k in range(n):
        y0, y1 = it + (ib - it) * k // n, it + (ib - it) * (k + 1) // n
        parts[f"Left{k + 1}"] = (l, y0, il, y1)
        parts[f"Right{k + 1}"] = (ir, y0, r, y1)
    ox, oy = origin
    return {prefix + name: (im.crop(box), {"x": box[0] / scale - ox, "y": box[1] / scale - oy,
                                           "w": (box[2] - box[0]) / scale, "h": (box[3] - box[1]) / scale})
            for name, box in parts.items()}


def grain_html():
    """The leather grain alone: one tile of leather-grain.svg, as the leather repeats it."""
    url = (DESIGN / "textures" / "leather-grain.svg").as_uri()
    return (f"<!doctype html><html><head><style>html,body{{margin:0;background:transparent}}</style></head>"
            f"<body><div style=\"width:{GRAIN_TILE}px;height:{GRAIN_TILE}px;background:url({url})\"></div></body></html>")


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
    css = {"window": stylesheet() + board_styles("WindowSkins.dc.html"),
           "extras": stylesheet("Extras.dc.html") + board_styles("GladiatorsRing.dc.html")
                     + board_styles("Parties.dc.html"),
           "ballot": stylesheet("BallotHall.dc.html")}
    render = {
        "window": lambda c, args: window_html(pages, css["window"], c, **args),
        "extras": lambda c, args: extras_html(css["extras"], c, **args),
        "ballot": lambda c, args: ballot_html(css["ballot"], c),
        "grain": lambda c, args: grain_html(),
    }
    view = {"ballot": BALLOT_VIEW, "grain": (GRAIN_TILE, GRAIN_TILE)}
    MEDIA.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="mota-textures-"))
    edge = Edge(work)
    print("Reading the layouts...")
    rects = {}
    rects.update(edge.rects("window", render["window"]("", {})))
    rects.update(edge.rects("extras", render["extras"]("", {})))
    rects.update(edge.rects("ballot", render["ballot"]("", {}), BALLOT_VIEW))
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
        im = edge.screenshot(name.replace(":", "_"), render[p["layout"]](p["css"], p["args"]), p["scale"],
                             view.get(p["layout"]))
        if p.get("raw"):
            return name, (im, None)
        return name, crop(im, p["scale"], origin[p["root"]])

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name, result in pool.map(draw, todo):
            drawn[name] = result

    # The grain tile is used whole, so it repeats without a seam.
    im = drawn["grain"][0]
    drawn["grain"] = (im.crop((0, 0, GRAIN_SIZE, GRAIN_SIZE)), {"x": 0, "y": 0, "w": GRAIN_TILE, "h": GRAIN_TILE})

    # Each metal's frame: the rim (its middle cleared) with the rules on top, and the page's
    # metal rim with its shadow, cut into bands; the subtitle's rule kept once, as the left one.
    win_origin = origin["win"]
    frame_parts, sub_rule = [], {}

    def add(name, tex, result):
        drawn[name] = result
        todo[name] = dict(tex=tex, root="win")

    for metal in METALS:
        tex = "frame_" + metal
        rim = drawn.pop(f"{metal}:rim")[0]
        clear_inside(rim, FRAME_SCALE, rects["rim"], 3)
        rim.alpha_composite(drawn.pop(f"{metal}:rules")[0])
        page = drawn.pop(f"{metal}:pagerim")[0]
        clear_inside(page, FRAME_SCALE, rects["page"], PAGE_RIM)
        cut = bands(rim, FRAME_SCALE, win_origin, rects["rim"], FRAME_BAND, "frame")
        cut.update(bands(page, FRAME_SCALE, win_origin, rects["page"], PAGE_RIM, "pageRim"))
        for name, result in cut.items():
            add(f"{metal}:{name}", tex, result)
        frame_parts = sorted(cut)
        for name in (f"{metal}:rim", f"{metal}:rules", f"{metal}:pagerim"):
            del todo[name]
        im, pos = drawn[f"{metal}:subRule"]
        half = im.width // 2
        left = trim(im.crop((0, 0, half, im.height)), pos, ATLAS_SCALE)
        right = trim(im.crop((half, 0, im.width, im.height)), pos, ATLAS_SCALE, half)[1]
        drawn[f"{metal}:subRule"] = left
        if metal == "gold":  # where the rules sit beside the page's name (subtitle1 is drawn on the same page)
            text = drawn["subtitle1"][1]
            sub_rule = {"gapL": round(text["x"] - (left[1]["x"] + left[1]["w"]), 2),
                        "gapR": round(right["x"] - (text["x"] + text["w"]), 2)}

    pieces, textures = {}, {}

    def place(name, tex, size, spot):
        im, pos = drawn[name]
        x, y = spot
        pieces[name] = dict(pos, tex=tex, root=todo[name]["root"], l=x / size[0], r=(x + im.width) / size[0],
                            t=y / size[1], b=(y + im.height) / size[1])

    packed = ["atlas", "extras", "ballot", "papers", "accent"] + ["frame_" + m for m in METALS] + ["skin_" + s[1] for s in SKINS]
    for tex in packed:
        items = [(n, drawn[n][0]) for n, p in todo.items() if p["tex"] == tex]
        image, spots = pack(items)
        for name, _ in items:
            place(name, tex, image.size, spots[name])
        textures[tex] = image
    for name, size in (("parch", (1024, 1024)), ("seal", None), ("grain", None)):
        canvas = on_canvas(drawn[name][0], size)
        place(name, name, canvas.size, (0, 0))
        textures[name] = canvas
    textures["shadow"] = shadow_texture()
    for old in ("chrome", "crest"):  # the window before skins: one picture, now in layers
        (MEDIA / f"{old}.tga").unlink(missing_ok=True)

    total = 0
    for name, im in sorted(textures.items()):
        im.save(MEDIA / f"{name}.tga")
        size = (MEDIA / f"{name}.tga").stat().st_size
        total += size
        print(f"  Media/{name}.tga  {im.width} x {im.height}  {size / 1048576:.2f} MB")
    print(f"  Textures in all: {total / 1048576:.2f} MB")

    media = {
        "dir": "Interface\\AddOns\\MinistryOfTheAllied\\Media\\",
        "window": {"w": WIN_W, "h": WIN_H},
        "textures": {name: f"{name}.tga" for name in textures},
        "shadow": {"inset": 96, "corner": 112, "size": 256},
        "heraldButtons": HERALD_BUTTONS,
        "pieces": pieces,
        "slots": slots,
        "pages": pages,
        # Window skins (ADDON_SPEC.md 9.7): per-skin pieces are named "<file>:<piece>",
        # per-metal ones "<metal>:<piece>"; frameParts are the metal's frame bands.
        "skins": {key: {"file": file, "metal": metal} for key, file, _, _, _, metal in SKINS},
        "frameParts": frame_parts,
        "subRule": sub_rule,
        "grain": {"tile": GRAIN_TILE},
    }
    lua = ("-- Generated by tools/textures/build.py from the design canvas. Don't edit by hand:\n"
           "-- change the design or the layouts, then run the script again.\n"
           "-- Positions are in canvas units from the top-left corner of the piece's root\n"
           "-- (win: the window, herald: the herald pop-up, settings: the settings page, ballot: the Ballot Hall layout;\n"
           "-- y goes down). l, r, t, b are the piece's texture coordinates.\n\n"
           "local _, MOTA = ...\n\nMOTA.Media = " + lua_value(media) + "\n")
    (ADDON / "Media.lua").write_text(lua, encoding="utf-8", newline="\n")
    print("  Media.lua")

    if "--preview" in sys.argv:
        out = Path(tempfile.gettempdir())
        for key, file, *_ in SKINS:
            preview_window(pieces, textures, slots, media, key, out / f"mota-window-{file}.png")
        preview_extras(pieces, textures, out / "mota-extras-preview.png")
        print(f"Previews: {out / 'mota-window-<skin>.png'} for each skin, {out / 'mota-extras-preview.png'}")


def put(img, pieces, textures, name, ox, oy, dx=0, dy=0, tint=None, at=None, flip=(False, False)):
    p = pieces[name]
    tex = textures[p["tex"]]
    W, H = tex.size
    part = tex.crop((round(p["l"] * W), round(p["t"] * H), round(p["r"] * W), round(p["b"] * H)))
    part = part.resize((max(1, round(p["w"])), max(1, round(p["h"]))), Image.LANCZOS)
    if flip[0]:
        part = part.transpose(Image.FLIP_LEFT_RIGHT)
    if flip[1]:
        part = part.transpose(Image.FLIP_TOP_BOTTOM)
    if tint:
        r, g, b = (int(tint[i:i + 2], 16) for i in (0, 2, 4))
        solid = Image.new("RGBA", part.size, (r, g, b, 255))
        solid.putalpha(part.getchannel("A"))
        part = solid
    x, y = at or (p["x"] + dx, p["y"] + dy)
    img.alpha_composite(part, (round(ox + x), round(oy + y)))


# Colours the add-on gives the white pieces, per skin (ADDON_SPEC.md 9.3; UI/Skin.lua holds the real ones).
PREVIEW_INK = {
    "UNREGISTERED": ("E5CF92", "EBC3B2", "0E1F45", "3A2A0A", "B9C9EE"),
    "SILVERHAND": ("DCE3EE", "AEB9CC", "1F4290", "2B3445", "D5DEF0"),
    "AZEROTH_EXCHANGE": ("F3D98A", "F0C9BC", "5A0E13", "3A2A0A", "F2CDBE"),
    "CROWN": ("F3D98A", "E8C6DC", "3E0A2F", "3A2A0A", "EBCBDF"),
}


def preview_window(pieces, textures, slots, media, key, out):
    """Assembles the window in one skin roughly the way the add-on does, for checking."""
    file, metal = media["skins"][key]["file"], media["skins"][key]["metal"]
    ink, small, ink_on, small_on, pale = PREVIEW_INK[key]
    img = Image.new("RGBA", (WIN_W + 240, WIN_H + 240), (17, 19, 27, 255))
    O = 120
    P = lambda name, **kw: put(img, pieces, textures, name, O, O, **kw)
    lp = pieces[f"{file}:leather"]
    P(f"{file}:leather")
    lr = slots["leather"]  # the grain, tiled over the leather
    tile = textures["grain"].crop((0, 0, GRAIN_SIZE, GRAIN_SIZE)).resize((GRAIN_TILE, GRAIN_TILE), Image.LANCZOS)
    layer = Image.new("RGBA", (round(lr["w"]), round(lr["h"])), (0, 0, 0, 0))
    for gx in range(0, layer.width, GRAIN_TILE):
        for gy in range(0, layer.height, GRAIN_TILE):
            layer.alpha_composite(tile, (gx, gy))
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, layer.width - 1, layer.height - 1), radius=7, fill=255)
    layer.putalpha(Image.composite(layer.getchannel("A"), mask, mask))
    img.alpha_composite(layer, (round(O + lr["x"]), round(O + lr["y"])))
    for part in media["frameParts"]:
        P(f"{metal}:{part}")
    P("parch")
    c, tr = pieces[f"{metal}:corner"], slots["corner-tr"]
    ox, oy = c["x"] - tr["x"], c["y"] - tr["y"]
    P(f"{metal}:corner")
    bl, br = slots["corner-bl"], slots["corner-br"]
    P(f"{metal}:corner", at=(bl["x"] + bl["w"] - ox - c["w"], bl["y"] + bl["h"] - oy - c["h"]), flip=(True, True))
    P(f"{metal}:corner", at=(br["x"] + ox, br["y"] + br["h"] - oy - c["h"]), flip=(False, True))
    P(f"{metal}:title")
    sub = pieces["subtitle1"]
    rule = pieces[f"{metal}:subRule"]
    P("subtitle1", tint=pale)
    P(f"{metal}:subRule", at=(sub["x"] - media["subRule"]["gapL"] - rule["w"], rule["y"]))
    P(f"{metal}:subRule", at=(sub["x"] + sub["w"] + media["subRule"]["gapR"], rule["y"]), flip=(True, False))
    for i in range(1, 8):
        if i == 1:
            P(f"{metal}:tabOn")
        else:
            P(f"{file}:tabRest", dy=(i - 2) * 57)
        P(f"icon{i}", tint=ink_on if i == 1 else ink)
        P(f"label{i}", tint=ink_on if i == 1 else ink)
        P(f"small{i}", tint=small_on if i == 1 else small)
    for name in ("eyebrow1", "divider"):
        P(name)
    for name in (f"{file}:knobSettings", f"{file}:knobClose", f"{metal}:portrait", f"{metal}:railLine",
                 f"{metal}:pip", f"{file}:crest"):
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
    S("segSkinBox")
    S("segPartyOn")
    S("segMinistryOff")
    img.save(out)


if __name__ == "__main__":
    main()
