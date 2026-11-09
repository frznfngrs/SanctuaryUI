"""Packs the shield option renders into flipbook sheets and composites them over the real console
art, the way the game would, beside today's Crystal shell and shatter.

  python globe_shields_compare.py sheets WORK SHEETS   WORK/np/*.npy + WORK/bl/<mode>/f###.png
  python globe_shields_compare.py still  SHEETS OUT.png
  python globe_shields_compare.py video  SHEETS OUT.mp4 [--jobs N]

Sheets are white RGB with luminance in alpha, the addon's glow-art format, for ADD. Everything is
drawn the way the existing Sprite()/stamp() pipeline does: one tint per flipbook, ADD only, no
masks but the globe circle.
"""
import argparse
import math
import os
import subprocess
import sys
from multiprocessing import Pool

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402
import globe_fx_compare as gfc  # noqa: E402

stamp, smooth, out_ease, mix = gfc.stamp, gfc.smooth, gfc.out, gfc.mix

# name: frames, cols, cell, sheet w, h, seconds
SPECS = {
    "aegis": (64, 8, 256, 2048, 2048, 8.0),
    "aegis_hit": (16, 4, 256, 1024, 1024, 0.45),
    "rime": (32, 8, 256, 2048, 1024, 5.0),
    "rime_hit": (16, 4, 256, 1024, 1024, 0.45),
    "hex": (32, 8, 256, 2048, 1024, 6.0),
    "hex_hit": (16, 4, 256, 1024, 1024, 0.45),
    "bulwark": (32, 8, 256, 2048, 1024, 5.0),
    "bulwark_hit": (16, 4, 256, 1024, 1024, 0.45),
    "dissolve": (25, 5, 409, 2048, 2048, 1.3),
    "shockwave": (16, 4, 256, 1024, 1024, 0.7),
    "melt": (25, 5, 409, 2048, 2048, 1.5),
    "crumble": (25, 5, 409, 2048, 2048, 1.2),
}
FROM_BLENDER = {"aegis", "bulwark", "bulwark_hit", "crumble"}
SUBS = {"crumble": 3}

TINTS = {
    "holy": ((1.0, 0.78, 0.32), (1.0, 0.95, 0.78)),
    "frost": ((0.35, 0.72, 1.0), (0.86, 0.96, 1.0)),
    "arcane": ((0.55, 0.35, 1.0), (0.85, 0.75, 1.0)),
    "fire": ((1.0, 0.35, 0.08), (1.0, 0.75, 0.4)),
    "shadow": ((0.62, 0.28, 1.0), (0.88, 0.74, 1.0)),
    "steel": ((0.65, 0.72, 0.82), (0.95, 0.97, 1.0)),
    "bark": ((0.62, 0.42, 0.2), (0.95, 0.8, 0.55)),
}

# Idle gains are set for how long these stay up: rim weighted, a look you can leave on.
OPTIONS = [
    dict(key="aegis", title="Aegis", tints=("holy", "steel"), brk="dissolve", tk=0.55, idle=0.72, hit=1.0, halo=0.42,
         brk_gain=1.0, brk_tk=0.5),
    dict(key="rime", title="Rime", tints=("frost", "arcane"), brk="melt", tk=0.5, idle=1.0, hit=1.0, halo=0.18,
         brk_gain=1.2, brk_tk=0.5),
    dict(key="hex", title="Hex ward", tints=("arcane", "fire"), brk="shockwave", tk=0.45, idle=1.0, hit=1.0, halo=0.0,
         brk_gain=1.0, brk_tk=0.55),
    dict(key="bulwark", title="Bulwark", tints=("steel", "bark"), brk="crumble", tk=0.6, idle=0.8, hit=1.0, halo=0.0,
         brk_gain=1.05, brk_tk=0.6),
]
BREAK_LABEL = {"dissolve": "Dissolve", "melt": "Melt", "shockwave": "Shockwave", "crumble": "Crumble", "shatter": "today's shatter"}

CYCLE = 6.2
FORM = 0.35
HITS = (1.6, 2.5)
HIT = 0.45
BREAK_AT = 3.5
FILL = 0.60


def read16(path):
    im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("missing " + path)
    return im[..., :3].mean(axis=2).astype(np.float32) / 65535


