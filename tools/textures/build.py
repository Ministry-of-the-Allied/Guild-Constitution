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
import os
import re
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

import districts  # the Districts page's map, outlines and pins (Batch D3)

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

# The window border (Max, 8 Nov: yes, at 1.5 times the lit tab's size): window-frame-gold.svg
# (WindowBorders board) as a nine-slice, drawn whole once in gold and once greyed for Silverhand,
# as the board's border-image: 28 / 42px round, 14 out from the window's edge.
BORDER_SVG = DESIGN / "textures" / "window-frame-gold.svg"
BORDER_SLICE, BORDER_WIDTH, BORDER_OUT = 28, 42, 14   # svg units cut; canvas units drawn; out from the edge
BORDER_SCALE = 3      # 80 svg units drawn 240 wide: sharp at 1.5x


# The game's Map & Quest Log, dressed (D5, World map skins board): one texture per skin.
# file name (as SKINS) -> the board's class for that skin
WM_SKINS = {"ministry": "sk-min", "silverhand": "sk-sh", "exchange": "sk-ex", "crown": "sk-cr"}
WM_VIEW = (1400, 1450)
WM_LEATHER_SCALE = 0.4  # a soft gradient: drawn small, stretched in the game
# Drawn at their own size (the game scales them to the button they dress).
WM_FIXED = {"title": "wm-title", "knobEnlarge": "wm-enlarge", "knobClose": "wm-close", "track": "wm-track",
            "reset": "wm-reset", "gear": "wm-gear", "round": "wm-round", "toggle": "wm-toggle",
            "arrowUp": "wm-up", "arrowDown": "wm-down", "seal": "wm-seal", "chev": "wm-chev"}
# Stretched in the game: piece -> (id, slice). slice = the edge kept whole, in canvas units:
# a number for all four sides, or (left, top, right, bottom); 0 stretches that way whole.
WM_STRETCH = {"rim": ("wm-rim", 12), "sep": ("wm-sep", (8, 0, 8, 0)), "nav": ("wm-nav", 6),
              "search": ("wm-search", 6), "count": ("wm-count", 6), "zone": ("wm-zone", 6),
              "plate": ("wm-plate", 6), "mapRim": ("wm-maprim", 5), "log": ("wm-log", 14),
              "scroll": ("wm-scroll", (0, 6, 0, 6)), "divider": ("wm-div", (0, 0, 0, 0)),
              "thumb": ("wm-thumb", (0, 6, 0, 6)), "crumbHome": ("wm-home", (4, 0, 13, 0)),
              "crumbStep": ("wm-step", (13, 0, 13, 0)), "crumbCur": ("wm-cur", (24, 0, 26, 0))}


def border_html(silver):
    url = BORDER_SVG.as_uri()
    filt = "filter:grayscale(1) brightness(1.15);" if silver else ""
    return (f"<!doctype html><html><head><style>html,body{{margin:0;background:transparent}}</style></head>"
            f"<body><img src=\"{url}\" style=\"display:block;width:80px;height:80px;{filt}\"></body></html>")


