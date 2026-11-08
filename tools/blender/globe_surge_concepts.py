"""Three ideas for "power pouring into a globe", to replace the rim swirl (GlobeAura.lua surge).
Procedural numpy art, the same way the seals' rays and corona are built, so no GPU is needed.

  python globe_surge_concepts.py gen   WORK         render every loop into WORK/*.npz
  python globe_surge_concepts.py still WORK OUT.png
  python globe_surge_concepts.py video WORK OUT.mp4

Concepts (white luminance art; each is a sat map and a hot map, tinted like TINTS):
  inhale   the seals' rays run backwards: streaks behind the globe rushing in to the glass, the
           glass flashing where each one lands
  pour     a column of light falling through the glass into the liquid, splashing on the surface
           and sending shafts down through it; rides the fill level
  upwell   the liquid itself fed from below: plumes rising through it, the surface lit from
           under; drawn in the liquid clip
"""
import math
import multiprocessing as mp
import os
import sys

import cv2
import numpy as np
from scipy.ndimage import map_coordinates
from scipy.special import ndtr

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402
import globe_fx_compare as fxc  # noqa: E402

FRAMES = 36
LOOP = 3.0  # seconds
CELL_FX = 320  # art covering twice the globe
CELL_IN = 256  # art covering the globe
CYCLE = 8.0

TINTS = {
    "arcane": ((0.16, 0.42, 1.0), (0.62, 0.84, 1.0)),
    "blood": ((0.9, 0.08, 0.05), (1.0, 0.55, 0.4)),
}
LIQUID = {"arcane": np.array([0.18, 0.36, 1.0], np.float32), "blood": np.array([0.86, 0.07, 0.05], np.float32)}


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


def grid(cell):
    c = (np.arange(cell, dtype=np.float32) + 0.5) / cell * 2 - 1
    x, y = np.meshgrid(c, -c)
    return x, y


def streak_canvas(cell):
    return np.zeros((cell * 2, cell * 2), np.float32)


def line(canvas, cell, p0, p1, value, width=2):
    def pt(p):
        return (int((p[0] + 1) * cell), int((1 - p[1]) * cell))
    cv2.line(canvas, pt(p0), pt(p1), float(value), width)


def finish(canvas, cell, blur=0.7):
    return np.clip(cv2.GaussianBlur(cv2.resize(canvas, (cell, cell), interpolation=cv2.INTER_AREA), (0, 0), blur), 0, 1)


def blob(canvas, cell, x, y, radius, value):
    px, py = (x + 1) * cell, (1 - y) * cell
    r = max(1, int(radius * cell))
    cv2.circle(canvas, (int(px), int(py)), r, float(value), -1)


def hash1(n):
    return fxc.hash1(n)


# -- inhale ---------------------------------------------------------------------------------------