def load_frames(work, name):
    n, _cols, cell, *_ = SPECS[name]
    if name in FROM_BLENDER:
        d = os.path.join(work, "bl", name)
        subs = SUBS.get(name, 1)
        frames = []
        for i in range(n):
            if subs == 1:
                a = read16(os.path.join(d, f"f{i:03d}.png"))
            else:
                a = sum(read16(os.path.join(d, f"f{i:03d}_{k}.png")) for k in range(subs)) / subs
            frames.append(cv2.resize(a, (cell, cell), interpolation=cv2.INTER_AREA))
        return np.stack(frames)
    return np.load(os.path.join(work, "np", name + ".npy"))


def grade(name, a):
    """Render -> display luminance. Metal is pushed so highlights carry the form and the bulk of
    each plate stays dim: ADD adds, it can't darken, so a bright plate would be a white wedge."""
    n = len(a)
    if name == "aegis":
        a = np.clip(a / np.percentile(a, 99.9), 0, 1) ** 1.25
    elif name == "bulwark":
        a = np.clip(a / np.percentile(a, 99.7), 0, 1) ** 1.9
    elif name == "bulwark_hit":
        idle_top = np.percentile(a[-1], 99.7)
        a = np.clip(a / idle_top, 0, 2.2) ** 1.5
        # A hit adds over the idle, so subtract what idle already draws.
        base = a[-1].copy()
        a = (np.clip(a - base, 0, 2.0) * 1.6 + sparks(a.shape[1], n) * 1.7) * gfc.cell_edge_fade(a.shape[1], 0.9, 1.0)
    elif name == "crumble":
        a = np.clip(a / np.percentile(a[6:14], 99.5), 0, 1.15) ** 1.15
        t = np.arange(n, dtype=np.float32) / (n - 1)
        env = 1 - np.clip((t - 0.62) / 0.38, 0, 1) ** 1.6
        a = a * env[:, None, None] * gfc.cell_edge_fade(a.shape[1], 0.74, 0.98)
    elif name == "aegis_hit":
        a = a * 1.5
    elif name == "dissolve":
        a = a * gfc.cell_edge_fade(a.shape[1], 0.82, 0.99)
    return np.clip(a, 0, 1)


def sparks(cell, n, half=1.08, blow_deg=38.0):
    """Hot metal off the struck plate: short ballistic streaks, a clang, not a glow."""
    rng = np.random.default_rng(7)
    px = cell / (2 * half)
    a0 = math.radians(blow_deg)
    start = np.array([math.cos(a0), math.sin(a0)]) * 0.93
    K = 48
    ang = a0 + rng.normal(0, 1.1, K)
    spd = rng.uniform(0.5, 2.8, K)
    t0 = rng.uniform(0, 0.05, K)
    out = np.zeros((n, cell, cell), np.float32)
    for i in range(n):
        t = i / (n - 1) * 0.45
        img = np.zeros((cell, cell), np.float32)
        for k in range(K):
            age = t - t0[k]
            if age <= 0 or age > 0.36:
                continue
            d = np.array([math.cos(ang[k]), math.sin(ang[k])])
            p = start + d * spd[k] * age + np.array([0, -2.0 * age * age])
            q = p - d * max(spd[k] * 0.035, 0.012)
            p0 = (int((q[0] + half) * px), int((half - q[1]) * px))
            p1 = (int((p[0] + half) * px), int((half - p[1]) * px))
            cv2.line(img, p0, p1, float(1 - age / 0.36), 1, cv2.LINE_AA)
        out[i] = cv2.GaussianBlur(img, (0, 0), 0.6) * 1.6 + cv2.GaussianBlur(img, (0, 0), 2.2) * 0.9
    return out


def pack(name, frames):
    n, cols, cell, w, h, _ = SPECS[name]
    sheet = np.zeros((h, w), np.uint8)
    for i, f in enumerate(frames):
        y, x = divmod(i, cols)
        sheet[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] = np.clip(f * 255 + 0.5, 0, 255).astype(np.uint8)
    white = np.full((h, w), 255, np.uint8)
    return Image.merge("RGBA", [Image.fromarray(white), Image.fromarray(white), Image.fromarray(white), Image.fromarray(sheet)])


def sheets(work, out):
    os.makedirs(out, exist_ok=True)
    for name in SPECS:
        a = grade(name, load_frames(work, name))
        pack(name, a).save(os.path.join(out, name + ".png"), compress_level=1)
        n, _, cell, w, h, _ = SPECS[name]
        print(f"{name:12s} {w}x{h} cell {cell} n {n}  {w * h * 4 / 1048576:.0f} MB")