# The canvas stores its textures under /_blob/ names; these are the same files in the repo.
BLOBS = {
    "c2d86e49cc4f265a0371294274387bd7": "textures/leather-grain.svg",
    "6d5fbe8d4c5384d8cf626886038701ac": "../tools/textures/corner-nogem.svg",  # the gem is its own layer, tinted per skin
    "d4a81ff364cfd13a95212c60a73bd187": "textures/parchment-grain.svg",
    "800598301eab1e913fea8bebb29ced92": "../tools/textures/tab-frame-gold.svg",  # small gold gems, the same in every skin
    "e91083b63eec292d284b54d9d2ba82db": "textures/divider-ink.svg",
    "94ef7c92a8bcd358781dc40e94b03f94": "textures/seal-official.svg",  # the Seal of the State (8-point star)
    "99bf4b4c93aa6e84722428af4ade0c71": "textures/seal-ring.svg",      # ...its Ring form (portcullis)
    "0e3ae79bcbb71b9e22d6acc9f26734b8": "textures/seal-treasury.svg",  # ...its Treasury form (crossed keys)
    "539190bbac866c98462ae1069c2f22b6": "textures/seal-crown.svg",
    "dd8568019d0ff8be3c87935987cf352a": "textures/seal-silverhand.svg",
    "2548a4e779105c6802c9276a14f27592": "textures/seal-exchange.svg",
    "95cd0584f50217d5706a3ab342656520": "textures/crest-crown.png",
    "7c545901b08ed0754c9e9eaf3000577b": "textures/alliance-crest.png",
    "1cb79e1436f6a97727600db25de81026": "../addon/MinistryOfTheAllied/Media/Fonts/MinistryDecorative-Bold.ttf",
    "b86b602a50d468e81c13dca06841b75b": "../addon/MinistryOfTheAllied/Media/Fonts/MinistryDecorative-Black.ttf",
    "e67051d19834004baffef1b06c6515bc": "../tools/textures/divider-ink-cr.svg",  # Window skins board's "as built" view only
    "8a59e9e54e86ea48093135cabb5c5d22": "../tools/textures/divider-ink-ex.svg",
    "956ea6aee795428e80ae248cd84d0698": "textures/window-frame-gold.svg",       # Window borders board (a sample)
    "8ae4bb35e6b8398e6daec3df55902667": "reference/stormwind-city-map.webp",   # Districts board's map (Max's screenshot)
}
# The Crown's mark everywhere (heralds, Royal Assent, the ballot's stamps, the minimap button,
# the settings page) is the Crown crest, which replaced the blue crown seal (Max, 8 Nov).
CROWN_CREST = DESIGN / "textures" / "crest-crown.png"
SEALS = ["official", "crown", "exchange", "silverhand", "ring", "treasury"]  # ring/treasury: the Seal of the State's page variants

FONT_FACES = [
    ("Cinzel", 600, "normal", "Cinzel-SemiBold.ttf"),
    ("Cinzel", 700, "normal", "Cinzel-Bold.ttf"),
    ("Cinzel Decorative", 700, "normal", "MinistryDecorative-Bold.ttf"),  # joined pairs spaced normally (tools/fonts)
    ("Cinzel Decorative", 900, "normal", "MinistryDecorative-Black.ttf"),
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
    "games": '<path d="M7.5 4h9v4.5a4.5 4.5 0 0 1-9 0zM7.5 5.5H5a2.5 2.5 0 0 0 3 3.6M16.5 5.5H19a2.5 2.5 0 0 1-3 3.6M12 13v3.5M9 20h6M10 16.5h4l.6 3.5H9.4z"></path>',
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
    ["kitBlue", "kitStepTodo", "kitMark"] + [f"kitRibbonOn{i}" for i in range(1, 18)]
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
        ".ribbon-mark{background:linear-gradient(90deg,DARK,TOP 50%,DARK)!important}",
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
    "win": [f"tab{i}" for i in range(1, 9)] + [
        "title", "subtitle", "knob-settings", "knob-close", "page", "parch", "eyebrow", "heading",
        "divider", "note", "note2", "railfoot", "portrait", "initials", "who", "who-small",
        "foot", "foot-left", "foot-right", "pip", "crest", "seal", "sheen",
        "rim", "leather", "corner-tr", "corner-bl", "corner-br"],
    "kit": ["kit"],
    "herald": ["herald", "hseal", "htext", "heyebrow", "htitle", "hbody", "hbutton"],
    "settings": ["settings", "sparch", "sseal", "seyebrow", "stitle", "seg", "seg-modest", "seg-royal",
                 "segskin", "seg-party", "seg-ministry", "segmap", "seg-mparty", "seg-mministry", "seg-mplain"]
    + [f"row{i}" for i in range(1, 8)] + [f"slabel{i}" for i in range(1, 8)]
    + [f"ssmall{i}" for i in range(1, 8)] + [f"sw{i}" for i in range(1, 5)],
    # The Ballot Hall's pieces, so the add-on knows each one's own box (without its shadow).
    "ballot": ["ballot", "rb-ballot", "rb-ballot-dot", "rb-ballot-on", "rb-ballot-on-dot", "rb-results",
               "rb-results-on", "rb-crown", "rb-crown-on", "seal-off", "seal-sh", "seal-ex", "seal-crown", "seal-tilt", "stamp", "held",
               "held-sh", "held-ex", "ring", "kdot-on", "kdot-off", "diamond", "portrait-king", "btn-seal", "btn-open", "btn-close",
               "btn-seal-ico", "btn-declare", "btn-runoff", "btn-last", "btn-add", "pill-general", "pill-general-on", "pill-snap",
               "pill-snap-on", "pill-runoff", "pill-runoff-on", "xbtn", "paper-ballot", "paper-half", "paper-wide"],
    # The world map's dress (D5): positions are from the window's top-left at the board's size.
    "wm": ["wm"],
}