def gen_inhale():
    cell = CELL_FX
    x, y = grid(cell)
    r = np.hypot(x, y)
    rho = r / 0.5
    th = np.arctan2(y, x)
    fine = noise3((1024, 48, FRAMES), (20, 2.0, 2.0), 11, 1.1)
    coarse = noise3((128, 16, FRAMES), (3.0, 1.2, 1.5), 12)
    sats, hots, rims = [], [], []
    X_in, Y_in = grid(CELL_IN)
    R_in = np.hypot(X_in, Y_in)
    TH_in = np.arctan2(Y_in, X_in)
    count = 58
    for i in range(FRAMES):
        t = i / FRAMES
        u = th / (2 * math.pi) * 5
        # Constant phase moves inward, quickening toward the rim.
        v = 0.34 * rho ** 1.5 + t
        n = sample(fine, u, v, t)
        p = sample(coarse, u * 0.6, 0.45 * rho ** 1.5 + t, t)
        rays = smooth(n, 0.52, 0.93) ** 1.5
        outer = 1 - smooth(rho, 1.0, 2.25)
        sat = rays * outer ** 2.1 * (0.3 + 1.15 * p) * 1.2
        rim = np.exp(-np.maximum(rho - 1, 0) / 0.13)
        sat += rim * (0.42 + 0.75 * p) * 0.75
        wide = np.exp(-np.maximum(rho - 1, 0) / 0.5) * 0.2
        sat += wide
        hot = np.clip(rays - 0.5, 0, 1) * 2 * outer ** 2.6 * p * 0.9

        canvas = streak_canvas(cell)
        rim_map = np.zeros_like(R_in)
        for k in range(count):
            lives = 1 + (k % 2)
            q = (t * lives + hash1(k * 3.1)) % 1
            a0 = math.radians(14 + 152 * hash1(k * 7.7))
            curl = (hash1(k * 5.3) - 0.5) * 0.5
            speed = 0.8 + 0.5 * hash1(k * 2.9)

            def at(pp):
                pp = min(pp, 1.0)
                d = 2.15 - 1.15 * pp ** 2.2
                a = a0 + curl * (d - 1) ** 2
                return (math.cos(a) * d * 0.5, math.sin(a) * d * 0.5)

            arrive = 0.88
            travel = q / arrive
            if travel < 1:
                fade = min(1.0, travel / 0.25)
                tail = 0.2 * speed
                segs = 7
                for s in range(segs):
                    a_ = max(0.0, travel - tail * (s + 1) / segs)
                    b_ = max(0.0, travel - tail * s / segs)
                    line(canvas, cell, at(a_), at(b_), fade * (1 - s / segs) ** 1.3 * (0.65 + 0.35 * speed), 2)
            else:
                # Landed: a flash on the glass where it arrived, dying quickly.
                decay = math.exp(-(travel - 1) / 0.055)
                a = a0 + curl * 0
                # Where it touches the glass, in the globe's cell (the rim is the cell's edge).
                sx, sy = math.cos(a) * 0.97, math.sin(a) * 0.97
                d2 = (X_in - sx) ** 2 + (Y_in - sy) ** 2
                rim_map = rim_map + np.exp(-d2 / 0.022) * decay * 0.95
                # and a thin sliver of light running along the rim from it
                da = np.angle(np.exp(1j * (TH_in - a)))
                rim_map += np.exp(-(da / 0.32) ** 2) * np.exp(-((R_in - 0.98) / 0.05) ** 2) * decay * 0.5
        hot = hot + finish(canvas, cell, 0.6)
        sats.append(np.clip(sat, 0, 1))
        hots.append(np.clip(hot, 0, 1))
        rims.append(np.clip(rim_map, 0, 1))
    return {"sat": np.stack(sats), "hot": np.stack(hots), "rim": np.stack(rims)}


# -- pour -----------------------------------------------------------------------------------------

