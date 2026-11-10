"""The herald pop-up's banner (Max, 9 Nov 2026), for tools/textures/build.py.

The design is Max's reference picture, design/reference/herald-banners.webp: three banners
(gold frame, blue velvet, crown and lions round a parchment panel) drawn on a checkerboard.
It is used as it is for the Ministry skin and only recoloured for the others, so nothing here
redraws it: the first banner is cut out of the checkerboard, its baked-in words, seal and button
are cleared off the parchment, and the parts are recoloured per skin. Live text, the add-on's own
seals and the buttons go back on in the game (UI/Herald.lua), where the reference has them.

Measured from the reference (banner 1): its frame is 1812 x 500 px with its top-left corner at
(94, 138), and at 2.43 px per canvas unit its words are exactly the herald's type (title 21,
body 16, eyebrow 9.5 spaced .32em, button labels 11 spaced .16em). Everything below is in
reference pixels; the game gets canvas units (pixels / K) from the frame's top-left corner.

Per skin (file name as build.SKINS): the frame with its drop shadow, the six seals in their
mount, and the three buttons (blue, gold, quiet), packed in one texture, herald_<file>.tga.
  ministry    the reference as it is
  silverhand  gold made silver; the velvet stays blue
  exchange    the velvet (and the blue button) in the Exchange's crimson accent
  crown       the velvet in the deep plum of the window's Crown leather; the blue button in the plum accent
Needs numpy as well as Pillow.
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
DESIGN = HERE.parents[1] / "design"
REF = DESIGN / "reference" / "herald-banners.webp"

K = 2.43                       # reference pixels per canvas unit
FX, FY, FW, FH = 94, 138, 1812, 500   # banner 1's frame (without the crown above it)
CUT = (70, 35, 1930, 665)      # banner 1 with a margin round it
TEX = (2048, 1024)

# The blue in the reference is the Ministry's accent; the other skins move it along their own.
BLUE = ["#2E58AA", "#1B3570", "#11264F", "#0A1636"]     # .btn: top, middle, bottom, edge
SKINS = {
    "ministry": dict(velvet=None, metal="gold"),
    "silverhand": dict(velvet=None, metal="silver"),
    "exchange": dict(velvet=["#B8343C", "#8E1A21", "#661118", "#2E0609"], metal="gold"),   # the ~ex accent
    # The Crown's velvet is the window's Crown leather (Max, 10 Nov: the accent's plum was lighter and redder
    # than the leather on the window and the map); its blue button keeps the ~cr accent, as its other buttons.
    "crown": dict(velvet=["#451539", "#310C2A", "#260A24", "#1C071D"], metal="gold",
                  button=["#86296A", "#58143F", "#3D0B2D", "#2A0720"]),
}
SEALS = ["official", "crown", "exchange", "silverhand", "ring", "treasury"]

# The seal's mount: the reference's gold bezel; the wax well sits a little high in it (a thicker lower lip).
BEZEL = (367.48, 390.5, 96.83)        # centre x, y and outer radius
WELL = (367.05, 384.87, 82.0)         # the seal is clipped round here
SEAL_PX = 0.875                       # reference px per seal-svg unit: the motto ring where the reference has its
MOUNT = 240                           # mount pictures are drawn this size, the bezel's centre in the middle

# Buttons: crop round it, its label's box (cleared), vertical stretch (banner 3 is drawn 476 tall, not 500),
# and where its body sits on banner 1 (the gold and quiet ones where banner 2 has its gold one: banner 2's
# frame starts at (95, 780), so its button's body, at (1485, 982), is at (1484, 340) on banner 1).
BUTTONS = {
    "blue": dict(crop=(1430, 305, 1765, 470), label=(1494, 364, 1698, 405), stretch=1.0, at=(1460, 332, 276, 109)),
    "gold": dict(crop=(1455, 955, 1756, 1105), label=(1527, 1009, 1685, 1047), stretch=1.0, at=(1484, 340, 240, 95)),
    "quiet": dict(crop=(1456, 1573, 1756, 1718), label=(1528, 1628, 1686, 1663), stretch=500 / 476,
                  at=(1484, 340, 240, 95)),
}

# The banner grows for a third line of text and more: these two thin bands of rows stretch, half the
# extra height each. They are where the side ornaments run straight up and down (rows that change least).
BANDS = [(300, 314), (461, 475)]

# Where the words go: the left edge, and the middle of each line (canvas units from the frame's top).
# Measured against the reference: each line's ink lands within a pixel of it. gap: from the text to
# the button; label_up: the label's middle above the button's. The close X (the reference has none)
# sits on the parchment above the button's right end, clear of the gilt corner: (1712, 300).
TEXT = dict(x=169.4, eyebrow=64.88 + 6, title=76.45 + 13, body=103.04 + 10, line=20, gap=16, label_up=0.2,
            closeX=round((1712 - FX) / K, 2), closeY=round((300 - FY) / K, 2))

LUM = np.array([.299, .587, .114], np.float32)


# ---------------------------------------------------------------------------------------------
# Small image tools (numpy arrays: H x W x C floats)
# ---------------------------------------------------------------------------------------------

def blur(img, r):
    """Gaussian-like blur: three box passes of width 2r + 1."""
    out = img.astype(np.float32)
    for _ in range(3):
        for axis in (0, 1):
            k = 2 * r + 1
            pad = [(0, 0)] * out.ndim
            pad[axis] = (r + 1, r)
            c = np.cumsum(np.pad(out, pad, mode="edge"), axis=axis)
            n = out.shape[axis]
            out = (np.take(c, range(k, k + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / k
    return out


def dilate(m, r):
    out = m.copy()
    for _ in range(r):
        n = out.copy()
        n[1:, :] |= out[:-1, :]
        n[:-1, :] |= out[1:, :]
        n[:, 1:] |= out[:, :-1]
        n[:, :-1] |= out[:, 1:]
        out = n
    return out


def erode(m, r):
    return ~dilate(~m, r)


def resize(arr, size):
    chans = [np.asarray(Image.fromarray(arr[..., i].astype(np.float32), "F").resize(size, Image.BILINEAR))
             for i in range(arr.shape[2])]
    return np.dstack(chans)


def pushpull(c, w):
    """Fills where w == 0, smoothly, from where w > 0 (a pull-push pyramid)."""
    H, W = w.shape
    if min(H, W) <= 2:
        m = (c * w[..., None]).sum((0, 1)) / max(w.sum(), 1e-6)
        return np.where(w[..., None] > 0, c, m)
    h2, w2 = (H + 1) // 2, (W + 1) // 2
    cp = np.pad(c * w[..., None], ((0, h2 * 2 - H), (0, w2 * 2 - W), (0, 0)))
    wp = np.pad(w, ((0, h2 * 2 - H), (0, w2 * 2 - W)))
    cs = cp.reshape(h2, 2, w2, 2, -1).sum((1, 3))
    ws = wp.reshape(h2, 2, w2, 2).sum((1, 3))
    f = pushpull(cs / np.maximum(ws, 1e-6)[..., None], np.minimum(ws, 1.0))
    return c * w[..., None] + resize(f, (W, H)) * (1 - w[..., None])


def harmonic(c, hole, iters):
    """Relaxes the hole to the average of its neighbours, so a fill meets its edges without a seam."""
    ys, xs = np.nonzero(hole)
    y0, y1, x0, x1 = max(ys.min() - 1, 0), ys.max() + 2, max(xs.min() - 1, 0), xs.max() + 2
    sub = c[y0:y1, x0:x1].astype(np.float32).copy()
    h = hole[y0:y1, x0:x1][..., None]
    for _ in range(iters):
        p = np.pad(sub, ((1, 1), (1, 1), (0, 0)), mode="edge")
        sub = np.where(h, (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) * 0.25, sub)
    out = c.copy()
    out[y0:y1, x0:x1] = sub
    return out


def flood(passable, seeds):
    """Everything reachable from the seeds through passable pixels (4-connected)."""
    H, W = passable.shape
    seen = np.zeros((H, W), bool)
    q = deque()
    for y, x in seeds:
        if passable[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < H and 0 <= nx < W and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def border(H, W):
    return [(y, x) for y in range(H) for x in (0, W - 1)] + [(y, x) for x in range(W) for y in (0, H - 1)]


def over(dst, rgb, a):
    """dst (H x W x 4, alpha 0-255) with rgb at alpha a (0-1) laid over it."""
    da = dst[..., 3] / 255
    oa = a + da * (1 - a)
    orgb = (rgb * a[..., None] + dst[..., :3] * (da * (1 - a))[..., None]) / np.maximum(oa, 1e-6)[..., None]
    return np.dstack([orgb, oa * 255])


def to_image(rgba):
    return Image.fromarray(rgba.clip(0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------------------------------------
# Colour: Lab for moving the velvet from one accent to another, and silver for Silverhand
# ---------------------------------------------------------------------------------------------

_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
_WHITE = np.array([0.95047, 1.0, 1.08883])


def lab(rgb):
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = c @ _M.T / _WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def srgb(lab_):
    L, a, b = lab_[..., 0], lab_[..., 1], lab_[..., 2]
    fy = (L + 16) / 116
    f = np.stack([fy + a / 500, fy, fy - b / 200], -1)
    xyz = np.where(f ** 3 > 216 / 24389, f ** 3, (116 * f - 16) / (24389 / 27)) * _WHITE
    c = np.clip(xyz @ np.linalg.inv(_M).T, 0, 1)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055) * 255


def _hex(h):
    return [int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]


def _lch(rgb):
    v = lab(np.asarray(rgb, float))
    return v[..., 0], np.hypot(v[..., 1], v[..., 2]), np.arctan2(v[..., 2], v[..., 1])


def accent_shift(rgb, weight, dst):
    """Moves colours along the blue accent's stops to the same place on another accent's:
    lightness shifted, chroma scaled, hue turned, so the velvet keeps its own texture."""
    v = lab(rgb)
    L, C, h = v[..., 0], np.hypot(v[..., 1], v[..., 2]), np.arctan2(v[..., 2], v[..., 1])
    sL, sC, sh = _lch([_hex(x) for x in BLUE])
    dL, dC, dh = _lch([_hex(x) for x in dst])
    o = np.argsort(sL)
    sL, sC, sh, dL, dC, dh = sL[o], sC[o], sh[o], dL[o], dC[o], dh[o]
    t = np.clip(L, sL[0], sL[-1])
    L2 = L + np.interp(t, sL, dL - sL)
    C2 = C * np.interp(t, sL, dC / sC)
    h2 = h + np.interp(t, sL, np.angle(np.exp(1j * (dh - sh))))
    out = srgb(np.stack([L2, C2 * np.cos(h2), C2 * np.sin(h2)], -1))
    return rgb * (1 - weight[..., None]) + out * weight[..., None]


def blue_weight(rgb):
    """How much of a pixel is the blue velvet (by Lab hue and chroma), 0-1."""
    v = lab(rgb)
    C = np.hypot(v[..., 1], v[..., 2])
    h = np.degrees(np.arctan2(v[..., 2], v[..., 1]))
    d = np.abs((h + 72 + 180) % 360 - 180)
    return np.clip((38 - d) / (38 * 0.35), 0, 1) * np.clip((C - 5) / 8, 0, 1)


def silver(rgb, weight):
    """Gold turned silver: grey by lightness, a little brighter, a cool tint (the Silverhand rim)."""
    g = ((rgb @ LUM) * 1.2 - 128) * 1.05 + 128
    out = np.clip(g[..., None] * np.array([0.95, 0.99, 1.06]), 0, 255)
    return rgb * (1 - weight[..., None]) + out * weight[..., None]


# ---------------------------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------------------------

def cut_out(ref):
    """Banner 1 lifted off the checkerboard: colour and alpha (0-1), the baked shadow left behind."""
    X0, Y0, X1, Y1 = CUT
    a = ref[Y0:Y1, X0:X1].copy()
    H, W = a.shape[:2]
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    sat = a.max(2) - a.min(2)
    grey = (sat < 20) & (np.abs(R - G) < 13) & (np.abs(G - B) < 13)
    bg = flood(grey, border(H, W))
    # grey pockets the flood can't reach (between the crown and its scrolls): big and plainly grey
    body = np.zeros((H, W), bool)
    body[144 - Y0:631 - Y0, 100 - X0:1899 - X0] = True     # the frame's body is solid
    left = grey & ~bg & ~body
    seen = np.zeros((H, W), bool)
    for y, x in zip(*np.nonzero(left)):
        if seen[y, x]:
            continue
        comp = flood(left, [(y, x)])
        seen |= comp
        if comp.sum() >= 40 and sat[comp].mean() < 9 and a[comp].mean() > 90:
            bg |= comp
    bg &= ~body
    fg = ~bg
    # soft edges: the two-pixel rim unmixed against the background next to it and the colour inside it
    edge = fg & dilate(bg, 1)
    band = edge | (fg & dilate(edge, 1))

    def box_mean(img, m, r):
        k = 2 * r + 1
        pad = lambda z: np.pad(z, ((r, r), (r, r)) + ((0, 0),) * (z.ndim - 2))
        def win(z):
            c = np.pad(z.cumsum(0).cumsum(1), ((1, 0), (1, 0)) + ((0, 0),) * (z.ndim - 2))
            return c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
        n = win(pad(m.astype(np.float32)))
        return win(pad(img * m[..., None])) / np.maximum(n, 1e-6)[..., None], n

    bgcol, nb = box_mean(a, bg, 3)
    fgcol, nf = box_mean(a, fg & ~band, 3)
    d = fgcol - bgcol
    al = np.clip(((a - bgcol) * d).sum(2) / np.maximum((d * d).sum(2), 1e-3), 0, 1)
    alpha = fg.astype(np.float32)
    use = band & (nb > 0) & (nf > 0)
    alpha[use] = al[use]
    rgb = a.copy()
    rgb[use] = fgcol[use]
    return rgb, alpha


def clean(rgb, alpha):
    """The parchment with the reference's seal, words and button taken off it."""
    X0, Y0 = CUT[:2]
    H, W = alpha.shape
    yy, xx = np.mgrid[0:H, 0:W]
    gx, gy = xx + X0, yy + Y0
    R, G, B = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb @ LUM
    parch = (lum > 150) & (R - B < 88) & (R - B > 20) & (R >= G)
    seal = np.hypot(gx - BEZEL[0], gy - BEZEL[1]) <= 112
    button = (gx >= 1436) & (gx <= 1762) & (gy >= 312) & (gy <= 478)
    textzone = (gx >= 496) & (gx <= 1430) & (gy >= 292) & (gy <= 497)
    base = blur(pushpull(rgb, (parch & ~seal & ~button).astype(np.float32)), 10)
    ink = dilate(textzone & ((lum < base @ LUM - 16) | (B > R - 25)), 3)
    gone = seal | button | ink
    src = parch & ~gone
    low = pushpull(rgb, src.astype(np.float32))
    hole = ~src & dilate(gone, 6) & (alpha > 0)
    low = harmonic(np.where(hole[..., None], low, blur(rgb, 1)), hole, 1500)
    # the parchment's grain (from a clean strip) and its mottling (noise of the same strength)
    sy0, sy1, sx0, sx1 = 446 - Y0, 500 - Y0, 830 - X0, 1420 - X0
    hp = (rgb - blur(rgb, 2))[sy0:sy1, sx0:sx1]
    hp = np.concatenate([hp, hp[::-1]], 0)
    hp = np.concatenate([hp, hp[:, ::-1]], 1)
    grain = hp[yy % hp.shape[0], xx % hp.shape[1]]
    bstd = (blur(rgb, 2) - blur(rgb, 14))[sy0:sy1, sx0:sx1].reshape(-1, 3).std(0)
    rng = np.random.default_rng(7)
    n1 = blur(rng.standard_normal((H, W)).astype(np.float32), 4)
    n2 = blur(rng.standard_normal((H, W)).astype(np.float32), 9)
    mott = 0.7 * (0.75 * n1 / n1.std() + 0.65 * n2 / n2.std())[..., None] * bstd
    fill = low + grain + mott
    w = np.maximum(blur(dilate(gone, 4).astype(np.float32), 5) * blur(parch.astype(np.float32), 1),
                   gone.astype(np.float32))
    return rgb * (1 - w[..., None]) + fill * w[..., None]