class Book:
    def __init__(self, sheets_dir, name):
        self.n, cols, cell, _, _, self.secs = SPECS[name]
        a = np.asarray(Image.open(os.path.join(sheets_dir, name + ".png")).getchannel("A"), np.float32) / 255
        self.frames = [a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] for y, x in
                       (divmod(i, cols) for i in range(self.n))]

    def loop(self, t):
        x = (t / self.secs % 1) * self.n
        i = int(x)
        f = x - i
        return self.frames[i % self.n] * (1 - f) + self.frames[(i + 1) % self.n] * f

    def shot(self, p):
        return self.frames[int(min(max(p, 0), 0.9999) * self.n)]


class Art(gfc.Art):
    def __init__(self):
        super().__init__()
        self.shatter = sheet_cells("shell-shatter.png", 25, 5, 409)
        self.today_hit = sheet_cells("shell-hit.png", 16, 4, 256)


def sheet_cells(name, n, cols, cell):
    im = Image.open(os.path.join(gc.ART, name)).convert("RGBA")
    a = np.asarray(im.getchannel("A"), np.float32) / 255
    return [a[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] for y, x in (divmod(i, cols) for i in range(n))]


LIQ_CACHE = {}


class Panel(gfc.Panel):
    """gfc.Panel with its own crop and the 60% fill."""

    def __init__(self, art, globe, crop=(76, -70, 340, 330)):
        self.art, self.globe = art, globe
        self.liq_art = gc.Art(globe)
        k = globe / 160
        self.k = k
        x0, y0, w, h = crop
        self.w, self.h = int(w * k), int(h * k)
        self.cx, self.cy = (243.5 - x0) * k, (99 - y0) * k
        frame = gc.load_png("frame.png")
        glass = gc.load_png("glass.png")
        canvas_f = np.zeros((h, w, 4), np.float32)
        canvas_g = np.zeros((h, w, 4), np.float32)
        ty0, ty1 = -min(y0, 0), min(h, 256 - y0)
        sy = max(y0, 0)
        canvas_f[ty0:ty1, :] = frame[sy:sy + ty1 - ty0, x0:x0 + w]
        canvas_g[ty0:ty1, :] = glass[sy:sy + ty1 - ty0, x0:x0 + w]
        size = (self.w, self.h)
        self.frame = cv2.resize(canvas_f, size, interpolation=cv2.INTER_CUBIC)
        self.glass = cv2.resize(canvas_g, size, interpolation=cv2.INTER_CUBIC)
        half = globe / 2
        self.globe_rect = (int(self.cx - half), int(self.cy - half))
        self.circle = cv2.GaussianBlur(cv2.resize(self.liq_art.mask.squeeze(), (globe, globe)), (0, 0), 0.5)

    def liquid(self, t):
        q = round(t * 15) / 15
        key = (self.globe, q)
        if key not in LIQ_CACHE:
            if len(LIQ_CACHE) > 60:
                LIQ_CACHE.clear()
            col = gc.current(self.liq_art, q, gfc.HEALTH)
            LIQ_CACHE[key] = gc.composite(self.liq_art, col, FILL, q, gfc.HEALTH)
        return LIQ_CACHE[key]


def state(t):
    level = smooth(t / FORM) if t < BREAK_AT else 0.0
    hit_p = None
    for h in HITS:
        if h <= t < h + HIT:
            hit_p = (t - h) / HIT
    return level, hit_p


