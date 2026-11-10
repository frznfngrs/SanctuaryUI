"""Golden radiance on the console's angel: the wings light up and the light runs down the feathers.

Three steps, the middle one in Blender:

  python angel_radiance_art.py prep WORK        relief, albedo and masks cut from frame.png
  blender -b --factory-startup -P angel_radiance.py -- WORK
  python angel_radiance_art.py build WORK       angel-radiance.png
  python angel_radiance_art.py extras WORK      angel-radiance-fx.png (needs no render)

The statue is a painting, so `prep` reads a relief out of it (paint brightness as height, the
silhouette puffed up like a carving) and Blender lights that relief with gold from above and
from the wing roots. `build` lays gold on the painting itself, in proportion to the paint so
the feathers stay as sharp as they are drawn, shaded and glinting as Blender's relief says, and
lets it through in a swell that travels from each wing's root to its feather tips. The sheet is
RGB on black, drawn with ADD.

Sheet: 2048 x 2048, 5 x 5 cells of 384 px, 24 frames, looping. A cell covers frame.png
x CELL_X..+192, y CELL_Y..+192 at two texels per console texel (see AngelRadiance.lua).
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter, gaussian_filter1d, map_coordinates
from scipy.special import ndtr

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "SanctuaryUI" / "Art"

# The statue's part of frame.png that Blender sees, and how much finer it works.
REGION = (1376, 36, 1600, 204)
SS = 4

# One flipbook cell covers CELL px of frame.png from CELL_X, CELL_Y, at OUT texels per console
# texel: the light is finer than the stone it lies on, so it stays clean when the console is
# drawn large. It hangs past the console's edges, as the glow does.
CELL_X, CELL_Y, CELL, OUT = 1420, 20, 192, 2
# The client plays the sheet itself, whole frames with nothing blended between them (the light
# is shown by an aura slot, where no addon code runs), so smoothness is bought with frames:
# 64 of them, each worked at OUT and stored at TEXELS a side, 8 x 8 filling the sheet exactly.
FRAMES, COLS, SHEET, TEXELS = 64, 8, 2048, 256

# Wing outlines in frame.png px, traced generously: the statue's alpha trims the outer edge.
NEAR_WING = [(1482, 60), (1484, 56), (1496, 55), (1506, 58), (1514, 64), (1524, 70), (1534, 78),
             (1546, 88), (1553, 98), (1556, 110), (1562, 120), (1566, 134), (1572, 148), (1578, 160),
             (1584, 174), (1588, 188), (1600, 198), (1600, 204),
             # The inner edge: the innermost feather lies in the figure's shadow, dark but wing.
             (1548, 204), (1543, 195), (1537, 185), (1531, 172), (1526, 160), (1522, 148),
             (1521, 136), (1522, 122), (1508, 106), (1499, 103),
             (1487, 100), (1489, 90), (1491, 79), (1484, 72)]
# The far wing's inner edge keeps clear of the hood, which stays unlit.
FAR_WING = [(1437, 63), (1440, 57), (1452, 56), (1463, 61), (1473, 69), (1482, 75), (1484, 72),
            (1491, 79), (1489, 90), (1487, 100), (1492, 104), (1480, 107), (1470, 110), (1466, 100),
            (1463, 91), (1459, 83), (1451, 75), (1443, 70), (1438, 68)]
# Where each wing's feathers fan out from, and how far its longest feather runs.
NEAR_ROOT, NEAR_REACH = (1493, 64), 172
FAR_ROOT, FAR_REACH = (1445, 62), 62


GOLD_DEEP = np.array([1.0, 0.66, 0.22], np.float32)
GOLD = np.array([1.0, 0.80, 0.38], np.float32)
HOT = np.array([1.0, 0.94, 0.72], np.float32)
BLOOM = np.array([1.0, 0.70, 0.30], np.float32)

def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def pulse(phase, rise, fall):
    """A crest passing where phase crosses a whole number: quick to arrive, slow to drain.

    Its front is no narrower than the crest moves between two frames, so blending frames in the
    addon gives one moving front and not two ghosts.
    """
    p = (phase + rise) % 1
    return (smooth(p, 0, rise) * np.exp(-np.maximum(p - rise, 0) / fall)).astype(np.float32)


def noise2(shape, scales, seed, power=1.2):
    """Noise that tiles on both axes, evened out to 0..1."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(shape, dtype=np.float32)
    grids = np.meshgrid(*[np.fft.fftfreq(n) * n for n in shape], indexing="ij", sparse=True)
    r2 = sum((g / s) ** 2 for g, s in zip(grids, scales))
    out = np.fft.ifft2(np.fft.fft2(white) / (1 + r2) ** power).real
    return ndtr((out - out.mean()) / out.std()).astype(np.float32)


