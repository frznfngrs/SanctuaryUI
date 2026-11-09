"""Sheets for the heal looks in GlobeAura.lua: the HoTs (Vines, Halo, Bloom, Veil, Rain, Pulse,
Embers) and the one-off heals (Mend, Benediction, Surge).

Procedural numpy art, white luminance in the alpha unless noted, tinted by GlobeAura.lua's TINTS.
Grown from tools/blender/globe_heals.py, the prototype the looks were chosen from. What moves fast
or lands somewhere (drops, ripples, motes, glints) is not in here: those are sprites the addon
moves every frame, so they never ghost between flipbook frames.

Frames are smoothed over time in the build (circularly for the loops, one-sided for the one-shots
and the growth): noise differing frame to frame flashes in game.

    build(out)   write every sheet into the directory out

heal-leaf.png    16 frames of a tumbling leaf, 128 cells, 4 cols, 512x512. The art is drawn into the
                 middle 70% of its cell so the addon can turn it inside its own cell with texcoords
heal-vines.png   16 growth stages, 256 cells, 4 cols, 1024x1024
heal-halo.png    ring core over ring glow, 512x256 each, 512x512
heal-rings.png   ripple core over ripple band, 256x64 each, 256x128
heal-drop.png    a falling drop, 32x64
heal-dome.png    a dome of rays, 256x256, surface across the middle
heal-veil.png    32 looping frames of aurora, 256x128 cells, 8 cols, 2048x512
heal-beam.png    beam core beside beam glow, 128x512 each, 256x512
heal-mound.png   16 frames, 256x128 cells, 8 cols, 2048x512: rows 0-1 the liquid's swell for BLEND
                 (colour = its cloudy shading, alpha = its coverage), rows 2-3 its lit edge for ADD
"""
import math

import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d, map_coordinates
from scipy.special import ndtr

LEAF_CELL = 128
LEAF_FRAMES = 16
LEAF_KEEP = 0.707  # of its cell the leaf is drawn into (GlobeAura.lua SpinCell samples this much)
VINE_CELL = 256
VINE_STAGES = 16
VEIL_FRAMES = 32
MOUND_FRAMES = 16

# Frames of smoothing over time; see the module note.
SMOOTH_LOOP = 0.8
SMOOTH_SHOT = 0.6


def smooth(x, a=0.0, b=1.0):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


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


def settle_loop(frames):
    return np.clip(gaussian_filter1d(np.stack(frames), SMOOTH_LOOP, axis=0, mode="wrap"), 0, 1)


def settle_shot(frames, sigma=SMOOTH_SHOT):
    return np.clip(gaussian_filter1d(np.stack(frames), sigma, axis=0, mode="nearest"), 0, 1)


# -- leaf ---------------------------------------------------------------------------------------

def leaf_frame(roll, pitch, yaw, fold, arch, cell=LEAF_CELL, ss=4):
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
            n = n / (np.linalg.norm(n) + 1e-6)
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


def fit_middle(img, keep):
    """The picture shrunk into the middle `keep` of its cell, so turning texcoords can't reach out of it."""
    h, w = img.shape
    ch, cw = max(1, int(h * keep)), max(1, int(w * keep))
    small = cv2.resize(img, (cw, ch), interpolation=cv2.INTER_AREA)
    out = np.zeros((h, w), np.float32)
    y, x = (h - ch) // 2, (w - cw) // 2
    out[y:y + ch, x:x + cw] = small
    return out


def gen_leaf():
    frames = []
    for i in range(LEAF_FRAMES):
        f = i / LEAF_FRAMES
        roll = f * 2 * math.pi
        pitch = 0.62 * math.sin(f * 2 * math.pi)
        yaw = 0.3 * math.sin(f * 2 * math.pi + 1.1)
        frames.append(fit_middle(leaf_frame(roll, pitch, yaw, fold=0.42, arch=0.45), LEAF_KEEP))
    return settle_loop(frames)


# -- vines --------------------------------------------------------------------------------------

def vine_path(side, n=240):
    """Polar path up one side of the glass, cell coordinates (the globe's circle radius is 1).
    GlobeAura.lua VineTip follows the same curve."""
    sgn = -1 if side == 0 else 1
    q = np.linspace(0, 1, n, dtype=np.float32)
    # From where the gargoyle and the console wall let go of the rim, up to nearly the crown.
    th = np.radians(74 - (74 - 5) * q) * sgn
    th = th + np.radians(2.2) * np.sin(q * 11 + side * 1.7) * (1 - q) ** 0.3 * sgn
    rad = 0.858 + 0.016 * np.sin(q * 15 + side * 2.1)
    return np.sin(th) * rad, np.cos(th) * rad, q


def leaflet(canvas, cell, x, y, ang, length, value, ss):
    """A small almond leaf at (x, y) pointing along ang, drawn on a supersampled canvas."""
    w = length * 0.42
    u = np.linspace(0, 1, 14, dtype=np.float32)
    wd = np.maximum(np.sin(np.pi * u ** 0.75), 0) ** 0.9 * w
    ca, sa = math.cos(ang), math.sin(ang)
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
    # A growth front eased over its neighbours; the first and last stages stay put.
    return settle_shot(frames, 0.45)


# -- halo, rings, drop, dome, beam ---------------------------------------------------------------

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
    return np.clip(core, 0, 1), np.clip(glow, 0, 1)


