"""Example looks for heals over time and one-off heals on the health globe, to pick from.

Procedural numpy art composited over the real console with the game's draw order, next to today's
Upwell. Prototype only: nothing here is wired into the addon.

  python globe_heals.py art   WORK             build every sprite and flipbook into WORK/art.npz
  python globe_heals.py check WORK NAME OUT    contact sheet of one option at a few moments
  python globe_heals.py still WORK OUT.png
  python globe_heals.py video WORK OUT.mp4

White luminance art tinted with GlobeAura.lua's TINTS, everything that lands on the fill line
anchored to it rather than computed from it, as the level can be a hidden value in combat. The
surface is what the addon's fill guide gives: the art rides it, nothing reads it.
"""
import math
import multiprocessing as mp
import os
import sys
import textwrap

import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402
import globe_fx_compare as fxc  # noqa: E402
import globe_surge_concepts as sc  # noqa: E402
import globe_surge_final as sf  # noqa: E402

RISE_CELL = 128
LEAF_FRAMES = 16
VINE_CELL = 256
VINE_STAGES = 16
FLARE = 1.1
DROP_TIME = 0.32

HOT_PERIOD = 3.0
ONE_SHOT = 2.8


def smooth(x, a=0.0, b=1.0):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def s1(x):
    return float(smooth(np.array(float(x))))


def rect_grid(w, h, x0, x1, y0, y1):
    xs = x0 + (np.arange(w, dtype=np.float32) + 0.5) / w * (x1 - x0)
    ys = y0 + (np.arange(h, dtype=np.float32) + 0.5) / h * (y1 - y0)
    return np.meshgrid(xs, ys)


