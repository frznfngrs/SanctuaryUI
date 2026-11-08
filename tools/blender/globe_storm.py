"""Lightning Shield prototype: rendered flipbook lightning, built and composited next to the
current GlobeAura.lua storm (real art, real numbers).

  python globe_storm.py sheets PREFIX        PREFIX-core.png, PREFIX-glow.png, and frame stats
  python globe_storm.py still  PREFIX OUT    contact sheet of the moments that matter
  python globe_storm.py video  PREFIX OUT    side-by-side mp4

Procedural rather than Cycles: lightning is emissive lines, with nothing to light or reflect, so
a path tracer adds only noise. Here every bolt is an explicit branching path with a real taper,
so frames are noise-free by construction and each strike can be scheduled.

The sheet is one full-frame flipbook, never rotated: 49 cells of 292 px covering +-1.75 globe
radii round the globe, a loop then a discharge. Two sheets: a hairline core (tinted hot) and a
half-size soft glow (tinted saturated), drawn ADD, stepped with no blending.
"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402
import globe_fx_compare as fx  # noqa: E402

CELL, COLS = 292, 7
EXT = 1.75  # the cell's half-width, in globe radii
SS = 3  # supersampling of the stroke canvas
LOOP, LOOP_FPS = 38, 18
DISCHARGE, DISCHARGE_FPS = 11, 20
FRAMES = LOOP + DISCHARGE
SCHEDULE_SEED = 2061
RING_OUT = 1.13  # the console ring's outer edge: art outside it is what shows behind the ring


# Paths. Everything is in globe radii, x right, y up, centred on the globe.

def polar(r, deg):
    a = math.radians(deg)
    return np.array((r * math.cos(a), r * math.sin(a)), np.float32)


def displace(rng, a, b, rough, depth):
    """A jagged path from a to b: midpoint displacement, sideways only."""
    pts = [np.array(a, np.float32), np.array(b, np.float32)]
    amp = rough * float(np.linalg.norm(np.array(b) - np.array(a)))
    for _ in range(depth):
        out = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            d = q - p
            side = np.array((-d[1], d[0]), np.float32)
            side /= max(float(np.linalg.norm(side)), 1e-6)
            out.append((p + q) * 0.5 + side * rng.normal(0, amp))
            out.append(q)
        pts = out
        amp *= 0.58
    return np.stack(pts)


def along_rim(rng, radius, start, span, wander, n=44):
    """A path following a circle, wandering in and out on a fractal."""
    t = np.linspace(0, 1, n)
    w = np.zeros(n, np.float32)
    for octave in range(1, 6):
        w += rng.normal(0, wander / octave) * np.sin(np.pi * t * octave * 2.1 + rng.uniform(0, 6.28))
    w += rng.normal(0, wander * 0.2, n)
    w *= np.sin(np.pi * t) ** 0.4  # pinned at the ends
    deg = start + span * t
    a = np.radians(deg)
    r = radius + w
    return np.stack((r * np.cos(a), r * np.sin(a)), 1).astype(np.float32)


class Stroke:
    """One line of a bolt: points, width root to tip (cell px), brightness."""

    def __init__(self, pts, w0, w1, bright):
        self.pts, self.w0, self.w1, self.bright = pts, w0, w1, bright


def forks(rng, stroke, count, length, out_of, spread=0.65):
    """Branches off a stroke, leaving at a shallow angle on the side given by out_of(point)."""
    result = []
    n = len(stroke.pts)
    for _ in range(count):
        i = int(rng.integers(n // 6, max(n // 6 + 1, n * 5 // 6)))
        p = stroke.pts[i]
        tan = stroke.pts[min(i + 2, n - 1)] - stroke.pts[max(i - 2, 0)]
        tan = tan / max(float(np.linalg.norm(tan)), 1e-6)
        direction = out_of(p) + tan * rng.uniform(-spread, spread)
        direction /= max(float(np.linalg.norm(direction)), 1e-6)
        k = 1 - 0.55 * i / n
        ln = length * rng.uniform(0.5, 1.0) * k
        path = displace(rng, p, p + direction * ln, 0.14, 4)
        result.append(Stroke(path, max(0.8, stroke.w0 * 0.5 * k), 0.55, stroke.bright * 0.85))
    return result


def outward(p):
    return p / max(float(np.linalg.norm(p)), 1e-6)


def inward(p):
    return -outward(p)


# Events: a bolt or arc with a birth, a life and a per-frame envelope.

ENV = {
    "strike": [0.5, 1.0, 0.4, 0.95, 0.6, 0.25],
    "crawl": [0.7, 1.0, 0.75, 0.9, 0.45],
    "inner": [0.6, 0.9, 0.65, 0.4],
    "crackle": [0.9, 0.5],
}


def mirrored(deg, side):
    return deg if side > 0 else 180 - deg


def top_angle(rng):
    # Weighted to the top, the part of the rim the console and gargoyle leave visible.
    return float(np.clip(rng.normal(58, 24), 16, 88))


def make_event(rng, kind, birth, side):
    deg = mirrored(top_angle(rng), side)
    strokes = []
    if kind == "strike":
        root = polar(RING_OUT - 0.04, deg)
        ln = rng.uniform(0.34, 0.6)
        tip = polar(RING_OUT + ln, deg + rng.uniform(-13, 13))
        main = Stroke(displace(rng, root, tip, 0.17, 6), 3.0, 0.85, 1.0)
        strokes.append(main)
        strokes += forks(rng, main, int(rng.integers(3, 6)), 0.34, outward)
    elif kind == "crawl":
        span = rng.uniform(18, 50) * (1 if rng.random() < 0.5 else -1)
        radius = RING_OUT + rng.uniform(0.04, 0.12)
        main = Stroke(along_rim(rng, radius, deg - span / 2, span, 0.05), 1.9, 1.1, 0.85)
        strokes.append(main)
        strokes += forks(rng, main, int(rng.integers(1, 4)), 0.2, outward, 0.9)
    elif kind == "inner":
        span = rng.uniform(16, 46) * (1 if rng.random() < 0.5 else -1)
        radius = rng.uniform(0.86, 0.97)
        main = Stroke(along_rim(rng, radius, deg - span / 2, span, 0.045), 1.4, 0.8, 0.55)
        strokes.append(main)
        strokes += forks(rng, main, int(rng.integers(1, 4)), 0.32, inward, 0.8)
    else:  # crackle: a short scratch of static on the ring's outer edge
        span = rng.uniform(5, 15) * (1 if rng.random() < 0.5 else -1)
        strokes.append(Stroke(along_rim(rng, RING_OUT + rng.uniform(0.0, 0.05), deg, span, 0.03, 18), 1.1, 0.7, 0.5))
    # Arcs near the end are simply cut by the wrap: nothing is left hanging over it.
    env = ENV[kind][:LOOP - birth]
    return {"kind": kind, "birth": birth, "env": env, "strokes": strokes, "seed": int(rng.integers(1 << 30))}


def schedule(rng):
    events = []
    side = 1

    def add(kind, frame):
        nonlocal side
        if frame + 2 > LOOP or (kind == "strike" and frame + len(ENV[kind]) > LOOP):
            return  # nothing crosses the wrap, so the loop can restart or mirror cleanly
        events.append(make_event(rng, kind, frame, side))
        side = -side  # every event mirrors the last, so the rim stays balanced

    for f in range(2, LOOP, 7):
        add("strike", f + int(rng.integers(-1, 2)))
    f = 0
    while f < LOOP:
        add("crawl", f)
        f += int(rng.integers(2, 4))
    f = 1
    while f < LOOP:
        add("inner", f)
        f += int(rng.integers(3, 6))
    for f in range(LOOP):
        for _ in range(3):
            add("crackle", f)
    return events


def draw_stroke(canvas, s, bright, reveal=(0.0, 1.0)):
    n = len(s.pts)
    a, b = int(reveal[0] * (n - 1)), int(round(reveal[1] * (n - 1)))
    k = CELL * SS / (2 * EXT)
    mid = CELL * SS / 2
    pts = np.stack((mid + s.pts[:, 0] * k, mid - s.pts[:, 1] * k), 1)
    v = int(np.clip(bright * s.bright, 0, 1) * 255 + 0.5)
    if v <= 0:
        return
    for i in range(a, min(b, n - 1)):
        t = i / max(n - 2, 1)
        w = s.w0 + (s.w1 - s.w0) * t
        th = max(1, int(round(w * SS)))
        p, q = tuple(np.round(pts[i]).astype(int).tolist()), tuple(np.round(pts[i + 1]).astype(int).tolist())
        cv2.line(canvas, p, q, v, th, cv2.LINE_8)


def jittered(s, rng, amp):
    """The same path, re-struck: a small redraw, never a slide."""
    d = rng.normal(0, amp, s.pts.shape).astype(np.float32)
    d[0] = d[-1] = 0
    return Stroke(s.pts + d, s.w0, s.w1, s.bright)


def render_loop(events):
    frames, energy = [], []
    for f in range(LOOP):
        canvas = np.zeros((CELL * SS, CELL * SS), np.uint8)
        active = []
        for e in events:
            k = f - e["birth"]
            env = e["env"]
            if 0 <= k < len(env):
                active.append((e, k, env[k]))
        active.sort(key=lambda a: a[2])
        for e, k, env in active:
            rng = np.random.default_rng(e["seed"] + k)
            for j, s in enumerate(e["strokes"]):
                st = jittered(s, rng, 0.006)
                # Arcs run along the rim as they form and let go behind: they travel, in jumps.
                if e["kind"] == "crawl":
                    rev = ((0.0, 0.55), (0.0, 0.9), (0.05, 1.0), (0.3, 1.0), (0.6, 1.0))[k] if j == 0 else (0.0, 1.0)
                elif e["kind"] == "strike" and k == 0:
                    rev = (0.0, 0.6)  # the leader
                else:
                    rev = (0.0, 1.0)
                draw_stroke(canvas, st, env, rev)
        frames.append(canvas)
    return frames


def render_discharge(seed=4242):
    """Every bolt on the rim lets go at once, and is flung outward."""
    rng = np.random.default_rng(seed)
    # Bolts all round the visible rim, evenly spread so it can't lean.
    n = 18
    angles = [8 + (164 / (n - 1)) * i + rng.uniform(-3, 3) for i in range(n)]
    bolts = []
    for deg in angles:
        root = polar(RING_OUT - 0.02, deg)
        ln = rng.uniform(0.42, 0.62)
        tip = polar(RING_OUT - 0.02 + ln, deg + rng.uniform(-9, 9))
        main = Stroke(displace(rng, root, tip, 0.15, 6), 2.8, 1.0, 1.0)
        bolts.append((main, forks(rng, main, int(rng.integers(3, 6)), 0.34, outward), 0))
    # Arcs racing round the glass.
    glass = [Stroke(along_rim(rng, rng.uniform(0.86, 0.97), 15 + rng.uniform(0, 90), rng.uniform(50, 80), 0.05), 1.8, 1.0, 0.8) for _ in range(8)]
    env = [1.0, 1.0, 0.75, 1.0, 0.9, 0.75, 0.6, 0.45, 0.32, 0.2, 0.1]
    # The window of each bolt that's still lit: whole, then torn free and flung outward.
    window = [(0, 1), (0, 1), (0, 1), (0, 1), (0.14, 1), (0.34, 1), (0.52, 1), (0.66, 1), (0.77, 1), (0.86, 1), (0.93, 1)]
    frames = []
    for f in range(DISCHARGE):
        canvas = np.zeros((CELL * SS, CELL * SS), np.uint8)
        fr = np.random.default_rng(seed + f)
        for main, fs, delay in bolts:
            if f < delay:
                continue
            # A later bolt runs its whole life in the frames it has left.
            k = int(round((f - delay) * (DISCHARGE - 1) / (DISCHARGE - 1 - delay)))
            for j, s in enumerate([main] + fs):
                st = jittered(s, fr, 0.007)
                draw_stroke(canvas, st, env[k], window[k] if j == 0 else (0, 1) if k < 5 else (min(1.0, (k - 4) / 5), 1))
        if f < 5:
            for s in glass:
                draw_stroke(canvas, jittered(s, fr, 0.006), env[f] * 0.9)
        frames.append(canvas)
    return frames


def edge_fade(size):
    c = (np.arange(size, dtype=np.float32) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.hypot(x, y)
    return np.clip((0.99 - r) / 0.09, 0, 1)


def grade(canvas, flash=0.0):
    a = cv2.resize(canvas, (CELL, CELL), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    tight = cv2.GaussianBlur(a, (0, 0), 1.1)
    core = np.clip(a * 1.35 + tight * 0.55, 0, 1) ** 0.85
    wide = cv2.GaussianBlur(a, (0, 0), 3.2) * 1.5 + cv2.GaussianBlur(a, (0, 0), 9) * 2.0 + cv2.GaussianBlur(a, (0, 0), 24) * 2.2
    wide = wide * (1 - 0.6 * min(flash * 4, 1)) + flash * cv2.GaussianBlur(a, (0, 0), 40) * 1.6
    glow = np.clip(wide, 0, 1)
    fade = edge_fade(CELL)
    return core * fade, glow * fade


def energies(cores):
    return [float(c.mean()) for c in cores]


def pack(frames, cell):
    cols = COLS
    w = h = cell * cols
    side = 2048 if cell == CELL else 1024
    sheet = np.zeros((side, side), np.uint8)
    for i, f in enumerate(frames):
        y, x = divmod(i, cols)
        sheet[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] = np.clip(f * 255 + 0.5, 0, 255).astype(np.uint8)
    white = np.full((side, side), 255, np.uint8)
    return Image.merge("RGBA", [Image.fromarray(white), Image.fromarray(white), Image.fromarray(white), Image.fromarray(sheet)])


def timing():
    """Loop frames an arc is born on (settled flickers start there) and frames a bolt strikes on
    (they light the whole glow). Also in GlobeAura.lua; the build step checks they agree."""
    events = schedule(np.random.default_rng(SCHEDULE_SEED))
    births = sorted({e["birth"] for e in events if e["kind"] in ("crawl", "strike")})
    strikes = sorted({e["birth"] + 1 for e in events if e["kind"] == "strike"})
    return births, strikes


def build(prefix):
    events = schedule(np.random.default_rng(SCHEDULE_SEED))
    loop = render_loop(events)
    disc = render_discharge()
    cores, glows = [], []
    for i, c in enumerate(loop + disc):
        flash = 0.0
        if i >= LOOP:
            flash = 0.5 * max(0.0, 1 - (i - LOOP) / 3)
        core, glow = grade(c, flash)
        cores.append(core)
        glows.append(glow)
    pack(cores, CELL).save(prefix + "-core.png", optimize=True)
    pack([cv2.resize(g, (CELL // 2, CELL // 2), interpolation=cv2.INTER_AREA) for g in glows], CELL // 2).save(prefix + "-glow.png", optimize=True)
    E = np.array(energies(cores[:LOOP]))
    G = np.array([g.mean() for g in glows[:LOOP]])
    print("events", {k: sum(1 for e in events if e["kind"] == k) for k in ENV})
    print("loop core mean %.4f, min %.4f, max %.4f" % (E.mean(), E.min(), E.max()))
    print("frame-to-frame core energy step: mean %.1f%% of mean, max %.1f%%" % (100 * np.abs(np.diff(E)).mean() / E.mean(), 100 * np.abs(np.diff(E)).max() / E.mean()))
    print("loop glow mean %.4f, step mean %.1f%%, max %.1f%%" % (G.mean(), 100 * np.abs(np.diff(G)).mean() / G.mean(), 100 * np.abs(np.diff(G)).max() / G.mean()))
    print("wrap step core %.1f%%" % (100 * abs(E[-1] - E[0]) / E.mean()))
    D = np.array(energies(cores[LOOP:]))
    print("discharge energy by frame", np.round(D / E.mean(), 2))
    for name in ("core", "glow"):
        path = f"{prefix}-{name}.png"
        w, h = Image.open(path).size
        print(path, (w, h), "%.2f MB png, %d MB VRAM" % (os.path.getsize(path) / 1e6, w * h * 4 // (1024 * 1024)))


class Sheet:
    def __init__(self, path, cell):
        a = np.asarray(Image.open(path).getchannel("A"), np.float32) / 255
        self.cells = [a[i // COLS * cell:(i // COLS + 1) * cell, (i % COLS) * cell:(i % COLS + 1) * cell] for i in range(FRAMES)]


class StormArt:
    def __init__(self):
        lum = fx.lum
        self.corona, self.ring = lum("aura-corona.png"), lum("aura-ring.png")
        self.rays = [lum("aura-rays-a.png"), lum("aura-rays-b.png")]
        self.wisps = [lum("aura-wisps-a.png"), lum("aura-wisps-b.png")]
        self.grim = lum("globe-rim.png")[::-1]
        self.static = lum("storm-static.png")
        self.arcs = [lum(f"storm-arcs-{c}.png") for c in "abcdef"]
        self.bolts = [lum(f"storm-bolt-{c}.png") for c in "abcd"]
        self.mote = lum("mote.png")


SAT, HOT = (0.3, 0.6, 1.0), (0.85, 0.95, 1.0)
LIT_AT, DISCHARGE_AT, CYCLE = 0.0, 13.2, 15.5


def hash1(n):
    x = math.sin(n * 12.9898) * 43758.5453
    return x - math.floor(x)


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def out(t):
    return 1 - (1 - t) ** 3


def flicker(phase, width):
    t = phase / width
    if t >= 1:
        return 0
    if t < 0.25:
        return 1
    if t < 0.4:
        return 0.25
    if t < 0.6:
        return 0.9
    return 0.9 * (1 - (t - 0.6) / 0.4)


def strobe(phase, width):
    t = phase / width
    if t >= 1:
        return 0, 0
    if t < 0.1:
        return 1, 1
    if t < 0.17:
        return 0.15, 1
    if t < 0.27:
        return 1, 2
    if t < 0.33:
        return 0.2, 2
    if t < 0.42:
        return 0.85, 3
    return 0.55 * (1 - (t - 0.42) / 0.58) ** 2, 3


def state(t):
    """level, calm, release progress (None before the discharge), ignite."""
    calm = smooth((t - LIT_AT - 8) / 2)
    release = None
    if t >= DISCHARGE_AT:
        release = (t - DISCHARGE_AT) / 0.55
    level = smooth((t - LIT_AT) / 0.35)
    if release is not None:
        level = max(0.0, 1 - release)
    ignite = max(0.0, 1 - (t - LIT_AT) / 0.8) ** 2 if t < 0.8 else 0.0
    return level, calm, release, ignite


def radiate(c, art, p, t, strike_gain):
    """The radiance every storm stands on: AnimateRadiate's numbers."""
    level, calm, release, ignite = state(t)
    e = smooth(level)
    if e <= 0 and release is None:
        return
    blow = out(min(release, 1)) if release is not None else 0
    base = e
    breath = 0.86 + 0.14 * math.sin(t * 2 * math.pi / 2.8)
    size = p.globe * 2
    flash = ignite
    fsize, falpha = 1.0, 0.0
    if ignite > 0:
        q = t / 0.8
        fsize, falpha = 1 + 0.55 * out(q), (1 - q) ** 1.5
    if release is not None and release < 1:
        flash, fsize, falpha = 1.5 * (1 - release) ** 2, 1 + blow, 1.3 * (1 - release) ** 1.2
    cx, cy = p.cx, p.cy
    fx.stamp(c, art.corona, cx, cy, size * (1 + 0.015 * math.sin(t * 2.2) + 0.15 * blow), SAT, 0.85 * breath * base * strike_gain * (1 - 0.5 * calm))
    rayk = 1 + 0.5 * blow
    fx.stamp(c, art.rays[0], cx, cy, size * rayk, SAT, 0.85 * base * (1 - 0.85 * calm) * (0.85 + 0.15 * math.sin(t * 0.9)) * (1 + 1.2 * flash), angle=t * 0.05)
    fx.stamp(c, art.rays[1], cx, cy, size * 1.04 * rayk, HOT, 0.4 * base * (1 - 0.85 * calm) * (0.8 + 0.2 * math.sin(t * 1.3 + 1)) * (1 + flash), angle=1.3 - t * 0.035)
    for i in range(2):
        q = t / 3 + i * 0.5
        k = math.floor(q)
        ph = q - k
        fx.stamp(c, art.wisps[i], cx, cy, size * (1 + 0.06 * ph + 0.2 * blow), SAT, 0.75 * math.sin(ph * math.pi) * base * (1 - 0.7 * calm), angle=hash1(k * 2 + i) * 6.283 + t * 0.04)
    fx.stamp(c, art.corona, cx, cy, size * 0.9, HOT, 0.55 * breath * base * (1 + 0.6 * flash) * strike_gain * (1 - 0.5 * calm))
    fx.stamp(c, art.ring, cx, cy, size * fsize, SAT, falpha)
    fx.stamp(c, art.ring, cx, cy, size * fsize * 0.99, HOT, 0.7 * falpha)