def gen_rings():
    x, y = rect_grid(256, 64, -1, 1, 0.25, -0.25)
    a = 0.86
    e = np.hypot(x / a, y / (a * 0.22)) - 1
    core = np.exp(-(e / 0.04) ** 2)
    band = np.exp(-(np.abs(e) / 0.16) ** 1.2)
    return np.clip(core, 0, 1), np.clip(band, 0, 1)


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
    return np.clip(core, 0, 1), np.clip(glow, 0, 1)


# -- veil, mound --------------------------------------------------------------------------------

def gen_veil():
    """An aurora hugging the top of the rim: curtains of light rising off it, fading outward.
    Cell x -1.7..1.7 and y 0..1.7 of the globe's radius; the rim at rho 1."""
    n = VEIL_FRAMES
    x, y = rect_grid(256, 128, -1.7, 1.7, 1.7, 0.0)
    rho = np.hypot(x, y)
    th = np.arctan2(x, np.maximum(y, 1e-3))
    curt = noise3((640, 24, n), (15, 2.0, 1.6), 51, 1.2)
    ribbon = noise3((256, 8, n), (5, 1.2, 1.4), 52, 1.4)
    frames = []
    for i in range(n):
        t = i / n
        # Curtains are vertical folds (in x, not radial), so this isn't radiance's sunburst.
        u = (x / 3.4 + 0.5) * 2  # no sideways drift: every moving term must be whole cycles over the loop
        streak = smooth(sample(curt, u, y * 0.12 + t, t), 0.3, 0.95)
        band = smooth(sample(ribbon, th / (2 * math.pi) * 3, 0.0, t), 0.25, 0.95)
        # A curtain's foot sits on the rim, brightest there, fading up and over the top.
        edge = 1.02 + 0.06 * band
        rise = np.exp(-np.maximum(rho - edge, 0) / 0.26) * smooth(rho, 0.96, 1.0) * (1 - smooth(rho, 1.28, 1.62))
        top = 1 - smooth(np.abs(th), math.radians(62), math.radians(112))
        frames.append(np.clip((0.5 + 0.6 * streak) * rise * (0.42 + 0.7 * band) * top, 0, 1))
    return settle_loop(frames)


def gen_mound():
    """The liquid lifting: a rounded swell over the surface. coverage, its own cloudy shading (the
    liquid's colour tints it in the game) and a lit edge. y is 0 at the surface; the cell starts a
    little below it so the sprite covers the surface's own wave. Drawn BLEND, one stepped frame at
    a time (GlobeAura.lua): two "over" layers must never crossfade."""
    w, h, n = 256, 128, MOUND_FRAMES
    x, y = rect_grid(w, h, -1, 1, 1, -0.12)
    cloud = noise3((64, 128, 16), (3.0, 2.0, 2.0), 41, 1.4)
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
        s = sample(cloud, x * 0.5 + 0.5, y * 0.8 + t * 0.6, t)
        shade.append(np.clip(0.5 + 0.42 * s + 0.1 * smooth(y, 0.0, 0.5), 0, 1))
        e = np.exp(-((y - rim) / 0.05) ** 2) * fade * smooth(rim, 0.02, 0.1)
        edge.append(np.clip(e, 0, 1))
    return settle_shot(cover), settle_shot(shade, 0.8), settle_shot(edge)


# -- sheets -------------------------------------------------------------------------------------

def to8(a):
    return np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)


def save_white(alpha, path):
    """White art, the luminance in the alpha (ADD, tinted in the addon)."""
    white = np.full(alpha.shape, 255, np.uint8)
    Image.merge("RGBA", [Image.fromarray(c) for c in (white, white, white, to8(alpha))]).save(path, optimize=True)


def sheet(frames, cols, cw, ch, w, h, row=0):
    out = np.zeros((h, w), np.float32)
    for i, f in enumerate(frames):
        y, x = divmod(i, cols)
        y += row
        out[y * ch:(y + 1) * ch, x * cw:(x + 1) * cw] = f
    return out


def build(out):
    save_white(sheet(gen_leaf(), 4, LEAF_CELL, LEAF_CELL, 512, 512), f"{out}/heal-leaf.png")
    save_white(sheet(gen_vines(), 4, VINE_CELL, VINE_CELL, 1024, 1024), f"{out}/heal-vines.png")
    core, glow = gen_halo()
    save_white(np.vstack([core, glow]), f"{out}/heal-halo.png")
    core, band = gen_rings()
    save_white(np.vstack([core, band]), f"{out}/heal-rings.png")
    save_white(gen_drop(), f"{out}/heal-drop.png")
    save_white(gen_dome(), f"{out}/heal-dome.png")
    save_white(sheet(gen_veil(), 8, 256, 128, 2048, 512), f"{out}/heal-veil.png")
    core, glow = gen_beam()
    save_white(np.hstack([core, glow]), f"{out}/heal-beam.png")

    cover, shade, edge = gen_mound()
    w, h = 2048, 512
    rgb = sheet(shade, 8, 256, 128, w, h)  # the shading fills its cells; the edge's rows stay white
    rgb[256:, :] = 1.0
    alpha = sheet(cover, 8, 256, 128, w, h)
    alpha[256:, :] = sheet(edge, 8, 256, 128, w, 256)
    channels = [Image.fromarray(to8(rgb)) for _ in range(3)] + [Image.fromarray(to8(alpha))]
    Image.merge("RGBA", channels).save(f"{out}/heal-mound.png", optimize=True)