def noise1(n, scale, seed, power=1.2):
    """Periodic 1-D noise, 0..1."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal(n, dtype=np.float32)
    f = np.fft.fftfreq(n) * n
    out = np.fft.ifft(np.fft.fft(w) / (1 + (f / scale) ** 2) ** power).real
    return np.clip((out - out.min()) / (out.max() - out.min()), 0, 1).astype(np.float32)


# -- leaf ---------------------------------------------------------------------------------------

def leaf_frame(roll, pitch, yaw, fold, arch, cell=RISE_CELL, ss=4):
    """One leaf as a real curved surface, rasterised back to front: body dim, edge and veins bright."""
    nu, nv = 56, 22
    size = cell * ss
    canvas = np.zeros((size, size), np.float32)
    us = np.linspace(0.0, 1.0, nu + 1, dtype=np.float32)
    vs = np.linspace(-1.0, 1.0, nv + 1, dtype=np.float32)
    U, V = np.meshgrid(us, vs, indexing="ij")
    width = np.maximum(np.sin(np.pi * U ** 0.8), 0) ** 0.85 * 0.3
    x = U - 0.5
    y = V * width
    z = fold * np.abs(y) * 1.2 + arch * (U - 0.5) ** 2 * 1.1
    pts = np.stack([x, y, z], -1)
    # Tumble: roll about the midrib, then pitch and yaw.
    cr, sr, cp, sp, cy, sy = math.cos(roll), math.sin(roll), math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
    Rx = np.array([[1, 0, 0], [0, cr, -sr], [0, sr, cr]], np.float32)
    Ry = np.array([[cp, 0, sp], [0, 1, 0], [-sp, 0, cp]], np.float32)
    Rz = np.array([[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]], np.float32)
    pts = pts @ (Rz @ Ry @ Rx).T
    px = (pts[..., 0] * 0.74 + 0.5) * size
    py = (0.5 - pts[..., 1] * 0.74) * size
    quads = []
    for i in range(nu):
        for j in range(nv):
            a, b, c, d = pts[i, j], pts[i + 1, j], pts[i + 1, j + 1], pts[i, j + 1]
            n = np.cross(c - a, d - b)
            ln = np.linalg.norm(n) + 1e-6
            n = n / ln
            facing = abs(float(n[2]))
            u = float(us[i] + us[i + 1]) * 0.5
            v = float(vs[j] + vs[j + 1]) * 0.5
            rim = (1 - facing) ** 1.6
            edge = math.exp(-((1 - abs(v)) / 0.16))
            mid = math.exp(-(v / 0.11) ** 2)
            veins = max(0.0, math.cos(((u - abs(v) * 0.42) * 9.5) * math.pi * 2)) ** 18 * (1 - abs(v)) * smooth(np.array(u), 0.08, 0.3)
            body = 0.2 + 0.55 * u ** 0.6
            lum = body + rim * 0.55 + edge * 0.7 + mid * 0.9 + float(veins) * 0.55
            z_q = float(a[2] + b[2] + c[2] + d[2]) * 0.25
            poly = np.array([[px[i, j], py[i, j]], [px[i + 1, j], py[i + 1, j]], [px[i + 1, j + 1], py[i + 1, j + 1]], [px[i, j + 1], py[i, j + 1]]], np.int32)
            quads.append((z_q, poly, lum))
    for _z, poly, lum in sorted(quads, key=lambda q: q[0]):
        cv2.fillConvexPoly(canvas, poly, float(min(lum, 1.0)))
    img = cv2.resize(canvas, (cell, cell), interpolation=cv2.INTER_AREA)
    return np.clip(cv2.GaussianBlur(img, (0, 0), 0.6), 0, 1)


def gen_leaf():
    frames = []
    for i in range(LEAF_FRAMES):
        f = i / LEAF_FRAMES
        roll = f * 2 * math.pi
        pitch = 0.62 * math.sin(f * 2 * math.pi)
        yaw = 0.3 * math.sin(f * 2 * math.pi + 1.1)
        frames.append(leaf_frame(roll, pitch, yaw, fold=0.42, arch=0.45))
    return np.stack(frames)


# -- vines --------------------------------------------------------------------------------------

def vine_path(side, n=240):
    """Polar path up one side of the glass, cell coordinates (the globe's circle radius is 1)."""
    sgn = -1 if side == 0 else 1
    q = np.linspace(0, 1, n, dtype=np.float32)
    # From where the gargoyle and the console wall let go of the rim, up to nearly the crown.
    th = np.radians(74 - (74 - 5) * q) * sgn
    th = th + np.radians(2.2) * np.sin(q * 11 + side * 1.7) * (1 - q) ** 0.3 * sgn
    rad = 0.858 + 0.016 * np.sin(q * 15 + side * 2.1)
    x = np.sin(th) * rad
    y = np.cos(th) * rad
    return x, y, q


def leaflet(canvas, cell, x, y, ang, length, value, ss):
    """A small almond leaf at (x, y) pointing along ang, drawn on a supersampled canvas."""
    w = length * 0.42
    u = np.linspace(0, 1, 14, dtype=np.float32)
    wd = np.maximum(np.sin(np.pi * u ** 0.75), 0) ** 0.9 * w
    ca, sa = math.cos(ang), math.sin(ang)
    px, py = [], []
    pts_top, pts_bot = [], []
    for ui, wi in zip(u, wd):
        cx_ = x + ca * length * ui
        cy_ = y + sa * length * ui
        pts_top.append((cx_ - sa * wi, cy_ + ca * wi))
        pts_bot.append((cx_ + sa * wi, cy_ - ca * wi))
    pts = pts_top + pts_bot[::-1]
    arr = np.array([[(p[0] + 1) * cell * 0.5 * ss, (1 - p[1]) * cell * 0.5 * ss] for p in pts], np.int32)
    cv2.fillPoly(canvas, [arr], float(value * 0.38))
    cv2.polylines(canvas, [arr], True, float(value * 0.9), max(1, int(ss * 0.7)), cv2.LINE_AA)
    mx0 = ((x + 1) * cell * 0.5 * ss, (1 - y) * cell * 0.5 * ss)
    mx1 = ((x + ca * length * 0.9 + 1) * cell * 0.5 * ss, (1 - (y + sa * length * 0.9)) * cell * 0.5 * ss)
    cv2.line(canvas, (int(mx0[0]), int(mx0[1])), (int(mx1[0]), int(mx1[1])), float(value), max(1, int(ss * 0.6)), cv2.LINE_AA)


def gen_vines():
    """Growth stages of the vines on the glass: stage k shows growth up to k/(n-1)."""
    ss = 4
    cell = VINE_CELL
    paths = [vine_path(0), vine_path(1)]
    rng = np.random.default_rng(7)
    buds = []
    for side in (0, 1):
        for k in range(7):
            s = 0.05 + 0.125 * k + (rng.random() - 0.5) * 0.03
            buds.append((side, s, 0.085 + rng.random() * 0.045, 1 if k % 2 else -1, rng.random() * 0.2 - 0.1))
    frames = []
    for stage in range(VINE_STAGES):
        g = stage / (VINE_STAGES - 1)
        canvas = np.zeros((cell * ss, cell * ss), np.float32)
        for side in (0, 1):
            x, y, q = paths[side]
            n = max(2, int(len(x) * g))
            for i in range(n - 1):
                width = 2.4 + (1 - q[i]) * 2.6
                t0 = (int((x[i] + 1) * cell * ss * 0.5), int((1 - y[i]) * cell * ss * 0.5))
                t1 = (int((x[i + 1] + 1) * cell * ss * 0.5), int((1 - y[i + 1]) * cell * ss * 0.5))
                cv2.line(canvas, t0, t1, 1.0, max(1, int(width * ss * 0.45)), cv2.LINE_AA)
        for side, s, length, flip, wob in buds:
            if s > g:
                continue
            age = min(1.0, (g - s) / 0.12)
            x, y, q = paths[side]
            i = int(s * (len(x) - 2))
            tx, ty = x[i + 2] - x[i], y[i + 2] - y[i]
            ang = math.atan2(ty, tx) + (0.9 if flip > 0 else -0.9) + wob
            leaflet(canvas, cell, float(x[i]), float(y[i]), ang, length * (0.35 + 0.65 * age), 1.0, ss)
        # The crown: the two vines meet and a bud opens at the very end.
        if g > 0.86:
            age = (g - 0.86) / 0.14
            for k in range(5):
                ang = math.pi / 2 + (k - 2) * 0.62
                leaflet(canvas, cell, 0.0, 0.88, ang, 0.14 * (0.25 + 0.75 * age), 1.0, ss)
        img = cv2.resize(canvas, (cell, cell), interpolation=cv2.INTER_AREA)
        glow = cv2.GaussianBlur(img, (0, 0), 3.0)
        frames.append(np.clip(img * 0.85 + glow * 0.75, 0, 1))
    return np.stack(frames)


# -- halo ---------------------------------------------------------------------------------------

def gen_halo():
    x, y = rect_grid(512, 256, -1, 1, 0.5, -0.5)
    a = 0.62
    asp = 0.31
    e = np.hypot(x / a, y / (a * asp)) - 1
    front = smooth(-y, -0.1, 0.14) * 0.55 + 0.45
    core = np.exp(-(e / 0.024) ** 2) * front
    # A wide haze and a tighter one, so the ring reads at 180 px and isn't a drawn line.
    glow = (np.exp(-(np.abs(e) / 0.1) ** 1.25) * 0.95 + np.exp(-(np.abs(e) / 0.34) ** 1.1) * 0.5) * (front * 0.8 + 0.2)
    glow = glow * (1 - smooth(np.abs(x), 0.78, 1.0)) * (1 - smooth(np.abs(y), 0.36, 0.5))
    fringe = noise1(1024, 22, 3)
    phi = (np.arctan2(y / asp, x) / (2 * math.pi) + 0.5) * 1024
    breaks = fringe[np.clip(phi.astype(int), 0, 1023)]
    core = core * (0.75 + 0.45 * breaks)
    return {"halo_core": np.clip(core, 0, 1), "halo_glow": np.clip(glow, 0, 1)}


# -- rings, drops, dome, beam, mound ------------------------------------------------------------

def gen_rings():
    x, y = rect_grid(256, 64, -1, 1, 0.25, -0.25)
    a = 0.86
    e = np.hypot(x / a, y / (a * 0.22)) - 1
    core = np.exp(-(e / 0.04) ** 2)
    band = np.exp(-(np.abs(e) / 0.16) ** 1.2)
    return {"ring_core": np.clip(core, 0, 1), "ring_band": np.clip(band, 0, 1)}


def gen_drop():
    x, y = rect_grid(32, 64, -1, 1, 1, -1)
    head = np.exp(-((x / 0.42) ** 2 + ((y + 0.42) / 0.42) ** 2))
    tail = np.exp(-(x / (0.12 + 0.28 * np.clip((0.6 - y) / 1.6, 0, 1))) ** 2) * smooth(-y, -1.0, 0.1) ** 1.3 * 0.75
    return np.clip(np.maximum(head, tail), 0, 1)


def gen_dome():
    x, y = rect_grid(256, 256, -1, 1, 1, -1)
    r = np.hypot(x, y)
    n = noise1(2048, 34, 5, 1.1)
    phi = np.arctan2(x, np.maximum(y, 0.0001))
    idx = (((phi / np.pi) + 1) * 512).astype(int) % 2048
    fan = n[idx]
    rays = np.exp(-(r / 0.62) ** 2.4) * (0.55 + 0.75 * smooth(fan, 0.32, 0.92)) * (1 - smooth(np.abs(phi), 1.1, 1.55))
    dome = np.exp(-(r / 0.44) ** 2.2) * 0.85 * (1 - smooth(np.abs(phi), 1.15, 1.6))
    cut = smooth(y, -0.06, 0.02)
    return np.clip((rays + dome) * cut, 0, 1)


def gen_beam():
    x, y = rect_grid(128, 512, -1, 1, 1, 0)
    n = noise1(1024, 80, 8, 1.0)
    idx = np.clip((x * 0.5 + 0.5) * 1023, 0, 1023).astype(int)
    strand = smooth(n[idx], 0.25, 0.95)
    env = 1 - smooth(y, 0.62, 1.0)
    core = np.exp(-(x / 0.2) ** 2) * (0.75 + 0.25 * strand) * env
    glow = np.exp(-(np.abs(x) / 0.42) ** 1.3) * 0.75 * env * (1 - smooth(np.abs(x), 0.62, 1.0))
    return {"beam_core": np.clip(core, 0, 1), "beam_glow": np.clip(glow, 0, 1)}


def gen_veil():
    """An aurora hugging the top of the rim: curtains of light rising off it, fading outward.
    Cell x -1.7..1.7 and y 0..1.7 of the globe's radius; the rim at rho 1. Flipbook, 32 frames."""
    n = 32
    cell_w, cell_h = 256, 128
    x, y = rect_grid(cell_w, cell_h, -1.7, 1.7, 1.7, 0.0)
    rho = np.hypot(x, y)
    th = np.arctan2(x, np.maximum(y, 1e-3))
    curt = sc.noise3((640, 24, n), (15, 2.0, 1.6), 51, 1.2)
    ribbon = sc.noise3((256, n), (5, 1.4), 52, 1.4) if False else None
    ribbon = sc.noise3((256, 8, n), (5, 1.2, 1.4), 52, 1.4)
    frames = []
    for i in range(n):
        t = i / n
        # Curtains are vertical folds (in x, not radial), so this isn't radiance's sunburst.
        u = (x / 3.4 + 0.5) * 2  # no sideways drift: every moving term must be whole cycles over the loop
        streak = smooth(sc.sample(curt, u, y * 0.12 + t, t), 0.3, 0.95)
        band = smooth(sc.sample(ribbon, th / (2 * math.pi) * 3, 0.0, t), 0.25, 0.95)
        # A curtain's foot sits on the rim, brightest there, fading up and over the top.
        edge = 1.02 + 0.06 * band
        rise = np.exp(-np.maximum(rho - edge, 0) / 0.26) * smooth(rho, 0.96, 1.0) * (1 - smooth(rho, 1.28, 1.62))
        top = 1 - smooth(np.abs(th), math.radians(62), math.radians(112))
        body = (0.5 + 0.6 * streak) * rise * (0.42 + 0.7 * band) * top
        frames.append(np.clip(body, 0, 1))
    return np.stack(frames)


def gen_mound():
    """The liquid lifting: a rounded swell over the surface, as coverage, its own cloudy shading
    (baked, tinted by the liquid colour in the game), and a lit edge. y is 0 at the surface; the
    cell starts a little below it so the sprite covers the surface's own wave."""
    w, h, n = 256, 128, 16
    x, y = rect_grid(w, h, -1, 1, 1, -0.12)
    cloud = sc.noise3((64, 128, 16), (3.0, 2.0, 2.0), 41, 1.4)
    cover, shade, edge = [], [], []
    for i in range(n):
        t = (i + 0.5) / n
        rise = math.sin(min(t / 0.7, 1) * math.pi * 0.5) ** 0.75 * (1 - smooth(np.array(t), 0.55, 1.0))
        height = 0.72 * float(rise)
        sigma = 0.7 + 0.25 * t
        swell = height * np.cos(np.clip(x / sigma, -1, 1) * math.pi * 0.5) ** 2
        # A slump travelling outward as it settles.
        slosh = 0.08 * math.sin(t * math.pi * 4.5) * np.cos(x * 4.0) * (1 - t) * float(rise)
        rim = np.maximum(swell + slosh, 0)
        c = smooth(rim - y, -0.012, 0.012)
        # Fully covering below the line, fading only at the sides, so the wave never shows through.
        fade = 1 - smooth(np.abs(x), 0.8, 1.0)
        below = smooth(-y, -0.012, 0.01) * (1 - smooth(-y, 0.012, 0.045)) * fade
        c = np.maximum(c * fade, np.clip(below * (rim > 0.002), 0, 1))
        cover.append(np.clip(c, 0, 1))
        s = sc.sample(cloud, x * 0.5 + 0.5, y * 0.8 + t * 0.6, t)
        shade.append(np.clip(0.5 + 0.42 * s + 0.1 * smooth(y, 0.0, 0.5), 0, 1))
        e = np.exp(-((y - rim) / 0.05) ** 2) * fade * smooth(rim, 0.02, 0.1)
        edge.append(np.clip(e, 0, 1))
    return {"mound": np.stack(cover), "mound_shade": np.stack(shade), "mound_edge": np.stack(edge)}


def gen(work):
    os.makedirs(work, exist_ok=True)
    art = {}
    art["leaf"] = gen_leaf()
    art["vines"] = gen_vines()
    art.update(gen_halo())
    art.update(gen_rings())
    art["drop"] = gen_drop()
    art["veil"] = gen_veil()
    art["dome"] = gen_dome()
    art.update(gen_beam())
    art.update(gen_mound())
    np.savez(os.path.join(work, "art.npz"), **{k: (np.clip(v, 0, 1) * 255 + 0.5).astype(np.uint8) for k, v in art.items()})
    print({k: v.shape for k, v in art.items()})


class Lib:
    def __init__(self, work):
        with np.load(os.path.join(work, "art.npz")) as z:
            self.d = {k: z[k].astype(np.float32) / 255 for k in z.files}

    def __getitem__(self, k):
        return self.d[k]

    def flip(self, key, pos):
        """Crossfaded flipbook frame at pos in 0..1 of the book, not wrapping."""
        a = self.d[key]
        x = min(max(pos, 0.0), 0.9999) * (len(a) - 1)
        i = int(x)
        f = x - i
        return a[i] * (1 - f) + a[min(i + 1, len(a) - 1)] * f

    def loop(self, key, pos):
        a = self.d[key]
        x = (pos % 1) * len(a)
        i = int(x)
        f = x - i
        return a[i % len(a)] * (1 - f) + a[(i + 1) % len(a)] * f


# -- compositing --------------------------------------------------------------------------------

def stamp_rect(c, img, cx, cy, w, h, color, alpha, ang=0.0, mask=None):
    if alpha <= 0.003 or w < 1 or h < 1:
        return
    H, W = c.shape[:2]
    pad = math.hypot(w, h) * 0.5 + 2
    x0, y0 = max(0, int(cx - pad)), max(0, int(cy - pad))
    x1, y1 = min(W, int(cx + pad) + 1), min(H, int(cy + pad) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    ih, iw = img.shape[:2]
    kx, ky = w / iw, h / ih
    cs, sn = math.cos(ang), math.sin(ang)
    M = np.array([[cs * kx, sn * ky, cx - x0 - cs * kx * iw / 2 - sn * ky * ih / 2],
                  [-sn * kx, cs * ky, cy - y0 + sn * kx * iw / 2 - cs * ky * ih / 2]], np.float32)
    p = cv2.warpAffine(img, M, (x1 - x0, y1 - y0), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    if mask is not None:
        for m_img, mx, my, msize in mask:
            p = p * fxc.stamp_sample(m_img, x0, y0, x1 - x0, y1 - y0, mx, my, msize)
    col = np.array(color, np.float32) * min(alpha, 1.0)
    c[y0:y1, x0:x1] = np.clip(c[y0:y1, x0:x1] + p[..., None] * col, 0, 1)


def mix(sat, hot, a, b):
    return tuple(min(1.0, s * a + h * b) for s, h in zip(sat, hot))


class Panel(sc.Panel):
    def __init__(self, art, globe, tint, level):
        super().__init__(art, globe, tint)
        self.color = gc.HEALTH
        self.level = level

    def liquid_at(self, t):
        q = round(t * 15) / 15
        if self.cached_t == q:
            return self.cached.copy()
        col = gc.current(self.liq_art, q, self.color)
        self.cached = gc.composite(self.liq_art, col, self.level, q, self.color)
        self.cached_t = q
        return self.cached.copy()

    def level_row(self, t):
        return (1 - self.level) * self.globe


def env_on(t, at=0.0, rise=0.7):
    return s1((t - at) / rise)


def hash1(n):
    return fxc.hash1(n)


# Each draw(p, L, t, env) composites one option. env: its light (0..1, fade in).

def d_none(p, L, t, env):
    return p.finish(t, lambda c: None, lambda lq: lq, lambda c: None)


def d_upwell(p, L, t, env):
    return sf.draw(p, "upwell", t)


def d_halo(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    breath = 0.88 + 0.12 * math.sin(t * 2 * math.pi / 4.2)
    w = 2.8 * r
    h = w / 2
    cy_h = cy - 1.09 * r
    a_w = 0.62 * w / 2
    b_w = a_w * 0.31
    # The ring passes behind the crown of the glass and in front of it: the back arc under the
    # globe, the front arc with the glass (each half of the one sprite, by texcoords in the game).
    H_i = L["halo_glow"].shape[0]

    def half(img, top):
        out = img.copy()
        if top:
            out[H_i // 2:, :] = 0
        else:
            out[:H_i // 2, :] = 0
        return out

    def behind(c):
        stamp_rect(c, half(L["halo_glow"], True), cx, cy_h, w, h, sat, 0.62 * env * breath)
        stamp_rect(c, half(L["halo_core"], True), cx, cy_h, w, h, hot, 0.7 * env * breath)

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.22 * env * breath)
        gm = [(art.gmask, cx, cy, g)]
        # A soft pool of the halo's light on the top of the glass.
        fxc.stamp(c, art.corona, cx, cy - r * 0.97, g * 1.1, sat, 0.22 * env * breath, mask=gm)
        stamp_rect(c, half(L["halo_glow"], False), cx, cy_h, w, h, sat, 0.78 * env * breath)
        stamp_rect(c, half(L["halo_core"], False), cx, cy_h, w, h, hot, 0.95 * env * breath)
        # Two glints walking the ring, in no hurry.
        for k in range(2):
            a = t * 0.5 * (1 if k == 0 else -1) + k * math.pi * 0.8
            fx = cx + math.cos(a) * a_w
            fy = cy_h + math.sin(a) * b_w
            front_w = 0.5 + 0.5 * max(0.0, math.sin(a))
            fxc.stamp(c, art.mote, fx, fy, r * 0.42, hot, 0.7 * env * front_w)
        for i in range(1, 6):
            q = (t / 7.5 + i / 5.0) % 1
            x = (hash1(i * 3.7) - 0.5) * r * 0.8
            y = cy - r * 0.82 + q * r * 0.72
            fade = s1(q / 0.2) * (1 - s1((q - 0.45) / 0.55))
            fxc.stamp(c, art.mote, cx + x + math.sin(q * 5 + i) * r * 0.05, y, r * (0.1 + 0.05 * hash1(i * 7.1)), hot, 0.55 * fade * env, mask=gm)

    return p.finish(t, behind, lambda lq: lq, front)


def d_bloom(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    leaf_tint = mix(sat, hot, 0.9, 0.22)
    weight = sc.weight_mask(art, p)
    n = 12
    period = 9.5

    def leaf(c, i, mirror):
        lives = 1
        q = (t * lives / period + i / n + hash1(i * 5.3) * 0.08) % 1
        # Rim positions spread evenly over the top, mirrored in pairs, so it can't lean.
        a0 = math.radians(40 + 100 * ((i // 2) + 0.5) / (n // 2))
        if mirror:
            a0 = math.pi - a0
        d0 = r * (0.96 + 0.03 * hash1(i * 2.2))
        sx = cx + math.cos(a0) * d0
        sy = cy - math.sin(a0) * d0
        # Rises up and away, slower the further out, swaying.
        rise = 1 - (1 - q) ** 1.6
        px = sx + math.cos(a0) * rise * r * 0.42 + math.sin(q * 4.2 + i * 2.1) * r * 0.09 * (1 + q)
        py = sy - (0.42 + 0.46 * hash1(i * 3.3)) * rise * r * 1.05
        fade = s1(q / 0.14) * (1 - s1((q - 0.52) / 0.48))
        size = r * (0.27 + 0.13 * hash1(i * 9.9)) * (0.85 + 0.15 * q)
        pos = t / (2.8 + 1.5 * hash1(i * 1.1)) + hash1(i)
        img = L.loop("leaf", pos)
        ang = q * 2.6 + hash1(i * 4.4) * 6.28
        fxc.stamp(c, art.mote, px, py, size * 1.7, sat, 0.34 * fade * env)
        stamp_rect(c, img, px, py, size, size, leaf_tint, 0.8 * fade * env, ang=ang)

    def behind(c):
        fxc.stamp(c, art.corona, cx, cy, g * 1.55, sat, 0.22 * env * (0.9 + 0.1 * math.sin(t * 1.3)), mask=weight)
        for i in range(n):
            leaf(c, i, i % 2 == 0)

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.22 * env)

    return p.finish(t, behind, lambda lq: lq, front)


def d_vines(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    # Mock: 12 s of growth; the game would tie it to the spell's length from the cast.
    c0 = t % VINE_CYCLE
    grow = min(1.0, c0 / (VINE_CYCLE * 0.82))
    fade = 1 - s1((c0 - VINE_CYCLE * 0.95) / (VINE_CYCLE * 0.05))
    tint = mix(sat, hot, 0.8, 0.5)

    def behind(c):
        fxc.stamp(c, art.corona, cx, cy, g * 1.4, sat, 0.14 * fade * env, mask=sc.weight_mask(art, p))

    def front(c):
        gm = [(art.gmask, cx, cy, g)]
        img = L.flip("vines", grow)
        fxc.stamp(c, img, cx, cy, g, tint, 0.78 * fade * env, mask=gm)
        fxc.stamp(c, img, cx, cy, g, hot, 0.12 * fade * env, mask=gm)
        for side in (0, 1):
            x, y, q = sc_path(side)
            i = int(min(0.995, grow) * (len(x) - 1))
            px, py = cx + float(x[i]) * g / 2, cy - float(y[i]) * g / 2
            fxc.stamp(c, art.mote, px, py, g * 0.13, hot, 0.85 * (0.75 + 0.25 * math.sin(t * 2.8)) * fade * env * (1 - s1((grow - 0.9) / 0.1)), mask=gm)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, sat, 0.12 * fade * env, mask=None)

    return p.finish(t, behind, lambda lq: lq, front)


VINE_CYCLE = 11.0
_paths = None


def sc_path(side):
    global _paths
    if _paths is None:
        _paths = (vine_path(0), vine_path(1))
    return _paths[side]


def d_veil(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    breath = 0.9 + 0.1 * math.sin(t * 2 * math.pi / 5.0)
    w = 3.4 * r
    h = 1.7 * r

    def behind(c):
        veil = L.loop("veil", t / 7.5)
        stamp_rect(c, veil, cx, cy - h / 2, w, h, sat, 1.0 * env * breath, mask=sc.weight_mask(art, p))
        stamp_rect(c, veil, cx, cy - h / 2, w, h, hot, 0.32 * env * breath, mask=sc.weight_mask(art, p))
        fxc.stamp(c, art.corona, cx, cy, g * 1.3, sat, 0.2 * env * breath, mask=sc.weight_mask(art, p))

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.3 * env * breath)

    return p.finish(t, behind, lambda lq: lq, front)


def d_rain(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    H = 0.58 * g
    drops = []
    n = 8
    period = 5.2
    # Eight lanes spread evenly over the middle of the surface.
    lanes = [-0.62, 0.18, -0.25, 0.62, 0.42, -0.5, 0.05, -0.08]
    for i in range(n):
        q = (t / period + i / n + hash1(i * 4.1) * 0.05) % 1
        fall = 0.36
        x = lanes[i] * g * 0.34
        drops.append((i, q, fall, x))

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.14 * env)
        fxc.stamp(c, sf.stretched(art, 1.0, 0.08), cx, surf, g, sat, 0.22 * env, mask=gm)
        for i, q, fall, x in drops:
            if q < fall:
                f = q / fall
                y = surf - H * (1 - f ** 1.45)
                a = s1(f / 0.3) * env
                stamp_rect(c, L["drop"], cx + x, y - g * 0.035, g * 0.04, g * 0.08, hot, 0.95 * a, mask=gm)
                fxc.stamp(c, art.mote, cx + x, y, g * 0.1, sat, 0.45 * a, mask=gm)
            else:
                rq = (q - fall) / (1 - fall)
                w = g * (0.08 + 0.72 * (1 - (1 - rq) ** 2.2))
                a = (1 - rq) ** 1.6 * env
                stamp_rect(c, L["ring_band"], cx + x, surf, w, w * 0.25, sat, 0.6 * a, mask=gm)
                stamp_rect(c, L["ring_core"], cx + x, surf, w, w * 0.25, hot, 0.62 * a, mask=gm)
                if rq > 0.12:
                    w2 = w * 0.55
                    a2 = (1 - rq) ** 2 * env
                    stamp_rect(c, L["ring_core"], cx + x, surf, w2, w2 * 0.25, hot, 0.34 * a2, mask=gm)
                if rq < 0.25:
                    fxc.stamp(c, art.mote, cx + x, surf, g * 0.14, hot, 0.8 * (1 - rq / 0.25) ** 1.4 * env, mask=gm)

    def in_liquid(lq):
        tmp = np.zeros_like(lq)
        lv = p.level_row(t)
        for i, q, fall, x in drops:
            if q >= fall:
                rq = (q - fall) / (1 - fall)
                fxc.stamp(tmp, art.corona, g / 2 + x, lv, g * 0.32, sat, 0.34 * (1 - rq) ** 1.5 * env)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, lambda c: None, in_liquid, front)


def d_embers(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    gm = [(art.gmask, cx, cy, g)]
    n = 13
    period = 10.0
    # Evenly spaced lanes over the top two thirds of the glass (mirrored pairs, centre-heavy).
    lanes = [-0.15, 0.3, -0.5, 0.05, 0.62, -0.32, 0.45, -0.7, 0.18, -0.05, 0.75, -0.6, 0.0]

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.14 * env)
        for i in range(1, n + 1):
            sp = 1 + (i % 3 == 0) * 0.35
            q = (t * sp / period + hash1(i * 5.7)) % 1
            lane = lanes[i - 1] * 0.72 * r
            y = cy + r * 0.86 - q * r * 1.74
            chord = math.sqrt(max(0.03, 1 - ((cy - y) / r) ** 2))
            x = cx + lane * chord + math.sin(q * 9 + i * 1.9) * r * 0.06
            fade = s1(q / 0.14) * (1 - s1((q - 0.72) / 0.28))
            tw = 0.84 + 0.16 * math.sin(t * (0.9 + hash1(i)) * 2 + i)
            size = g * (0.07 + 0.04 * hash1(i * 2.1))
            fxc.stamp(c, art.mote, x, y, size * 3.0, sat, 0.34 * fade * tw * env, mask=gm)
            fxc.stamp(c, art.mote, x, y, size * 1.05, hot, 0.9 * fade * tw * env, mask=gm)

    return p.finish(t, lambda c: None, lambda lq: lq, front)


def d_pulse(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    lv = p.level_row(t)
    D = 0.62 * g
    tq = (t % HOT_PERIOD) / HOT_PERIOD
    ts = t % HOT_PERIOD
    rise = 1.15

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.1 * env)
        if ts >= rise:
            a = (ts - rise) / 0.9
            if a <= 1:
                ca = (1 - a) ** 1.4 * env
                ww = g * (0.55 + 0.45 * a)
                fxc.stamp(c, sf.stretched(art, 1.0, 0.09), cx, surf, ww, sat, 0.9 * ca, mask=gm)
                fxc.stamp(c, sf.stretched(art, 1.0, 0.04), cx, surf, ww * 0.65, hot, 1.1 * ca, mask=gm)
                dome = L["dome"]
                fxc.stamp(c, dome, cx, surf - g * 0.05, g * 0.8, sat, 0.42 * ca * (1 - a), mask=gm)
                fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.28 * ca)

    def in_liquid(lq):
        if ts >= rise:
            return lq
        tmp = np.zeros_like(lq)
        f = ts / rise
        y = lv + D * (1 - f)
        fade = s1(f / 0.25) * env
        w = g * 0.64
        stamp_rect(tmp, L["ring_band"], g / 2, y + g * 0.02, w, w * 0.25, sat, 0.95 * fade)
        stamp_rect(tmp, L["ring_core"], g / 2, y, w, w * 0.25, hot, 0.6 * fade)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, lambda c: None, in_liquid, front)


# One-off heals: a moment at `age` seconds after the cast (None between casts).

def shot_age(t):
    a = (t - 0.8) % ONE_SHOT
    return a


def d_mend(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    age = shot_age(t)
    dur = 1.25
    q = min(age / dur, 1.0)
    glow = math.sin(min(q / 0.32, 1) * math.pi * 0.5) * (1 - s1((q - 0.25) / 0.75))
    size = g * (0.55 + 0.9 * (1 - (1 - q) ** 2))

    def front(c):
        fxc.stamp(c, L["dome"], cx, surf, size, sat, 0.95 * glow, mask=gm)
        fxc.stamp(c, L["dome"], cx, surf, size * 0.72, hot, 0.7 * glow, mask=gm)
        fxc.stamp(c, sf.stretched(art, 1.0, 0.07), cx, surf, g * 1.05, hot, 0.85 * glow, mask=gm)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.42 * glow)
        for i in range(8):
            mq = q * 1.25 - hash1(i * 3.1) * 0.25
            if 0 < mq < 1:
                x = (hash1(i * 6.7) - 0.5) * g * 0.7
                y = surf - g * (0.08 + 0.46 * (1 - (1 - mq) ** 2)) * (0.6 + 0.8 * hash1(i * 2.3))
                fxc.stamp(c, art.mote, cx + x, y, g * 0.07, hot, (1 - mq) ** 1.2 * 0.9, mask=gm)

    def behind(c):
        fxc.stamp(c, art.corona, cx, cy, g * 1.45, sat, 0.5 * glow, mask=sc.weight_mask(art, p))

    def in_liquid(lq):
        tmp = np.zeros_like(lq)
        lv = p.level_row(t)
        fxc.stamp(tmp, L["dome"][::-1], g / 2, lv, size * 0.55, sat, 0.42 * glow)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, behind, in_liquid, front)


def d_benediction(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    age = shot_age(t)
    q = min(age / 1.15, 1.0)
    beam = s1(q / 0.1) * (1 - s1((q - 0.32) / 0.4))
    ring_q = min(age / 1.0, 1.0)

    def behind(c):
        size = g * 2
        ring_a = math.sin(min(1.0, ring_q * 1.2) * math.pi) * (1 - ring_q) ** 0.3
        fxc.stamp(c, art.ring, cx, cy, size * (1.05 + 0.32 * (1 - (1 - ring_q) ** 3)), sat, 1.05 * ring_a, mask=sc.weight_mask(art, p))
        fxc.stamp(c, art.ring, cx, cy, size * (1.04 + 0.3 * (1 - (1 - ring_q) ** 3)), hot, 0.7 * ring_a, mask=sc.weight_mask(art, p))
        fxc.stamp(c, art.corona, cx, cy, g * 1.5, sat, 0.42 * beam, mask=sc.weight_mask(art, p))

    def front(c):
        # The beam stops at the level: a clip frame whose bottom is the fill guide.
        H = c.shape[0]
        layer = np.zeros_like(c)
        top = cy - r * 1.85
        length = surf - top
        stamp_rect(layer, L["beam_glow"], cx, top + length * 0.5, g * 0.72, length, sat, 0.95 * beam)
        stamp_rect(layer, L["beam_core"], cx, top + length * 0.5, g * 0.5, length, hot, 0.72 * beam)
        rows = np.arange(H, dtype=np.float32) + 0.5
        keep = np.clip(surf - rows + 1, 0, 1)[..., None, None]
        c[:] = np.clip(c + layer * keep, 0, 1)
        # Where it lands.
        spot = (1 - s1((q - 0.05) / 0.5))
        fxc.stamp(c, art.mote, cx, surf, g * 0.4, hot, 1.0 * spot * beam, mask=gm)
        rq = min(age / 0.75, 1.0)
        w = g * (0.12 + 0.9 * (1 - (1 - rq) ** 2.4))
        stamp_rect(c, L["ring_band"], cx, surf, w, w * 0.25, sat, 0.7 * (1 - rq) ** 1.2, mask=gm)
        stamp_rect(c, L["ring_core"], cx, surf, w, w * 0.25, hot, 1.0 * (1 - rq) ** 1.3, mask=gm)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.32 * beam)

    return p.finish(t, behind, lambda lq: lq, front)


def d_surge(p, L, t, env):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    age = shot_age(t)
    q = age / 1.15
    gm = [(art.gmask, cx, cy, g)]
    live = q < 1

    def front(c):
        if not live:
            return
        u = g * 0.42
        w = g * 1.15
        h = u * 1.12
        cover = L.flip("mound", q)
        shade = L.flip("mound_shade", q)
        edge = L.flip("mound_edge", q)
        # Bottom edge a little below the surface (the sprite is anchored to the fill guide).
        x0, y0 = int(cx - w / 2), int(surf - u)
        ww, hh = int(w), int(h)
        lift = cv2.resize(cover, (ww, hh), interpolation=cv2.INTER_LINEAR)
        body = cv2.resize(shade, (ww, hh), interpolation=cv2.INTER_LINEAR)
        lit = cv2.resize(edge, (ww, hh), interpolation=cv2.INTER_LINEAR)
        cx0, cy0 = max(0, x0), max(0, y0)
        lift, body, lit = (a[cy0 - y0:, cx0 - x0:][:c.shape[0] - cy0, :c.shape[1] - cx0] for a in (lift, body, lit))
        hh2, ww2 = lift.shape
        m = fxc.stamp_sample(art.gmask, cx0, cy0, ww2, hh2, cx, cy, g)
        a = (lift * m)[..., None]
        patch = c[cy0:cy0 + hh2, cx0:cx0 + ww2]
        patch = patch * (1 - a) + p.color[None, None] * body[..., None] * a
        patch = np.clip(patch + (lit * m)[..., None] * np.array(mix(sat, hot, 0.8, 0.3), np.float32) * 0.42, 0, 1)
        c[cy0:cy0 + hh2, cx0:cx0 + ww2] = patch
        # Light along the lifting surface and a touch through the glass as it rises.
        rise = math.sin(min(q / 0.45, 1) * math.pi * 0.5)
        fall = 1 - s1((q - 0.3) / 0.7)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.26 * rise * fall)
        fxc.stamp(c, art.corona, cx, surf - u * 0.3, g * 0.9, sat, 0.12 * rise * fall, mask=gm)

    def in_liquid(lq):
        tmp = np.zeros_like(lq)
        if live:
            lv = p.level_row(t)
            rise = math.sin(min(q / 0.45, 1) * math.pi * 0.5)
            fall = 1 - s1((q - 0.25) / 0.6)
            fxc.stamp(tmp, sf.stretched(art, 0.85, 0.5), g / 2, lv, g * 1.05, sat, 0.22 * rise * fall)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, lambda c: None, in_liquid, front)


def d_flare(p, L, t, env):
    """Today's one-off (BuildFlare, dir "in", FLARE seconds)."""
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    age = shot_age(t)
    q = min(age / FLARE, 1.0)
    glow = math.sin(q * math.pi)
    bloom = s1(q * 1.6) * (1 - q) ** 0.8 * 1.4
    ring = 1.7 - 0.7 * (1 - (1 - q) ** 3)
    size = g * 2

    def behind(c):
        fxc.stamp(c, art.corona, cx, cy, size * (0.95 + 0.1 * glow), sat, 0.9 * glow)
        ra = math.sin(min(1.0, q * 1.2) * math.pi)
        fxc.stamp(c, art.ring, cx, cy, size * ring, sat, 1.1 * ra)
        fxc.stamp(c, art.ring, cx, cy, size * ring * 0.99, hot, 0.7 * ra)

    def front(c):
        fxc.stamp(c, art.grim, cx, cy, g, hot, min(1, 0.6 * bloom))
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, 0.5 * bloom))

    return p.finish(t, behind, lambda lq: lq, front)


