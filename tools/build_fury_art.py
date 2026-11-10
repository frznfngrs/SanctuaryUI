"""Art for the Fury globe aura (SanctuaryUI/GlobeAura.lua BUILD.fury / DRAW.fury).

  python tools/build_fury_art.py [OUT_DIR]

gargoyle-fury.png   2048 x 1024, 8 x 4 cells of 256 px. Rows 0-1: 16 frames of rage light on
                    the console's gargoyle, a looping heartbeat (lub-dub) of heat running out
                    from its chest over the stone. Rows 2-3: the same 16 frames' hot parts (the
                    carved edges, the maw). Luminance; the addon tints the two and draws them
                    with ADD, crossfading frames. A cell covers CELL px of frame.png from
                    CORNER, so it has to sit texel for texel on the statue.
gargoyle-horns.png  512 x 512 over the same cell: the horns' own paint, brightened, with their
                    shape in the alpha. The addon lays it on with normal blending in a deep
                    colour, so the horns turn that colour instead of only being lit.
fury-breath.png     1024 x 512, 8 x 4 cells of 128 px: fire roaring from the maw, 16 looping
                    frames (rows 0-1) and their hot core (rows 2-3). Luminance, tinted, ADD. A
                    cell covers BREATH_CELL px of frame.png from BREATH_CORNER.
fury-vortex.png     512 x 512, luminance: a whirlpool's arms, for the addon to spin inside the
                    globe's liquid.

The gargoyle's light is laid on in proportion to the painting's own brightness, so the carved
edges stay as crisp as they are painted. Needs numpy, scipy and pillow.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ROOT = Path(__file__).resolve().parent.parent
FRAME = ROOT / "SanctuaryUI" / "Art" / "frame.png"

CORNER, CELL = (28, 12), 192  # frame.png px
TEXELS = 256
SS = 3  # worked at this many times TEXELS
FRAMES, COLS = 16, 8

HEART = (168, 152)  # the chest: where each beat starts
HEAD = (190, 124)
MAW = (203.5, 143.5)
REACH = 150.0  # px a beat travels

# The horns as centrelines with half widths, frame.png px: the great ram's horn from tip to
# brow, and the tip of the far one showing behind it.
HORNS = [
    [(97, 58, 1.5), (106, 65, 2.6), (118, 69, 3.6), (130, 71, 4.6), (142, 72.5, 5.6), (153, 75, 7.0),
     (162, 82, 8.6), (170, 93, 10.5), (176, 104, 11.0), (181, 113, 9.5)],
    [(140, 62, 1.2), (152, 58.5, 2.0), (162, 59.5, 2.4), (166, 64, 2.0)],
]

# The fire: from the maw, out over the glass and a little down, under the globe's numbers.
BREATH_CORNER, BREATH_CELL, BREATH_TEXELS = (196, 108), 72, 128
BREATH_FROM, BREATH_ANGLE, BREATH_LENGTH = (204.0, 143.5), 11.0, 60.0


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def pulse(phase, rise, fall):
    """A beat's front passing: quick to arrive, slower to drain. phase wraps at 1."""
    p = phase % 1.0
    return np.where(p < rise, smooth(p, 0, rise), np.exp(-(p - rise) / fall))