def catch_glass(c, art, p, t):
    level, calm, _, _ = state(t)
    if level <= 0:
        return
    breath = 0.86 + 0.14 * math.sin(t * 2 * math.pi / 2.8)
    fx.stamp(c, art.grim, p.cx, p.cy, p.globe, HOT, 0.35 * breath * smooth(level) * (1 - 0.6 * calm))


def storm_current(c, art, p, t):
    """AnimateStorm at its real numbers. Returns the strike for next frame's radiance."""
    level, calm, release, _ = state(t)
    base = smooth(level)
    if base <= 0:
        return 0
    size, r = p.globe * 2, p.globe / 2
    cx, cy = p.cx, p.cy
    strike = 0
    for k, sat_hot in ((1, SAT), (2, HOT)):
        tick = math.floor(t * 20) + k * 31
        fx.stamp(c, art.static, cx, cy, size * (1 + 0.01 * k), sat_hot, (0.45 - 0.2 * calm) * (0.5 + 0.5 * hash1(tick + 7)) * base, angle=hash1(tick) * 6.283)
    for k in range(1, 7):
        period = 0.17 + 0.045 * k
        q = t / period + k * 0.37
        cyc = math.floor(q)
        ph = q - cyc
        fire = flicker(ph, 0.55) if hash1(cyc * 3 + k) > 0.35 + 0.5 * calm else 0
        crawl = (1 if hash1(cyc * 13 + k) > 0.5 else -1) * ph * period * 2.2
        fx.stamp(c, art.arcs[k - 1], cx, cy, size * (1 + 0.02 * (hash1(cyc + k) - 0.5)), HOT if k % 3 == 0 else SAT, 1.3 * fire * base, angle=hash1(cyc * 7 + k) * 6.283 + crawl)
        strike = max(strike, fire * 0.35)
    for k in range(1, 5):
        period = 0.5 + 0.21 * k
        q = t / period + k * 0.61
        cyc = math.floor(q)
        fire, fl = 0, 0
        if hash1(cyc * 5 + k * 13) > 0.4 + 0.5 * calm:
            fire, fl = strobe(q - cyc, 0.45)
        if fire > 0:
            a = math.radians(25 + 130 * hash1(cyc * 11 + k)) + (hash1(cyc * 19 + fl) - 0.5) * 0.08
            ln = r * (0.8 + 0.7 * hash1(cyc * 17 + k))
            dist = r * 0.98 + ln * 0.5
            fx.stamp(c, art.bolts[k - 1], cx + math.cos(a) * dist, cy - math.sin(a) * dist, ln * 1.05, HOT, 1.4 * fire * base, angle=a - math.pi / 2)
            fx.stamp(c, art.mote, cx + math.cos(a) * r, cy - math.sin(a) * r, r * 0.55, HOT, 1.2 * fire * base)
            strike = max(strike, fire)
    return strike