# -- options ------------------------------------------------------------------------------------

UPWELL_TINT = "nature"

OPTIONS = [
    {"name": "Upwell (today)", "fn": d_upwell, "tint": "nature", "hot": True, "now": True},
    {"name": "Halo", "fn": d_halo, "tint": "holy", "hot": True,
     "what": "A soft ring of gold light floating above the crown of the globe, two glints walking it, the top of the glass catching its light.",
     "suits": "Renew; any holy HoT.",
     "cost": "2 static 512x256 sprites, ring core and glow (1 MB), reused motes. No flipbook.",
     "limit": "Knows nothing but the cast. Nothing inside the liquid."},
    {"name": "Bloom", "fn": d_bloom, "tint": "nature", "hot": True,
     "what": "Glowing leaves drifting up off the top of the rim, tumbling, behind the globe. Faint top corona.",
     "suits": "Rejuvenation; Abolish Poison; nature HoTs.",
     "cost": "1 flipbook sprite sheet of tumbling leaves, 512x512 (1 MB); 16 moved sprites.",
     "limit": "Nothing to read; lives entirely above the rim, so it never touches the liquid."},
    {"name": "Vines", "fn": d_vines, "tint": "nature", "hot": True, "still_t": 9.6,
     "what": "Two vines climb the glass from the sides and meet at the crown, budding leaves as the buff runs. Grown fully it is a quiet wreath.",
     "suits": "Regrowth; Lifebloom-style long HoTs.",
     "cost": "16 growth stages of 256 px, 1024x1024 (4 MB).",
     "limit": "Growth is timed by the spell length from your own cast; a refresh restarts it. Shown here sped up (21 s in game).", "note": "sped up"},
    {"name": "Veil", "fn": d_veil, "tint": "holy", "hot": True,
     "what": "Soft curtains of aurora rising off the top of the rim, drifting slowly. The closest relative of seal radiance, but quieter and only over the crown.",
     "suits": "Renew, Rejuvenation; any long or stacked HoT.",
     "cost": "1 flipbook, 32 frames 256x128, 2048x512 (4 MB).",
     "limit": "Pure loop with no state: any HoT that is up can use it. Nothing in the liquid."},
    {"name": "Rain", "fn": d_rain, "tint": "water", "hot": True,
     "what": "Drops fall slowly through the glass and land on the surface in ripples. Ripples and drops ride the fill guide.",
     "suits": "Healing Stream, Mana Spring, Mana Tide (mana globe).",
     "cost": "Sprites only: 2 ring sprites 256x64, 1 drop 32x64, reused motes (under 0.2 MB).",
     "limit": "Each drop is positioned above the fill guide, so it lands in sync whatever the level; no value is read."},
    {"name": "Embers", "fn": d_embers, "tint": "nature", "hot": True,
     "what": "A few slow lights rise from the bottom of the globe right through the surface and fade under the glass.",
     "suits": "Frenzied Regeneration; Lifebloom; any HoT as a cheap fallback.",
     "cost": "13 reused mote sprites (no new art).",
     "limit": "Drawn in the glass layer, not clipped to the liquid, so it reads the level for nothing."},
    {"name": "Pulse", "fn": d_pulse, "tint": "holy", "hot": True, "still_t": 3.75,
     "what": "A thin ring rises through the liquid to the surface once per tick, the surface answering with a soft flash. Dark between ticks.",
     "suits": "Rejuvenation, Renew, Regrowth: every tick-based HoT.",
     "cost": "2 small ring sprites 256x64 and the dome 256x256 (under 0.5 MB), riding the fill guide.",
     "limit": "Ticks are predicted from the spell's period after your own cast (no aura read in combat). Others' HoTs on you can't be timed."},
    {"name": "Mend", "fn": d_mend, "tint": "holy", "hot": False,
     "what": "A warm dome of light swells off the surface, fading as it reaches the glass.",
     "suits": "Flash of Light, Holy Light, Flash Heal, Healing Touch (self).",
     "cost": "1 dome sprite 256x256 (0.25 MB), reused motes.",
     "limit": "Your own cast on yourself only; another healer's heal can't be seen in combat."},
    {"name": "Benediction", "fn": d_benediction, "tint": "holy", "hot": False,
     "what": "A short narrow beam from above strikes the surface; one ring spreads on the water, one swells off the rim.",
     "suits": "Greater Heal, Holy Light, Lay on Hands (on you).",
     "cost": "2 beam sprites 128x512 (0.5 MB), reused ring sprites.",
     "limit": "Own casts only. The beam stops at the level through the existing clip frame."},
    {"name": "Surge", "fn": d_surge, "tint": "holy", "hot": False,
     "what": "The liquid itself heaves up in a mound over the surface and slumps back. A fake lift: the real level does not move.",
     "suits": "Healing potions, healthstones, big single heals.",
     "cost": "16-frame mound flipbook 256x128: 1024x512 RGBA (coverage + baked shade) and 1024x512 lit edge (4 MB).",
     "limit": "The mound is a BLEND sprite in the liquid's colour riding the fill guide, not the real level; a look, not a physics change. Own casts and items only."},
]