def gen_pour():
    cell = CELL_FX
    x, y = grid(cell)
    streaks = noise3((128, 48, FRAMES), (14, 3.5, 1.6), 21, 1.0)
    fans = noise3((256, 32, FRAMES), (14, 2.4, 1.8), 22, 1.0)
    cols, glows, unders, overs = [], [], [], []
    top = 0.74
    for i in range(FRAMES):
        t = i / FRAMES
        fall = np.clip((top - y) / 1.74, 0, 1)
        hw = 0.021 + 0.028 * fall ** 0.8
        sway = 0.006 * np.sin(y * 9 + t * 2 * math.pi * 2)
        nx = (x + sway) / hw
        n = sample(streaks, nx * 0.11, y * 0.9 + t * 3, t)
        core = np.exp(-(nx / 0.85) ** 2) * (0.55 + 0.75 * smooth(n, 0.25, 0.9))
        body = np.exp(-(nx / 2.1) ** 2) * (0.3 + 0.9 * smooth(n, 0.4, 0.95))
        env = 1 - smooth(y, top - 0.3, top + 0.02)
        halo = np.exp(-(x / 0.16) ** 2) * 0.14
        flare = np.exp(-(x ** 2 + (y - top + 0.1) ** 2) / 0.009) * 0.55
        cols.append(np.clip(core * env * 1.1 + flare, 0, 1))
        glows.append(np.clip((body * 0.65 + halo) * env + flare * 0.5, 0, 1))

        # Under the surface: shafts fanning down from where it lands, rings spreading out.
        R = np.hypot(x, y)
        phi = np.arctan2(x, -y)
        f = sample(fans, phi / 2.6 + 0.5, R * 1.1 - t * 2, t)
        fan = smooth(f, 0.5, 0.95) ** 1.5 * np.exp(-R / 0.26) * (1 - smooth(np.abs(phi), 0.65, 1.2)) * (y < 0.01)
        ring_map = np.zeros_like(x)
        for k in range(3):
            q = (t * 2 + k / 3) % 1
            a = 0.05 + 0.5 * q ** 0.75
            e = np.hypot(x / a, y / (a * 0.16)) - 1
            ring_map += np.exp(-(e / (0.16 / (1 + 2 * q))) ** 2) * (1 - q) ** 1.5
        hot_spot = np.exp(-((x / 0.075) ** 2 + (y / 0.12) ** 2))
        unders.append(np.clip(fan * 0.9 + ring_map * 0.75 + hot_spot * 0.8, 0, 1))

        # Over the surface: the crown and the droplets, and the line lit from the entry point.
        canvas = streak_canvas(cell)
        for k in range(20):
            lives = 1 + (k % 2)
            q = (t * lives + hash1(k * 4.3)) % 1
            vx = (hash1(k * 6.1) - 0.5) * 0.9
            vy = 0.32 + 0.5 * hash1(k * 2.7)
            g = 2.3
            px = vx * q * 0.75
            py = vy * q - 0.5 * g * q * q * 0.72
            if py < -0.005:
                continue
            fade = (1 - q) ** 0.7
            blob(canvas, cell, px, py, 0.0075 + 0.005 * hash1(k * 9.1), fade * 0.95)
            q0 = max(0.0, q - 0.05)
            line(canvas, cell, (vx * q0 * 0.75, vy * q0 - 0.5 * g * q0 * q0 * 0.72), (px, py), fade * 0.6, 2)
        crown = np.exp(-((x / 0.06) ** 2 + ((y - 0.04) / 0.05) ** 2)) * (0.75 + 0.25 * math.sin(t * 2 * math.pi * 3))
        lit = np.exp(-(y / 0.012) ** 2) * np.exp(-np.abs(x) / 0.2)
        overs.append(np.clip(finish(canvas, cell, 0.8) * (y > -0.015) + crown * 0.9 + lit * 0.95, 0, 1))
    return {"col": np.stack(cols), "glow": np.stack(glows), "under": np.stack(unders), "over": np.stack(overs)}


# -- upwell ---------------------------------------------------------------------------------------