def statue():
    """The gargoyle's paint in the cell at working size: luminance, alpha."""
    im = Image.open(FRAME).convert("RGBA")
    x0, y0 = CORNER
    side = TEXELS * SS
    crop = im.crop((x0, y0, x0 + CELL, y0 + CELL)).resize((side, side), Image.LANCZOS)
    a = np.asarray(crop, dtype=np.float32) / 255
    lum = a[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    return lum, a[..., 3]


def horn_mask(px, py):
    """1 on the horns, feathered over a px at their edges."""
    best = np.full(px.shape, 1e9, np.float32)
    for horn in HORNS:
        for (x0, y0, r0), (x1, y1, r1) in zip(horn, horn[1:]):
            dx, dy = x1 - x0, y1 - y0
            t = np.clip(((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy), 0, 1)
            d = np.hypot(px - (x0 + t * dx), py - (y0 + t * dy)) - (r0 + t * (r1 - r0))
            best = np.minimum(best, d)
    return 1 - smooth(best, -0.8, 0.8)


def horns(out_dir):
    im = Image.open(FRAME).convert("RGBA")
    n = 512
    crop = im.crop((CORNER[0], CORNER[1], CORNER[0] + CELL, CORNER[1] + CELL)).resize((n, n), Image.LANCZOS)
    a = np.asarray(crop, dtype=np.float32) / 255
    lum = a[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    xs = CORNER[0] + (np.arange(n) + 0.5) * CELL / n
    ys = CORNER[1] + (np.arange(n) + 0.5) * CELL / n
    px, py = np.meshgrid(xs, ys)
    mask = horn_mask(px, py) * a[..., 3]
    # The paint's own shading, lifted so a deep colour still shows its segments and cracks.
    shade = np.clip(0.22 + 1.5 * lum, 0, 1)
    rgba = np.dstack([shade, shade, shade, mask])
    path = out_dir / "gargoyle-horns.png"
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)
    print(path, (n, n))


def breath(out_dir):
    n = BREATH_TEXELS * SS
    k = n / BREATH_CELL
    xs = BREATH_CORNER[0] + (np.arange(n) + 0.5) / k
    ys = BREATH_CORNER[1] + (np.arange(n) + 0.5) / k
    px, py = np.meshgrid(xs, ys)
    ang = math.radians(BREATH_ANGLE)
    dx, dy = px - BREATH_FROM[0], py - BREATH_FROM[1]
    s = dx * math.cos(ang) + dy * math.sin(ang)
    across = -dx * math.sin(ang) + dy * math.cos(ang)
    along = s / BREATH_LENGTH
    width = 2.4 + 0.36 * np.clip(s, 0, None)
    v = across / width

    rng = np.random.default_rng(23)
    def tile(sigma):
        f = gaussian_filter(rng.standard_normal((256, 256)), sigma, mode="wrap")
        return (f - f.min()) / (f.max() - f.min())
    coarse, fine = tile(7), tile(3)
    def look(noise, a, b):
        x, y = (a % 1) * 256, (b % 1) * 256
        x0, y0 = np.floor(x).astype(int) % 256, np.floor(y).astype(int) % 256
        fx, fy = x - np.floor(x), y - np.floor(y)
        x1, y1 = (x0 + 1) % 256, (y0 + 1) % 256
        return ((noise[y0, x0] * (1 - fx) + noise[y0, x1] * fx) * (1 - fy)
                + (noise[y1, x0] * (1 - fx) + noise[y1, x1] * fx) * fy)

    u = (np.arange(n) + 0.5) / n
    edge = smooth(np.minimum(u, 1 - u), 0.0, 0.07)
    window = edge[None, :] * edge[:, None]
    profile = np.exp(-(v * 1.15) ** 2)
    start = smooth(s, -0.5, 2.5)

    sheet = np.zeros((4 * BREATH_TEXELS, COLS * BREATH_TEXELS), np.float32)
    for i in range(FRAMES):
        t = i / FRAMES
        # Tongues of flame carried out along the jet (the noise slides a whole tile a loop, so
        # the loop closes), eaten away more and more toward the end, so it ends ragged.
        carry = 0.62 * look(coarse, across / 30.0 + 0.3, s / 52.0 - 2 * t) + 0.38 * look(fine, across / 15.0, s / 26.0 - 3 * t)
        eaten = (1 - carry) * (0.25 + 2.4 * np.clip(along, 0, 1.3) ** 1.4)
        flame = np.clip(profile * 1.75 - eaten, 0, 1) * start * np.clip(1 - along, 0, 1) ** 0.6
        core = np.clip(np.exp(-(v * 2.1) ** 2) * 1.7 - eaten * 1.5 - 0.9 * np.clip(along, 0, 1), 0, 1) * start
        # The glow of it in the air around the jet.
        glow = 0.22 * np.exp(-(v * 0.55) ** 2) * start * np.clip(1 - along, 0, 1) ** 1.5
        row, col = divmod(i, COLS)
        for off, image in ((0, flame + glow), (2, core)):
            image = (1 - np.exp(-1.7 * image)) * window
            image = image.reshape(BREATH_TEXELS, SS, BREATH_TEXELS, SS).mean(axis=(1, 3))
            y0, x0 = (row + off) * BREATH_TEXELS, col * BREATH_TEXELS
            sheet[y0:y0 + BREATH_TEXELS, x0:x0 + BREATH_TEXELS] = image
    save(sheet, out_dir / "fury-breath.png", rng)


def gargoyle(out_dir):
    lum, alpha = statue()
    side = TEXELS * SS
    k = side / CELL  # working texels per frame.png px
    xs = CORNER[0] + (np.arange(side) + 0.5) / k
    ys = CORNER[1] + (np.arange(side) + 0.5) / k
    px, py = np.meshgrid(xs, ys)
    # The horns take their own deep colour (gargoyle-horns.png): little of this light on them.
    off_horns = 1 - 0.85 * horn_mask(px, py)

    # The globe's ring arcs up behind the horns: no light on it. The head itself lies over the
    # glass, so the ring is only cut where it stands clear of the statue.
    ring = np.hypot(px - 243.5, py - 99)
    arc = smooth(ring, 74, 78) * (1 - smooth(ring, 94, 98)) * (1 - smooth(py, 62, 72)) * smooth(px, 154, 160)
    body = alpha * (1 - arc)
    # Strongest on the head, horns and wing, dying away into the skulls at its feet.
    head = np.hypot(px - HEAD[0], py - HEAD[1])
    near = 0.25 + 0.75 * np.exp(-(head / 78.0) ** 2)
    floor = 1 - 0.75 * smooth(py, 168, 200)

    paint = np.clip(lum * 2.4, 0, 1) ** 0.85
    ridge = np.clip((lum - gaussian_filter(lum, 2.2 * k)) * 7, 0, 1)
    ridge = ridge * smooth(lum, 0.12, 0.35)
    crack = np.clip((gaussian_filter(lum, 1.6 * k) - lum) * 9, 0, 1) * smooth(lum, 0.02, 0.10)

    along = np.hypot(px - HEART[0], py - HEART[1]) / REACH
    maw = np.exp(-(np.hypot((px - MAW[0]) / 1.5, py - MAW[1]) / 5.2) ** 2)
    throat = np.exp(-(np.hypot(px - MAW[0], py - MAW[1]) / 11.0) ** 2)

    rng = np.random.default_rng(7)
    grain = gaussian_filter(rng.standard_normal((side, side)), 5 * k)
    grain = (grain - grain.min()) / (grain.max() - grain.min())

    u = (np.arange(side) + 0.5) / side
    edge = smooth(np.minimum(u, 1 - u), 0.0, 0.06)
    window = edge[None, :] * edge[:, None]

    wide_frames, hot_frames = [], []
    for i in range(FRAMES):
        t = i / FRAMES
        # Lub-dub: two beats a loop, the second close behind the first and fainter. The front
        # is kept as wide as it travels between frames, so the addon's crossfade can't ghost.
        beat = pulse(t - along * 0.55, 0.10, 0.22) + 0.6 * pulse(t - along * 0.55 - 0.30, 0.10, 0.16)
        thin = 1 - 0.4 * smooth(along, 0.4, 1.0)
        flicker = 0.85 + 0.15 * math.sin(2 * math.pi * (3 * t)) * (0.5 + grain)
        heat = (0.13 + 1.0 * beat * thin) * flicker
        wide = paint * heat * near * floor
        # Heat held in the carved lines between the beats, flaring as one passes.
        wide += 0.55 * crack * (0.25 + 0.75 * beat * thin) * near * floor
        hot = ridge * (0.10 + 1.0 * beat * thin) * near * floor
        # The maw: a furnace behind the teeth, lighting the jaw around it.
        breath = 0.75 + 0.25 * math.sin(2 * math.pi * (2 * t + 0.2))
        wide += throat * paint * 0.9 * breath + maw * 0.55 * breath
        hot += maw * (0.5 + 0.5 * beat[int((MAW[1] - CORNER[1]) * k), int((MAW[0] - CORNER[0]) * k)]) * breath
        wide_frames.append(wide * body * off_horns)
        hot_frames.append(hot * body * (1 - 0.6 * (1 - off_horns) / 0.85))

    def cell(image):
        # A little bloom, so the light sits in the air on the stone instead of being cut out.
        image = image + 0.35 * gaussian_filter(image, 2.0 * k) * (1 - arc)
        image = (1 - np.exp(-1.5 * image)) * window
        return image.reshape(TEXELS, SS, TEXELS, SS).mean(axis=(1, 3))

    sheet = np.zeros((4 * TEXELS, COLS * TEXELS), np.float32)
    for i in range(FRAMES):
        r, c = divmod(i, COLS)
        sheet[r * TEXELS:(r + 1) * TEXELS, c * TEXELS:(c + 1) * TEXELS] = cell(wide_frames[i])
        sheet[(r + 2) * TEXELS:(r + 3) * TEXELS, c * TEXELS:(c + 1) * TEXELS] = cell(hot_frames[i])
    save(sheet, out_dir / "gargoyle-fury.png", rng)


def vortex(out_dir):
    n = 512
    ax = (np.arange(n, dtype=np.float32) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(ax, ax)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    rng = np.random.default_rng(11)
    image = np.zeros((n, n), np.float32)
    # Arms winding in to the middle, each broken along its length so the turning shows.
    for arms, wind, weight, seed in ((3, 5.2, 1.0, 0.0), (5, 7.0, 0.55, 1.7), (2, 3.6, 0.5, 4.1)):
        phase = arms * th + wind * np.log(np.maximum(r, 0.02)) * arms / 3 + seed
        arm = (0.5 + 0.5 * np.cos(phase)) ** 6
        breaks = 0.7 + 0.3 * np.cos(2 * arms * th - 9.0 * r + seed * 3)
        image += weight * arm * breaks
    noise = gaussian_filter(rng.standard_normal((n, n)), 6)
    noise = (noise - noise.min()) / (noise.max() - noise.min())
    image *= 0.6 + 0.8 * noise
    # Nothing in the eye of it or at the rim: the globe's mask finishes the edge.
    image *= smooth(r, 0.05, 0.28) * (1 - smooth(r, 0.78, 0.98))
    image = gaussian_filter(image, 1.2)
    image = 1 - np.exp(-1.3 * image)
    save(image, out_dir / "fury-vortex.png", rng)


def save(grey, path, rng):
    dither = (rng.random(grey.shape) - 0.5) / 255
    grey = np.clip(grey + dither * (grey > 0.004), 0, 1)
    im = Image.fromarray((grey * 255 + 0.5).astype(np.uint8), "L").convert("RGB")
    im.save(path, optimize=True)
    print(path, im.size, f"peak {grey.max():.2f} mean {grey.mean():.3f}")


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "SanctuaryUI" / "Art"
    gargoyle(out_dir)
    horns(out_dir)
    breath(out_dir)
    vortex(out_dir)


if __name__ == "__main__":
    main()