def render_today(panel, t, tint, strength=1.3):
    """Today's Crystal shell (procedural idle sprites) with the shipped hit and shatter sheets,
    at the numbers in GlobeAura.lua."""
    art, g, cx, cy = panel.art, panel.globe, panel.cx, panel.cy
    sat, hot = TINTS[tint]
    level, hit_p = state(t)
    size = g * 1.03
    hit = (1 - hit_p) ** 2 if hit_p is not None else 0
    form = max(0.0, 1 - t / 0.8) if t < BREAK_AT else 0
    base = smooth(level) * strength
    swell = (1 - 0.08 * form ** 2) * (1 - 0.035 * hit)
    breath = 0.9 + 0.1 * math.sin(t * 2 * math.pi / 3.2)
    shatter = (t - BREAK_AT) / 0.9 if BREAK_AT <= t < BREAK_AT + 0.9 else None

    def behind(c):
        if base > 0:
            stamp(c, art.corona, cx, cy, g * 2 * 0.96, sat, 0.7 * breath * base * (1 + 0.8 * hit))
            if form > 0:
                stamp(c, art.ring, cx, cy, g * 2 * (1 + 0.4 * out_ease(1 - form)), hot, 0.8 * form ** 1.5)
        if shatter is not None:
            rs = g * 2 * (1 + 0.5 * out_ease(shatter))
            stamp(c, art.ring, cx, cy, rs, sat, 0.7 * (1 - shatter) ** 1.5)
            stamp(c, art.ring, cx, cy, rs * 0.99, hot, 0.25 * (1 - shatter) ** 1.5)

    def front(c):
        if base > 0:
            s = size * swell
            stamp(c, art.rim, cx, cy, s, sat, base * (1 + 0.5 * form + hit))
            stamp(c, art.facets, cx, cy, s, hot, 0.65 * base * (0.85 + 0.15 * math.sin(t * 1.7)) * (1 + 1.5 * form + 2.5 * hit), angle=t * 0.03)
            if hit_p is not None:
                img = art.today_hit[int(min(hit_p, 0.9999) * 16)]
                stamp(c, img[:, ::-1], cx, cy, g * 1.09 * swell, hot, 1.15)
            p = (t % 3) / 3
            off = (p - 0.5) * size * 0.8
            stamp(c, art.sheen, cx + off, cy + off, size * 1.6, hot, 0.55 * base * math.sin(p * math.pi), mask=[(art.gmask, cx, cy, size)])

    def shards(c):
        if shatter is not None:
            stamp(c, art.shatter[int(min(shatter, 0.9999) * 25)], cx, cy, g * 2.1, mix(sat, hot, 0.65), 1.0)

    return panel.compose(t, behind, front, shards)


class Option:
    def __init__(self, sheets_dir, spec):
        self.spec = spec
        k = spec["key"]
        self.idle = Book(sheets_dir, k)
        self.hit = Book(sheets_dir, k + "_hit")
        self.brk = Book(sheets_dir, spec["brk"])
        self.brk_secs = SPECS[spec["brk"]][5]

    def render(self, panel, t, tint):
        art, g, cx, cy = panel.art, panel.globe, panel.cx, panel.cy
        sat, hot = TINTS[tint]
        sp = self.spec
        col = mix(sat, hot, sp["tk"])
        level, hit_p = state(t)
        hit = (1 - hit_p) ** 2 if hit_p is not None else 0
        base = smooth(level)
        size = g * 1.08
        breaking = None
        if BREAK_AT <= t < BREAK_AT + self.brk_secs:
            breaking = (t - BREAK_AT) / self.brk_secs
        form = max(0.0, 1 - t / FORM) if t < FORM else 0

        def behind(c):
            if sp["halo"] > 0 and base > 0:
                stamp(c, art.corona, cx, cy, g * 2 * 0.96, sat, sp["halo"] * base * (0.9 + 0.1 * math.sin(t * 2 * math.pi / 3.2)) * (1 + 0.7 * hit))

        def front(c):
            if base > 0:
                swell = (1 - 0.05 * form ** 2) * (1 - 0.015 * hit)
                stamp(c, self.idle.loop(t), cx, cy, size * swell, col, sp["idle"] * base * (1 + 0.35 * hit + 0.6 * form))
                if hit_p is not None:
                    stamp(c, self.hit.shot(hit_p), cx, cy, size, mix(sat, hot, 0.75), sp["hit"])

        def shards(c):
            if breaking is not None:
                stamp(c, self.brk.shot(breaking), cx, cy, g * 2.1, mix(sat, hot, sp["brk_tk"]), sp["brk_gain"])

        return panel.compose(t, behind, front, shards)


def put(canvas, img, x, y):
    H, W = canvas.shape[:2]
    h = min(img.shape[0], H - y)
    w = min(img.shape[1], W - x)
    canvas[y:y + h, x:x + w] = img[:h, :w]


