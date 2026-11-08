"""Packs tools/blender/globe_fx.py renders into flipbook sheets and composites them the way the
game would, against the current GlobeAura.lua effects at their real numbers.

  python globe_fx_compare.py sheets WORK OUTPREFIX   WORK/{shell,shatter,hit,swirl}/f###.png
  python globe_fx_compare.py still  OUTPREFIX OUT.png
  python globe_fx_compare.py video  OUTPREFIX OUT.mp4

Sheets are white RGB with luminance in alpha, the addon's glow-art format, for ADD.
"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402

SPECS = {
    # frames, cols, cell, seconds (loop or one-shot)
    "shell": (32, 8, 256, 4.0),
    "shatter": (25, 5, 409, 0.9),
    "hit": (16, 4, 256, 0.45),
    "swirl": (32, 8, 256, 2.6),
}
SHEET = {"shell": (2048, 1024), "shatter": (2048, 2048), "hit": (1024, 1024), "swirl": (2048, 1024)}

TINTS = {
    "gold": ((1.0, 0.78, 0.32), (1.0, 0.95, 0.78)),
    "frost": ((0.35, 0.72, 1.0), (0.86, 0.96, 1.0)),
}
HEALTH = np.array([0.86, 0.07, 0.05], np.float32)
SHARDS = 14
SHATTER, IGNITE, HIT = 0.9, 0.8, 0.45
FX_SCALE = 2


def read16(path):
    im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("missing " + path)
    return im[..., :3].mean(axis=2).astype(np.float32) / 65535


def cell_edge_fade(n, inner, outer):
    c = (np.arange(n, dtype=np.float32) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.hypot(x, y)
    return np.clip((outer - r) / (outer - inner), 0, 1)


def load_frames(work, mode):
    n, _cols, cell, _secs = SPECS[mode]
    subs = 3 if mode == "shatter" else 1
    d = os.path.join(work, mode)
    frames = []
    for i in range(n):
        if subs == 1:
            a = read16(os.path.join(d, f"f{i:03d}.png"))
        else:
            a = sum(read16(os.path.join(d, f"f{i:03d}_{k}.png")) for k in range(subs)) / subs
        frames.append(cv2.resize(a, (cell, cell), interpolation=cv2.INTER_AREA))
    return frames


def grade(mode, frames):
    """Render -> display luminance. D3's FX are hot lines over a soft glow, and clear in the
    middle, so this lifts contrast rather than brightness."""
    n, _, cell, secs = SPECS[mode]
    a = np.stack(frames)
    if mode == "shell":
        top = np.percentile(a, 99.6)
        a = np.clip(a / top, 0, 1) ** 1.8
    elif mode == "hit":
        top = np.percentile(a[1:6], 99.7)
        a = np.clip(a / top, 0, 1) ** 1.15
    elif mode == "swirl":
        top = np.percentile(a, 99.7)
        a = np.clip(a / top, 0, 1) ** 1.35
    else:
        top = np.percentile(a[:18], 99.4)
        a = np.clip(a / top, 0, 1) ** 1.45
        # Shards fade with time, and before the cell's edge so nothing clips on a square.
        env = np.ones(n, np.float32)
        for i in range(n):
            t = i / (n - 1)
            env[i] = 1 - np.clip((t - 0.5) / 0.5, 0, 1) ** 1.6
        a = a * env[:, None, None] * cell_edge_fade(cell, 0.74, 0.98)
    return [f for f in a]


def pack(mode, frames):
    n, cols, cell, _ = SPECS[mode]
    w, h = SHEET[mode]
    sheet = np.zeros((h, w), np.uint8)
    for i, f in enumerate(frames):
        y, x = divmod(i, cols)
        sheet[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] = np.clip(f * 255 + 0.5, 0, 255).astype(np.uint8)
    white = np.full((h, w), 255, np.uint8)
    return Image.merge("RGBA", [Image.fromarray(white), Image.fromarray(white), Image.fromarray(white), Image.fromarray(sheet)])


def sheets(work, prefix):
    for mode in SPECS:
        frames = grade(mode, load_frames(work, mode))
        im = pack(mode, frames)
        path = f"{prefix}{mode}.png"
        im.save(path, optimize=True)
        w, h = im.size
        print(mode, im.size, f"{os.path.getsize(path) / 1e6:.2f} MB png, {w * h * 4 / (1024 * 1024):.0f} MB VRAM")


class Sheet:
    def __init__(self, prefix, mode):
        self.n, cols, cell, self.secs = SPECS[mode]
        a = np.asarray(Image.open(f"{prefix}{mode}.png").getchannel("A"), np.float32) / 255
        self.frames = []
        for i in range(self.n):
            y, x = divmod(i, cols)
            self.frames.append(a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell])

    def loop(self, t):
        x = (t / self.secs % 1) * self.n
        i = int(x)
        f = x - i
        return self.frames[i % self.n] * (1 - f) + self.frames[(i + 1) % self.n] * f

    def shot(self, p):
        """p 0..1 through a one-shot, no blending: fast shards would double up."""
        return self.frames[int(min(max(p, 0), 0.9999) * self.n)]


def lum(name):
    a = gc.load_png(name)
    return a[..., 3]


def stamp_sample(img, x0, y0, w, h, cx, cy, size, angle=0.0):
    """img as it lands in a w x h patch whose top-left is x0,y0 on the canvas."""
    n = img.shape[0]
    k = size / n
    c = math.cos(angle) * k
    s = math.sin(angle) * k
    half = n / 2
    # image pixel (u,v) -> canvas; angle is counter-clockwise on screen (y down).
    m = np.array([[c, s, cx - x0 - c * half - s * half],
                  [-s, c, cy - y0 + s * half - c * half]], np.float32)
    return cv2.warpAffine(img, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def stamp(canvas, img, cx, cy, size, color, alpha, angle=0.0, mask=None):
    if alpha <= 0.002 or img is None:
        return
    H, W = canvas.shape[:2]
    pad = size * 0.5 * 1.42 + 1
    x0, y0 = max(0, int(cx - pad)), max(0, int(cy - pad))
    x1, y1 = min(W, int(cx + pad) + 1), min(H, int(cy + pad) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    w, h = x1 - x0, y1 - y0
    p = stamp_sample(img, x0, y0, w, h, cx, cy, size, angle)
    if mask is not None:
        for m_img, mx, my, msize in mask:
            p = p * stamp_sample(m_img, x0, y0, w, h, mx, my, msize)
    canvas[y0:y1, x0:x1] = np.clip(canvas[y0:y1, x0:x1] + p[..., None] * np.array(color, np.float32) * min(alpha, 1.0), 0, 1)


class Art:
    def __init__(self):
        self.rim = lum("shell-rim.png")
        self.facets = lum("shell-facets.png")
        self.sheen = lum("shell-sheen.png")
        self.shard = [lum("shell-shard-a.png"), lum("shell-shard-b.png")]
        self.spiral = lum("aura-spiral.png")
        self.ring = lum("aura-ring.png")
        self.corona = lum("aura-corona.png")
        self.weight = gc.load_png("aura-topweight.png")[..., 3]
        self.mote = lum("mote.png")
        self.grim = lum("globe-rim.png")
        self.gmask = gc.load_png("globe-mask.png")[..., 3]
        if self.gmask.max() < 0.01:
            self.gmask = gc.load_png("globe-mask.png")[..., 0]


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def out(t):
    return 1 - (1 - t) ** 3


def hash1(n):
    x = math.sin(n * 12.9898) * 43758.5453
    return x - math.floor(x)


class Panel:
    """A piece of console around the health globe, with the game's draw order."""

    def __init__(self, art, globe):
        self.art, self.globe = art, globe
        self.liq_art = gc.Art(globe)
        k = globe / 160
        self.k = k
        # Canvas in frame units; the frame art only exists from y=0 on.
        x0, y0, w, h = 76, -70, 340, 330
        self.w, self.h = int(w * k), int(h * k)
        self.cx, self.cy = (243.5 - x0) * k, (99 - y0) * k
        frame = gc.load_png("frame.png")
        glass = gc.load_png("glass.png")
        canvas_f = np.zeros((h, w, 4), np.float32)
        canvas_g = np.zeros((h, w, 4), np.float32)
        ty0, ty1 = 0 - y0, min(h, 256 - y0)
        canvas_f[ty0:ty1, :] = frame[0:ty1 - ty0, x0:x0 + w]
        canvas_g[ty0:ty1, :] = glass[0:ty1 - ty0, x0:x0 + w]
        size = (self.w, self.h)
        self.frame = cv2.resize(canvas_f, size, interpolation=cv2.INTER_CUBIC)
        self.glass = cv2.resize(canvas_g, size, interpolation=cv2.INTER_CUBIC)
        half = globe / 2
        sh, _sw = self.h, self.w
        self.globe_rect = (int(self.cx - half), int(self.cy - half))
        self.circle = cv2.GaussianBlur(cv2.resize(self.liq_art.mask.squeeze(), (globe, globe)), (0, 0), 0.5)
        self.cached = None
        self.cached_t = None

    def liquid(self, t):
        # Quantised: the liquid isn't what's being compared.
        q = round(t * 15) / 15
        if self.cached_t == q:
            return self.cached
        col = gc.current(self.liq_art, q, HEALTH)
        self.cached = gc.composite(self.liq_art, col, 0.72, q, HEALTH)
        self.cached_t = q
        return self.cached

    def compose(self, t, behind, front, shards):
        canvas = np.full((self.h, self.w, 3), 0.055, np.float32)
        behind(canvas)
        x, y = self.globe_rect
        g = self.globe
        lq = self.liquid(t)
        a = self.circle[..., None]
        canvas[y:y + g, x:x + g] = canvas[y:y + g, x:x + g] * (1 - a) + lq * a
        front(canvas)
        canvas[:] = gc.add(canvas, self.glass[..., :3], self.glass[..., 3])
        canvas[:] = gc.over(canvas, self.frame[..., :3], self.frame[..., 3])
        shards(canvas)
        return canvas