def gen_upwell():
    cell = CELL_IN
    x, y = grid(cell)
    plume = noise3((192, 192, FRAMES), (3.2, 2.4, 1.5), 31, 1.6)
    wisp = noise3((256, 192, FRAMES), (7, 3.0, 1.6), 32, 1.5)
    warp = noise3((96, 96, FRAMES), (1.6, 1.2, 1.2), 33, 1.7)
    bodies, cores, crests_s, crests_h = [], [], [], []
    for i in range(FRAMES):
        t = i / FRAMES
        wx = (sample(warp, x * 0.5 + 0.5, y * 0.5 - t, t) - 0.5) * 0.42
        h = (y + 1) / 2
        half = 0.16 + 0.62 * h ** 1.1
        nx = (x + wx) / half
        col = np.exp(-nx ** 2)
        p = sample(plume, (x + wx) * 0.5 + 0.5, y * 0.5 - t, t)
        w = sample(wisp, (x + wx) * 0.5 + 0.5, y * 0.5 - t, t)
        billow = smooth(p, 0.38, 0.95) ** 1.1
        body = col * (0.18 + 0.95 * billow) * (0.45 + 0.55 * h) * 0.85
        strand = smooth(w, 0.62, 0.98) ** 1.5 * col ** 0.7 * 0.8
        base = np.exp(-((x + wx * 0.5) ** 2 / 0.13 + (y + 1.08) ** 2 / 0.1)) * (0.6 + 0.2 * math.sin(t * 2 * math.pi * 2))
        hot = strand * 0.95 + base

        canvas = streak_canvas(cell)
        for k in range(30):
            lives = 1 + (k % 3 == 0)
            q = (t * lives + hash1(k * 5.7)) % 1
            spread = 0.14 + 0.5 * q
            px = (hash1(k * 3.3) - 0.5) * 2 * spread + math.sin(q * 6.3 + k) * 0.03
            py = -0.96 + 1.9 * q
            fade = min(1.0, q / 0.15) * (1 - smooth(np.array(q), 0.7, 1.0).item())
            blob(canvas, cell, px, py, 0.008 + 0.012 * hash1(k * 2.1), fade * (0.55 + 0.45 * hash1(k * 8.7)))
        hot = hot + finish(canvas, cell, 0.9)
        bodies.append(np.clip(body, 0, 1))
        cores.append(np.clip(hot, 0, 1))

        # The surface lit from below, as a strip that rides the level (globe-wide cell).
        pulse = 0.78 + 0.22 * math.sin(t * 2 * math.pi * 2)
        s = np.exp(-np.abs(x) / 0.42) * np.exp(-(y / 0.075) ** 2) * pulse
        h_ = np.exp(-np.abs(x) / 0.22) * np.exp(-(y / 0.018) ** 2) * pulse
        crests_s.append(np.clip(s, 0, 1))
        crests_h.append(np.clip(h_, 0, 1))
    return {"body": np.stack(bodies), "core": np.stack(cores), "crestS": np.stack(crests_s), "crestH": np.stack(crests_h)}


def gen(work):
    os.makedirs(work, exist_ok=True)
    for name, fn in (("inhale", gen_inhale), ("pour", gen_pour), ("upwell", gen_upwell)):
        out = fn()
        np.savez(os.path.join(work, name + ".npz"), **{k: (v * 255 + 0.5).astype(np.uint8) for k, v in out.items()})
        print(name, {k: v.shape for k, v in out.items()}, flush=True)


# -- compositing ----------------------------------------------------------------------------------

class Loops:
    def __init__(self, work):
        self.d = {}
        for name in ("inhale", "pour", "upwell"):
            with np.load(os.path.join(work, name + ".npz")) as z:
                self.d[name] = {k: z[k].astype(np.float32) / 255 for k in z.files}

    def at(self, name, key, t, speed=1.0):
        arr = self.d[name][key]
        pos = (t * speed / LOOP) % 1 * FRAMES
        i = int(pos)
        f = pos - i
        return arr[i] * (1 - f) + arr[(i + 1) % FRAMES] * f


def envelope(t):
    return float(fxc.smooth((t - 0.3) / 0.45) * (1 - fxc.smooth((t - 6.9) / 0.6)))


def rush(t):
    return max(0.0, 1 - (t - 0.3) / fxc.IGNITE) if 0.3 <= t else 0.0


def fill(t):
    """The level rises while the surge feeds it."""
    p = fxc.smooth((t - 0.3) / 6.2)
    back = fxc.smooth((t - 7.0) / 0.9)
    return 0.42 + (0.8 - 0.42) * p * (1 - back)