class Video:
    W, H = 1920, 1080

    def __init__(self, sheets_dir):
        art = Art()
        self.options = [Option(sheets_dir, s) for s in OPTIONS]
        self.small = Panel(art, 180)
        self.small_tight = Panel(art, 180, crop=(76, -44, 340, 276))
        self.big = Panel(art, 400, crop=(96, -70, 300, 330))

    # An overview of everything at real size, then each option zoomed beside today.
    def segments(self):
        segs = [("overview", None, CYCLE * 2)]
        for o in self.options:
            segs.append(("detail", o, CYCLE * 1.0))
        return segs

    def total(self):
        return sum(s[2] for s in self.segments())

    def frame(self, t):
        canvas = np.full((self.H, self.W, 3), 0.06, np.float32)
        labels = []
        cur = 0.0
        for kind, opt, dur in self.segments():
            if t < cur + dur:
                local = t - cur
                c = local % CYCLE
                if kind == "overview":
                    self.overview(canvas, c, labels)
                else:
                    self.detail(canvas, c, opt, labels)
                break
            cur += dur
        return canvas, labels

    def overview(self, canvas, c, labels):
        pw = self.small.w + 1
        top = 44
        rows = [("today: Crystal shell", 0), ("", 1)]
        for row, offs in enumerate((0, 1)):
            y = top + row * (self.small.h + 38)
            x = 2
            tint_today = ("holy", "frost")[row]
            img = render_today(self.small, c, tint_today)
            put(canvas, img, x, y)
            labels.append((x + 4, y - 26, f"today: Crystal shell ({tint_today})"))
            x += pw
            for o in self.options:
                tint = o.spec["tints"][row]
                img = o.render(self.small, c, tint)
                put(canvas, img, x, y)
                labels.append((x + 4, y - 26, f"{o.spec['title']} + {BREAK_LABEL[o.spec['brk']]} ({tint})"))
                x += pw
        state_ = "forming" if c < FORM else "idle" if c < HITS[0] else "HIT" if c < HITS[1] + HIT else "idle" if c < BREAK_AT else "BREAK" if c < BREAK_AT + 1.5 else "(rekindle)"
        labels.append((self.W - 330, self.H - 34, f"real size 180 px   {state_}  t={c:.1f}"))

    def detail(self, canvas, c, opt, labels):
        spec = opt.spec
        for j, tint in enumerate(spec["tints"]):
            y = 28 + j * (self.small_tight.h + 26)
            put(canvas, opt.render(self.small_tight, c, tint), 8, y)
            labels.append((12, y - 22, f"{spec['title']}  real size, {tint}"))
        y = 28 + 2 * (self.small_tight.h + 26)
        put(canvas, render_today(self.small_tight, c, spec["tints"][0]), 8, y)
        labels.append((12, y - 22, f"today: Crystal  real size, {spec['tints'][0]}"))
        x = 8 + self.small.w + 12
        put(canvas, opt.render(self.big, c, spec["tints"][0]), x, 28)
        labels.append((x + 8, 4, f"{spec['title']}  zoom 2.2x  (break: {BREAK_LABEL[spec['brk']]})"))
        put(canvas, render_today(self.big, c, spec["tints"][0]), x + self.big.w + 8, 28)
        labels.append((x + self.big.w + 16, 4, "today: Crystal shell + shatter  zoom 2.2x"))
        state_ = "forming" if c < FORM else "idle" if c < HITS[0] else "HIT" if c < HITS[1] + HIT else "idle" if c < BREAK_AT else "BREAK" if c < BREAK_AT + 1.5 else "(rekindle)"
        labels.append((self.W - 290, self.H - 34, state_))


VIDEO = None


def compose(v, t):
    canvas, labels = v.frame(t)
    img = np.clip(canvas, 0, 1)
    pil = Image.fromarray((img * 255).astype(np.uint8))
    from PIL import ImageDraw, ImageFont
    d = ImageDraw.Draw(pil)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 19)
    for x, y, text in labels:
        d.text((x, y), text, fill=(235, 225, 205), font=font)
    return np.asarray(pil)


def worker(job):
    sheets_dir, tmp, idx, f0, f1, fps = job
    global VIDEO
    if VIDEO is None:
        VIDEO = Video(sheets_dir)
    import imageio_ffmpeg
    path = os.path.join(tmp, f"piece{idx:03d}.mp4")
    w = imageio_ffmpeg.write_frames(path, (Video.W, Video.H), fps=fps, codec="libx264", quality=None,
                                    bitrate=None, pix_fmt_out="yuv420p", macro_block_size=1,
                                    output_params=["-crf", "20", "-preset", "veryfast"])
    w.send(None)
    for i in range(f0, f1):
        w.send(compose(VIDEO, i / fps).tobytes())
    w.close()
    return path