def by_name(name):
    for o in OPTIONS:
        if o["name"].lower().startswith(name.lower()):
            return o
    raise SystemExit(name)


LEVELS = (0.6, 0.2)
REAL = 180
ZOOM = 306


class Board:
    def __init__(self, work):
        self.art = fxc.Art()
        self.L = Lib(work)
        self.panels = {}

    def panel(self, globe, tint, level):
        key = (globe, tint, level)
        if key not in self.panels:
            self.panels[key] = Panel(self.art, globe, tint, level)
        return self.panels[key]

    def render(self, opt, globe, level, t, tint=None, hot_env=True):
        p = self.panel(globe, tint or opt["tint"], level)
        env = env_on(t) if hot_env else 1.0
        return opt["fn"](p, self.L, t, env)

    def crop(self, p, img, tight=False, narrow=False):
        k = p.k
        x0 = int(p.cx - (100 if narrow else 118) * k)
        x1 = int(p.cx + (110 if narrow else 124) * k)
        y0 = max(0, int(p.cy - 165 * k))
        y1 = int(p.cy + (60 if tight else 104) * k)
        return img[y0:y1, x0:x1]

    def tile(self, opt, globe, level, t, tint=None, tight=False, title=None, narrow=False):
        p = self.panel(globe, tint or opt["tint"], level)
        img = self.crop(p, self.render(opt, globe, level, t, tint), tight, narrow)
        if title is not None:
            img = np.pad(img, ((26, 0), (0, 0), (0, 0)), constant_values=0.075)
            img = gc.label(img, title, (6, 3), size=17)
        return img