class Panel(fxc.Panel):
    def __init__(self, art, globe, tint):
        super().__init__(art, globe)
        self.color = LIQUID[tint]
        self.sat, self.hot = TINTS[tint]
        self.xp = None

    def liquid_at(self, t):
        q = round(t * 15) / 15
        if self.cached_t == q:
            return self.cached.copy()
        col = gc.current(self.liq_art, q, self.color)
        self.cached = gc.composite(self.liq_art, col, fill(q), q, self.color)
        self.cached_t = q
        return self.cached.copy()

    def level_row(self, t):
        """Canvas row of the surface inside the globe's square."""
        return (1 - fill(t)) * self.globe

    def rows(self, t, below=True):
        g = self.globe
        y = np.arange(g, dtype=np.float32) + 0.5
        lv = self.level_row(t)
        m = np.clip(y - lv, 0, 1) if below else np.clip(lv - y + 1, 0, 1)
        return m[..., None, None]

    def stamp_in(self, lq, img, cy, color, alpha, size=None):
        g = self.globe
        temp = np.zeros_like(lq)
        fxc.stamp(temp, img, g / 2, cy, size or g, color, alpha)
        return temp

    def finish(self, t, behind, in_liquid, front):
        canvas = np.full((self.h, self.w, 3), 0.055, np.float32)
        behind(canvas)
        x, y = self.globe_rect
        g = self.globe
        lq = in_liquid(self.liquid_at(t))
        a = self.circle[..., None]
        canvas[y:y + g, x:x + g] = canvas[y:y + g, x:x + g] * (1 - a) + np.clip(lq, 0, 1) * a
        front(canvas)
        canvas[:] = gc.add(canvas, self.glass[..., :3], self.glass[..., 3])
        canvas[:] = gc.over(canvas, self.frame[..., :3], self.frame[..., 3])
        return canvas

    def crop(self, img):
        k = self.k
        x0 = int(self.cx - 118 * k)
        x1 = int(self.cx + 124 * k)
        y0 = max(0, int(self.cy - 165 * k))
        y1 = int(self.cy + 104 * k)
        return img[y0:y1, x0:x1]



def weight_mask(art, panel):
    return [(art.weight, panel.cx, panel.cy, panel.globe * 2 * 1.35)]


def render_swirl(p, t):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    size = g * 2
    e = envelope(t)
    rsh = rush(t) if e > 0 else 0
    sat, hot = p.sat, p.hot
    r = g / 2
    weight = weight_mask(art, p)

    def behind(c):
        for i in range(2):
            q = (t / 1.6 + i * 0.5) % 1
            fxc.stamp(c, art.spiral, cx, cy, size * (1.18 - 0.18 * q), sat, 0.75 * math.sin(q * math.pi) * e * (1 + rsh), angle=t * 0.9 - i * 3, mask=weight)
        fxc.stamp(c, art.corona, cx, cy, size * 0.95, sat, 0.5 * e, mask=weight)
        q = (t / 1.1) % 1
        fxc.stamp(c, art.ring, cx, cy, size * (1.3 - 0.3 * q), hot, 0.6 * q * e, mask=weight)

    def front(c):
        breath = 0.8 + 0.2 * math.sin(t * 2 * math.pi / 1.6)
        fxc.stamp(c, art.grim, cx, cy, g, hot, min(1, 0.45 * breath * e * (1 + rsh)))
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, 0.35 * breath * e * (1 + rsh)))
        for i in range(1, 11):
            q = (t * 0.7 + i / 10) % 1
            a = i * 2.39 + q * 2.2 * -1
            d = r * 1.55 * (1 - 0.5 * q)
            fxc.stamp(c, art.mote, cx + math.cos(a) * d, cy - math.sin(a) * d, r * (0.2 + 0.12 * (1 - q)), hot, math.sin(q * math.pi) * 0.9 * e)

    return p.finish(t, behind, lambda lq: lq, front)


