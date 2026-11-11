#!/usr/bin/env python3
"""Build the minimap art (SanctuaryUI/Map.lua, MapPins.lua, MapOverlay.lua).

  blender -b --factory-startup -P tools/blender/minimap_ring.py -- <work> [samples]
  python3 tools/build_minimap_art.py <work>

Needs Pillow and numpy. Writes into SanctuaryUI/Art:
  map-ring       the Scrying globe: the rendered ring with glass painted inside radius 100/128
  map-parchment  Diablo III's torn minimap sheet (art-src/hud/2DUIMiniMap.png) as a dark edge
  map-mask-torn  the same sheet's outline, for the minimap's own mask
  map-mask-fade  a round mask that feathers out to nothing
  map-mask-round a plain round mask
  map-pins       8 x 2 cells of 64: see PINS in MapPins.lua for the order
  map-plaque     the name plate under the globe
Sizes and cell order are the contract with the Lua.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SanctuaryUI" / "Art"
SHEET = ROOT / "art-src" / "hud" / "2DUIMiniMap.png"


def polar(size):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    dx, dy = (x - c) / c, (c - y) / c
    return np.hypot(dx, dy), dx, dy


def rgba(rgb, alpha):
    a = np.zeros(alpha.shape + (4,), np.float32)
    a[..., :3] = rgb
    a[..., 3] = alpha.clip(0, 1) * 255
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def ring(work):
    im = Image.open(work / "ring.png").convert("RGBA")
    size = im.width
    r, dx, dy = polar(size)
    R = 100 / 128
    q = (r / R).clip(0, 1)
    inside = ((R + 0.004 - r) / 0.008).clip(0, 1)
    # Glass over the map: clear in the middle, the ring's shadow at the rim, a window light
    # up and left as the health globe has.
    shadow = 0.70 * q ** 5
    hx, hy = dx / R + 0.36, dy / R - 0.52
    spot = np.exp(-((hx / 0.46) ** 2 + (hy / 0.17) ** 2)) * 0.20
    lift = ((dx - dy) / R * 0.5 + 0.5).clip(0, 1) * q ** 3 * 0.10   # room light, lower right
    light = spot + lift
    a = (shadow + light).clip(0, 1)
    col = np.zeros((size, size, 3), np.float32)
    k = (light / np.maximum(a, 1e-4))[..., None]
    col[:] = np.array([4, 5, 8], np.float32) * (1 - k) + np.array([226, 232, 244], np.float32) * k
    glass = rgba(col, a * inside)
    glass.alpha_composite(im)
    glass.save(OUT / "map-ring.png")


def parchment():
    size = 512
    sheet = Image.open(SHEET).convert("RGBA").crop((0, 0, 360, 360)).resize((size, size), Image.LANCZOS)
    sa = np.asarray(sheet.getchannel("A"), np.float32)
    on = sa > 6
    rows = np.maximum.accumulate(on, 1) & np.maximum.accumulate(on[:, ::-1], 1)[:, ::-1]
    cols = np.maximum.accumulate(on, 0) & np.maximum.accumulate(on[::-1], 0)[::-1]
    shape = Image.fromarray(((rows & cols) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    sh = np.asarray(shape, np.float32) / 255
    mask = np.zeros((size, size, 4), np.uint8)
    mask[..., :3] = (sh * 255)[..., None]
    mask[..., 3] = sh * 255
    Image.fromarray(mask, "RGBA").save(OUT / "map-mask-torn.png")
    # The sheet is heaviest at its border: a burnt edge over the map, and a pale line on the tear.
    burn = rgba(np.array([16, 11, 6], np.float32), (sa * 2.8 / 255) * sh)
    edge = np.asarray(shape.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(1.1)), np.float32) / 255
    burn.alpha_composite(rgba(np.array([198, 172, 122], np.float32), (edge * 2.2).clip(0, 0.8)))
    burn.save(OUT / "map-parchment.png")


def fade():
    size = 256
    r, _, _ = polar(size)
    t = ((r - 0.56) / (0.98 - 0.56)).clip(0, 1)
    a = 1 - t * t * (3 - 2 * t)
    m = np.zeros((size, size, 4), np.uint8)
    m[..., :3] = (a * 255)[..., None]
    m[..., 3] = a * 255
    Image.fromarray(m, "RGBA").save(OUT / "map-mask-fade.png")


def round_mask():
    size = 256
    r, _, _ = polar(size)
    a = ((0.985 - r) / 0.012).clip(0, 1)
    m = np.zeros((size, size, 4), np.uint8)
    m[..., :3] = (a * 255)[..., None]
    m[..., 3] = a * 255
    Image.fromarray(m, "RGBA").save(OUT / "map-mask-round.png")


CELL, SS = 64, 4


def cell(draw):
    """One 64 px cell drawn at 4x: white shapes with a dark edge, so the Lua can tint them."""
    big = Image.new("RGBA", (CELL * SS, CELL * SS), (0, 0, 0, 0))
    draw(ImageDraw.Draw(big), CELL * SS)
    return big.resize((CELL, CELL), Image.LANCZOS)


W, K = (255, 255, 255, 255), (10, 8, 6, 255)


def pins():
    def arrow(d, s):       # the player: points up
        c = s / 2
        d.polygon([(c, s * .10), (s * .80, s * .86), (c, s * .66), (s * .20, s * .86)], fill=W, outline=K, width=s // 28)

    def wedge(d, s):       # something off the map: points up, toward it
        c = s / 2
        d.polygon([(c, s * .12), (s * .82, s * .74), (c, s * .58), (s * .18, s * .74)], fill=W, outline=K, width=s // 24)

    def pip(d, s):
        d.ellipse((s * .18, s * .18, s * .82, s * .82), fill=W, outline=K, width=s // 18)
        d.ellipse((s * .32, s * .26, s * .52, s * .44), fill=(255, 255, 255, 255))

    def diamond(d, s):
        c = s / 2
        d.polygon([(c, s * .08), (s * .80, c), (c, s * .92), (s * .20, c)], fill=W, outline=K, width=s // 22)

    def dot(d, s):
        d.ellipse((s * .30, s * .30, s * .70, s * .70), fill=W)

    def corpse(d, s):      # a grave marker
        d.rounded_rectangle((s * .26, s * .14, s * .74, s * .88), s * .22, fill=W, outline=K, width=s // 22)
        d.rectangle((s * .26, s * .52, s * .74, s * .88), fill=W)
        d.line([(s * .26, s * .52), (s * .26, s * .88), (s * .74, s * .88), (s * .74, s * .52)], fill=K, width=s // 22)
        d.line([(s * .50, s * .28), (s * .50, s * .64)], fill=K, width=s // 14)
        d.line([(s * .38, s * .40), (s * .62, s * .40)], fill=K, width=s // 14)

    def mail(d, s):
        w = s // 14
        d.rectangle((s * .16, s * .28, s * .84, s * .72), outline=W, width=w)
        d.line([(s * .16, s * .28), (s * .5, s * .56), (s * .84, s * .28)], fill=W, width=w)

    def track(d, s):
        w = s // 13
        d.ellipse((s * .18, s * .14, s * .62, s * .58), outline=W, width=w)
        d.line([(s * .56, s * .54), (s * .84, s * .84)], fill=W, width=int(w * 1.6))

    def calendar(d, s):
        w = s // 14
        d.rectangle((s * .20, s * .22, s * .80, s * .82), outline=W, width=w)
        d.line([(s * .20, s * .40), (s * .80, s * .40)], fill=W, width=w)
        for x in (.36, .64):
            d.line([(s * x, s * .13), (s * x, s * .29)], fill=W, width=w)

    def more(d, s):
        for x in (.24, .5, .76):
            d.ellipse((s * (x - .075), s * .425, s * (x + .075), s * .575), fill=W)

    def flag(d, s):        # a waypoint the player set
        w = s // 14
        d.line([(s * .30, s * .12), (s * .30, s * .90)], fill=K, width=w + s // 28)
        d.polygon([(s * .30, s * .14), (s * .82, s * .30), (s * .30, s * .48)], fill=W, outline=K, width=s // 28)
        d.line([(s * .30, s * .12), (s * .30, s * .90)], fill=W, width=w)

    def north(d, s):       # a small N for the borderless style
        w = s // 11
        d.line([(s * .30, s * .78), (s * .30, s * .22), (s * .70, s * .78), (s * .70, s * .22)], fill=W, width=w, joint="curve")

    order = [arrow, wedge, pip, diamond, dot, corpse, mail, track, calendar, more, flag, north]
    sheet = Image.new("RGBA", (CELL * 8, CELL * 2), (0, 0, 0, 0))
    for i, fn in enumerate(order):
        sheet.alpha_composite(cell(fn), ((i % 8) * CELL, (i // 8) * CELL))
    sheet.save(OUT / "map-pins.png")


def plaque():
    w, h, ss = 256, 64, 3
    big = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((3 * ss, 3 * ss, (w - 3) * ss, (h - 3) * ss), 7 * ss, fill=(20, 18, 17, 236), outline=(104, 94, 78, 255), width=2 * ss)
    d.rounded_rectangle((6 * ss, 6 * ss, (w - 6) * ss, (h - 6) * ss), 5 * ss, outline=(6, 6, 6, 255), width=ss)
    im = big.resize((w, h), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    rng = np.random.default_rng(5)
    grain = np.asarray(Image.fromarray((rng.random((h // 2, w // 2)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
    a[..., :3] *= (0.86 + 0.28 * grain)[..., None]
    a[..., :3] *= np.linspace(1.12, 0.84, h, dtype=np.float32)[:, None, None]   # lit from above
    Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA").save(OUT / "map-plaque.png")


def main():
    work = Path(sys.argv[1])
    ring(work)
    parchment()
    fade()
    round_mask()
    pins()
    plaque()


main()