def wrap(lines, width):
    out = []
    for line in lines:
        out.extend(textwrap.wrap(line, width) or [""])
    return out


def compare_tile(b, opt, t, level, globe, tight=False):
    return b.tile(opt, globe, level, t, tight=tight, title=f"{opt['name']}  {int(level * 100)}%")


def page_option(b, opt, idx, total, t):
    """One option beside today's Upwell: real size left, zoom right, both fills, notes."""
    W, H = 1920, 1080
    out = np.full((H, W, 3), 0.06, np.float32)
    upw = OPTIONS[0]
    y0 = 62
    # Real size.
    x = 16
    tint = opt["tint"]
    upw_for = dict(upw)
    for row, level in enumerate(LEVELS):
        a = b.tile(upw_for, REAL, level, t, tint=tint, title=f"Upwell {int(level * 100)}%")
        o = b.tile(opt, REAL, level, t, title=f"{opt['name']} {int(level * 100)}%")
        h = a.shape[0]
        out[y0 + row * h:y0 + row * h + h, x:x + a.shape[1]] = a
        out[y0 + row * h:y0 + row * h + h, x + a.shape[1] + 2:x + 2 + 2 * a.shape[1]] = o
    rx = x + 2 * a.shape[1] + 20
    out = gc.label(out, f"real size (180 px globe), both beside today's Upwell", (x, 8), size=18)
    # Zoomed.
    zx = rx
    for row, level in enumerate(LEVELS):
        a = b.tile(upw_for, ZOOM, level, t, tint=tint, tight=True, title=f"Upwell {int(level * 100)}%  (zoom)")
        o = b.tile(opt, ZOOM, level, t, tight=True, title=f"{opt['name']} {int(level * 100)}%  (zoom)")
        h = a.shape[0]
        out[y0 + row * h:y0 + row * h + h, zx:zx + a.shape[1]] = a
        out[y0 + row * h:y0 + row * h + h, zx + a.shape[1] + 2:zx + 2 + 2 * a.shape[1]] = o
    tx = zx + 2 * a.shape[1] + 20
    notes = [opt["name"] + ("  (one-off heal)" if not opt["hot"] else "  (HoT)"), "", opt.get("what", ""), "", "Suits: " + opt.get("suits", ""), "", "Cost: " + opt.get("cost", ""), "", "In-game limits: " + opt.get("limit", "")]
    if opt.get("note"):
        notes.append("")
        notes.append("(Mock: " + opt["note"] + ")")
    yy = y0
    for ln in wrap(notes, 42):
        out = gc.label(out, ln, (tx, yy), size=16)
        yy += 22
    out = gc.label(out, f"{idx}/{total}", (W - 70, 8), size=18)
    return out


