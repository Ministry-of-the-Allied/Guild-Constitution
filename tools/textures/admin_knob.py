"""Builds Media/admin_knob.tga: the Admin Controls knob, one cell per skin.

The knob has the Settings (gear) knob's shape and colours, with the lock where the
gear is. For each skin it crops the gear knob out of skin_<name>.tga, paints the gear
out of the face by smooth diffusion inpainting, lifts the lock glyph from that skin's
lock knob and pastes it, centred, on the face.

Run from the repo root:  python tools/textures/admin_knob.py [preview.png]
Output: addon/MinistryOfTheAllied/Media/admin_knob.tga, RGBA, 4 cells of 128x128 side
by side (crown, exchange, ministry, silverhand), the picture at each cell's top-left.
In the add-on: texcoords left=i*128/512, right=(i*128+W)/512, top=0, bottom=H/128.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

MEDIA = "addon/MinistryOfTheAllied/Media/"
CELL = 128
TEX = 1024, 512

# (gear l, r), (lock l, r) as fractions of the texture; t, b shared per kind
GEAR_TB = (0.19922, 0.38281)
LOCK_TB = (0.00391, 0.19141)
SKINS = [
    ("crown", (0.82129, 0.9248), (0.71387, 0.80762)),
    ("exchange", (0.68652, 0.79004), (0.68652, 0.78027)),
    ("ministry", (0.8252, 0.92871), (0.71777, 0.81152)),
    ("silverhand", (0.68555, 0.78906), (0.68555, 0.7793)),
]


def box(lr, tb):
    return (round(lr[0] * TEX[0]), round(tb[0] * TEX[1]),
            round(lr[1] * TEX[0]), round(tb[1] * TEX[1]))


def lum(a):
    return a[..., :3].astype(float) @ np.array([0.299, 0.587, 0.114])


def disc(h, w, cx, cy, r):
    yy, xx = np.mgrid[0:h, 0:w]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


def grow(mask, n):
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * n + 1))
    return np.array(m) > 127


def inpaint(rgb, mask, iters=4000):
    """Fills the masked pixels by diffusion from their surroundings."""
    out = rgb.astype(float).copy()
    known = ~mask
    # start from the mean of the known neighbourhood
    out[mask] = out[known].mean(axis=0)
    for _ in range(iters):
        p = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        out[mask] = avg[mask]
    return out


def build(name, gear_lr, lock_lr):
    tex = Image.open(f"{MEDIA}skin_{name}.tga").convert("RGBA")
    gear = np.array(tex.crop(box(gear_lr, GEAR_TB))).astype(float)
    lock = np.array(tex.crop(box(lock_lr, LOCK_TB))).astype(float)
    h, w = gear.shape[:2]
    alpha = gear[..., 3]
    cx, cy = (w - 1) / 2, (h - 1) / 2

    # --- paint the gear out: bright pixels in a disc around the centre, grown
    L = lum(gear)
    face_ref = np.median(L[disc(h, w, cx, cy, 30) & ~disc(h, w, cx, cy, 22) & (alpha > 250)])
    # the gear is the lightest thing on the face: a clear step above the face colour.
    # Its centre is the face's centre (the crop's own centre is off by the drop shadow).
    bright = L > face_ref + 25
    fx, fy = cx, cy
    mask = disc(h, w, fx, fy, 14) & bright
    for _ in range(3):
        my, mx = np.nonzero(mask)
        fx, fy = mx.mean(), my.mean()
        mask = disc(h, w, fx, fy, 15) & bright
    mask = grow(mask, 3)
    face = inpaint(gear[..., :3], mask)
    base = np.dstack([face, alpha])

    # --- lift the lock glyph: bright pixels inside its inner face disc, soft alpha
    lh, lw = lock.shape[:2]
    lcx, lcy = (lw - 1) / 2, (lh - 1) / 2
    LL = lum(lock)
    lface = np.median(LL[disc(lh, lw, lcx, lcy, 32) & ~disc(lh, lw, lcx, lcy, 26)])
    region = disc(lh, lw, lcx, lcy, 24)
    glyph = np.clip((LL - lface - 18) / 40, 0, 1) * region
    ys, xs = np.nonzero(glyph > 0.5)
    gx0, gx1, gy0, gy1 = xs.min() - 3, xs.max() + 4, ys.min() - 3, ys.max() + 4
    g_rgb = lock[gy0:gy1, gx0:gx1, :3]
    g_a = glyph[gy0:gy1, gx0:gx1]
    # centre of the glyph's own bounds goes on the knob's face centre
    gh, gw = g_a.shape
    ox = int(round(fx - gw / 2 + 0.5))
    oy = int(round(fy - gh / 2 + 0.5))
    res = base.copy()
    sl = (slice(oy, oy + gh), slice(ox, ox + gw))
    a = g_a[..., None]
    res[sl][..., :3] = base[sl][..., :3] * (1 - a) + g_rgb * a
    return Image.fromarray(np.clip(res, 0, 255).astype(np.uint8), "RGBA")


def main():
    sheet = Image.new("RGBA", (CELL * len(SKINS), CELL), (0, 0, 0, 0))
    for i, (name, g, l) in enumerate(SKINS):
        im = build(name, g, l)
        assert im.width <= CELL and im.height <= CELL, im.size
        sheet.paste(im, (i * CELL, 0))
        print(name, im.size)
    sheet.save(MEDIA + "admin_knob.tga")
    if len(sys.argv) > 1:
        bg = Image.new("RGBA", sheet.size, (110, 110, 110, 255))
        bg.alpha_composite(sheet)
        bg.resize((sheet.width * 3, sheet.height * 3), Image.LANCZOS).save(sys.argv[1])


if __name__ == "__main__":
    main()