def metal_weight(rgb, alpha):
    """Where the frame is metal (not paper, not velvet): the panel's paper is what is left once the
    gilt ornaments are made solid (strong gold or dark, gaps closed, cream rolls filled)."""
    H, W = alpha.shape
    v = lab(rgb)
    L, C = v[..., 0], np.hypot(v[..., 1], v[..., 2])
    strict = (C > 38) | (L < 45) | (alpha < 1)
    metal = erode(dilate(strict, 4), 4)
    comp = flood(~metal, [(H // 2 + 10, W // 2)])
    paper = comp | (dilate(comp, 4) & ~strict)
    pw = blur(paper.astype(np.float32), 1)
    return (1 - pw) * (1 - blue_weight(rgb))


def with_shadow(rgb, alpha):
    """The frame on a larger canvas with its drop shadow (fitted to the reference's: light from the top left)."""
    L, T, R, B = 60, 40, 80, 110
    H, W = alpha.shape
    a = np.zeros((H + T + B, W + L + R), np.float32)
    a[T:T + H, L:L + W] = alpha
    s = blur(np.roll(np.roll(a, 24, 0), 2, 1), 18) * 0.55
    out = np.zeros(a.shape + (4,), np.float32)
    out[..., 3] = s * 255
    big = np.zeros(a.shape + (3,), np.float32)
    big[T:T + H, L:L + W] = rgb
    out = over(out, big, a)
    return out, (CUT[0] - L, CUT[1] - T)


# ---------------------------------------------------------------------------------------------
# The seals in their mount
# ---------------------------------------------------------------------------------------------

def seal_html(name):
    """The seal as drawn for the pages, but its wax a clean round disc (no drip), a little larger."""
    svg = (DESIGN / "textures" / f"seal-{name}.svg").read_text(encoding="utf-8")
    svg = svg.replace(' filter="url(#drip)"', "")
    svg = svg.replace('<circle cx="110" cy="110" r="90" fill="url(#wax)"', '<circle cx="110" cy="110" r="98" fill="url(#wax)"')
    return ('<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head>'
            f'<body><div style="width:220px;height:220px">{svg}</div></body></html>')


def mounts(edge, ref, cleaned):
    """{metal: {seal: picture}} in the mount, each MOUNT px square with the bezel's centre in the middle."""
    S = MOUNT
    OX, OY = BEZEL[0] - S / 2, BEZEL[1] - S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

    def sample(img, ox, oy, dx=0.0, dy=0.0):
        x = xx + OX - ox + dx
        y = yy + OY - oy + dy
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = (x - x0)[..., None], (y - y0)[..., None]
        return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
                + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)

    rb = np.hypot(xx + OX - BEZEL[0], yy + OY - BEZEL[1])
    rw = np.hypot(xx + OX - WELL[0], yy + OY - WELL[1])
    here = sample(ref, 0, 0)
    under = sample(cleaned, *CUT[:2])
    ring_a = np.clip(BEZEL[2] + 0.5 - rb, 0, 1) * np.clip(rw - 81.0, 0, 1)
    # its shadow on the parchment: how much darker the reference is there than the cleaned parchment
    sh = np.clip(1 - (here @ LUM) / np.maximum(under @ LUM, 1), 0, 0.85)
    sh = blur(sh * np.clip(rb - BEZEL[2] + 0.5, 0, 1) * np.clip((BEZEL[2] + 24 - rb) / 6, 0, 1), 1)
    clip = np.clip(WELL[2] + 0.5 - rw, 0, 1)
    seam = 1 - 0.55 * np.clip((rw - (WELL[2] - 6)) / 6, 0, 1) ** 1.5   # the lip's shade on the wax

    def place(im, cx, cy):
        lay = Image.new("RGBA", (S * 2, S * 2))
        lay.alpha_composite(im, (round(cx * 2 - im.width / 2), round(cy * 2 - im.height / 2)))
        return np.asarray(lay.resize((S, S), Image.LANCZOS)).astype(np.float32)

    def wax(name):
        im = edge.screenshot(f"hseal_{name}", seal_html(name), 4, (220, 220)).crop((0, 0, 880, 880))
        big = im.resize((round(880 * SEAL_PX / 2), round(880 * SEAL_PX / 2)), Image.LANCZOS)   # at 2x
        return place(big, WELL[0] - OX, WELL[1] - OY)

    def medallion():
        # banner 2's gold face, fitted smooth (its crest taken away), with the Crown crest on it
        cx2, cy2 = 370.38 - 0.43, 1028.87 - 5.63
        gx, gy = xx + OX - WELL[0] + cx2, yy + OY - WELL[1] + cy2
        face = ref[np.floor(gy).astype(int), np.floor(gx).astype(int)]
        r = np.hypot(gx - cx2, gy - cy2)
        L = face @ LUM
        loc = blur(L, 2)
        field = ((r < 80) & (r > 30) & (face[..., 0] > face[..., 1]) & (face[..., 1] > face[..., 2] + 20)
                 & (L > 95) & (blur((L - loc) ** 2, 2) < 60))
        u, v = (gx - cx2) / 80, (gy - cy2) / 80
        A = np.stack([np.ones_like(u), u, v, u * u, v * v, u * v], -1)
        out = np.zeros((S, S, 3), np.float32)
        for c in range(3):
            coef, *_ = np.linalg.lstsq(A[field], face[..., c][field], rcond=None)
            out[..., c] = A @ coef
        out += blur(np.random.default_rng(3).standard_normal((S, S)).astype(np.float32), 1)[..., None] * 2.5
        lay = np.dstack([out, np.full((S, S), 255, np.float32)])
        crest = Image.open(DESIGN / "textures" / "crest-crown.png").convert("RGBA")
        crest = crest.crop(crest.getbbox())
        h = 157 * 2
        crest = crest.resize((round(crest.width * h / crest.height), h), Image.LANCZOS)
        c2 = place(crest, WELL[0] - OX - 1, WELL[1] - OY + 3)
        a = c2[..., 3:] / 255
        lay[..., :3] = lay[..., :3] * (1 - a) + c2[..., :3] * a
        return lay

    out = {"gold": {}, "silver": {}}
    for name in SEALS:
        s = medallion() if name == "crown" else wax(name)
        for metal in out:
            pic = np.zeros((S, S, 4), np.float32)
            pic[..., 3] = sh * 255
            pic = over(pic, s[..., :3] * seam[..., None], s[..., 3] / 255 * clip)
            ring = silver(here, np.ones((S, S), np.float32)) if metal == "silver" else here
            out[metal][name] = to_image(over(pic, ring, ring_a))
    return out, (OX, OY)


# ---------------------------------------------------------------------------------------------
# The buttons
# ---------------------------------------------------------------------------------------------

def buttons(ref):
    """{style: (picture as array, rim weight, (body x, body y) inside the picture)}, label-free."""
    out = {}
    for style, b in BUTTONS.items():
        x0, y0, x1, y1 = b["crop"]
        a = ref[y0:y1, x0:x1].copy()
        H, W = a.shape[:2]
        # the body: everything inside its dark outer line
        body = ~flood(~((a @ LUM) < 125), border(H, W))
        body = erode(dilate(body, 2), 2)
        # its label cleared: the box relaxed from its edges
        lx0, ly0, lx1, ly1 = b["label"][0] - x0, b["label"][1] - y0, b["label"][2] - x0, b["label"][3] - y0
        box = np.zeros((H, W), bool)
        box[ly0:ly1, lx0:lx1] = True
        a = harmonic(a, box, 3000)
        # one soft pixel round the body
        alpha = np.clip((np.where(body, np.maximum(blur(body.astype(np.float32), 1), 0.5), 0) - 0.5) * 2, 0, 1)
        alpha = np.maximum(alpha, erode(body, 1).astype(np.float32))
        # the blue button is raised (a soft shadow fitted to the reference); gold and quiet sit flat
        if style == "blue":
            shadow = blur(np.roll(np.roll(body.astype(np.float32), 6, 0), 2, 1), 9) * 0.42 * ~body
        else:
            shadow = np.zeros((H, W), np.float32)
        pic = np.zeros((H, W, 4), np.float32)
        pic[..., 3] = shadow * 255
        pic = over(pic, a, alpha)
        rim = (body & ~erode(body, 11)).astype(np.float32)
        ys, xs = np.nonzero(body)
        bx, by = xs.min(), ys.min()
        if b["stretch"] != 1.0:
            nh = round(H * b["stretch"])
            pic = np.asarray(to_image(pic).resize((W, nh), Image.LANCZOS)).astype(np.float32)
            rim = np.asarray(Image.fromarray(rim, "F").resize((W, nh), Image.BILINEAR))
            by = by * b["stretch"]
        out[style] = (pic, rim, (bx, by))
    return out


def skin_button(style, pic, rim, skin):
    rgb, a = pic[..., :3], pic[..., 3]
    bw = blue_weight(rgb)
    s = SKINS[skin]
    if style == "blue" and (s.get("button") or s["velvet"]):
        rgb = accent_shift(rgb, bw, s.get("button") or s["velvet"])
    if s["metal"] == "silver":
        rgb = silver(rgb, np.ones(a.shape, np.float32) if style == "gold" else rim * (1 - bw))
    return to_image(np.dstack([rgb, a]))


# ---------------------------------------------------------------------------------------------
# Putting it together
# ---------------------------------------------------------------------------------------------

def trim(im, x, y):
    """The picture cut to what it draws, and its new top-left (reference pixels)."""
    box = im.getchannel("A").point(lambda v: 255 if v > 1 else 0).getbbox()
    return im.crop(box), (x + box[0], y + box[1])


def units(x, y, w, h):
    return {"x": round(float(x - FX) / K, 3), "y": round(float(y - FY) / K, 3),
            "w": round(float(w) / K, 3), "h": round(float(h) / K, 3)}


def build(edge):
    """Returns (textures, pieces, media) for build.py: herald_<file> textures, their pieces
    ("herald_<file>:frame", ":seal_<name>", ":btn_<style>", root "banner"), and Media.herald."""
    ref = np.asarray(Image.open(REF).convert("RGB")).astype(np.float32)
    print("  cutting the banner out of the reference...")
    rgb, alpha = cut_out(ref)
    print("  clearing its parchment...")
    cleaned = clean(rgb, alpha)
    metal_w = metal_weight(cleaned, alpha)
    blue_w = blue_weight(cleaned)
    print("  mounting the seals...")
    seal_pics, seal_at = mounts(edge, ref, cleaned)
    btns = buttons(ref)
    textures, pieces = {}, {}
    for skin, s in SKINS.items():
        frame = cleaned
        if s["velvet"]:
            frame = accent_shift(frame, blue_w, s["velvet"])
        if s["metal"] == "silver":
            frame = silver(frame, metal_w)
        pic, at = with_shadow(frame, alpha)
        parts = [("frame",) + trim(to_image(pic), *at)]
        for name in SEALS:
            parts.append((f"seal_{name}",) + trim(seal_pics[s["metal"]][name], *seal_at))
        for style, (bpic, rim, (bx, by)) in btns.items():
            ax, ay = BUTTONS[style]["at"][:2]
            parts.append((f"btn_{style}",) + trim(skin_button(style, bpic, rim, skin), ax - bx, ay - by))
        # packed: the frame across the top; under it the seals, the blue button, and the gold
        # button with the quiet one below it
        P = 2
        spots, x = {}, 0
        frame_h = parts[0][1].height
        spots["frame"] = (P, P)
        y = frame_h + 3 * P
        for part, im, _ in parts[1:]:
            if part in ("btn_gold", "btn_quiet"):
                continue
            spots[part] = (x + P, y)
            x += im.width + 2 * P
        spots["btn_gold"] = (x + P, y)
        spots["btn_quiet"] = (x + P, y + dict((p, im) for p, im, _ in parts)["btn_gold"].height + 2 * P)
        tex = Image.new("RGBA", TEX, (0, 0, 0, 0))
        name = f"herald_{skin}"
        for part, im, (px, py) in parts:
            sx, sy = spots[part]
            if sx + im.width > TEX[0] or sy + im.height > TEX[1]:
                raise RuntimeError(f"{name}: {part} doesn't fit in {TEX}")
            tex.paste(im, (sx, sy))
            pieces[f"{name}:{part}"] = dict(units(px, py, im.width, im.height), tex=name, root="banner",
                                            l=sx / TEX[0], r=(sx + im.width) / TEX[0],
                                            t=sy / TEX[1], b=(sy + im.height) / TEX[1])
        textures[name] = tex
    media = {
        "w": round(FW / K, 3), "h": round(FH / K, 3),
        "bands": [[round((a - FY) / K, 3), round((b - FY) / K, 3)] for a, b in BANDS],
        "text": TEXT,
        "buttons": {style: units(*b["at"]) for style, b in BUTTONS.items()},
    }
    return textures, pieces, media