def page_overview(b, t, kind):
    W, H = 1920, 1080
    out = np.full((H, W, 3), 0.06, np.float32)
    if kind == "hot":
        opts = [o for o in OPTIONS if o["hot"]]
        title = "heals over time: every option, real size (180 px)"
    else:
        opts = [OPTIONS[0]] + [o for o in OPTIONS if not o["hot"]] + [{"name": "Flare (today)", "fn": d_flare, "tint": "holy", "hot": False}]
        title = "one-off heals: every option, real size (180 px). Casts repeat every 2.8 s"
    out = gc.label(out, title, (16, 10), size=22)
    x0 = 2
    y0 = 50
    for row, level in enumerate(LEVELS):
        x = x0
        for o in opts:
            tile = b.tile(o, REAL, level, t, title=f"{o['name']} {int(level * 100)}%", narrow=True)
            h, w = tile.shape[:2]
            if x + w > W:
                break
            out[y0 + row * (h + 8):y0 + row * (h + 8) + h, x:x + w] = tile
            x += w + 1
    return out


TIMELINE = None


def timeline():
    global TIMELINE
    if TIMELINE is None:
        pages = [("hot", None, 11.0)]
        for o in OPTIONS:
            if o["hot"] and not o.get("now"):
                pages.append(("option", o, 11.0 if o.get("note") == "sped up" else 8.5))
        pages.append(("heal", None, 6.5))
        for o in OPTIONS:
            if not o["hot"]:
                pages.append(("option", o, 7.0))
        TIMELINE = pages
    return TIMELINE


