"""Packs tools/blender/globe_freeze.py's renders into the frozen globe's art (Freeze.lua).

    python tools/build_freeze_art.py WORK [--out SanctuaryUI/Art]

WORK holds hold/hold.png, glint/glint{0,1,2}.png, grow/f###.png and shatter/f###_{0,1,2}.png.
Needs numpy, opencv and pillow.

  freeze-ice.png      512 x 512    the finished crust, full colour with alpha
  freeze-grow.png     2048 x 2048  25 cells of 409: the crust crystallising in from the rim
  freeze-shatter.png  2048 x 2048  25 cells of 409: the crust bursting off; a cell is 1.7 globes
  freeze-glint.png    1024 x 1024  four cells of 512, white with the light in alpha, for ADD:
                                   three glints (one hard light in three places) and the cracks
  freeze-liquid.png   512 x 512    the liquid frozen: a cold dark cast, rime and fracture lines
"""
import argparse
import math
import os

import cv2
import numpy as np
from PIL import Image

CELL, COLS, SHEET, FRAMES = 409, 5, 2048, 25
SHATTER_SUBS = 3
HALF_SHATTER = 1.7  # globe_freeze.py
WINDOW = 0.55  # how much of the crust's cover the middle of the globe gives up


def read(path):
    im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("missing " + path)
    im = im.astype(np.float32) / (65535 if im.dtype == np.uint16 else 255)
    return im[..., [2, 1, 0, 3]]


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def grade(im, window=1.0, half=1.0):
    """Render -> what the game draws. The render is paler and more solid than ice over a red
    globe wants: deepen the body toward blue, and thin the alpha of the plain faces so the
    liquid shows through them, while edges, rime and highlights keep their cover.

    window: the middle of the globe is thinned further, to a window the liquid's level and the
    health number read through; the cover climbs back to full at the rim. half is the view's
    half-width in globes."""
    rgb, a = im[..., :3], im[..., 3]
    lum = rgb.mean(axis=2)
    spec = smooth(lum, 0.80, 0.98)
    body = rgb ** np.array([1.55, 1.25, 1.02], np.float32)
    rgb = body * (1 - spec[..., None]) + rgb * spec[..., None]
    thin = a * (0.50 + 0.50 * smooth(a, 0.52, 0.9))
    if window > 0:
        r = disc(a.shape[0], half)
        clear = 1 - window * WINDOW * (1 - smooth(r, 0.34, 0.92))
        thin = thin * clear
    a = np.maximum(thin, a * spec * 0.9)
    return np.dstack([rgb, a])


def resize(im, size):
    """Area resize on premultiplied colour, so clear pixels don't darken the edges."""
    pm = np.dstack([im[..., :3] * im[..., 3:], im[..., 3]])
    pm = cv2.resize(pm, (size, size), interpolation=cv2.INTER_AREA)
    a = pm[..., 3]
    rgb = pm[..., :3] / np.maximum(a, 1e-4)[..., None]
    return np.dstack([np.clip(rgb, 0, 1), a])


def bleed(im):
    """Colour under clear pixels, from their neighbours: the game filters straight alpha, and
    black there would rim every shard in grey."""
    a = im[..., 3]
    rgb = im[..., :3].copy()
    pm = rgb * a[..., None]
    filled = a >= 0.02
    for sigma in (1.5, 4, 12):
        blur_a = cv2.GaussianBlur(a, (0, 0), sigma)
        blur = cv2.GaussianBlur(pm, (0, 0), sigma) / np.maximum(blur_a, 1e-4)[..., None]
        todo = ~filled & (blur_a > 1e-3)
        rgb[todo] = blur[todo]
        filled |= todo
    return np.dstack([np.clip(rgb, 0, 1), a])


