"""Sheets for the surge styles in GlobeAura.lua (SURGE_ART): Inhale, Pour and Upwell.

Procedural numpy art, grown from globe_surge_concepts.py, luminance only so TINTS colours it. What
moves fast or lands somewhere (Inhale's streaks, Pour's droplets, Upwell's motes) is not in here:
those are sprites the addon moves every frame, so they never ghost between flipbook frames.

Each generator returns {name: frames} with frames shaped (n, h, w), 0..1, looping seamlessly.
"""
import math

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates
from scipy.special import ndtr

FRAMES = 32
SETTLE = 0.8  # frames of circular smoothing: noise differing frame to frame flashes in game


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise3(shape, scales, seed, power=1.1):
    """Noise periodic on all three axes, stretched per axis, evened out to 0..1."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(shape, dtype=np.float32)
    grids = np.meshgrid(*[np.fft.fftfreq(n) * n for n in shape], indexing="ij", sparse=True)
    r2 = sum((g / s) ** 2 for g, s in zip(grids, scales))
    out = np.fft.ifftn(np.fft.fftn(white) / (1 + r2) ** power).real
    return ndtr((out - out.mean()) / out.std()).astype(np.float32)


def sample(n, u, v, w):
    su, sv, sw = n.shape
    u, v, w = np.broadcast_arrays(u, v, w)
    return map_coordinates(n, [(u % 1) * su, (v % 1) * sv, (w % 1) * sw], order=1, mode="grid-wrap").astype(np.float32)


def rect(w, h, x0, x1, y0, y1):
    """Pixel centres of a w by h cell spanning x0..x1, y0 (top)..y1 (bottom)."""
    xs = x0 + (np.arange(w, dtype=np.float32) + 0.5) / w * (x1 - x0)
    ys = y0 + (np.arange(h, dtype=np.float32) + 0.5) / h * (y1 - y0)
    return np.meshgrid(xs, ys)


def settle(frames):
    return np.clip(gaussian_filter1d(np.stack(frames), SETTLE, axis=0, mode="wrap"), 0, 1)


def gen_inhale(cell=256):
    """Rays behind the globe, running inward: 2x the globe, x and y -1..1, the rim at 0.5."""
    x, y = rect(cell, cell, -1, 1, 1, -1)
    r = np.hypot(x, y)
    rho = r / 0.5
    th = np.arctan2(y, x)
    fine = noise3((1024, 48, FRAMES), (20, 2.0, 2.0), 11, 1.1)
    coarse = noise3((128, 16, FRAMES), (3.0, 1.2, 1.5), 12)
    rays = []
    for i in range(FRAMES):
        t = i / FRAMES
        u = th / (2 * math.pi) * 5  # five-fold, so it can't lean
        n = sample(fine, u, 0.34 * rho ** 1.5 + t, t)
        p = sample(coarse, u * 0.6, 0.45 * rho ** 1.5 + t, t)
        streak = smooth(n, 0.52, 0.93) ** 1.5
        outer = 1 - smooth(rho, 1.0, 2.25)
        rim = np.exp(-np.maximum(rho - 1, 0) / 0.13)
        sat = streak * outer ** 2.1 * (0.3 + 1.15 * p) * 1.2
        sat = sat + rim * (0.42 + 0.75 * p) * 0.75 + np.exp(-np.maximum(rho - 1, 0) / 0.5) * 0.2
        rays.append(np.clip(sat * (r >= 0.42), 0, 1))
    return {"rays": settle(rays)}


def gen_pour(w=128, h=256, under_w=256, under_h=128):
    """The column: half the globe wide and the globe tall (x -0.25..0.25, y 0.5..-0.5 of the globe),
    its top behind the ring, so it comes from the ring and nothing floats above it. Under: 1.2 by
    0.6 of the globe, 0.05 above the surface to 0.55 below it."""
    x, y = rect(w, h, -0.25, 0.25, 0.5, -0.5)
    streaks = noise3((128, 48, FRAMES), (14, 3.5, 1.6), 21, 1.0)
    cols, glows = [], []
    for i in range(FRAMES):
        t = i / FRAMES
        fall = np.clip((0.5 - y) / 1.0, 0, 1)
        hw = 0.021 + 0.028 * fall ** 0.8
        sway = 0.006 * np.sin(y * 9 + t * 2 * math.pi * 2)
        nx = (x + sway) / hw
        n = sample(streaks, nx * 0.11, y * 0.9 + t * 3, t)
        core = np.exp(-(nx / 0.85) ** 2) * (0.55 + 0.75 * smooth(n, 0.25, 0.9))
        body = np.exp(-(nx / 2.1) ** 2) * (0.3 + 0.9 * smooth(n, 0.4, 0.95))
        halo = np.exp(-(x / 0.16) ** 2) * 0.14 * (1 - smooth(np.abs(x), 0.17, 0.25))
        cols.append(core * 1.1)
        glows.append((body * 0.65 + halo))

    x, y = rect(under_w, under_h, -0.6, 0.6, 0.05, -0.55)
    fans = noise3((256, 32, FRAMES), (7, 2.0, 1.6), 22, 1.25)  # wide soft shafts, not a burst of lines
    unders = []
    for i in range(FRAMES):
        t = i / FRAMES
        R = np.hypot(x, y)
        phi = np.arctan2(x, -y)
        f = sample(fans, phi / 2.6 + 0.5, R * 0.8 - t * 1, t)
        fan = smooth(f, 0.32, 1.0) * np.exp(-R / 0.3) * (1 - smooth(np.abs(phi), 0.55, 1.35)) * 0.62
        rings = np.zeros_like(x)
        for k in range(3):
            q = (t * 2 + k / 3) % 1
            a = 0.05 + 0.5 * q ** 0.75
            e = np.hypot(x / a, y / (a * 0.16)) - 1
            rings += np.exp(-(e / (0.16 / (1 + 2 * q))) ** 2) * (1 - q) ** 1.5
        volume = np.exp(-((x / 0.24) ** 2 + ((y + 0.06) / 0.2) ** 2)) * 0.34
        spot = np.exp(-((x / 0.075) ** 2 + (y / 0.1) ** 2)) * 0.5
        fade = 1 - smooth(y, 0.0, 0.05)  # nothing against the cell's top edge
        low = 1 - smooth(-y, 0.42, 0.55)
        unders.append(((fan + rings * 0.75 + volume) * low + spot) * fade)
    return {"col": settle(cols), "glow": settle(glows), "under": settle(unders)}


def gen_upwell(cell=256):
    """Plumes in the liquid, the globe's own size. Bright all the way down: heals are cast when
    the globe is low, and the liquid is then only this art's lower part."""
    x, y = rect(cell, cell, -1, 1, 1, -1)
    plume = noise3((192, 192, FRAMES), (3.2, 2.4, 1.5), 31, 1.6)
    wisp = noise3((256, 192, FRAMES), (7, 3.0, 1.6), 32, 1.5)
    warp = noise3((96, 96, FRAMES), (1.6, 1.2, 1.2), 33, 1.7)
    bodies, cores = [], []
    for i in range(FRAMES):
        t = i / FRAMES
        wx = (sample(warp, x * 0.5 + 0.5, y * 0.5 - t, t) - 0.5) * 0.42
        h = (y + 1) / 2
        half = 0.44 + 0.34 * h ** 1.1
        col = np.exp(-((x + wx) / half) ** 2)
        p = sample(plume, (x + wx) * 0.5 + 0.5, y * 0.5 - t, t)
        w = sample(wisp, (x + wx) * 0.5 + 0.5, y * 0.5 - t, t)
        body = col * (0.22 + 0.95 * smooth(p, 0.38, 0.95) ** 1.1) * (0.92 + 0.08 * h) * 0.9
        strand = smooth(w, 0.6, 0.98) ** 1.4 * col ** 0.7 * 0.85
        base = np.exp(-((x + wx * 0.5) ** 2 / 0.3 + (y + 1.02) ** 2 / 0.16)) * (0.72 + 0.2 * math.sin(t * 2 * math.pi * 2))
        bodies.append(body)
        cores.append(strand + base * 0.9)
    return {"body": settle(bodies), "core": settle(cores)}


def streak(size=128):
    """One streak of light, its head low and its tail fading upward. In the art the streak spans
    STREAK_SPAN of the height, so the addon can size it by its length."""
    y = (np.arange(size, dtype=np.float32) + 0.5) / size
    x = (np.arange(size, dtype=np.float32) + 0.5) / size - 0.5
    X, Y = np.meshgrid(x, y)
    v = np.clip((Y - 0.1) / 0.78, 0, 1)
    inside = (Y > 0.1) & (Y < 0.92)
    width = 0.012 + 0.036 * v ** 1.2
    line = np.exp(-(X / width) ** 2) * v ** 1.5 * inside
    head = np.exp(-(X ** 2 + (Y - 0.84) ** 2) / 0.0024) * 0.8
    return cv2.GaussianBlur(np.clip(line + head, 0, 1).astype(np.float32), (0, 0), 0.8)