def duration():
    return sum(p[2] for p in timeline())


def frame_at(b, t):
    pages = timeline()
    start = 0.0
    n_opts = sum(1 for p in pages if p[0] == "option")
    idx = 0
    for kind, o, length in pages:
        if t < start + length:
            local = t - start
            if kind == "hot":
                return page_overview(b, local, "hot")
            if kind == "heal":
                return page_overview(b, local, "heal")
            idx = sum(1 for p in pages if p[0] == "option" and pages.index(p) <= pages.index((kind, o, length)))
            return page_option(b, o, idx, n_opts, local)
        start += length
    return page_overview(b, 0.0, "hot")


# -- check --------------------------------------------------------------------------------------

def check(work, name, out):
    b = Board(work)
    o = by_name(name)
    times = [0.9, 1.6, 2.5, 3.4, 4.3, 5.2] if o["hot"] else [0.8 + a for a in (0.08, 0.2, 0.36, 0.6, 0.85, 1.15)]
    rows = []
    for level in LEVELS:
        row = [b.tile(o, REAL, level, t, title=f"{o['name']} {level} t={t:.2f}") for t in times]
        rows.append(np.hstack(row))
    z = np.hstack([b.tile(o, ZOOM, 0.6, times[2], tight=True), b.tile(o, ZOOM, 0.2, times[2], tight=True), b.tile(OPTIONS[0], ZOOM, 0.6, times[2], tint=o["tint"], tight=True)])
    # Pad to same width
    W = max(r.shape[1] for r in rows + [z])
    def pad(a):
        return np.pad(a, ((0, 0), (0, W - a.shape[1]), (0, 0)), constant_values=0.07)
    sheet = np.vstack([pad(r) for r in rows] + [pad(z)])
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(out)
    print(out)


