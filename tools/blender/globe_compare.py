"""Builds flipbook sheets from tools/blender/globe_liquid.py renders and composites them the
way the game would, next to an approximation of the current procedural liquid.

  python globe_compare.py sheets WORK       make body/light sheets from WORK/{calm,agitated}
  python globe_compare.py still  WORK OUT   one comparison PNG
  python globe_compare.py video  WORK OUT   mp4 and png

Everything blends in display space, as WoW's UI does.
"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "SanctuaryUI", "Art")
CELL = 256
COLS = 8

# Frame of the loop for each variant: (frames, seconds).
LOOPS = {"calm": (48, 5.0), "agitated": (32, 2.8)}

HEALTH = np.array([0.86, 0.07, 0.05], np.float32)
MANA = np.array([0.18, 0.36, 1.0], np.float32)


def hotter(c, k):
    r, g, b = c
    return np.array([min(1, r + (1 - r) * k), min(1, g * (1 + 0.6 * k) + 0.3 * k), min(1, b * (1 + 0.4 * k) + 0.05 * k)], np.float32)


def lighter(c, k):
    return np.array([min(1, x * (1 - k) + k) for x in c], np.float32)


def light_of(c, k):
    return hotter(c, k) if c[0] > c[2] else lighter(c, k)


def load_png(name):
    return np.asarray(Image.open(os.path.join(ART, name)).convert("RGBA"), np.float32) / 255


def read16(path):
    im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("missing " + path)
    return im[..., ::-1].astype(np.float32) / 65535


def sharpen(x, r, k):
    return np.clip(x + k * (x - cv2.GaussianBlur(x, (0, 0), r)), 0, 1)


def grade(work, variant):
    """Render channels -> display-referred luminance body and light frames, per cell."""
    n = LOOPS[variant][0]
    frames = [read16(os.path.join(work, variant, f"f{i:03d}.png")) for i in range(n)]
    em = np.stack([f[..., 0] for f in frames])
    sc = np.stack([f[..., 1] for f in frames])
    th = np.stack([f[..., 2] for f in frames])
    g_top = np.percentile(sc, 99.7)
    r_top = np.percentile(em, 99.8)
    body, light = [], []
    calm = variant == "calm"
    for i in range(n):
        g = np.clip(sc[i] / g_top, 0, 1)
        r = np.clip(em[i] / r_top, 0, 1)
        # Thin liquid shows the well behind it: darker where the volume is thin.
        thick = 1 - np.clip(th[i], 0, 1)
        lit = g ** (0.55 if calm else 0.7)
        # A floor so the deep liquid still has colour, then the strands as fine detail.
        b = np.clip(0.26 + lit * (0.45 + 0.55 * thick) * 0.95 + r ** 1.5 * (0.38 if calm else 0.3), 0, 1)
        b = sharpen(b, 3.0, 0.5)
        if not calm:
            b = b * 0.72
        l = np.clip(r, 0, 1) ** 2.1
        l = sharpen(l, 2.0, 0.6)
        body.append(cv2.resize(b, (CELL, CELL), interpolation=cv2.INTER_AREA))
        light.append(cv2.resize(l, (CELL, CELL), interpolation=cv2.INTER_AREA))
    return np.stack(body), np.stack(light)


def pack(frames):
    n = len(frames)
    rows = math.ceil(n / COLS)
    sheet = np.zeros((rows * CELL, COLS * CELL), np.float32)
    for i, f in enumerate(frames):
        y, x = divmod(i, COLS)
        sheet[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = f
    return sheet


def save_sheets(work, out):
    os.makedirs(out, exist_ok=True)
    for v in LOOPS:
        if not os.path.exists(os.path.join(work, v, "f000.png")):
            continue
        body, light = grade(work, v)
        for name, fr in (("body", body), ("light", light)):
            sheet = pack(fr)
            path = os.path.join(out, f"globe-render-{v}-{name}.png")
            Image.fromarray((sheet * 255 + 0.5).astype(np.uint8), "L").convert("RGBA").save(path)
            print(path, sheet.shape[1], "x", sheet.shape[0], f"{sheet.size * 4 / 1048576:.1f} MB RGBA")


def load_sheet(path, n):
    a = np.asarray(Image.open(path).convert("L"), np.float32) / 255
    out = []
    for i in range(n):
        y, x = divmod(i, COLS)
        out.append(a[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL])
    return out


class Book:
    """Two adjacent cells mixed by the fraction: the game's two-texture frame blend."""
    def __init__(self, frames, seconds, size):
        self.frames = [cv2.resize(f, (size, size), interpolation=cv2.INTER_LINEAR if size > CELL else cv2.INTER_AREA) for f in frames]
        self.seconds = seconds

    def at(self, t):
        n = len(self.frames)
        x = (t / self.seconds % 1) * n
        i = int(x)
        f = x - i
        return self.frames[i % n] * (1 - f) + self.frames[(i + 1) % n] * f