# --------------------------------------------------------------------- live text
# Text inside a piece is not baked into the picture: the build measures it (words, font, size,
# spacing, colour, shadow, where it sits), draws the piece without it, and the add-on lays the
# same words over the picture as game text (UI/LiveText.lua), which stays sharp at any window
# size (Max, 8 Nov). Kept as pictures: the window's title (gold gradient letters) and the tabs'
# label/small pieces (the tabs draw their own text; the pieces only give the places), and the Ballot
# Hall's held block, whose strip is tilted (game text can't tilt).
BAKED_TEXT = re.compile(r"(^|:)title$|^label\d+$|^small\d+$|^b_held")

# Finds every visible text run on the page; build.py keeps the ones inside the piece being drawn.
TEXT_JS = r"""<script>(function () {
  const runs = [];
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = walk.nextNode())) {
    const raw = n.nodeValue;
    if (!raw || !raw.trim()) continue;
    const el = n.parentElement;
    if (!el || el.closest('svg,script,style,pre,title,head')) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none') continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    const lines = Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0);
    if (!lines.length) continue;
    const b = range.getBoundingClientRect();
    const anc = [];
    for (let e = el.parentElement; e && e !== document.body; e = e.parentElement) if (e.id) anc.push(e.id);
    let text = raw.replace(/\s+/g, ' ').trim();
    if (cs.textTransform === 'uppercase') text = text.toUpperCase();
    else if (cs.textTransform === 'lowercase') text = text.toLowerCase();
    runs.push({ text, own: el.id || '', anc, x: b.left, y: b.top, w: b.width, h: b.height, lines: lines.length,
      family: cs.fontFamily, weight: parseInt(cs.fontWeight, 10) || 400, style: cs.fontStyle,
      size: parseFloat(cs.fontSize), ls: cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing) || 0,
      color: cs.color, fill: cs.webkitTextFillColor, align: cs.textAlign, shadow: cs.textShadow });
  }
  const pre = document.createElement('pre');
  pre.id = 'texts-json';
  pre.style.display = 'none';
  pre.textContent = JSON.stringify(runs);
  document.body.appendChild(pre);
})();</script>"""

# Makes the piece's own text invisible for the picture (its runs are wrapped in a clear span).
HIDE_JS = r"""<script>(function (show, hide) {
  const pick = (el, list) => list.exact.includes(el.id) ||
    (function () { for (let e = el.parentElement; e; e = e.parentElement) if (e.id && list.desc.includes(e.id)) return true; return false; })();
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const todo = [];
  let n;
  while ((n = walk.nextNode())) {
    const el = n.parentElement;
    if (!n.nodeValue.trim() || !el || el.closest('svg,script,style,pre')) continue;
    if (pick(el, show) && !pick(el, hide)) todo.push(n);
  }
  for (const t of todo) {
    const s = document.createElement('span');
    for (const p of ['color', '-webkit-text-fill-color']) s.style.setProperty(p, 'transparent', 'important');
    s.style.setProperty('text-shadow', 'none', 'important');
    t.parentNode.insertBefore(s, t);
    s.appendChild(t);
  }
})(%s, %s);</script>"""


def piece_lists(css):
    """The ids a piece's only() CSS shows and hides: {"exact": [...], "desc": [...]} each."""
    def ids(rule):
        out = {"exact": [], "desc": []}
        if rule:
            for sel in rule.group(1).split(","):
                m = re.fullmatch(r"\s*#([\w-]+)(\s+\*)?\s*", sel)
                if m:
                    out["desc" if m.group(2) else "exact"].append(m.group(1))
        return out
    show = re.search(r"\n([^{}\n]+)\{visibility:visible!important\}", css)
    hide = re.search(r"\n(?!body \*)([^{}\n]+)\{visibility:hidden!important\}", css)
    return ids(show), ids(hide)


def css_without_visibility(css):
    return re.sub(r"[^{}\n]*\{visibility:(?:hidden|visible)!important\}", "", css)


def font_key(family, weight, style):
    first = family.split(",")[0].strip(" '\"").lower()
    if "decorative" in first:
        return "decoBlack" if weight >= 800 else "decoBold"
    if first == "cinzel":
        return "cinzel" if weight >= 650 else "cinzelSemi"
    if style == "italic":
        return "garamondItalic"
    return "garamondMedium" if weight >= 500 else "garamond"