def sample(n, u, v):
    su, sv = n.shape
    return map_coordinates(n, [(u % 1) * su, (v % 1) * sv], order=1, mode="grid-wrap").astype(np.float32)


def polygon_mask(points, feather):
    """A soft mask of a frame.png polygon over REGION, at SS times the size."""
    x0, y0, x1, y1 = REGION
    w, h = (x1 - x0) * SS, (y1 - y0) * SS
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).polygon([((x - x0) * SS, (y - y0) * SS) for x, y in points], fill=255)
    return gaussian_filter(np.asarray(im, np.float32) / 255, feather * SS)


def statue():
    frame = Image.open(ART / "frame.png").convert("RGBA").crop(REGION)
    big = frame.resize((frame.width * SS, frame.height * SS), Image.BICUBIC)
    a = np.asarray(big, np.float32) / 255
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    return lum, a[..., 3]


def prep(work):
    work.mkdir(parents=True, exist_ok=True)
    lum, alpha = statue()
    solid = alpha > 0.5

    # The painter put light on what stands proud, so brightness is the fine relief. A wide blur
    # carries the big forms, a narrow one the feather ridges and the armour's edges.
    fine = gaussian_filter(lum, 0.5 * SS)
    broad = gaussian_filter(lum, 2.5 * SS)
    paint = 0.65 * fine + 0.35 * broad
    # The silhouette rounds off like stone carved in the round.
    depth = distance_transform_edt(solid) / SS
    dome = np.sqrt(1 - (1 - np.clip(depth / 9, 0, 1)) ** 2)
    height = (7.0 * paint + 5.0 * dome) * solid
    height = gaussian_filter(height, 0.35 * SS)
    np.save(work / "height.npy", height.astype(np.float32))

    # Paint with most of its own shading taken back out: stone that the new light can shade.
    albedo = np.clip(0.30 + 0.75 * lum ** 0.6, 0, 1)
    rgba = np.dstack([albedo] * 3 + [alpha])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(work / "albedo.png")
    print("prep:", height.shape, "height max", float(height.max()))


def load_pass(work, name):
    im = np.asarray(Image.open(work / f"{name}.png"), np.float32)
    im = im / (65535 if im.max() > 255 else 255)
    return im[..., :3] * im[..., 3:4]


def fan(root, reach):
    """Along (0 at the root, 1 at the longest feather's tip) and across (the angle) a wing."""
    x0, y0, x1, y1 = REGION
    w, h = (x1 - x0) * SS, (y1 - y0) * SS
    xs = x0 + (np.arange(w, dtype=np.float32) + 0.5) / SS
    ys = y0 + (np.arange(h, dtype=np.float32) + 0.5) / SS
    x, y = np.meshgrid(xs, ys)
    dx, dy = x - root[0], y - root[1]
    return np.hypot(dx, dy) / reach, np.arctan2(dy, dx) / math.pi