class Art:
    def __init__(self, size):
        self.size = size
        def res(a):
            return cv2.resize(a, (size, size), interpolation=cv2.INTER_AREA if a.shape[0] > size else cv2.INTER_LINEAR)
        self.mask = res(load_png("globe-mask.png"))[..., 3:]
        if self.mask.max() < 0.01:
            self.mask = res(load_png("globe-mask.png"))[..., :1]
        self.shade = res(load_png("globe-shade.png"))
        self.rim = res(load_png("globe-rim.png"))
        self.tile = load_png("liquid-tile.png")
        self.wisps = load_png("liquid-wisps.png")
        self.streaks = load_png("liquid-streaks.png")
        glow = "surface-glow.png" if os.path.exists(os.path.join(ART, "surface-glow.png")) else "hotline.png"
        self.glow = load_png(glow)
        self.well = load_png("liquid.png")
        self.well = res(self.well)
        grid = (np.arange(size, dtype=np.float32) + 0.5) / size
        self.xx, self.yy = np.meshgrid(grid, grid)

    def affine(self, tex, cu, cv, half, angle):
        cu, cv = cu % 1 + 1.5, cv % 1 + 1.5
        c, s = math.cos(angle) * half, math.sin(angle) * half
        h, w = tex.shape[:2]
        u = cu - c + s + self.xx * 2 * c + self.yy * (-2 * s)
        v = cv - s - c + self.xx * 2 * s + self.yy * 2 * c
        return cv2.remap(tex, (u * w).astype(np.float32), (v * h).astype(np.float32), cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP)


def over(dst, col, alpha):
    if alpha.ndim == 2:
        alpha = alpha[..., None]
    return dst * (1 - alpha) + col * alpha


def add(dst, col, alpha):
    if alpha.ndim == 2:
        alpha = alpha[..., None]
    return np.clip(dst + col * alpha, 0, 1)


def hash1(n):
    x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)


LAYERS = dict(
    base=dict(span=1.0, spin=0.045, du=0.018, dv=0.006, breathe=0.035, rate=0.31),
    swirl=dict(span=1.5, spin=-0.085, du=-0.03, dv=0.012, breathe=0.05, rate=0.23, alpha=0.28),
    streaks=dict(span=1.0, du=0.085, sway=0.018, sway_rate=0.6, alpha=0.26),
)
WISPS = dict(span=1.15, period=6.5, travel=0.16, spin=0.05, alpha=0.24)