# Timeline, seconds into a 10 s cycle.
FORM_AT = 0.0
HITS = (1.7, 2.7)
BREAK_AT = 3.9
SURGE_FROM, SURGE_TO = 5.6, 9.6
CYCLE = 10.0


def shell_state(t):
    """form 1..0, hit strength and time, shattering t or None, level."""
    form = 1 - (t - FORM_AT) / IGNITE if t < FORM_AT + IGNITE else 0
    level = smooth((t - FORM_AT) / 0.35) if t < BREAK_AT else 0
    hit_p = None
    for h in HITS:
        if h <= t < h + HIT:
            hit_p = (t - h) / HIT
    shatter = (t - BREAK_AT) / SHATTER if BREAK_AT <= t < BREAK_AT + SHATTER else None
    return form, level, hit_p, shatter


def surge_level(t):
    if t < SURGE_FROM or t > SURGE_TO + 0.5:
        return 0.0
    return smooth((t - SURGE_FROM) / 0.35) * (1 - smooth((t - SURGE_TO) / 0.5))


def render_current(panel, t, tint, strength=1.3):
    art, g, cx, cy = panel.art, panel.globe, panel.cx, panel.cy
    sat, hot = TINTS[tint]
    form, level, hit_p, shatter = shell_state(t)
    shell_size = g * 1.03
    hit = (1 - hit_p) ** 2 if hit_p is not None else 0
    hit_angle = 0.9
    base = smooth(level) * strength
    swell = (1 - 0.08 * form ** 2) * (1 - 0.035 * hit)
    breath = 0.9 + 0.1 * math.sin(t * 2 * math.pi / 3.2)
    circ = [(art.gmask, cx, cy, shell_size)]
    surge = surge_level(t)
    usize = g * FX_SCALE
    rush = max(0, 1 - (t - SURGE_FROM) / IGNITE) if t >= SURGE_FROM else 0
    ubase = surge * 1.0
    weight = [(art.weight, cx, cy, usize * 1.35)]

    def behind(c):
        if base > 0:
            stamp(c, art.corona, cx, cy, g * FX_SCALE * 0.96, sat, 0.7 * breath * base * (1 + 0.8 * hit))
            stamp(c, art.ring, cx, cy, g * FX_SCALE * (1 + 0.4 * out(1 - form)), hot, 0.8 * form ** 1.5 if form > 0 else 0)
        if shatter is not None:
            rs = g * FX_SCALE * (1 + 0.5 * out(shatter))
            stamp(c, art.ring, cx, cy, rs, sat, 1.2 * (1 - shatter))
            stamp(c, art.ring, cx, cy, rs * 0.99, hot, 0.8 * (1 - shatter))
        if ubase > 0:
            for i in range(2):
                p = (t / 1.6 + i * 0.5) % 1
                stamp(c, art.spiral, cx, cy, usize * (1.18 - 0.18 * p), sat, 0.75 * math.sin(p * math.pi) * ubase * (1 + rush),
                      angle=-(t * 0.9) - i * 3 * -1, mask=weight)
            stamp(c, art.corona, cx, cy, usize * 0.95, sat, 0.5 * ubase, mask=weight)
            p = (t / 1.1) % 1
            stamp(c, art.ring, cx, cy, usize * (1.3 - 0.3 * p), hot, 0.6 * p * ubase, mask=weight)

    def front(c):
        if base > 0:
            size = shell_size * swell
            stamp(c, art.rim, cx, cy, size, sat, base * (1 + 0.5 * form + hit))
            stamp(c, art.facets, cx, cy, size, hot, 0.65 * base * (0.85 + 0.15 * math.sin(t * 1.7)) * (1 + 1.5 * form + 2.5 * hit), angle=t * 0.03)
            if hit_p is not None:
                r = shell_size / 2
                hx, hy = math.cos(hit_angle) * r * 0.5, math.sin(hit_angle) * r * 0.5
                spread = shell_size * (0.2 + 2.4 * out(hit_p))
                stamp(c, art.ring, cx + hx, cy - hy, spread, sat, 1.6 * (1 - hit_p) ** 1.2, mask=circ)
                stamp(c, art.ring, cx + hx, cy - hy, spread * 0.92, hot, 1.3 * (1 - hit_p) ** 1.2, mask=circ)
                stamp(c, art.mote, cx + hx, cy - hy, shell_size * (0.35 + 0.25 * hit_p), hot, 1.5 * (1 - hit_p) ** 2.5, mask=circ)
            p = (t % 3) / 3
            off = (p - 0.5) * shell_size * 0.8
            stamp(c, art.sheen, cx + off, cy + off, shell_size * 1.6, hot, 0.55 * base * math.sin(p * math.pi), mask=[(art.gmask, cx, cy, shell_size)])
        if ubase > 0:
            br = 0.8 + 0.2 * math.sin(t * 2 * math.pi / 1.6)
            stamp(c, art.grim, cx, cy, g, hot, min(1, 0.45 * br * ubase * (1 + rush)))
            stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, 0.35 * br * ubase * (1 + rush)))
            r = g / 2
            for i in range(1, 11):
                q = (t * 0.7 + i / 10) % 1
                a = i * 2.39 + q * 2.2 * -1
                d = r * 1.55 * (1 - 0.5 * q)
                stamp(c, art.mote, cx + math.cos(a) * d, cy - math.sin(a) * d, r * (0.2 + 0.12 * (1 - q)), hot, math.sin(q * math.pi) * 0.9 * ubase)

    def shards(c):
        if shatter is None:
            return
        r = g / 2
        for i in range(1, SHARDS + 1):
            seed = 31 + i * 17
            a = math.radians(15 + 150 * hash1(seed)) if i <= 10 else hash1(seed) * 6.283
            speed = 0.7 + 0.6 * hash1(seed + 1)
            dist = r * (0.95 + 1.1 * speed * out(shatter))
            x = math.cos(a) * dist
            y = math.sin(a) * dist - r * 0.6 * shatter * shatter
            sz = r * (0.28 + 0.24 * hash1(seed + 2)) * (1 - 0.3 * shatter)
            spin = hash1(seed + 3) * 6.283 + (hash1(seed + 4) - 0.5) * 8 * shatter
            alpha = (1 - shatter) ** 0.7
            tex = art.shard[i % 2]
            stamp(c, tex, cx + x, cy - y, sz, sat, 1.6 * alpha, angle=spin)
            stamp(c, tex, cx + x, cy - y, sz, hot, 0.8 * alpha, angle=spin)

    return panel.compose(t, behind, front, shards)


