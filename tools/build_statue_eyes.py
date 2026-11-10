"""Wisps of light from the console statues' eyes (SanctuaryUI/StatueEyes.lua).

  python tools/build_statue_eyes.py [OUT_DIR]

Writes, for the angel and the gargoyle, two 512 x 512 flipbooks of 8 x 8 cells (64 frames, a
seamless loop): eyes-<statue>-body.png, the wisp, which the addon tints, and
eyes-<statue>-core.png, its hot centre, which the addon tints paler. Both are drawn with ADD.

The client plays these itself (a FlipBook animation: whole frames, no blending between them),
so the motion has to be smooth at one frame a step. A cell covers CELL px of frame.png from the
statue's corner below, at twice the console's texel density.

Needs numpy, scipy and pillow.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

CELL = 32  # frame.png px a cell covers
OUT = 2  # texels per frame.png px
SS = 4  # supersampling
GRID = 8
FRAMES = GRID * GRID

# corner: the cell's top left in frame.png. eyes: (x, y, size, phase). lean: where the wisps
# go, as degrees from straight up, positive to the right. curl bends them further as they rise.
STATUES = {
    # Hooded, facing left: the eyes are in the hood's shadow and the wisps slip out under its
    # brim, forward and up.
    "angel": {
        "corner": (1410, 90),
        "eyes": [(1436.4, 112.6, 1.0, 0.0), (1431.9, 113.5, 0.8, 0.37)],
        "lean": -30, "curl": -10, "length": 22,
    },
    # In profile, facing right: one eye, the wisp streaming back over the brow.
    "gargoyle": {
        "corner": (170, 102),
        "eyes": [(196.6, 126.2, 1.15, 0.0)],
        "lean": -38, "curl": -14, "length": 23,
    },
}


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def tile_noise(rng, size, sigma):
    """Noise that tiles both ways, 0..1."""
    field = gaussian_filter(rng.standard_normal((size, size)), sigma, mode="wrap")
    field -= field.min()
    return field / field.max()


def sample(noise, u, v):
    """Bilinear lookup with wrapping; u, v in tiles."""
    size = noise.shape[0]
    x, y = (u % 1) * size, (v % 1) * size
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    x0 %= size
    y0 %= size
    x1, y1 = (x0 + 1) % size, (y0 + 1) % size
    return ((noise[y0, x0] * (1 - fx) + noise[y0, x1] * fx) * (1 - fy)
            + (noise[y1, x0] * (1 - fx) + noise[y1, x1] * fx) * fy)


# Three strands to a wisp: (sway, wavelength in px, waves a loop, phase, width, weight).
STRANDS = [
    (1.00, 15.0, 1, 0.00, 1.70, 1.00),
    (0.75, 10.0, 2, 0.41, 1.20, 0.65),
    (1.35, 21.0, 1, 0.68, 1.00, 0.50),
]


def wisp(px, py, eye, spec, t, noise):
    """One eye's wisp and its hot centre at loop time t (0..1), on the px grid."""
    ex, ey, size, phase = eye
    length = spec["length"] * size
    dx, dy = px - ex, py - ey
    r2 = dx * dx + dy * dy

    # The wisp's own axes: s along it, n across. The lean grows with the distance, so it bends.
    reach = np.sqrt(r2)
    angle = np.radians(spec["lean"] + spec["curl"] * np.clip(reach / length, 0, 1.2))
    ax, ay = np.sin(angle), -np.cos(angle)
    s = dx * ax + dy * ay
    n = dx * ay - dy * ax
    along = s / length

    rise = smooth(s, -0.3, 1.6)
    fade = np.clip(1 - along, 0, 1) ** 1.4
    body = np.zeros_like(px)
    for sway, wave, waves, at, width, weight in STRANDS:
        tt = t + phase
        centre = sway * 0.20 * length * np.clip(along, 0, 1.2) ** 1.25 * np.sin(
            2 * np.pi * (s / wave - waves * tt + at))
        w = size * (width * (1 - 0.55 * np.clip(along, 0, 1)) + 0.25)
        strand = np.exp(-((n - centre) / w) ** 2)
        # Breaks and thickenings carried up the strand.
        grain = sample(noise, n / 9.0 + at, s / 13.0 - waves * tt + at)
        strand *= 0.50 + 1.0 * smooth(grain, 0.30, 0.75)
        body += weight * strand
    body *= rise * fade

    flicker = 1 + 0.10 * np.sin(2 * np.pi * (3 * t + phase)) + 0.05 * np.sin(2 * np.pi * (5 * t + 2 * phase))
    ember = np.exp(-r2 / (1.25 * size) ** 2)
    halo = np.exp(-r2 / (4.2 * size) ** 2)
    wide = 0.85 * body + flicker * (0.9 * ember + 0.30 * halo)
    hot = 0.55 * body ** 2 + flicker * np.exp(-r2 / (0.85 * size) ** 2)
    return size * wide, size * hot


def tone(x):
    return 1 - np.exp(-1.6 * x)


def build(name, spec, out_dir):
    rng = np.random.default_rng(sum(map(ord, name)))
    noise = tile_noise(rng, 256, 9)
    side = CELL * OUT * SS
    step = 1.0 / (OUT * SS)
    xs = spec["corner"][0] + (np.arange(side) + 0.5) * step
    ys = spec["corner"][1] + (np.arange(side) + 0.5) * step
    px, py = np.meshgrid(xs, ys)

    # Nothing may reach a cell's edge: the neighbouring frame starts there.
    u = (np.arange(side) + 0.5) / side
    edge = smooth(np.minimum(u, 1 - u), 0.0, 0.10)
    window = edge[None, :] * edge[:, None]

    cell = CELL * OUT
    sheets = {"body": np.zeros((GRID * cell, GRID * cell)), "core": np.zeros((GRID * cell, GRID * cell))}
    for i in range(FRAMES):
        t = i / FRAMES
        wide = np.zeros_like(px)
        hot = np.zeros_like(px)
        for eye in spec["eyes"]:
            a, b = wisp(px, py, eye, spec, t, noise)
            wide += a
            hot += b
        row, col = divmod(i, GRID)
        for key, image in (("body", wide), ("core", hot)):
            image = tone(image) * window
            image = image.reshape(cell, SS, cell, SS).mean(axis=(1, 3))
            sheets[key][row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = image

    for key, sheet in sheets.items():
        dither = (rng.random(sheet.shape) - 0.5) / 255
        grey = np.clip(sheet + dither * (sheet > 0.004), 0, 1)
        im = Image.fromarray((grey * 255 + 0.5).astype(np.uint8), "L").convert("RGB")
        path = out_dir / f"eyes-{name}-{key}.png"
        im.save(path, optimize=True)
        print(path, im.size, f"peak {sheet.max():.2f}")


def main():
    root = Path(__file__).resolve().parent.parent
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "SanctuaryUI" / "Art"
    for name, spec in STATUES.items():
        build(name, spec, out_dir)


if __name__ == "__main__":
    main()