class StormNew:
    def __init__(self, prefix):
        self.core = Sheet(prefix + "-core.png", CELL)
        self.glow = Sheet(prefix + "-glow.png", CELL // 2)
        self.births, strikes = timing()
        self.strikes = set(strikes)
        self.energy = [float(c.mean()) for c in self.core.cells[:LOOP]]

    def pick(self, t):
        """(cell index, mirrored, strength, whole-glow gain) at time t, as the driver would."""
        level, calm, release, _ = state(t)
        if release is not None:
            i = int(release * 0.55 * DISCHARGE_FPS)
            if i >= DISCHARGE:
                return None
            return LOOP + i, False, 1.0, 1.0
        if level <= 0:
            return None
        if calm < 1:
            f = t * LOOP_FPS
            n = int(f // LOOP)
            i = int(f % LOOP)
            gain = 1 - calm
            if gain > 0.02:
                return i, hash1(n) > 0.5, gain, self.gain_at(i)
        # Settled: now and then one short run of the loop.
        period = 1.15
        q = t / period
        cyc = math.floor(q)
        if hash1(cyc * 3.7) < 0.3:
            return None
        ph = (q - cyc) * period * LOOP_FPS
        run = 4
        if ph >= run:
            return None
        start = self.births[int(hash1(cyc * 11.3) * len(self.births))]
        return (start + int(ph)) % LOOP, hash1(cyc * 5.1) > 0.5, 0.55, 1.0

    def gain_at(self, i):
        return 1.0


def flip(img, mirrored_):
    return img[:, ::-1] if mirrored_ else img


def storm_new(p, sheets, art, canvas_behind, canvas_front, t):
    pick = sheets.pick(t)
    if pick is None:
        return 0
    i, m, strength, _ = pick
    core, glow = flip(sheets.core.cells[i], m), flip(sheets.glow.cells[i], m)
    level, calm, release, _ = state(t)
    size = p.globe * EXT  # the cell spans +-EXT radii
    cx, cy = p.cx, p.cy
    if canvas_behind is not None:
        fx.stamp(canvas_behind, glow, cx, cy, size, SAT, 1.0 * strength)
        fx.stamp(canvas_behind, core, cx, cy, size, HOT, 1.0 * strength)
    if canvas_front is not None:
        mask = [(art_mask(p), cx, cy, p.globe)]
        gk, ck = (0.7, 0.95) if i >= LOOP else (0.65, 0.75)
        fx.stamp(canvas_front, glow, cx, cy, size, SAT, gk * strength, mask=mask)
        fx.stamp(canvas_front, core, cx, cy, size, HOT, ck * strength, mask=mask)
    # A strike lights the whole glow for a blink, as today.
    return 1.0 if (i in sheets.strikes and release is None) else 0.0


_masks = {}


def art_mask(p):
    if p.globe not in _masks:
        _masks[p.globe] = p.art.gmask
    return _masks[p.globe]


class Stage:
    def __init__(self, prefix):
        art = fx.Art()
        self.st = StormArt()
        self.small = fx.Panel(art, 180)
        self.big = fx.Panel(art, 300)
        self.new = StormNew(prefix)
        self.strike = {}

    def render(self, panel, t, kind):
        key = (id(panel), kind)
        last = self.strike.get(key, 0.0)
        result = [0.0]

        def behind(c):
            radiate(c, self.st, panel, t, 1 + 0.6 * last)
            if kind == 0:
                result[0] = storm_current(c, self.st, panel, t)
            else:
                result[0] = storm_new(panel, self.new, self.st, c, None, t)

        def front(c):
            catch_glass(c, self.st, panel, t)
            if kind == 1:
                storm_new(panel, self.new, self.st, None, c, t)

        img = panel.compose(t, behind, front, lambda c: None)
        self.strike[key] = result[0]
        return img


def state_name(t):
    if t < 8:
        return "lit up"
    if t < 10:
        return "settling"
    if t < DISCHARGE_AT:
        return "settled"
    if t < DISCHARGE_AT + 0.6:
        return "DISCHARGE (charges spent)"
    return "gone"


W, H = 1720, 820


def board(stage, t):
    t = t % CYCLE
    out_ = np.full((H, W, 3), 0.07, np.float32)
    labels = []

    def put(img, x, y):
        h, w = img.shape[:2]
        h, w = min(h, H - y), min(w, W - x)
        out_[y:y + h, x:x + w] = img[:h, :w]

    sm = stage.small
    big = stage.big
    put(stage.render(sm, t, 0), 16, 34)
    put(stage.render(sm, t, 1), 16, 34 + sm.h + 26)
    x = 16 + sm.w + 16
    put(stage.render(big, t, 0), x, 60)
    put(stage.render(big, t, 1), x + big.w + 12, 60)
    labels += [(16, 10, "current, real size"), (16, 34 + sm.h + 2, "rendered, real size"), (x, 34, "zoom: current (real GlobeAura.lua numbers)"), (x + big.w + 12, 34, "zoom: rendered"), (W - 420, 8, f"{state_name(t)}  t={t:4.1f}s")]
    for lx, ly, text in labels:
        out_ = gc.label(out_, text, (lx, ly))
    return out_


def settled_moments(new):
    """A flicker and the quiet between, found by asking the driver."""
    lit, quiet = None, None
    for i in range(int(10.5 * 60), int(13 * 60)):
        t = i / 60
        p = new.pick(t)
        if p is not None and lit is None:
            lit = t + 2 / 60
        if p is None and quiet is None and lit is not None:
            quiet = t + 0.2
    return lit or 11.0, quiet or 11.5


def still(prefix, out_path):
    s = Stage(prefix)
    grid = []
    lit, quiet = settled_moments(s.new)
    moments = [(2.05, "lit up"), (2.9, "lit up, a strike"), (lit, "settled, a flicker"), (quiet, "settled, between"), (DISCHARGE_AT + 0.18, "discharge, at its peak"), (DISCHARGE_AT + 0.32, "discharge, torn free")]
    for t, name in moments:
        pair = np.hstack([s.render(s.big, t, 0), s.render(s.big, t, 1)])
        grid.append(gc.label(pair, f"{name}   current | rendered", (10, 8)))
    rows = [np.hstack(grid[i:i + 2]) for i in range(0, len(grid), 2)]
    g = np.vstack(rows)
    scale = 1800 / g.shape[1]
    g = cv2.resize(g, (1800, int(g.shape[0] * scale)), interpolation=cv2.INTER_AREA)
    Image.fromarray(np.clip(g * 255, 0, 255).astype(np.uint8)).save(out_path)
    print(out_path)


def video(prefix, out_path):
    import imageio_ffmpeg
    s = Stage(prefix)
    fps = 60
    w = imageio_ffmpeg.write_frames(out_path, (W, H), fps=fps, codec="libx264", quality=None, bitrate="12M", pix_fmt_out="yuv420p", macro_block_size=None)
    w.send(None)
    n = int(CYCLE * fps)
    for i in range(n):
        w.send(np.clip(board(s, i / fps) * 255, 0, 255).astype(np.uint8).tobytes())
        if i % 120 == 0:
            print(i, n, flush=True)
    w.close()
    print(out_path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sheets":
        build(sys.argv[2])
    elif mode == "still":
        still(sys.argv[2], sys.argv[3])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