def render_inhale(p, L, t):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    size = g * 2
    e = envelope(t)
    rsh = rush(t) if e > 0 else 0
    sat, hot = p.sat, p.hot
    weight = weight_mask(art, p)
    breath = 0.88 + 0.12 * math.sin(t * 2 * math.pi / 2.2)

    def behind(c):
        if e <= 0:
            return
        fxc.stamp(c, art.corona, cx, cy, size * 0.98, sat, 0.42 * breath * e, mask=weight)
        fxc.stamp(c, L.at("inhale", "sat", t), cx, cy, size * 1.02, sat, min(1, 1.15 * e * (1 + 0.5 * rsh)), mask=weight)
        fxc.stamp(c, L.at("inhale", "hot", t), cx, cy, size * 1.02, hot, min(1, 1.0 * e * (1 + 0.4 * rsh)), mask=weight)

    def front(c):
        if e <= 0:
            return
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, 0.42 * breath * e * (1 + rsh)))
        fxc.stamp(c, L.at("inhale", "rim", t), cx, cy, g * 1.0, hot, min(1, 1.1 * e), mask=[(art.gmask, cx, cy, g * 1.01)])

    return p.finish(t, behind, lambda lq: lq, front)


def render_pour(p, L, t):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    size = g * 2
    e = envelope(t)
    sat, hot = p.sat, p.hot
    lv = p.level_row(t)
    surface_cy = p.globe_rect[1] + lv

    def behind(c):
        if e <= 0:
            return
        fxc.stamp(c, art.corona, cx, cy, size * 0.7, sat, 0.22 * e, mask=weight_mask(art, p))

    def in_liquid(lq):
        if e <= 0:
            return lq
        t_ = p.stamp_in(lq, L.at("pour", "under", t), lv, sat, 1.1 * e, size)
        t2 = p.stamp_in(lq, L.at("pour", "under", t), lv, hot, 0.55 * e, size)
        return lq + (t_ + t2) * p.rows(t, True)

    def front(c):
        if e <= 0:
            return
        # The column stops at the level: a clip frame whose bottom is anchored to the fill guide.
        H = c.shape[0]
        glow, col = np.zeros_like(c), np.zeros_like(c)
        rows = np.arange(H, dtype=np.float32) + 0.5
        keep = np.clip(surface_cy - rows + 1, 0, 1)[..., None, None]
        fxc.stamp(glow, L.at("pour", "glow", t), cx, cy, size, sat, min(1, 1.25 * e))
        fxc.stamp(col, L.at("pour", "col", t), cx, cy, size, hot, min(1, 1.2 * e))
        c[:] = np.clip(c + (glow + col) * keep, 0, 1)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.22 * e)
        fxc.stamp(c, L.at("pour", "over", t), cx, surface_cy, size, hot, min(1, 1.1 * e), mask=[(art.gmask, cx, cy, g * 1.0)])

    return p.finish(t, behind, in_liquid, front)


def render_upwell(p, L, t):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    size = g * 2
    e = envelope(t)
    rsh = rush(t) if e > 0 else 0
    sat, hot = p.sat, p.hot
    lv = p.level_row(t)
    surface_cy = p.globe_rect[1] + lv
    breath = 0.85 + 0.15 * math.sin(t * 2 * math.pi / 1.5)

    def behind(c):
        if e <= 0:
            return
        fxc.stamp(c, art.corona, cx, cy, size * 0.9, sat, 0.34 * breath * e, mask=weight_mask(art, p))

    def in_liquid(lq):
        if e <= 0:
            return lq
        body = L.at("upwell", "body", t)
        core = L.at("upwell", "core", t)
        a = p.stamp_in(lq, body, g / 2, sat, min(1, 1.2 * e * (1 + 0.4 * rsh)))
        b = p.stamp_in(lq, body, g / 2, hot, 0.5 * e)
        d = p.stamp_in(lq, core, g / 2, hot, min(1, 1.0 * e))
        return lq + (a + b + d) * p.rows(t, True)

    def front(c):
        if e <= 0:
            return
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, 0.4 * breath * e * (1 + rsh)))
        mask = [(art.gmask, cx, cy, g * 1.0)]
        fxc.stamp(c, L.at("upwell", "crestS", t), cx, surface_cy, g, sat, min(1, 1.0 * e), mask=mask)
        fxc.stamp(c, L.at("upwell", "crestH", t), cx, surface_cy, g, hot, min(1, 1.15 * e), mask=mask)

    return p.finish(t, behind, in_liquid, front)