# -- still --------------------------------------------------------------------------------------

def still(work, out):
    b = Board(work)
    upw = OPTIONS[0]
    rows = []
    fontsize = 17
    head = gc.label(np.full((42, 1880, 3), 0.075, np.float32), "Heal effects, options against today's Upwell: real size, then zoomed, both at 60% and 20% fill", (8, 8), size=22)
    rows.append(head)
    for o in OPTIONS[1:]:
        t = o.get("still_t", 4.6) if o["hot"] else 0.8 + 0.3
        tiles = [b.tile(upw, REAL, 0.6, t, tint=o["tint"], title="Upwell 60%"), b.tile(o, REAL, 0.6, t, title=f"{o['name']} 60%"),
                 b.tile(upw, REAL, 0.2, t, tint=o["tint"], title="Upwell 20%"), b.tile(o, REAL, 0.2, t, title=f"{o['name']} 20%"),
                 b.tile(o, 230, 0.6, t, title=f"{o['name']} 60% zoomed"), b.tile(o, 230, 0.2, t, title=f"{o['name']} 20% zoomed")]
        H = max(t_.shape[0] for t_ in tiles)
        for i, tl in enumerate(tiles):
            pad_y = (H - tl.shape[0])
            tiles[i] = np.pad(tl, ((0, pad_y), (0, 2), (0, 0)), constant_values=0.075)
        rows.append(np.hstack(tiles))
    W = max(r.shape[1] for r in rows)
    def pad(a):
        return np.pad(a, ((0, 0), (0, W - a.shape[1]), (0, 0)), constant_values=0.075)
    sheet = np.vstack([pad(r) for r in rows])
    if W > 2100:
        k = 2100 / W
        sheet = cv2.resize(sheet, (2100, int(sheet.shape[0] * k)), interpolation=cv2.INTER_AREA)
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(out, optimize=True)
    print(out, sheet.shape, os.path.getsize(out) // 1024, "KB")


# -- metrics ------

def metrics(work, out):
    """Calmness and colour numbers per option: added light on the liquid and its green shift (does it
    drown the red?), and frame-to-frame change of the whole tile (does it strobe?)."""
    b = Board(work)
    none = {"name": "none", "fn": d_none, "tint": "nature", "hot": True}
    lines = ["option, tint, level, mean_added_on_liquid(0-1), mean_G_added, p99_frame_step(0-1), peak_tile_step"]
    for o in OPTIONS:
        for level in LEVELS:
            p = b.panel(REAL, o["tint"], level)
            x, y = p.globe_rect
            g = p.globe
            rows = np.arange(g, dtype=np.float32) + 0.5
            mask = np.clip(rows - p.level_row(0), 0, 1)[..., None] * p.circle[..., None]
            added, green, steps = [], [], []
            ts = np.linspace(2.0, 9.5, 24)
            prev = None
            for t in ts:
                img = b.render(o, REAL, level, float(t))
                base = b.render(none, REAL, level, float(t), tint=o["tint"])
                d = (img - base)[y:y + g, x:x + g]
                added.append(float((np.abs(d) * mask).sum() / (mask.sum() * 3)))
                green.append(float((d[..., 1] * mask[..., 0]).sum() / mask.sum()))
                if prev is not None:
                    steps.append(float(np.abs(img - prev).mean()))
                prev = img
            # finer step: t and t + 1/30
            fine = []
            for t in ts[:8]:
                a = b.render(o, REAL, level, float(t))
                c = b.render(o, REAL, level, float(t) + 1 / 30)
                fine.append(float(np.percentile(np.abs(a - c), 99.5)))
            lines.append(f"{o['name']}, {o['tint']}, {level}, {np.mean(added):.3f}, {np.mean(green):.3f}, {np.mean(fine):.3f}, {np.max(fine):.3f}")
    open(out, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


# -- video --------------------------------------------------------------------------------------

BOARD = None


def init_worker(work):
    global BOARD
    os.nice(19)
    cv2.setNumThreads(1)
    BOARD = Board(work)


def render_frame(t):
    return np.clip(frame_at(BOARD, t) * 255, 0, 255).astype(np.uint8).tobytes()


def video(work, path):
    import imageio_ffmpeg

    fps = 30
    n = int(duration() * fps)
    writer = imageio_ffmpeg.write_frames(path, (1920, 1080), fps=fps, codec="libx264", bitrate="2100k", pix_fmt_out="yuv420p", macro_block_size=1, ffmpeg_log_level="error", output_params=["-preset", "slow"])
    writer.send(None)
    with mp.Pool(16, init_worker, (work,)) as pool:
        for i, data in enumerate(pool.imap(render_frame, [i / fps for i in range(n)], chunksize=3)):
            writer.send(data)
            if i % 120 == 0:
                print(i, n, flush=True)
    writer.close()
    print(path, os.path.getsize(path) / 1e6, "MB", n / fps, "s")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "art":
        gen(sys.argv[2])
    elif mode == "check":
        check(sys.argv[2], sys.argv[3], sys.argv[4])
    elif mode == "still":
        still(sys.argv[2], sys.argv[3])
    elif mode == "metrics":
        metrics(sys.argv[2], sys.argv[3])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