def css_color(text):
    """'rgb(1, 2, 3)' or 'rgba(1, 2, 3, .5)' -> ("010203", alpha), or None."""
    m = re.match(r"rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)", text or "")
    if not m:
        return None
    r, g, b = (round(float(v)) for v in m.group(1, 2, 3))
    return f"{r:02X}{g:02X}{b:02X}", float(m.group(4)) if m.group(4) else 1.0


def text_record(run, ox, oy, pos):
    """One run as the add-on reads it: place relative to the piece, font, colour, spacing."""
    col = css_color(run["color"]) or ("000000", 1.0)
    fill = css_color(run["fill"])
    if fill and fill[1] > 0:
        col = fill
    rec = {"s": run["text"], "x": round(run["x"] - ox - pos["x"], 2), "y": round(run["y"] - oy - pos["y"], 2),
           "w": round(run["w"], 2), "h": round(run["h"], 2), "f": font_key(run["family"], run["weight"], run["style"]),
           "z": round(run["size"], 2), "t": round(run["ls"] / run["size"], 3) if run["size"] else 0,
           "c": col[0], "a": round(col[1], 3),
           "j": {"center": "CENTER", "right": "RIGHT", "end": "RIGHT"}.get(run["align"], "LEFT"), "n": run["lines"]}
    m = re.match(r"(rgba?\([^)]*\))\s+(-?[\d.]+)px\s+(-?[\d.]+)px", run["shadow"] or "")
    if m:
        sc = css_color(m.group(1))
        if sc and sc[1] > 0:
            rec.update(sx=float(m.group(2)), sy=float(m.group(3)), sc=sc[0], sa=round(sc[1], 3))
    return rec


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
        "seal": CROWN_CREST.as_uri(),  # the minimap button: the Crown crest (Max, 8 Nov)
        "subtitle": html.escape(p["subtitle"], quote=False),
        "eyebrow": html.escape(p["eyebrow"], quote=False),
        "heading": html.escape(p["heading"], quote=False),
        "note": html.escape(p["note"], quote=False),
    })


def extras_html(css, piece_css="", seal="official", button="Vote now", style="blue", seg="full", skin_seg="party",
                map_seg="party"):
    return fill("extras.html", {
        "party_class": "on" if skin_seg == "party" else "",
        "ministry_class": "on" if skin_seg == "ministry" else "",
        "mparty_class": "on" if map_seg == "party" else "",
        "mministry_class": "on" if map_seg == "ministry" else "",
        "mplain_class": "on" if map_seg == "plain" else "",
        "css": css + "\n" + piece_css,
        "seal": (CROWN_CREST if seal == "crown" else DESIGN / "textures" / f"seal-{seal}.svg").as_uri(),
        "crown": CROWN_CREST.as_uri(),
        "seal_sh": (DESIGN / "textures" / "seal-silverhand.svg").as_uri(),
        "seal_ex": (DESIGN / "textures" / "seal-exchange.svg").as_uri(),
        "coin_g": (DESIGN / "textures" / "coin-g.svg").as_uri(),
        "coin_s": (DESIGN / "textures" / "coin-s.svg").as_uri(),
        "coin_c": (DESIGN / "textures" / "coin-c.svg").as_uri(),
        "button": html.escape(button, quote=False),
        "button_class": "btn sm" if style == "blue" else "btn quiet sm",
        "modest_class": "on" if seg == "small" else "",
        "royal_class": "on" if seg == "full" else "",
    })


def ballot_html(css, piece_css=""):
    return fill("ballot.html", {
        "css": css + "\n" + piece_css,
        "official": (DESIGN / "textures" / "seal-official.svg").as_uri(),
        "crown": CROWN_CREST.as_uri(),
        "silverhand": (DESIGN / "textures" / "seal-silverhand.svg").as_uri(),
        "exchange": (DESIGN / "textures" / "seal-exchange.svg").as_uri(),
    })