def save(im, path):
    Image.fromarray((np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)
    print(f"{os.path.basename(path):22s} {im.shape[1]}x{im.shape[0]}  {im.shape[0] * im.shape[1] * 4 / 1048576:.0f} MB in video memory")


def disc(n, half=1.0):
    g = (np.arange(n, dtype=np.float32) + 0.5) / n * 2 - 1
    xx, yy = np.meshgrid(g * half, g * half)
    return np.hypot(xx, yy)


def pack(frames):
    sheet = np.zeros((SHEET, SHEET, 4), np.float32)
    for i, f in enumerate(frames):
        y, x = divmod(i, COLS)
        sheet[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = f
    return sheet


def ice(work):
    im = grade(read(os.path.join(work, "hold", "hold.png")))
    return im


def grow(work):
    frames = []
    for i in range(FRAMES):
        im = grade(read(os.path.join(work, "grow", f"f{i:03d}.png")))
        frames.append(bleed(resize(im, CELL)))
    return pack(frames)


def shatter(work):
    r = disc(CELL)
    edge = 1 - smooth(r, 0.80, 0.99)
    frames = []
    for i in range(FRAMES):
        acc = 0
        for k in range(SHATTER_SUBS):
            # The first frames sit where the still did, so they keep its window; then the
            # pieces have moved and are simply ice.
            im = grade(read(os.path.join(work, "shatter", f"f{i:03d}_{k}.png")), max(0.0, 1 - i / 3), HALF_SHATTER)
            acc = acc + np.dstack([im[..., :3] * im[..., 3:], im[..., 3]])
        acc /= SHATTER_SUBS
        im = np.dstack([acc[..., :3] / np.maximum(acc[..., 3:], 1e-4), acc[..., 3]])
        im = resize(im, CELL)
        t = i / (FRAMES - 1)
        im[..., 3] *= edge * (1 - smooth(t, 0.5, 1.0))
        frames.append(bleed(im))
    return pack(frames)


def glints(work, hold):
    """Each glint is what one small hard light adds: only the tops of its highlights, so three
    of them faded in turn read as light moving over the facets. The fourth cell is the cracks
    between the plates, for the flash as the crust locks and as it breaks."""
    cells = []
    r = disc(512)
    inside = 1 - smooth(r, 0.94, 1.0)
    for i in range(3):
        im = resize(read(os.path.join(work, "glint", f"glint{i}.png")), 512)
        lum = im[..., :3].mean(axis=2) * im[..., 3]
        lo, hi = np.percentile(lum[r < 0.95], 93), np.percentile(lum[r < 0.95], 99.9)
        g = np.clip((lum - lo) / (hi - lo), 0, 1) ** 1.3
        g = np.clip(g + cv2.GaussianBlur(g, (0, 0), 3.0) * 0.6, 0, 1)
        cells.append(g * inside)
    a = resize(hold, 512)[..., 3]
    # Cracks: thin gaps in the cover, between covered neighbours.
    closed = cv2.morphologyEx(a, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    cracks = np.clip((closed - a) * 3.0, 0, 1)
    cracks = np.clip(cracks + cv2.GaussianBlur(cracks, (0, 0), 2.5) * 0.9, 0, 1) * inside
    cells.append(cracks)
    sheet = np.zeros((1024, 1024, 4), np.float32)
    sheet[..., :3] = 1
    for i, c in enumerate(cells):
        y, x = divmod(i, 2)
        sheet[y * 512:(y + 1) * 512, x * 512:(x + 1) * 512, 3] = c
    return sheet


def fractal(n, rng, octaves=6, base=4):
    out = np.zeros((n, n), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        k = base * 2 ** o
        g = rng.random((k + 1, k + 1)).astype(np.float32)
        out += cv2.resize(g, (n, n), interpolation=cv2.INTER_CUBIC) * amp
        total += amp
        amp *= 0.55
    return out / total


def liquid():
    """The liquid frozen through, drawn over the stopped liquid at its level. Mostly a cold dark
    cast, so red goes to a deep frozen crimson rather than pink; then rime clouding in from the
    glass, and a few long fractures with fine feathering."""
    n = 512
    rng = np.random.default_rng(5)
    r = disc(n)
    cloud = fractal(n, rng)
    fine = fractal(n, rng, octaves=5, base=24)
    rime = smooth(cloud * 0.75 + smooth(r, 0.35, 1.0) * 0.6, 0.62, 1.02) * (0.55 + 0.45 * fine)
    lines = np.zeros((n, n), np.float32)
    for _ in range(9):
        p = rng.uniform(0.15, 0.85, 2) * n
        ang = rng.uniform(0, math.pi)
        for side in (1, -1):
            q = p.copy()
            a = ang
            for _ in range(rng.integers(3, 7)):
                step = rng.uniform(0.05, 0.16) * n
                a += rng.normal(0, 0.28)
                q2 = q + side * step * np.array([math.cos(a), math.sin(a)])
                cv2.line(lines, tuple(int(v) for v in q), tuple(int(v) for v in q2), float(rng.uniform(0.5, 1.0)), 1, cv2.LINE_AA)
                if rng.uniform() < 0.5:  # a feather off the fracture
                    b = a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1)
                    q3 = q2 + rng.uniform(0.02, 0.07) * n * np.array([math.cos(b), math.sin(b)])
                    cv2.line(lines, tuple(int(v) for v in q2), tuple(int(v) for v in q3), float(rng.uniform(0.25, 0.6)), 1, cv2.LINE_AA)
                q = q2
    lines = np.clip(cv2.GaussianBlur(lines, (0, 0), 0.7) * 1.3 + cv2.GaussianBlur(lines, (0, 0), 4) * 0.5, 0, 1)
    dark = np.array([0.03, 0.07, 0.17], np.float32)
    white = np.array([0.74, 0.90, 1.0], np.float32)
    a_dark = 0.30 + 0.12 * cloud
    a_white = np.clip(rime * 0.5 + lines * 0.5, 0, 0.9)
    a = a_dark + a_white * (1 - a_dark)
    rgb = (dark[None, None] * (a_dark * (1 - a_white))[..., None] + white[None, None] * a_white[..., None]) / a[..., None]
    return np.dstack([rgb, a])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("work")
    p.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "SanctuaryUI", "Art"))
    a = p.parse_args()
    hold = ice(a.work)
    save(bleed(resize(hold, 512)), os.path.join(a.out, "freeze-ice.png"))
    save(glints(a.work, hold), os.path.join(a.out, "freeze-glint.png"))
    save(liquid(), os.path.join(a.out, "freeze-liquid.png"))
    save(grow(a.work), os.path.join(a.out, "freeze-grow.png"))
    save(shatter(a.work), os.path.join(a.out, "freeze-shatter.png"))


if __name__ == "__main__":
    main()