class Fx:
    def __init__(self, prefix):
        self.shell = Sheet(prefix, "shell")
        self.shatter = Sheet(prefix, "shatter")
        self.hit = Sheet(prefix, "hit")
        self.swirl = Sheet(prefix, "swirl")


def mix(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


def render_new(panel, fx, t, tint, strength=1.3):
    art, g, cx, cy = panel.art, panel.globe, panel.cx, panel.cy
    sat, hot = TINTS[tint]
    dome_tint = mix(sat, hot, 0.45)
    form, level, hit_p, shatter = shell_state(t)
    base = smooth(level) * strength
    dome_size = g * 1.03 * 1.06
    hit = (1 - hit_p) ** 2 if hit_p is not None else 0
    breath = 0.9 + 0.1 * math.sin(t * 2 * math.pi / 3.2)
    surge = surge_level(t)
    usize = g * FX_SCALE
    weight = [(art.weight, cx, cy, usize * 1.35)]
    circ = [(art.gmask, cx, cy, g)]
    rush = max(0, 1 - (t - SURGE_FROM) / IGNITE) if t >= SURGE_FROM else 0
    # Forming: the shatter played backward, the pieces flying in; the dome takes over.
    forming = 1 - form if form > 0 else None
    swirl_img = fx.swirl.loop(t) if surge > 0 else None

    def behind(c):
        if base > 0:
            stamp(c, art.corona, cx, cy, g * FX_SCALE * 0.96, sat, 0.55 * breath * base * (1 + 0.8 * hit))
        if shatter is not None:
            rs = g * FX_SCALE * (1 + 0.5 * out(shatter))
            stamp(c, art.ring, cx, cy, rs, sat, 0.7 * (1 - shatter) ** 1.5)
        if surge > 0:
            stamp(c, swirl_img, cx, cy, usize, sat, 1.0 * surge * (1 + 0.5 * rush), mask=weight)
            stamp(c, swirl_img, cx, cy, usize, hot, 0.7 * surge * (1 + 0.5 * rush), mask=weight)

    def front(c):
        if base > 0:
            img = fx.shell.loop(t)
            stamp(c, img, cx, cy, dome_size, dome_tint, base * 0.62 * (1 + 0.5 * hit + 0.5 * form))
            if hit_p is not None:
                # The game flips the cell's texcoords toward the blow; here, one way.
                stamp(c, fx.hit.shot(hit_p), cx, cy, dome_size, hot, 1.15)
        if surge > 0:
            stamp(c, swirl_img, cx, cy, usize, mix(sat, hot, 0.5), 0.8 * surge * (1 + 0.5 * rush), mask=circ)
            br = 0.8 + 0.2 * math.sin(t * 2 * math.pi / 1.6)
            stamp(c, art.grim, cx, cy, g, hot, min(1, 0.3 * br * surge * (1 + rush)))

    def shards(c):
        if shatter is not None:
            stamp(c, fx.shatter.shot(shatter), cx, cy, g * 2.1, mix(sat, hot, 0.65), 1.0)
        elif forming is not None and level < 1:
            pass
        if forming is not None and base > 0:
            stamp(c, fx.shatter.shot(0.55 * (1 - min(1, forming / 0.75))), cx, cy, g * 2.1, mix(sat, hot, 0.5), 1.0 * max(0, 1 - forming / 0.85))

    return panel.compose(t, behind, front, shards)


labels = []


class Board:
    def __init__(self, prefix):
        art = Art()
        self.fx = Fx(prefix)
        self.small = Panel(art, 180)
        self.big = Panel(art, 400)
        self.prefix = prefix

    def frame(self, t):
        W, H = 1920, 1080
        out_ = np.full((H, W, 3), 0.07, np.float32)

        def put(img, x, y):
            h, w = img.shape[:2]
            h = min(h, H - y)
            w = min(w, W - x)
            out_[y:y + h, x:x + w] = img[:h, :w]

        c = t % CYCLE
        pw = self.small.w + 14
        x = 16
        for name, kind, tint in (("current gold", 0, "gold"), ("rendered gold", 1, "gold"), ("current frost", 0, "frost"), ("rendered frost", 1, "frost")):
            img = render_current(self.small, c, tint) if kind == 0 else render_new(self.small, self.fx, c, tint)
            put(img, x, 40)
            labels.append((x, 12, name))
            x += pw
        y = 40 + self.small.h + 32
        a = render_current(self.big, c, "gold")
        b = render_new(self.big, self.fx, c, "gold")
        put(a, 16, y)
        put(b, 16 + self.big.w + 12, y)
        labels.append((16, y - 26, "zoom: current (real GlobeAura.lua numbers)"))
        labels.append((16 + self.big.w + 12, y - 26, "zoom: rendered"))
        state = "forming" if c < 0.8 else "idle + hits" if c < BREAK_AT else "shatter" if c < BREAK_AT + SHATTER else "" if c < SURGE_FROM else "surge"
        labels.append((W - 330, 12, f"t={c:4.1f}s  {state}"))
        return out_


def compose_board(b, t):
    labels.clear()
    f = b.frame(t)
    for lx, ly, text in labels:
        f = gc.label(f, text, (lx, ly))
    return f


def still(prefix, out_path):
    b = Board(prefix)
    # A contact sheet of the moments that matter.
    moments = [(0.45, "form"), (2.5, "idle"), (1.75, "hit"), (BREAK_AT + 0.12, "crack"), (BREAK_AT + 0.42, "shatter"), (7.0, "surge")]
    a = []
    for t, name in moments:
        row = [render_current(b.big, t, "gold"), render_new(b.big, b.fx, t, "gold")]
        strip = np.hstack(row)
        a.append(gc.label(strip, f"{name}  current | rendered", (10, 8)))
    h = a[0].shape[1]
    grid = np.vstack([np.hstack(a[i:i + 2]) if i + 1 < len(a) else a[i] for i in range(0, len(a), 2)])
    s = 1600 / grid.shape[1]
    grid = cv2.resize(grid, (1600, int(grid.shape[0] * s)), interpolation=cv2.INTER_AREA)
    Image.fromarray(np.clip(grid * 255, 0, 255).astype(np.uint8)).save(out_path)
    print(out_path)


def video(prefix, out_path):
    import imageio_ffmpeg
    b = Board(prefix)
    fps, seconds = 60, 20.0
    writer = imageio_ffmpeg.write_frames(out_path, (1920, 1080), fps=fps, codec="libx264", quality=None, bitrate="18M", pix_fmt_out="yuv420p", macro_block_size=None)
    writer.send(None)
    n = int(fps * seconds)
    for i in range(n):
        writer.send(np.clip(compose_board(b, i / fps) * 255, 0, 255).astype(np.uint8).tobytes())
        if i % 120 == 0:
            print(i, n, flush=True)
    writer.close()
    print(out_path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sheets":
        sheets(sys.argv[2], sys.argv[3])
    elif mode == "still":
        still(sys.argv[2], sys.argv[3])
    elif mode == "video":
        video(sys.argv[2], sys.argv[3])