def current(art, t, color, phase=0.29):
    """The procedural liquid, per Pool:Animate (without motes)."""
    m = LAYERS["base"]
    b = 1 + m["breathe"] * math.sin(t * m["rate"] + phase * 7)
    tex = art.affine(art.tile, phase + t * m["du"], phase * 0.7 + t * m["dv"], m["span"] * 0.5 * b, t * m["spin"] + phase * 6)
    img = np.zeros((art.size, art.size, 3), np.float32)
    img = over(img, tex[..., :3] * color, tex[..., 3])
    m = LAYERS["swirl"]
    b = 1 + m["breathe"] * math.sin(t * m["rate"] + phase * 3)
    tex = art.affine(art.tile, phase + 0.37 + t * m["du"], 0.5 + t * m["dv"], m["span"] * 0.5 * b, t * m["spin"] + phase * 2)
    img = add(img, tex[..., :3] * color, tex[..., 3] * m["alpha"])
    wc = light_of(color, 0.35)
    for k in (1, 2):
        cyc = t / WISPS["period"] + phase + (k - 1) * 0.5
        n = math.floor(cyc)
        p = cyc - n
        seed = n * 2 + k + phase * 13
        d = hash1(seed + 0.5) * math.pi * 2
        travel = (p - 0.5) * WISPS["travel"]
        a = math.sin(p * math.pi)
        tex = art.affine(art.wisps, hash1(seed) + math.cos(d) * travel, hash1(seed + 1.7) + math.sin(d) * travel,
                         WISPS["span"] * 0.5, hash1(seed + 3.1) * 6.283 + (p - 0.5) * WISPS["spin"] * WISPS["period"])
        img = add(img, tex[..., :3] * wc, tex[..., 3] * a * a * WISPS["alpha"])
    m = LAYERS["streaks"]
    tex = art.affine(art.streaks, phase + 0.71 + t * m["du"], phase + math.sin(t * m["sway_rate"] + phase * 40) * m["sway"], m["span"] * 0.5, 0)
    img = add(img, tex[..., :3] * light_of(color, 0.5), tex[..., 3] * m["alpha"])
    img = add(img, art.rim[..., :3] * light_of(color, 0.3), art.rim[..., 3] * 0.42)
    return img


class Rendered:
    def __init__(self, sheets, size):
        self.calm_body = Book(load_sheet(os.path.join(sheets, "globe-render-calm-body.png"), LOOPS["calm"][0]), LOOPS["calm"][1], size)
        self.calm_light = Book(load_sheet(os.path.join(sheets, "globe-render-calm-light.png"), LOOPS["calm"][0]), LOOPS["calm"][1], size)
        self.ag_body = Book(load_sheet(os.path.join(sheets, "globe-render-agitated-body.png"), LOOPS["agitated"][0]), LOOPS["agitated"][1], size)
        self.ag_light = Book(load_sheet(os.path.join(sheets, "globe-render-agitated-light.png"), LOOPS["agitated"][0]), LOOPS["agitated"][1], size)

    def draw(self, art, t, color, urge=0.0):
        hot = light_of(color, 0.55)
        img = self.calm_body.at(t)[..., None] * color
        img = add(img, hot, self.calm_light.at(t) * 0.8)
        if urge > 0:
            # Laid over at the alpha the health curve drives, then its own light added.
            dark = color * np.array([0.62, 0.45, 0.45], np.float32)
            img = over(img, self.ag_body.at(t)[..., None] * dark, np.full((art.size, art.size), urge, np.float32))
            img = add(img, hotter(color, 0.75) if color[0] > color[2] else lighter(color, 0.6), self.ag_light.at(t) * urge)
        img = add(img, art.rim[..., :3] * light_of(color, 0.3), art.rim[..., 3] * 0.3)
        return img


