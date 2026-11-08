"""Sheets and comparison for tools/blender/globe_pollution.py.

  python globe_pollution_compare.py test  WORK OUT [frame]   frame over the liquid at 60%, per kind
  python globe_pollution_compare.py sheets WORK OUT_DIR      mix and glow sheets
  python globe_pollution_compare.py still  OUT_DIR OUT.png [t]
  python globe_pollution_compare.py video  OUT_DIR OUT.mp4

Everything plays the way the client would: one sheet cell at a time, no blend between cells.
Sheets are straight alpha, as WoW's UI expects: RGB is the colour, A how much of it.
"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import globe_compare as gc  # noqa: E402

KINDS = ("poison", "disease", "curse", "magic")
CELL, COLS, FRAMES = 170, 6, 36
SHEET = 1024
FPS = 10.0
LOOP = FRAMES / FPS

# Colour ramp over the volume's lit shape: shadow, mid, high. opacity: most of the mix over the
# liquid. gamma: how quickly thin volume becomes opaque. glow: colour of the ADD layer.
LOOK = {
    "poison": dict(ramp=((0.015, 0.06, 0.008), (0.09, 0.26, 0.02), (0.34, 0.62, 0.06)), opacity=0.9, gamma=1.05, glow=(0.3, 0.8, 0.05), glow_k=0.3, spin=-6.0),
    "disease": dict(ramp=((0.03, 0.028, 0.008), (0.15, 0.15, 0.022), (0.44, 0.42, 0.09)), opacity=0.86, gamma=0.85, s_gamma=1.1,
                    glow=(1.0, 0.72, 0.2), glow_k=0.0, spin=4.0, head=(0.84, 0.82, 0.42), head_k=0.95, settle=0.35),
    "curse": dict(ramp=((0.003, 0.0, 0.008), (0.02, 0.003, 0.05), (0.095, 0.02, 0.2)), opacity=0.72, gamma=1.5, glow=(0.5, 0.16, 0.95), glow_k=0.5, spin=-3.0, settle=0.8),
    "magic": dict(ramp=((0.02, 0.05, 0.2), (0.05, 0.16, 0.58), (0.12, 0.34, 0.86)), opacity=0.74, gamma=1.0, glow=(0.08, 0.36, 1.0), glow_k=0.36, spin=8.0, settle=1.1, spark=0.45, seconds=5.0),
}


def ramp(x, stops):
    a, b, c = (np.array(s, np.float32) for s in stops)
    x = np.clip(x, 0, 1)[..., None]
    lo = a + (b - a) * np.clip(x * 2, 0, 1)
    return lo + (c - b) * np.clip(x * 2 - 1, 0, 1)


def disc(n):
    g = (np.arange(n, dtype=np.float32) + 0.5) / n * 2 - 1
    xx, yy = np.meshgrid(g, g)
    return np.clip((0.985 - np.sqrt(xx * xx + yy * yy)) * n / 4, 0, 1)


def soft_dot(buf, cx, cy, r, value):
    """Adds a soft round dot into a float image."""
    x0, x1 = max(0, int(cx - r * 2)), min(buf.shape[1], int(cx + r * 2) + 2)
    y0, y1 = max(0, int(cy - r * 2)), min(buf.shape[0], int(cy + r * 2) + 2)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    d = ((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r)
    buf[y0:y1, x0:x1] = np.maximum(buf[y0:y1, x0:x1], np.exp(-d * 2.2) * value)


def bubbles(n, size, seed=11, count=11):
    """Rising bubbles for poison. Each makes a whole number of trips per loop, so it wraps."""
    rng = np.random.default_rng(seed)
    specs = [(rng.uniform(-0.72, 0.72), rng.uniform(0, 1), int(rng.integers(1, 3)), rng.uniform(0.022, 0.05), rng.uniform(0, 6.28)) for _ in range(count)]
    rims, hots, bodies = [], [], []
    for f in range(n):
        u = f / n
        rim = np.zeros((size, size), np.float32)
        hot = np.zeros((size, size), np.float32)
        body = np.zeros((size, size), np.float32)
        for x, y0, trips, r, ph in specs:
            y = (y0 + u * trips) % 1
            h = y * 2 - 1
            chord = math.sqrt(max(0, 1 - h * h)) * 0.86
            bx = x * chord + 0.02 * math.sin(2 * math.pi * u * trips + ph)
            cx, cy = (bx + 1) * size / 2, (1 - y) * size
            fade = min(1, y / 0.1) * min(1, (1 - y) / 0.08)
            rad = r * size
            soft_dot(body, cx, cy, rad, 0.3 * fade)
            # The rim: a ring brighter than the middle, and a glint up and left.
            x0, x1 = max(0, int(cx - rad * 1.8)), min(size, int(cx + rad * 1.8) + 2)
            y0p, y1p = max(0, int(cy - rad * 1.8)), min(size, int(cy + rad * 1.8) + 2)
            if x0 < x1 and y0p < y1p:
                yy, xx = np.mgrid[y0p:y1p, x0:x1].astype(np.float32)
                d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
                rim[y0p:y1p, x0:x1] = np.maximum(rim[y0p:y1p, x0:x1], np.exp(-((d - 1) ** 2) * 16) * fade)
            soft_dot(hot, cx - rad * 0.38, cy - rad * 0.4, max(1.1, rad * 0.32), fade)
        rims.append(rim)
        hots.append(hot)
        bodies.append(body)
    return np.stack(rims), np.stack(hots), np.stack(bodies)


def motes(n, size, seed=5, count=14):
    """Sparks for magic: each twinkles once per loop, slowly enough not to strobe."""
    rng = np.random.default_rng(seed)
    specs = [(rng.uniform(0, 6.28), rng.uniform(0.1, 0.9), 1, rng.uniform(0, 6.28), rng.uniform(0.01, 0.02)) for _ in range(count)]
    out = []
    for f in range(n):
        u = f / n
        buf = np.zeros((size, size), np.float32)
        for a, rad, tw, ph, r in specs:
            # Drifts a little round its own small circle, so it can't pop on loop.
            cx = size / 2 * (1 + rad * math.cos(a) + 0.03 * math.cos(2 * math.pi * u + ph))
            cy = size / 2 * (1 + rad * math.sin(a) + 0.03 * math.sin(2 * math.pi * u + ph))
            v = max(0.0, math.sin(2 * math.pi * tw * u + ph)) ** 3
            soft_dot(buf, cx, cy, r * size, v)
        out.append(buf)
    return np.stack(out)


def grade(work, kind):
    frames = [gc.read16(os.path.join(work, kind, f"f{i:03d}.png")) for i in range(FRAMES) if os.path.exists(os.path.join(work, kind, f"f{i:03d}.png"))]
    return grade_frames(frames, kind)


def grade_frames(frames, kind):
    em = np.stack([f[..., 0] for f in frames])
    sc = np.stack([f[..., 1] for f in frames])
    tr = np.stack([f[..., 2] for f in frames])
    look = LOOK[kind]
    n = len(frames)
    size = em.shape[1]
    e_top = max(1e-4, float(np.percentile(em, 99.9)))
    s_top = max(1e-4, float(np.percentile(sc, 99.6)))
    circle = disc(size)
    rim, hot, body = bubbles(n, size) if kind == "poison" else (None, None, None)
    spark = motes(n, size) if kind == "magic" else None
    mix, glow = [], []
    for i in range(n):
        s = np.clip(sc[i] / s_top, 0, 1) ** (0.75 * look.get("s_gamma", 1.0))
        e = np.clip(em[i] / e_top, 0, 1)
        cover = np.clip(1 - tr[i], 0, 1) ** look["gamma"]
        rgb = ramp(s, look["ramp"])
        a = cover * look["opacity"]
        if rim is not None:
            # Bubbles: the mix thins inside them, and their rims catch the light.
            thin = 1 - body[i]
            a = np.maximum(a * thin, rim[i] * 0.55)
            rgb = rgb * (1 - rim[i][..., None]) + np.array((0.22, 0.5, 0.05), np.float32) * rim[i][..., None]
            e = np.maximum(e ** 1.4, hot[i])
        else:
            e = e ** 1.4
        if spark is not None:
            e = np.maximum(e, spark[i] * look.get("spark", 1.0))
        if "head" in look:
            # Pustule heads: pale and thick, painted into the mix rather than lit.
            h = np.clip(em[i] / e_top, 0, 1)[..., None] * look["head_k"]
            rgb = rgb * (1 - h) + np.array(look["head"], np.float32) * h
            a = np.maximum(a, h[..., 0] * 0.95)
            e = e * 0
        a = gc.sharpen(a, 2.5, 0.45) * circle
        mix.append(cv2.resize(np.dstack([rgb, np.clip(a, 0, 1)]), (CELL, CELL), interpolation=cv2.INTER_AREA))
        g = np.clip(e, 0, 1) * look["glow_k"] * circle
        glow.append(cv2.resize(g, (CELL, CELL), interpolation=cv2.INTER_AREA))
    mix, glow = np.stack(mix), np.stack(glow)
    sigma = look.get("settle")
    if sigma and n > 1:
        # Circular smoothing through time, on premultiplied colour: per-frame noise flashes in game.
        from scipy.ndimage import gaussian_filter1d
        a = gaussian_filter1d(mix[..., 3], sigma, axis=0, mode="wrap")
        pre = gaussian_filter1d(mix[..., :3] * mix[..., 3:], sigma, axis=0, mode="wrap")
        mix = np.concatenate([pre / np.maximum(a[..., None], 1e-3), a[..., None]], axis=-1)
        glow = gaussian_filter1d(glow, sigma, axis=0, mode="wrap")
    return mix, glow


def save_sheets(work, out, kinds=KINDS):
    os.makedirs(out, exist_ok=True)
    for kind in kinds:
        mix, glow = grade(work, kind)
        sheet = np.zeros((SHEET, SHEET, 4), np.float32)
        gsheet = np.zeros((SHEET, SHEET, 4), np.float32)
        col = np.array(LOOK[kind]["glow"], np.float32)
        for i in range(len(mix)):
            y, x = divmod(i, COLS)
            sheet[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = mix[i]
            cell = gsheet[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL]
            cell[..., :3] = col
            cell[..., 3] = np.clip(glow[i], 0, 1)
        Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, f"globe-pollution-{kind}-mix.png"))
        Image.fromarray((np.clip(gsheet, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, f"globe-pollution-{kind}-glow.png"))
        print(kind, len(mix), "cells", f"{SHEET * SHEET * 4 / 1048576:.1f} MB each sheet")


class Stain:
    """One kind, played stepped, with its slow rotation and a breath on the glow."""
    def __init__(self, out, kind, size):
        self.kind, self.size = kind, size
        mix = np.asarray(Image.open(os.path.join(out, f"globe-pollution-{kind}-mix.png")).convert("RGBA"), np.float32) / 255
        glow = np.asarray(Image.open(os.path.join(out, f"globe-pollution-{kind}-glow.png")).convert("RGBA"), np.float32) / 255
        interp = cv2.INTER_LINEAR if size > CELL else cv2.INTER_AREA
        self.mix, self.glow = [], []
        for i in range(FRAMES):
            y, x = divmod(i, COLS)
            self.mix.append(cv2.resize(mix[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL], (size, size), interpolation=interp))
            self.glow.append(cv2.resize(glow[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL], (size, size), interpolation=interp))
        self.spin = LOOK[kind]["spin"]

    def cell(self, t, phase=0.0):
        return int(((t + phase) * FRAMES / LOOK[self.kind].get("seconds", LOOP)) % FRAMES)

    def layers(self, t, phase=0.0, rotate=True):
        i = self.cell(t, phase)
        m, g = self.mix[i], self.glow[i]
        if rotate:
            rot = cv2.getRotationMatrix2D(((self.size - 1) / 2, (self.size - 1) / 2), self.spin * t, 1.0)
            m = cv2.warpAffine(m, rot, (self.size, self.size), flags=cv2.INTER_LINEAR)
            g = cv2.warpAffine(g, rot, (self.size, self.size), flags=cv2.INTER_LINEAR)
        return m, g

    def over(self, img, t, alpha=1.0, phase=0.0):
        # As Pollution.lua plays it: the flipbook alone, no rotation or breath.
        m, g = self.layers(t, phase, rotate=False)
        breath = 1.0
        img = gc.over(img, m[..., :3], m[..., 3] * alpha)
        return gc.add(img, g[..., :3], g[..., 3] * alpha * breath)


def test(work, out, frame):
    arts = gc.Art(180), gc.Art(360)
    sheets = os.path.join(gc.ROOT, "mockups")
    rens = gc.Rendered(sheets, 180), gc.Rendered(sheets, 360)
    ctxs = gc.Context(180), gc.Context(360)
    rows = []
    for kind in KINDS:
        f = gc.read16(os.path.join(work, kind, f"f{frame:03d}.png"))
        row = []
        mix, glow = grade_frames([f], kind)
        for (art, ren, ctx, s) in ((arts[0], rens[0], ctxs[0], 180), (arts[1], rens[1], ctxs[1], 360)):
            interp = cv2.INTER_LINEAR if s > CELL else cv2.INTER_AREA
            m = cv2.resize(mix[0], (s, s), interpolation=interp)
            g = cv2.resize(glow[0], (s, s), interpolation=interp)
            for level in (0.6, 1.0) if s == 180 else (0.6,):
                liq = ren.draw(art, 1.0, gc.HEALTH)
                liq = gc.over(liq, m[..., :3], m[..., 3])
                liq = gc.add(liq, np.array(LOOK[kind]["glow"], np.float32), g)
                row.append(ctx.draw(gc.composite(art, liq, level, 1.0, gc.HEALTH)))
            # The art alone, on mid grey, to see the alpha.
            if s == 180:
                bg = np.full((s, s, 3), 0.35, np.float32)
                bg = gc.over(bg, m[..., :3], m[..., 3])
                bg = gc.add(bg, np.array(LOOK[kind]["glow"], np.float32), g)
                row.append(bg)
        h = max(a.shape[0] for a in row)
        line = np.full((h, sum(a.shape[1] for a in row) + 12 * len(row), 3), 0.07, np.float32)
        x = 0
        for a in row:
            line[:a.shape[0], x:x + a.shape[1]] = a
            x += a.shape[1] + 12
        rows.append(line)
    w = max(r.shape[1] for r in rows)
    H = sum(r.shape[0] + 10 for r in rows)
    canvas = np.full((H, w, 3), 0.07, np.float32)
    y = 0
    for r in rows:
        canvas[y:y + r.shape[0], :r.shape[1]] = r
        y += r.shape[0] + 10
    Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).save(out)
    print(out)


PHASE = {"poison": 0.0, "disease": 1.3, "curse": 2.1, "magic": 0.7}
LIFE = 8.0  # the lifecycle panels: seconds round
FADE_IN = 1.2
CLEANSE_AT = 6.0
FLASH = 0.4
GOLD = np.array((1.0, 0.86, 0.5), np.float32)


def life_alpha(t):
    p = t % LIFE
    if p < FADE_IN:
        return p / FADE_IN
    return 1.0 if p < CLEANSE_AT else 0.0


def life_flash(t):
    p = t % LIFE - CLEANSE_AT
    return max(0.0, 1 - p / FLASH) ** 1.5 if 0 <= p < FLASH else 0.0


def life_state(t):
    p = t % LIFE
    if p < FADE_IN:
        return "applied: fades in"
    if p < CLEANSE_AT:
        return "debuff up"
    return "cleansed: gone at once"


class Board:
    REAL, ZOOM = 180, 360
    W, H = 1920, 1240

    def __init__(self, out):
        self.art = {False: gc.Art(self.REAL), True: gc.Art(self.ZOOM)}
        self.ctx = {False: gc.Context(self.REAL), True: gc.Context(self.ZOOM)}
        sheets = os.path.join(gc.ROOT, "mockups")
        self.ren = {False: gc.Rendered(sheets, self.REAL), True: gc.Rendered(sheets, self.ZOOM)}
        self.stain = {z: {k: Stain(out, k, self.REAL if not z else self.ZOOM) for k in KINDS} for z in (False, True)}

    def bases(self, t):
        self.base = {
            (False, "rendered"): self.ren[False].draw(self.art[False], t, gc.HEALTH),
            (True, "rendered"): self.ren[True].draw(self.art[True], t, gc.HEALTH),
            (False, "current"): gc.current(self.art[False], t, gc.HEALTH),
        }

    def panel(self, zoom, base, t, level, kinds, alpha=1.0, flash=0.0):
        art = self.art[zoom]
        liq = self.base[(zoom, base)]
        for k in kinds:
            liq = self.stain[zoom][k].over(liq, t, alpha=alpha, phase=PHASE[k])
        out = gc.composite(art, liq, level, t, gc.HEALTH)
        if flash > 0:
            out = gc.add(out, art.rim[..., :3] * GOLD, art.rim[..., 3] * flash)
            out = gc.add(out, GOLD, art.mask[..., 0] * 0.55 * flash)
        return self.ctx[zoom].draw(out)

    def frame(self, t):
        self.bases(t)
        out = np.full((self.H, self.W, 3), 0.07, np.float32)
        tags = []

        def put(img, x, y, text):
            h, w = img.shape[:2]
            out[y:y + h, x:x + w] = img[:self.H - y, :self.W - x]
            tags.append((x, y - 24, text))

        x0, gap = 12, 237
        y = 32
        i = 0
        for k in KINDS:
            for level, name in ((0.6, "60%"), (0.25, "25%")):
                put(self.panel(False, "rendered", t, level, [k]), x0 + i * gap, y, f"{k} {name}")
                i += 1
        y = 288
        for i, k in enumerate(KINDS):
            put(self.panel(False, "rendered", t, 1.0, [k]), x0 + i * gap, y, f"{k} 100%")
        put(self.panel(False, "rendered", t, 0.6, ["poison", "curse"]), x0 + 4 * gap, y, "poison + curse")
        put(self.panel(False, "rendered", t, 0.6, ["disease", "magic"]), x0 + 5 * gap, y, "disease + magic")
        put(self.panel(False, "rendered", t, 0.6, ["poison"], life_alpha(t), life_flash(t)), x0 + 6 * gap, y, "own cleanse: flash")
        put(self.panel(False, "rendered", t, 0.6, ["curse"], life_alpha(t)), x0 + 7 * gap, y, life_state(t))
        y = 544
        for i, k in enumerate(KINDS):
            put(self.panel(False, "current", t, 0.6, [k]), x0 + i * gap, y, f"current liquid: {k}")
        put(self.panel(False, "current", t, 0.6, ["poison", "curse"]), x0 + 4 * gap, y, "current: poison + curse")
        put(self.panel(False, "current", t, 0.6, ["magic"], life_alpha(t)), x0 + 5 * gap, y, life_state(t))
        put(self.panel(False, "rendered", t, 0.6, []), x0 + 6 * gap, y, "clean: rendered")
        put(self.panel(False, "current", t, 0.6, []), x0 + 7 * gap, y, "clean: current")
        y = 800
        for i, k in enumerate(KINDS):
            put(self.panel(True, "rendered", t, 0.6, [k]), x0 + i * 468, y, f"2x {k}")
        for lx, ly, text in tags:
            out = gc.label(out, text, (lx, ly), size=17)
        return out


def still(out, path, t):
    b = Board(out)
    Image.fromarray((np.clip(b.frame(t), 0, 1) * 255).astype(np.uint8)).save(path)
    print(path)


def final(out, path, t=3.0):
    """Every type at each level on both liquids, a stacked row, and what you pay at 2x."""
    import tempfile
    b = Board(out)
    # The liquid as shipped (Art/liquid-*), not the prototype sheets in mockups/.
    d = tempfile.mkdtemp()
    for v in ("calm", "agitated"):
        for p_ in ("body", "light"):
            os.symlink(os.path.join(gc.ART, f"liquid-{v}-{p_}.png"), os.path.join(d, f"globe-render-{v}-{p_}.png"))
    b.ren = {False: gc.Rendered(d, b.REAL), True: gc.Rendered(d, b.ZOOM)}
    b.bases(t)
    b.base[(True, "current")] = gc.current(b.art[True], t, gc.HEALTH)
    W, H = 1420, 1560
    canvas = np.full((H, W, 3), 0.07, np.float32)
    tags = []

    def put(img, x, y, text):
        h, w = img.shape[:2]
        canvas[y:y + h, x:x + w] = img[:H - y, :W - x]
        tags.append((x, y - 22, text))

    x0, gx, gy = 12, 234, 236
    y = 30
    order = ("poison", "disease", "curse", "magic")
    for k in order:
        for i, (base, name) in enumerate((("rendered", "rendered"), ("current", "classic"))):
            for j, (lv, label) in enumerate(((1.0, "100"), (0.6, "60"), (0.25, "25"))):
                put(b.panel(False, base, t, lv, [k]), x0 + (i * 3 + j) * gx, y, f"{k} {label} {name}")
        y += gy
    combos = ((["curse", "poison"], "curse+poison"), (["disease", "magic"], "disease+magic"), (["curse", "disease", "poison", "magic"], "all four"))
    for i, (kinds, name) in enumerate(combos):
        put(b.panel(False, "rendered", t, 0.6, kinds), x0 + i * gx, y, f"{name} rendered")
        put(b.panel(False, "current", t, 0.6, kinds), x0 + (i + 3) * gx, y, f"{name} classic")
    y += gy
    for i, k in enumerate(order):
        put(b.panel(True, "rendered", t, 0.6, [k]), x0 + i * 352, y + 4, f"2x {k}")
    for lx, ly, text in tags:
        canvas = gc.label(canvas, text, (lx, ly), size=15)
    Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).save(path)
    print(path)


def video(out, path):
    import imageio_ffmpeg
    b = Board(out)
    fps, seconds = 30, 16.0
    writer = imageio_ffmpeg.write_frames(path, (b.W, b.H), fps=fps, codec="libx264", quality=None,
                                         bitrate="16M", pix_fmt_out="yuv420p", macro_block_size=None)
    writer.send(None)
    n = int(fps * seconds)
    for i in range(n):
        frame = b.frame(i / fps)
        writer.send((np.clip(frame, 0, 1) * 255).astype(np.uint8).tobytes())
        if i % 60 == 0:
            print(i, n, flush=True)
    writer.close()
    print(path)


def seams(out):
    """Largest step in the loop against the wrap, on the sheets as shipped (0-255 scale)."""
    for kind in KINDS:
        mix = np.asarray(Image.open(os.path.join(out, f"globe-pollution-{kind}-mix.png")), np.float32)
        cells = [mix[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] for i in range(FRAMES) for y, x in [divmod(i, COLS)]]
        d = [np.mean(np.abs(cells[i] - cells[(i + 1) % FRAMES])) for i in range(FRAMES)]
        print(kind, "mean step", round(float(np.mean(d[:-1])), 2), "max", round(float(max(d[:-1])), 2), "wrap", round(float(d[-1]), 2))


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "test":
        test(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 0)
    elif mode == "sheets":
        save_sheets(sys.argv[2], sys.argv[3], tuple(sys.argv[4].split(",")) if len(sys.argv) > 4 else KINDS)
        seams(sys.argv[3])
    elif mode == "final":
        final(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 3.0)
    elif mode == "still":
        still(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 3.0)
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