def build(work):
    lum, alpha = statue()
    key = load_pass(work, "key")  # gold raking down from above
    roots = load_pass(work, "roots")  # light held at the wing roots

    near = polygon_mask(NEAR_WING, 0.6) * alpha
    far = polygon_mask(FAR_WING, 0.6) * alpha
    far = far * (1 - smooth(near, 0.3, 0.8))  # the near wing lies over the far one
    wings = np.clip(near + far, 0, 1)
    inside = wings > 0.5

    s_near, a_near = fan(NEAR_ROOT, NEAR_REACH)
    s_far, a_far = fan(FAR_ROOT, FAR_REACH)
    along = np.where(near >= far, s_near, s_far)
    across = np.where(near >= far, a_near, a_far + 0.37)

    # The painting carries the detail: the light is laid on in proportion to it, so every
    # feather edge the painter drew stays as sharp as it is on the console.
    paint = np.clip(lum / np.percentile(lum[inside], 97), 0, 1.5)
    high = lum - gaussian_filter(lum, 2.5 * SS)
    ridge = np.clip(high / np.percentile(high[inside], 98.5), 0, 1.4)
    # Blender's relief only says which way the stone faces the light and where it glints.
    klum = key @ np.array([0.3, 0.6, 0.1], np.float32)
    shade = np.clip(klum / np.percentile(klum[inside], 92), 0, 1.3)
    shade = 0.5 + 0.5 * gaussian_filter(shade, 0.5 * SS)
    glint = klum - gaussian_filter(klum, 1.2 * SS)
    glint = np.clip(glint / np.percentile(glint[inside], 99.3), 0, 1.5) * ridge
    rlum = roots @ np.array([0.3, 0.6, 0.1], np.float32)
    well = np.clip(rlum / np.percentile(rlum[inside], 99), 0, 1)

    # Broad, soft streams along the feathers, and a slow phase that makes the glints twinkle.
    streaks = noise2((256, 256), (3.0, 9.0), 3)
    phase = noise2((256, 256), (40.0, 40.0), 5, 0.8)
    twinkle_at = sample(phase, across * 9.0, along * 7.0)
    # Feathers fan out by angle, so a slow noise across the fan sets each one's timing.
    lag = 0.09 * sample(noise2((256, 8), (5.0, 4.0), 9), across * 3.0, across * 0)
    stagger = 3.0 * sample(noise2((256, 8), (10.0, 4.0), 7), across * 3.0, across * 0)

    size = CELL * OUT
    # Nothing glows across the figure itself: the hood and cloak stay stone.
    figure = _cell(_down(alpha * (1 - wings)))
    air = 1 - 0.95 * smooth(gaussian_filter(figure, 1.0), 0.15, 0.6)

    frames = []
    for i in range(FRAMES):
        t = i / FRAMES
        # Two crests a loop run root to tip, the second fainter: each a quick front with the
        # light draining away behind it.
        crest = pulse(t - along - lag, 0.045, 0.20) + 0.6 * pulse(t - along - lag + 0.5, 0.045, 0.16)
        run = sample(streaks, across * 2.2, along * 1.3 - t)
        stream = smooth(run, 0.42, 0.80) * crest
        # Rivulets: beads of light running down the painted feather edges, each feather in its
        # own time.
        bead = pulse(2 * t - along * 3.0 + stagger, 0.10, 0.45)
        # Brightest where it wells up at the root, thinning toward the tips.
        source = np.exp(-along * 3.4)
        thin = 1 - 0.35 * smooth(along, 0.35, 1.0)
        light = 0.13 + 0.30 * source + (1.25 * crest + 0.45 * stream) * thin

        # The stone turned to gold...
        rgb = GOLD_DEEP[None, None] * (paint * shade * light)[..., None]
        # ...its edges catching the light as it passes...
        edge = ridge * (0.10 + 0.20 * source + (1.1 * crest + 0.5 * stream) * thin)
        rgb += GOLD[None, None] * (0.75 * edge)[..., None]
        rgb += HOT[None, None] * (0.85 * ridge * bead * (0.30 + 0.70 * crest) * thin)[..., None]
        # ...and glints on the ridges that come and go.
        twinkle = (0.5 + 0.5 * np.cos(2 * math.pi * (2 * t + twinkle_at))) ** 4
        spark = glint * (0.25 + 0.75 * twinkle) * (0.12 + 1.1 * crest * thin + 0.4 * source)
        rgb += HOT[None, None] * (0.80 * spark + 0.30 * well * paint * (0.5 + 0.5 * crest))[..., None]
        rgb *= wings[..., None]

        small = np.stack([_down(rgb[..., c]) for c in range(3)], axis=-1)
        cell = _cell(small)
        # Bloom: the wings glow into the air around them.
        halo = sum(wgt * np.stack([gaussian_filter(cell[..., c], sg * OUT) for c in range(3)], axis=-1)
                   for sg, wgt in ((1.2, 0.16), (4.0, 0.24), (13.0, 0.44)))
        cell = cell + halo * BLOOM[None, None] * air[..., None]
        # Roll off toward white instead of clipping, so the hottest light keeps its gold.
        peak = cell.max(axis=-1, keepdims=True)
        frames.append(cell * (1 - np.exp(-1.5 * peak)) / np.maximum(peak, 1e-4))

    frames = np.stack(frames)
    # Fade to nothing at the cell's edges so the quad never shows.
    ramp = np.minimum(np.arange(size), size - 1 - np.arange(size)).astype(np.float32)
    frames *= smooth(np.minimum.outer(ramp, ramp), 0, 10 * OUT)[None, ..., None]
    frames = np.clip(frames, 0, 1)

    sheet = np.zeros((SHEET, SHEET, 3), np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, COLS)
        small = np.stack([np.asarray(Image.fromarray(np.ascontiguousarray(f[..., ch]), "F").resize(
            (TEXELS, TEXELS), Image.LANCZOS)) for ch in range(3)], axis=-1)
        sheet[r * TEXELS:(r + 1) * TEXELS, c * TEXELS:(c + 1) * TEXELS] = np.clip(small, 0, 1)
    # Ordered noise under the 8-bit step: the wide glow is too smooth to survive banding.
    rng = np.random.default_rng(1)
    dither = (rng.random(sheet.shape[:2], dtype=np.float32) - 0.5)[..., None]
    out = ART / "angel-radiance.png"
    Image.fromarray(np.clip(sheet * 255 + 0.5 + dither * (sheet > 0), 0, 255).astype(np.uint8), "RGB").save(out, optimize=True)
    print("wrote", out, sheet.shape, "peak", float(frames.max()), "mean", float(frames.mean()))
    np.save(work / "frames.npy", frames.astype(np.float16))