def surface(art, dst, t, level, color, lift):
    """The surface band at the fill line: same model for both, a rippling glow strip."""
    if level >= 0.985 or level <= 0.015:
        return dst
    s = art.size
    h = int(s * 0.16)
    y0 = (1 - level) * s
    x = (np.arange(s, dtype=np.float32) + 0.5) / s * 2 - 1
    wave = 0.0055 * s * (np.sin(x * 7.2 + t * 1.9) + 0.6 * np.sin(-x * 11.5 + t * 2.7))
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    v = (yy - (y0 + wave[None, :])) / h
    u = ((xx / s + t * -0.025) % 1) * art.glow.shape[1]
    g = cv2.remap(art.glow, u.astype(np.float32), (v * art.glow.shape[0]).astype(np.float32), cv2.INTER_LINEAR,
                  borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    col = g[..., :3] * light_of(color, 0.45)
    return add(dst, col, g[..., 3] * lift * art.mask[..., 0])


def composite(art, liquid, level, t, color, context=True):
    """Well, clipped liquid, sphere shade, surface."""
    s = art.size
    well = art.well[..., :3] * np.array([0.07, 0.035, 0.03], np.float32)
    dst = np.full((s, s, 3), 0.055, np.float32)
    dst = over(dst, well, art.well[..., 3])
    clip = np.ones((s, s), np.float32)
    x = (np.arange(s, dtype=np.float32) + 0.5) / s * 2 - 1
    top = (1 - level) * s
    wave = 0.0055 * s * (np.sin(x * 7.2 + t * 1.9) + 0.6 * np.sin(-x * 11.5 + t * 2.7))
    rows = np.arange(s, dtype=np.float32)[..., None] + 0.5
    clip = np.clip(rows - (top + wave[None, :]), 0, 1)
    dst = over(dst, liquid, clip * art.mask[..., 0])
    dst = over(dst, art.shade[..., :3], art.shade[..., 3] * art.mask[..., 0])
    dst = surface(art, dst, t, level, color, 0.95)
    return dst


class Context:
    """The console around the health globe: glass ADD and frame, the game's draw order."""
    def __init__(self, globe):
        k = globe / 160
        self.k = k
        self.x0, self.y0 = 145, 3
        self.w, self.h = 200, 196
        frame = load_png("frame.png")[self.y0:self.y0 + self.h, self.x0:self.x0 + self.w]
        glass = load_png("glass.png")[self.y0:self.y0 + self.h, self.x0:self.x0 + self.w]
        dsize = (int(self.w * k), int(self.h * k))
        self.frame = cv2.resize(frame, dsize, interpolation=cv2.INTER_CUBIC)
        self.glass = cv2.resize(glass, dsize, interpolation=cv2.INTER_CUBIC)
        self.cx, self.cy = int((243.5 - self.x0) * k), int((99 - self.y0) * k)

    def draw(self, liquid):
        h, w = self.frame.shape[:2]
        out = np.full((h, w, 3), 0.055, np.float32)
        s = liquid.shape[0]
        x0, y0 = self.cx - s // 2, self.cy - s // 2
        x1, y1 = min(w, x0 + s), min(h, y0 + s)
        sx, sy = max(0, -x0), max(0, -y0)
        x0, y0 = max(0, x0), max(0, y0)
        out[y0:y1, x0:x1] = liquid[sy:sy + y1 - y0, sx:sx + x1 - x0]
        out = add(out, self.glass[..., :3], self.glass[..., 3])
        return over(out, self.frame[..., :3], self.frame[..., 3])


def label(img, text, xy, size=20, color=(235, 225, 205)):
    pil = Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(pil)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
    except OSError:
        font = ImageFont.load_default()
    d.text(xy, text, fill=color, font=font)
    return np.asarray(pil, np.float32) / 255


class Board:
    """One frame of the comparison: real size row, then 3x."""
    REAL, ZOOM = 180, 540

    def __init__(self, sheets):
        self.art_r, self.art_z = Art(self.REAL), Art(self.ZOOM)
        self.ren_r, self.ren_z = Rendered(sheets, self.REAL), Rendered(sheets, self.ZOOM)
        self.ctx_r, self.ctx_z = Context(self.REAL), Context(self.ZOOM)

    def globe(self, zoom, kind, t, level, color, urge=0.0):
        art = self.art_z if zoom else self.art_r
        ren = self.ren_z if zoom else self.ren_r
        ctx = self.ctx_z if zoom else self.ctx_r
        if kind == "current":
            liq = current(art, t, color)
            if urge > 0:
                # The current churn: the tile laid over dark.
                tex = art.affine(art.tile, 0.82 + t * 0.07, 0.21 - t * 0.035, 0.625, t * -0.32 + 1.2)
                liq = over(liq, tex[..., :3] * color * np.array([0.3, 0.2, 0.2], np.float32), tex[..., 3] * 0.5 * urge)
        else:
            liq = ren.draw(art, t, color, urge)
        return ctx.draw(composite(art, liq, level, t, color))

    def frame(self, t):
        """Layout: real-size strip on top, 3x pair below, tint and low-health on the right."""
        W, H = 1920, 1120
        out = np.full((H, W, 3), 0.07, np.float32)

        def put(img, x, y):
            h, w = img.shape[:2]
            out[y:y + h, x:x + w] = img[:H - y, :W - x]

        x = 16
        for level, name in ((1.0, "100%"), (0.6, "60%"), (0.25, "25%")):
            for kind in ("current", "rendered"):
                img = self.globe(False, kind, t, level, HEALTH)
                put(img, x, 44)
                labels.append((x, 16, f"{kind} {name}"))
                x += img.shape[1] + 12
            x += 16
        ty = 44 + self.ctx_r.frame.shape[0] + 44
        cur = self.globe(True, "current", t, 0.6, HEALTH)
        ren = self.globe(True, "rendered", t, 0.6, HEALTH)
        put(cur, 16, ty)
        put(ren, 16 + cur.shape[1] + 12, ty)
        labels.append((16, ty - 28, "3x current (procedural)"))
        labels.append((16 + cur.shape[1] + 12, ty - 28, "3x rendered flipbook, same frame clip and shade"))
        rx = 16 + 2 * cur.shape[1] + 36
        blue = self.globe(False, "rendered", t, 0.6, MANA)
        put(blue, rx, ty)
        labels.append((rx, ty - 28, "same art, mana tint"))
        low_u = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 10 - math.pi / 2)
        lo = self.globe(False, "rendered", t, 0.25, HEALTH, urge=low_u)
        put(lo, rx, ty + blue.shape[0] + 44)
        labels.append((rx, ty + blue.shape[0] + 16, f"low-health loop, curve alpha {low_u:.2f}"))
        lc = self.globe(False, "current", t, 0.25, HEALTH, urge=low_u)
        put(lc, rx, ty + 2 * blue.shape[0] + 88)
        labels.append((rx, ty + 2 * blue.shape[0] + 60, "current low-health churn"))
        return out


labels = []


def still(work, out):
    b = Board(work)
    t = 5.0  # the low-health panel's curve alpha peaks here
    frame = b.frame(t)
    for lx, ly, text in labels:
        frame = label(frame, text, (lx, ly))
    Image.fromarray(np.clip(frame * 255, 0, 255).astype(np.uint8)).save(out)
    print(out)


def video(work, out):
    import imageio_ffmpeg
    b = Board(work)
    fps, seconds = 60, 10.0
    writer = imageio_ffmpeg.write_frames(out, (1920, 1120), fps=fps, codec="libx264", quality=None,
                                         bitrate="24M", pix_fmt_out="yuv420p", macro_block_size=None)
    writer.send(None)
    n = int(fps * seconds)
    for i in range(n):
        labels.clear()
        frame = b.frame(i / fps)
        for lx, ly, text in labels:
            frame = label(frame, text, (lx, ly))
        writer.send(np.clip(frame * 255, 0, 255).astype(np.uint8).tobytes())
        if i % 60 == 0:
            print(i, n, flush=True)
    writer.close()
    print(out)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sheets":
        save_sheets(sys.argv[2], sys.argv[3])
    elif mode == "still":
        still(sys.argv[2], sys.argv[3])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