def worldmap_html(css, piece_css="", skin="sk-min", emblem="alliance-crest.png", emblem_cls=""):
    # the seal: the skin's own emblem (the window's), a shield crest or a round party seal
    return fill("worldmap.html", {"css": css + "\n" + piece_css, "skin": skin,
                                  "crest": (DESIGN / "textures" / emblem).as_uri(),
                                  "crest_class": "" if emblem_cls == "seal" else "crest"})


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
                 "kitRibbonOff2", "kitRibbonOff3", "kitGem", "kitGemHollow", "kitCoinG", "kitCoinS", "kitCoinC", "kitBand", "kitMark",
                 "kitRibbonOn8", "kitRibbonOn9", "kitRibbonOn10", "kitRibbonOff4", "kitRibbonOff8", "kitRibbonOff9", "kitRibbonOff10",
                 "kitStepTodo", "kitStepDone", "kitStepNow", "kitRibbonOn5", "kitRibbonOn6", "kitRibbonOn7",
                 "kitRibbonOff5", "kitRibbonOff6", "kitRibbonOff7", "kitPortraitSh", "kitPortraitEx",
                 "kitRibbonOn11", "kitRibbonOn12", "kitRibbonOn13", "kitRibbonOff11", "kitRibbonOff12", "kitRibbonOff13",
                 # The Games Hall (Duncan, 8 Nov): Lottery, The Hunt, The Cup, Honours, and the medallions
                 "kitRibbonOn14", "kitRibbonOn15", "kitRibbonOn16", "kitRibbonOn17",
                 "kitRibbonOff14", "kitRibbonOff15", "kitRibbonOff16", "kitRibbonOff17", "kitMedalG", "kitMedalS"):
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
    # The world map skin switch (Batch D5f): Party, Ministry, Plain
    settings("segMapBox", only(["#segmap"]))
    for value, el in (("party", "seg-mparty"), ("ministry", "seg-mministry"), ("plain", "seg-mplain")):
        name = "segMap" + value.title()
        settings(name + "On", only([f"#{el}"]), map_seg=value)
        settings(name + "Off", only([f"#{el}"]), map_seg="ministry" if value == "party" else "party")

    # The Ballot Hall (Milestone 4). Piece names are the layout's ids, prefixed "b_".
    for el in SLOTS["ballot"][1:]:
        if el == "btn-seal-ico":
            continue  # only a place (where the party's seal goes on the Seal button), nothing to draw
        if el.startswith("paper-"):
            ballot("b_" + el, only([f"#{el}"]), tex="papers", scale=PAPER_SCALE)
        else:
            ballot("b_" + el, only([f"#{el}", f"#{el} *"]))

    # The world map's dress (D5), once per skin, named "wm_<file>:<piece>" in "wmap_<file>".
    for file, cls in WM_SKINS.items():
        _, _, _, emblem, emblem_cls, _ = next(s for s in SKINS if s[1] == file)
        def w(name, css, scale=ATLAS_SCALE, cls=cls, file=file, emblem=emblem, emblem_cls=emblem_cls):
            d[f"wm_{file}:{name}"] = dict(tex="wmap_" + file, scale=scale, layout="worldmap", root="wm",
                                          args={"skin": cls, "emblem": emblem, "emblem_cls": emblem_cls}, css=css)
        w("leather", only(["#wm-leather"]), scale=WM_LEATHER_SCALE)
        for name, el in WM_FIXED.items():
            w(name, only([f"#{el}", f"#{el} *"]),
              scale=1.3 if name == "title" else CREST_SCALE if name == "seal" else 3 if name == "chev" else ATLAS_SCALE)
        for name, (el, _) in WM_STRETCH.items():
            w(name, only([f"#{el}", f"#{el} *"]))

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

    def texts(self, name, text, size=None):
        """The text runs TEXT_JS finds on a page."""
        page = self.workdir / f"{name}-texts.html"
        page.write_text(text, encoding="utf-8")
        out = subprocess.run(self._args(1, size) + ["--dump-dom", page.as_uri()],
                             capture_output=True, timeout=180, text=True, encoding="utf-8")
        m = re.search(r'<pre id="texts-json"[^>]*>(.*?)</pre>', out.stdout, re.S)
        if not m:
            raise RuntimeError(f"Edge didn't report the text on {name}")
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
           "ballot": stylesheet("BallotHall.dc.html"),
           "worldmap": stylesheet("WorldMapSkins.dc.html")}
    render = {
        "window": lambda c, args: window_html(pages, css["window"], c, **args),
        "extras": lambda c, args: extras_html(css["extras"], c, **args),
        "ballot": lambda c, args: ballot_html(css["ballot"], c),
        "grain": lambda c, args: grain_html(),
        "worldmap": lambda c, args: worldmap_html(css["worldmap"], c, **args),
    }
    view = {"ballot": BALLOT_VIEW, "grain": (GRAIN_TILE, GRAIN_TILE), "worldmap": WM_VIEW}
    MEDIA.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="mota-textures-"))
    edge = Edge(work)
    print("Reading the layouts...")
    rects = {}
    rects.update(edge.rects("window", render["window"]("", {})))
    rects.update(edge.rects("extras", render["extras"]("", {})))
    rects.update(edge.rects("ballot", render["ballot"]("", {}), BALLOT_VIEW))
    rects.update(edge.rects("worldmap", render["worldmap"]("", {}), WM_VIEW))
    origin = {root: (rects[root]["x"], rects[root]["y"]) for root in SLOTS}
    slots = {}
    for root, names in SLOTS.items():
        ox, oy = origin[root]
        for n in names:
            r = rects[n]
            slots[n] = {"x": r["x"] - ox, "y": r["y"] - oy, "w": r["w"], "h": r["h"], "root": root}

    todo = pieces_to_draw(pages)

    # Live text (see BAKED_TEXT): measure each piece's text, on one page per distinct look.
    combos, wanted = {}, {}
    for name, p in todo.items():
        if p.get("raw") or p["layout"] == "grain" or BAKED_TEXT.search(name):
            continue
        show, hide = piece_lists(p["css"])
        if not (show["exact"] or show["desc"]):
            continue
        key = (p["layout"], json.dumps(p["args"], sort_keys=True), css_without_visibility(p["css"]))
        combos.setdefault(key, len(combos))
        wanted[name] = (key, show, hide)
    print(f"Measuring the text on {len(combos)} pages...")

    def measure(key):
        layout, args, extra = key
        page = render[layout](extra, json.loads(args)).replace("</body>", TEXT_JS + "</body>")
        return key, edge.texts(f"texts{combos[key]}", page, view.get(layout))

    runs_on = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for key, runs in pool.map(measure, list(combos)):
            runs_on[key] = runs

    def picked(run, lists):
        return run["own"] in lists["exact"] or any(a in lists["desc"] for a in run["anc"])

    def drawn_colour(run):  # clear text (the gradient title's letters) has nothing to lay over
        fill = css_color(run["fill"])
        col = fill if fill else css_color(run["color"])
        return col and col[1] > 0

    live = {}
    for name, (key, show, hide) in wanted.items():
        runs = [r for r in runs_on[key] if picked(r, show) and not picked(r, hide) and drawn_colour(r)]
        if runs:
            live[name] = (runs, show, hide)
    print(f"  {len(live)} pieces carry text; it is drawn live in the game")

    print(f"Drawing {len(todo)} pieces in Edge...")
    drawn = {}

    def draw(name):
        p = todo[name]
        page = render[p["layout"]](p["css"], p["args"])
        if name in live:
            _, show, hide = live[name]
            page = page.replace("</body>", HIDE_JS % (json.dumps(show), json.dumps(hide)) + "</body>")
        im = edge.screenshot(name.replace(":", "_"), page, p["scale"], view.get(p["layout"]))
        if p.get("raw"):
            return name, (im, None)
        try:
            return name, crop(im, p["scale"], origin[p["root"]])
        except RuntimeError:
            if name not in live:
                raise
            # nothing but text: a clear picture the size of the text keeps the piece's place
            runs, ox, oy, s = live[name][0], *origin[p["root"]], p["scale"]
            x0, y0 = min(r["x"] for r in runs), min(r["y"] for r in runs)
            x1, y1 = max(r["x"] + r["w"] for r in runs), max(r["y"] + r["h"] for r in runs)
            clear = Image.new("RGBA", (max(1, round((x1 - x0) * s)), max(1, round((y1 - y0) * s))), (0, 0, 0, 0))
            return name, (clear, {"x": x0 - ox, "y": y0 - oy, "w": x1 - x0, "h": y1 - y0})

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name, result in pool.map(draw, todo):
            drawn[name] = result
    texts = {}
    for name, (runs, _, _) in live.items():
        ox, oy = origin[todo[name]["root"]]
        texts[name] = [text_record(r, ox, oy, drawn[name][1]) for r in runs]

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

    packed = (["atlas", "extras", "ballot", "papers", "accent"] + ["frame_" + m for m in METALS]
              + ["skin_" + s[1] for s in SKINS] + ["wmap_" + f for f in WM_SKINS])
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

    # The window border: gold, and greyed for Silverhand, side by side in one texture.
    print("Drawing the window border...")
    border = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    for i, metal in enumerate(("gold", "silver")):
        im = edge.screenshot(f"border_{metal}", border_html(metal == "silver"), BORDER_SCALE, (200, 200))
        im = im.crop((0, 0, 80 * BORDER_SCALE, 80 * BORDER_SCALE))
        border.paste(im, (i * 256, 0))
        pieces[f"border_{metal}"] = dict(tex="border", root="win", x=0, y=0, w=80, h=80,
                                         l=i * 256 / 512, r=(i * 256 + 80 * BORDER_SCALE) / 512, t=0, b=80 * BORDER_SCALE / 256)
    textures["border"] = border

    # The Districts page (Batch D3): the Stormwind City map, the district outlines, the pins.
    print("Drawing the districts...")
    dz_tex, dz_pieces, dz_media = districts.build(pack, pow2)
    textures.update(dz_tex)
    pieces.update(dz_pieces)
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
        # Text laid over a piece as game text (UI/LiveText.lua): s words, x y w h its box from the piece's
        # top-left, f font, z size, t letter-spacing in em, c a colour, j justify, n lines, sx sy sc sa shadow.
        "texts": {name: recs for name, recs in texts.items() if name in pieces},
        "slots": slots,
        "pages": pages,
        # Window skins (ADDON_SPEC.md 9.7): per-skin pieces are named "<file>:<piece>",
        # per-metal ones "<metal>:<piece>"; frameParts are the metal's frame bands.
        "skins": {key: {"file": file, "metal": metal} for key, file, _, _, _, metal in SKINS},
        "frameParts": frame_parts,
        "subRule": sub_rule,
        "grain": {"tile": GRAIN_TILE},
        # The window border's nine-slice: slice in svg units (of 80), width drawn, out from the window's edge.
        "border": {"slice": BORDER_SLICE, "size": 80, "width": BORDER_WIDTH, "out": BORDER_OUT},
        # The Districts page's chart (root "map": screenshot pixels from the chart's top-left).
        "districts": dz_media,
        # The world map's dress (D5): its pieces are "wm_<file>:<name>" (root "wm": canvas units from
        # the board window's top-left, 1100 x 749). slice: the stretched pieces' edges kept whole,
        # {left, top, right, bottom} in canvas units (0 = stretched that way whole).
        "wmap": {"window": {"w": 1100, "h": 749}, "skins": {f: "wmap_" + f for f in WM_SKINS},
                 "slice": {name: dict(zip(("l", "t", "r", "b"), s if isinstance(s, tuple) else (s,) * 4))
                           for name, (_, s) in WM_STRETCH.items()},
                 # each stretched piece's own box (its picture can reach past it: shadows, the hairline)
                 "box": {name: {"w": rects[el]["w"], "h": rects[el]["h"]} for name, (el, _) in WM_STRETCH.items()},
                 # each whole piece's own box on the board (canvas units from the window's top-left): its
                 # picture reaches past it by its shadow, so the game fits the box, not the picture, to
                 # the button it dresses (the seal's box differs by skin: UI/WorldMapSkin.lua has it)
                 "at": {name: {k: round(rects[el][k] - (rects["wm"][k] if k in "xy" else 0), 2) for k in "xywh"}
                        for name, el in WM_FIXED.items() if name != "seal"}},
    }
    lua = ("-- Generated by tools/textures/build.py from the design canvas. Don't edit by hand:\n"
           "-- change the design or the layouts, then run the script again.\n"
           "-- Positions are in canvas units from the top-left corner of the piece's root\n"
           "-- (win: the window, herald: the herald pop-up, settings: the settings page, ballot: the Ballot Hall layout;\n"
           "-- y goes down). l, r, t, b are the piece's texture coordinates.\n\n"
           "local _, MOTA = ...\n\nMOTA.Media = " + lua_value(media) + "\n")
    # through a temporary file: a direct write sometimes fails "Invalid argument" on this machine
    tmp = ADDON / "Media.lua.tmp"
    tmp.write_text(lua, encoding="utf-8", newline="\n")
    os.replace(tmp, ADDON / "Media.lua")
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
    for i in range(1, len(media["pages"]) + 1):
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