def extras(work=None):
    """angel-radiance-fx.png (512 x 256, luminance, drawn with ADD and tinted by the addon).

    Left 256: the glow behind the statue, soft with a few long rays in it. Right 256: the shaft
    of light that lands on the wings when the effect arrives, its foot at the bottom.
    """
    n = 256
    ax = (np.arange(n, dtype=np.float32) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(ax, ax)
    r = np.hypot(x, y)
    th = np.arctan2(y, x) / (2 * math.pi)
    glow = 0.55 * np.exp(-(r / 0.34) ** 2) + 0.45 * np.exp(-(r / 0.62) ** 1.6)
    spokes = noise2((1024, 8), (7.0, 4.0), 21)[:, 0]
    fine = noise2((1024, 8), (2.0, 4.0), 22)[:, 0]
    at = ((th % 1) * 1024).astype(int) % 1024
    rays = smooth(spokes[at], 0.5, 0.95) * (0.6 + 0.4 * fine[at]) * np.exp(-r / 0.55) * smooth(r, 0.05, 0.3)
    halo = (0.75 * glow + 0.55 * rays) * smooth(1 - r, 0, 0.35)
    halo = gaussian_filter(halo, 1.0)

    v = (np.arange(n, dtype=np.float32) + 0.5) / n  # 0 at the top
    lines = noise2((256, 8), (3.0, 4.0), 23)[:, 0]
    across = 0.5 * np.exp(-(ax / 0.42) ** 2) + 0.8 * np.exp(-(ax / 0.10) ** 2) * (0.7 + 0.3 * lines)
    down = smooth(v, 0.02, 0.55) * (1 - smooth(v, 0.80, 1.0))
    beam = np.outer(down, across) * smooth(1 - np.abs(ax), 0, 0.25)[None]

    sheet = np.hstack([halo / halo.max(), beam / beam.max()])
    rng = np.random.default_rng(2)
    noisy = sheet * 255 + 0.5 + (rng.random(sheet.shape, dtype=np.float32) - 0.5) * (sheet > 0)
    out = ART / "angel-radiance-fx.png"
    Image.fromarray(np.dstack([np.clip(noisy, 0, 255).astype(np.uint8)] * 3), "RGB").save(out, optimize=True)
    print("wrote", out, sheet.shape)


def _cell(a):
    """REGION-sized art (at OUT) laid into a cell, cut where the cell ends."""
    size = CELL * OUT
    out = np.zeros((size, size) + a.shape[2:], np.float32)
    px, py = (REGION[0] - CELL_X) * OUT, (REGION[1] - CELL_Y) * OUT
    sx, sy = max(0, -px), max(0, -py)
    dx, dy = max(0, px), max(0, py)
    w, h = min(a.shape[1] - sx, size - dx), min(a.shape[0] - sy, size - dy)
    out[dy:dy + h, dx:dx + w] = a[sy:sy + h, sx:sx + w]
    return out


def _down(a):
    k = SS // OUT
    h, w = a.shape
    return a.reshape(h // k, k, w // k, k).mean(axis=(1, 3))


if __name__ == "__main__":
    step, work = sys.argv[1], Path(sys.argv[2])
    {"prep": prep, "build": build, "extras": extras}[step](work)