def video(sheets_dir, out_path, jobs):
    import imageio_ffmpeg
    fps = 60
    v = Video(sheets_dir)
    n = int(v.total() * fps)
    print("frames", n)
    tmp = os.path.join(os.path.dirname(sheets_dir.rstrip("/")), "pieces")
    os.makedirs(tmp, exist_ok=True)
    chunk = n // jobs + 1
    work = [(sheets_dir, tmp, i, i * chunk, min(n, (i + 1) * chunk), fps) for i in range(jobs)]
    with Pool(jobs) as pool:
        paths = pool.map(worker, work)
    lst = os.path.join(tmp, "list.txt")
    with open(lst, "w") as f:
        for p in paths:
            f.write(f"file '{p}'\n")
    subprocess.check_call([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out_path])
    print(out_path, f"{os.path.getsize(out_path) / 1e6:.1f} MB")


def still(sheets_dir, out_path):
    art = Art()
    options = [Option(sheets_dir, s) for s in OPTIONS]
    real = Panel(art, 180, crop=(76, -44, 340, 276))
    zoom = Panel(art, 300, crop=(96, -70, 300, 330))
    moments = [("idle", 1.2), ("hit", HITS[0] + 0.05), ("break 12%", None), ("break 40%", None), ("break 75%", None)]
    rows = []
    cols = len(moments)

    def panel_row(name, render_real, render_zoom, tints, brk_secs):
        cells = [render_real(tints[0]), render_real(tints[1])]
        for label, m in moments:
            if m is None:
                frac = float(label.split("%")[0].split()[1]) / 100
                t = BREAK_AT + brk_secs * frac
            else:
                t = m
            cells.append(render_zoom(t, tints[0]))
        return cells

    all_cells = []
    for o in options:
        def rr(tint, o=o):
            return o.render(real, 1.2, tint)
        def rz(t, tint, o=o):
            return o.render(zoom, t, tint)
        all_cells.append((o.spec["title"] + " + " + BREAK_LABEL[o.spec["brk"]], panel_row(o.spec["key"], rr, rz, o.spec["tints"], o.brk_secs), o.spec["tints"]))

    def rr_t(tint):
        return render_today(real, 1.2, tint)

    def rz_t(t, tint):
        return render_today(zoom, t, tint)

    all_cells.insert(0, ("today: Crystal + shatter", panel_row("today", rr_t, rz_t, ("holy", "frost"), 0.9), ("holy", "frost")))
    heads = ["real size", "real size"] + ["zoom " + m[0] for m in moments]
    W = 2 * real.w + 3 * 8
    Wz = zoom.w
    cw = [real.w, real.w] + [Wz] * cols
    H = 58 + (zoom.h + 30) * len(all_cells)
    canvas = np.full((H, sum(cw) + 8 * (len(cw) + 1), 3), 0.06, np.float32)
    labels = []
    for r, (title, cells, tints) in enumerate(all_cells):
        y = 58 + r * (zoom.h + 30)
        x = 8
        labels.append((x, y - 28, title))
        for c, img in enumerate(cells):
            put(canvas, img, x, y + (zoom.h - img.shape[0]) // 2)
            if r == 0:
                labels.append((x + 2, 2, heads[c]))
            if c < 2:
                labels.append((x + 2, y + (zoom.h - img.shape[0]) // 2 - 22, tints[c]))
            x += cw[c] + 8
    img = np.clip(canvas, 0, 1)
    pil = Image.fromarray((img * 255).astype(np.uint8))
    from PIL import ImageDraw, ImageFont
    d = ImageDraw.Draw(pil)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    for x, y, text in labels:
        d.text((x, y), text, fill=(235, 225, 205), font=font)
    pil.save(out_path, optimize=True)
    print(out_path, pil.size, f"{os.path.getsize(out_path) / 1e6:.1f} MB")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode")
    p.add_argument("a")
    p.add_argument("b")
    p.add_argument("--jobs", type=int, default=6)
    a = p.parse_args()
    if a.mode == "sheets":
        sheets(a.a, a.b)
    elif a.mode == "still":
        still(a.a, a.b)
    elif a.mode == "video":
        video(a.a, a.b, a.jobs)


if __name__ == "__main__":
    main()