NAMES = [("current swirl", None), ("1 inhale", render_inhale), ("2 pour", render_pour), ("3 upwell", render_upwell)]


class Board:
    def __init__(self, work):
        art = fxc.Art()
        self.loops = Loops(work)
        self.small = {tint: Panel(art, 180, tint) for tint in TINTS}
        self.big = {tint: Panel(art, 300, tint) for tint in TINTS}

    def one(self, p, fn, t):
        return p.crop(render_swirl(p, t) if fn is None else fn(p, self.loops, t))

    def grid(self, panels, t):
        rows = []
        for tint, label_y in (("arcane", 30), ("blood", 30)):
            row = []
            for name, fn in NAMES:
                img = self.one(panels[tint], fn, t)
                img = gc.label(np.pad(img, ((26, 0), (0, 8), (0, 0)), constant_values=0.07), f"{name} - {tint}", (6, 2), size=18)
                row.append(img)
            rows.append(np.hstack(row))
        return np.vstack(rows)

    def frame(self, t):
        part = int(t // CYCLE) % 2
        c = t % CYCLE
        panels = self.small if part == 0 else self.big
        grid = self.grid(panels, c)
        out = np.full((1080, 1920, 3), 0.05, np.float32)
        h, w = grid.shape[:2]
        h_, w_ = min(h, 1080), min(w, 1920)
        y0, x0 = (1080 - h_) // 2, (1920 - w_) // 2
        out[y0:y0 + h_, x0:x0 + w_] = grid[:h_, :w_]
        tag = "real size (180 px globe)" if part == 0 else "zoomed"
        out = gc.label(out, f"{tag}   surge lit {max(0.0, min(c, 7.5)):.1f}s", (12, 1052), size=20)
        return out


def still(work, path):
    from PIL import Image

    b = Board(work)
    moments = [1.6, 4.3]
    sheets = [b.grid(b.small, t) for t in moments]
    big = b.grid(b.big, 3.2)
    W = max(big.shape[1], sum(s.shape[1] for s in sheets))
    top = np.hstack([*sheets])
    sc = W / top.shape[1]
    if sc != 1:
        top = cv2.resize(top, (W, int(top.shape[0] * sc)), interpolation=cv2.INTER_AREA)
    bot = big if big.shape[1] == W else cv2.resize(big, (W, int(big.shape[0] * W / big.shape[1])), interpolation=cv2.INTER_AREA)
    img = np.vstack([top, bot])
    s = min(1900 / img.shape[1], 1)
    if s < 1:
        img = cv2.resize(img, (int(img.shape[1] * s), int(img.shape[0] * s)), interpolation=cv2.INTER_AREA)
    Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8)).save(path)
    print(path)


BOARD = None


def init_worker(work):
    global BOARD
    os.nice(19)
    cv2.setNumThreads(1)
    BOARD = Board(work)


def render_frame(t):
    return np.clip(BOARD.frame(t) * 255, 0, 255).astype(np.uint8).tobytes()


def video(work, path):
    import imageio_ffmpeg

    fps, seconds = 30, CYCLE * 2
    writer = imageio_ffmpeg.write_frames(path, (1920, 1080), fps=fps, codec="libx264", bitrate="9M", pix_fmt_out="yuv420p", macro_block_size=None, ffmpeg_log_level="error")
    writer.send(None)
    n = int(fps * seconds)
    with mp.Pool(6, init_worker, (work,)) as pool:
        for i, data in enumerate(pool.imap(render_frame, [i / fps for i in range(n)], chunksize=4)):
            writer.send(data)
            if i % 60 == 0:
                print(i, n, flush=True)
    writer.close()
    print(path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "gen":
        gen(sys.argv[2])
    elif mode == "still":
        still(sys.argv[2], sys.argv[3])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
