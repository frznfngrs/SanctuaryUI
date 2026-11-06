#!/usr/bin/env python3
"""Build SanctuaryUI/Art from the modern Diablo III PC HUD textures.

Sources are decoded PNGs in art-src/hud (extract with tools/extract_d3.sh).
Every output is padded to power-of-two sizes; the Lua side uses the texcoords
noted next to each file.

  frame.png      2048x256  BottomBar_GameRes widened to 1595 (two extra sockets, a sixth menu plate), glass cut out, key plaques (1595x201 used)
  glass.png      2048x256  the cut-out glass, drawn ADD over the liquid (same coords as frame)
  liquid.png     256x256   healthBall_liquid as shaded luminance in a circle, tinted by vertex color
  hotline.png    256x32    surface band at the liquid level, white, tinted by vertex color
  xp-*.png       1024x8    rail fills (orange, gold, blue, neutral white), stretched from 744
  menu.png       512x256   menu buttons + town portal + bag + flyout tome, 8 columns of 40x66, rows normal/hover/pressed
  button-glow.png 256x256  bottomBar_buttonFX_frameGlow, the hover glow
  socket.png     128x128   one empty skill socket with border (76x80 used)
  socket-hover/press.png 128x128  gold rim + glow; the button maps to the inner 96x96
  bag-frame.png  1024x1024 D3 inventory window: header (600x155), body band (600x300), footer (600x207)
  bank-frame.png 1024x1024 the same, with D3's stash header (treasure-chest medallion)
  bag-cells.png  512x64    item cells: empty, uncommon, rare, epic, legendary, heirloom, new
  d3-button.png  128x64    framed D3 plate for text buttons (120x52 used)
  pips.png       512x64    socket, amethyst, emerald, ruby, topaz, diamond, round glow, socket ring alone (64 px cells)
  liquid-shimmer.png 128x128  seamless surface texture, scrolled inside the surface band
  pip-horn.png   128x128   D3 horned skull ring frame, hole (42 px) centred, rotated per small globe
  unit-fill*.png 512x16   D3's red health strip (and a white copy to tint), lighting levelled along its length
  unit-well.png  512x16    D3's dark empty strip, under the health bar so missing health is shaded
  unit-gloss.png 8x32      inner shadow and glass band, over the whole health bar
  unit-glow.png  64x32     ember at the health bar's leading edge, ADD: bloom (0-18) and hot core (32-50), white, tinted in Lua
  target-rings.png 512x128 D3 hero portrait frames for the target portrait (normal, elite, boss), hole centred
  pip-sockets.png 512x64   Kanai's Cube socket rims, centres open: black, orange, green, red, blue
  blade.png      64x256    Demon Hunter split-globe blade, widened sheet x 1329..1393 (64x201 used)
  liquid-left/right.png 128x256  halves of liquid.png for the split resource globe (no-mask fallback)
  liquid-tile.png 256x256  seamless HD luminance tile of the liquid, scrolled/rotated with REPEAT texcoords
  liquid-wisps.png 256x256 seamless curling filaments (alpha), crossfaded in two phases
  liquid-streaks.png 256x256  seamless white streaks (alpha), scrolled faster over the liquid
  globe-shade.png 512x512  black sphere shading lit from the top left (alpha), fixed over the liquid
  globe-rim.png  512x512   inner rim light (alpha), brightest at the bottom, tinted per globe
  globe-mask.png 512x512   anti-aliased circle mask for the scrolling layers
  surface-glow.png / surface-shimmer.png 256x32  the liquid surface, sliced into a moving wave
  mote.png       32x32     soft glow for motes rising through the liquid
  (animated_liquid needs numpy and scipy)
  menu-flyout.png 512x256  the menu flyout's buttons: menu plates with gold icons, 6 columns of 40x66, rows normal/hover/pressed
  unit-fill(-white).png 512x16  the red health fill and its neutral copy (StatusBar textures)
  cast-fill.png  512x16    D3's orange progress fill (2DUIControls), the target cast bar
  unit-frames.png 1024x256 D3 enemy health frames (boss banner, elite gold, normal silver), red and neutral fills, party frames
  skill-timer.png 128x32   skill timer tab (steel, gold) and its amber and green fills, from 2DUIBottomBar
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "art-src" / "hud"
OUT = ROOT / "SanctuaryUI" / "Art"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_art  # noqa: E402  (tex decoder)

GLOBE_R = 80
GLOBE_CY = 99
# Positions in the widened 1595 px console (see widen()).
GLOBE_CX = (243.5, 1354.5)
RAIL = (336, 96, 1259, 104)

# The stone bar repeats every 74 px: gap, socket, rail post. Copying one period from just
# after a post (413) to the end of the next (487) adds a socket that was never there.
COLUMN = (413, 487)
# Left: after socket 2, where nothing sits above the rail. Right: after the old potion
# socket, just past the tail of the bat wing. One on each side keeps the skull centred.
INSERT_AT = (487, 859)
# The menu panel is widened by one plate (31 px) for the bag button. The slice comes from a
# stretch of panel with no rail post above it and no ornament (old x 952-983), and goes in
# right after it, so the rail, panel border and base continue unbroken.
PANEL_SLICE = (1100, 1131)
WIDE_W = 1416 + 2 * (COLUMN[1] - COLUMN[0]) + (PANEL_SLICE[1] - PANEL_SLICE[0])

# Socket centres in the widened sheet, left to right: nine action sockets.
# The gold pair (6, 7) keeps D3's plaques; every other socket gets a steel copy.
SOCKET_CX = (373.5, 447.5, 521.5, 595.5, 669.5, 746.0, 819.0, 893.5, 967.5)
GOLD_CX = (746.0, 819.0)


def widen(image: Image.Image) -> Image.Image:
    col = image.crop((COLUMN[0], 0, COLUMN[1], image.height))
    out = image
    shift = 0
    for at in INSERT_AT:
        x = at + shift
        wider = Image.new("RGBA", (out.width + col.width, out.height), (0, 0, 0, 0))
        wider.paste(out.crop((0, 0, x, out.height)), (0, 0))
        wider.paste(col, (x, 0))
        wider.paste(out.crop((x, 0, out.width, out.height)), (x + col.width, 0))
        out = wider
        shift += col.width
    piece = out.crop((PANEL_SLICE[0], 0, PANEL_SLICE[1], out.height))
    x = PANEL_SLICE[1]
    wider = Image.new("RGBA", (out.width + piece.width, out.height), (0, 0, 0, 0))
    wider.paste(out.crop((0, 0, x, out.height)), (0, 0))
    wider.paste(piece, (x, 0))
    wider.paste(out.crop((x, 0, out.width, out.height)), (x + piece.width, 0))
    return wider


def load_frame(name: str) -> Image.Image:
    return widen(load(name))

# Menu cells in 2DUIBottomBar, by state: sheet x centre of each cell, rows 58..124.
# D3's resting buttons are the muted maroon plates; the bright orange-bordered plates are
# hover, and the slightly smaller plates are pressed. The portal's third state is disabled.
MENU_CELLS = [
    # name,       normal, hover, pressed/disabled
    ("character", 1385, 89, 687),
    ("spellbook", 135, 181, 227),
    ("talents", 273, 319, 365),
    ("social", 411, 457, 503),
    ("quests", 549, 595, 1339),
    ("hearth", 1581, 1635, 1526),
]
CELL_W, CELL_H = 40, 66


def load(name: str) -> Image.Image:
    png = SRC / f"{name}.png"
    if not png.is_file():
        tex = SRC / f"{name}.tex"
        if not tex.is_file():
            tex = ROOT / "art-src" / "spike2" / f"{name}.tex"
        if not tex.is_file():
            tex = ROOT / "art-src" / "spike3" / f"{name}.tex"
        prepare_art.parse_tex(tex.read_bytes())["image"].convert("RGBA").save(png)
    return Image.open(png).convert("RGBA")


def pad(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(image)
    return out


def frame_and_glass() -> None:
    frame = load_frame("BottomBar_GameRes")
    glass = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    fpx, gpx = frame.load(), glass.load()
    for cx in GLOBE_CX:
        for y in range(GLOBE_CY - GLOBE_R, frame.height):
            for x in range(int(cx - GLOBE_R), int(cx + GLOBE_R) + 1):
                if (x - cx) ** 2 + (y - GLOBE_CY) ** 2 > GLOBE_R ** 2:
                    continue
                r, g, b, a = fpx[x, y]
                if a < 200:
                    gpx[x, y] = (r, g, b, a)
                    fpx[x, y] = (r, g, b, 0)
    blank_mouse_plaques(frame)
    add_key_plaques(frame)
    pad(frame, (2048, 256)).save(OUT / "frame.png")
    pad(glass, (2048, 256)).save(OUT / "glass.png")


# The gold sockets carry D3's mouse-button icons. WoW binds them to keys, so the mouse is
# filled with dark stone and the gold oval stays as a plaque for the key label.
MOUSE_PLAQUES = ((746, 186.5), (819, 186.5))


def blank_mouse_plaques(frame: Image.Image) -> None:
    px = frame.load()
    rx, ry = 7.0, 10.5
    for cx, cy in MOUSE_PLAQUES:
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if abs((x - cx) / rx) ** 4 + abs((y - cy) / ry) ** 4 > 1:
                    continue
                r, g, b, a = px[x, y]
                if r > b + 40 and r > 110:
                    continue  # gold rim
                shade = int(34 - 14 * (y - (cy - ry)) / (2 * ry))
                px[x, y] = (shade, shade - 2, shade - 4, 255)


def add_key_plaques(frame: Image.Image) -> None:
    """Every socket gets a key plaque. The gold one is lifted from under gold socket 6 by
    diffing against the strip under plain socket 5, re-toned to steel, and stamped under
    each plain socket."""
    half = 36
    gold, plain = GOLD_CX[0], SOCKET_CX[4]
    a = frame.crop((int(gold) - half, 172, int(gold) + half, frame.height))
    b = frame.crop((int(plain) - half, 172, int(plain) + half, frame.height))
    apx, bpx = a.load(), b.load()
    plaque = Image.new("RGBA", a.size, (0, 0, 0, 0))
    ppx = plaque.load()
    for y in range(a.height):
        for x in range(a.width):
            # Rows above 179 are the socket's own bottom border (gold vs steel); keep only
            # the oval there, which overlaps that border.
            if y + 172 < 179 and abs(x - half) > 9:
                continue
            p, q = apx[x, y], bpx[x, y]
            if sum(abs(i - j) for i, j in zip(p[:3], q[:3])) > 45:
                r, g, bl, al = p
                lum = 0.3 * r + 0.59 * g + 0.11 * bl
                gold_ish = r > bl + 12
                # Gold to steel: keep the light, drop the warmth.
                if gold_ish:
                    lum = min(255, lum * 1.15)
                    ppx[x, y] = (int(lum * 0.93), int(lum * 0.97), int(min(255, lum * 1.04)), al)
                else:
                    ppx[x, y] = p
    for cx in SOCKET_CX:
        if cx in GOLD_CX:
            continue
        frame.alpha_composite(plaque, (int(cx) - half, 172))


def liquid() -> None:
    d = 256
    r = d // 2
    lum = load("healthBall_liquid").convert("L").resize((d, d), Image.LANCZOS)
    lum = ImageEnhance.Contrast(lum).enhance(1.6)
    # Normalise so the brightest swirl reaches full white; vertex color then sets the hue.
    lo, hi = lum.getextrema()
    lum = lum.point(lambda v: int(255 * (v - lo) / max(1, hi - lo) * 0.55 + 255 * 0.45))
    shade = Image.new("L", (d, d), 0)
    draw = ImageDraw.Draw(shade)
    for i in range(r, 0, -1):
        draw.ellipse((r - i, r - i, r + i, r + i), fill=int(255 * (0.45 + 0.55 * (1 - (i / r) ** 3) ** 0.5)))
    lum = ImageChops.multiply(lum, shade)
    circle = Image.new("L", (d, d), 0)
    ImageDraw.Draw(circle).ellipse((0, 0, d - 1, d - 1), fill=255)
    out = Image.merge("RGBA", (lum, lum, lum, circle))
    out.save(OUT / "liquid.png")


def wrap_blend(image: Image.Image, band: int = 6) -> Image.Image:
    """Cross-fade each edge with the opposite one so REPEAT scrolling has no seam."""
    out = image.copy()
    w, h = image.size
    src, px = image.load(), out.load()

    def mix(a, b, t):
        if isinstance(a, int):
            return int(a * (1 - t) + b * t)
        return tuple(int(a[k] * (1 - t) + b[k] * t) for k in range(len(a)))

    for i in range(band):
        t = 0.5 * (1 - i / band)
        for y in range(h):
            a, b = src[i, y], src[w - 1 - i, y]
            px[i, y] = mix(a, b, t)
            px[w - 1 - i, y] = mix(b, a, t)
    src = out.copy().load()
    for i in range(band):
        t = 0.5 * (1 - i / band)
        for x in range(w):
            a, b = src[x, i], src[x, h - 1 - i]
            px[x, i] = mix(a, b, t)
            px[x, h - 1 - i] = mix(b, a, t)
    return out


# --- HD globe layers -------------------------------------------------------------------
# D3's liquid tile is 128 px DXT1 with only ~26 grey levels, so stretching its contrast
# posterises it into blotches. These helpers rebuild it as a clean, truly periodic tile:
# periodic+smooth decomposition removes the seam, FFT filtering is periodic by construction,
# and band-limited FFT noise adds detail that tiles perfectly. Needs numpy and scipy.


def _np():
    import numpy as np  # noqa: PLC0415  (only the globe steps need numpy)

    return np


def periodic(u):
    """Moisan's periodic component: the image minus the smooth field its seams imply."""
    np = _np()
    u = u.astype(np.float64)
    h, w = u.shape
    v = np.zeros_like(u)
    v[0, :] += u[-1, :] - u[0, :]
    v[-1, :] += u[0, :] - u[-1, :]
    v[:, 0] += u[:, -1] - u[:, 0]
    v[:, -1] += u[:, 0] - u[:, -1]
    fy = np.cos(2 * np.pi * np.fft.fftfreq(h))[:, None]
    fx = np.cos(2 * np.pi * np.fft.fftfreq(w))[None, :]
    denom = 2 * fx + 2 * fy - 4
    denom[0, 0] = 1
    s = np.fft.fft2(v) / denom
    s[0, 0] = 0
    return u - np.real(np.fft.ifft2(s))


def periodic_blur(u, sigma):
    np = _np()
    h, w = u.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(u) * g))


def periodic_resize(u, n):
    """Upsample a periodic tile by zero-padding its spectrum: exact, seamless, no ringing at the wrap."""
    np = _np()
    h, w = u.shape
    f = np.fft.fftshift(np.fft.fft2(u))
    out = np.zeros((n, n), dtype=complex)
    oy, ox = (n - h) // 2, (n - w) // 2
    out[oy:oy + h, ox:ox + w] = f
    return np.real(np.fft.ifft2(np.fft.ifftshift(out))) * (n * n) / (h * w)


def periodic_noise(n, lo, hi, beta, seed):
    """Seamless noise from cycles lo..hi per tile with a 1/f^beta spectrum, normalised 0..1."""
    np = _np()
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n, 1 / n)[:, None]
    fx = np.fft.fftfreq(n, 1 / n)[None, :]
    r = np.sqrt(fx * fx + fy * fy)
    band = np.clip((r - lo) / max(1, lo), 0, 1) * np.exp(-((r / hi) ** 2))
    amp = np.where(r > 0, band / np.maximum(r, 1) ** (beta / 2), 0)
    return normalise(np.real(np.fft.ifft2(f * amp)))


def normalise(u, lo_pct=0.5, hi_pct=99.5):
    np = _np()
    lo, hi = np.percentile(u, [lo_pct, hi_pct])
    return np.clip((u - lo) / max(1e-9, hi - lo), 0, 1)


def to_l(u):
    np = _np()
    return Image.fromarray(np.clip(u * 255 + 0.5, 0, 255).astype(np.uint8), "L")


def save_rgba(path, rgb, alpha):
    """rgb, alpha: float arrays 0..1 (rgb may be a single plane, used for all three)."""
    lum = to_l(rgb)
    Image.merge("RGBA", (lum, lum, lum, to_l(alpha))).save(path)


def disc(n, ss=4):
    """Sphere geometry on an n x n grid, supersampled: (coverage, x, y, z) with x right, y up."""
    np = _np()
    c = (np.arange(n * ss) + 0.5) / (n * ss) * 2 - 1
    x, y = np.meshgrid(c, -c)
    rr = x * x + y * y
    inside = rr < 1
    z = np.sqrt(np.clip(1 - rr, 0, 1))

    def down(a):
        return a.reshape(n, ss, n, ss).mean(axis=(1, 3))

    return down(inside.astype(float)), down(x), down(y), down(z * inside), down


def animated_liquid() -> None:
    """Layers for the moving globe. Tiles scroll and rotate; shade, rim and mask stay put.

    liquid-tile.png    256  D3's liquid, de-banded and seamless, plus periodic detail (luminance)
    liquid-wisps.png   256  domain-warped filaments (alpha), crossfaded in two phases for churn
    liquid-streaks.png 256  D3's streaks, seamless and de-blocked (alpha)
    globe-shade.png    512  sphere shading lit from the top left (black, alpha)
    globe-rim.png      512  inner rim light, strongest at the bottom where light refracts (alpha)
    globe-mask.png     512  anti-aliased circle
    surface-glow.png   256x32  D3's hotline fade, seamless along u, for the wavy surface
    surface-shimmer.png 256x32 D3's surface texture cut to a smooth fade, seamless along u
    mote.png           32   soft glow with a hot core, for rising motes
    """
    np = _np()
    from scipy.ndimage import map_coordinates  # noqa: PLC0415

    n = 256
    src = np.asarray(load("healthBall_liquid").convert("L"), dtype=np.float64)
    base = periodic_resize(periodic(src), n)
    # The source steps every ~1/26 of the range and has 4x4 DXT blocks (8 px here); a 2.6 px
    # blur melts both and keeps the D3 swirl shapes.
    base = normalise(periodic_blur(base, 2.6))
    detail = periodic_noise(n, 5, 40, 2.2, seed=7)
    fine = periodic_noise(n, 24, 90, 1.4, seed=11)
    v = normalise(0.7 * base + 0.22 * detail + 0.08 * fine)
    v = v * v * (3 - 2 * v)  # gentle S-curve: richer darks under the bright swirls
    save_rgba(OUT / "liquid-tile.png", 0.4 + 0.6 * v, np.ones_like(v))

    # Wisps: ridged noise pushed along a smooth flow field, so filaments curl like smoke in liquid.
    w1 = periodic_noise(n, 1, 5, 3.0, seed=21) - 0.5
    w2 = periodic_noise(n, 1, 5, 3.0, seed=22) - 0.5
    body = periodic_noise(n, 3, 22, 2.4, seed=23)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    warped = map_coordinates(body, [yy + w1 * 70, xx + w2 * 70], order=3, mode="grid-wrap")
    ridge = (1 - np.abs(2 * normalise(warped) - 1)) ** 6
    density = periodic_noise(n, 1, 4, 3.0, seed=24)
    wisps = normalise(periodic_blur(ridge * (0.35 + 0.65 * density), 0.7), 1, 99.8)
    save_rgba(OUT / "liquid-wisps.png", np.ones_like(wisps), wisps)

    streak = np.asarray(load("healthBall_streaks_alpha").convert("L"), dtype=np.float64)
    streak = np.clip(periodic_blur(periodic(streak), 0.8), 0, 255) / 255
    streak = np.clip(streak / max(1e-6, np.percentile(streak, 99.7)), 0, 1)
    save_rgba(OUT / "liquid-streaks.png", np.ones_like(streak), streak)

    d = 512
    cover, x, y, z, down = disc(d)
    # Shade: lit from top left and in front. Centre stays clear, edges and bottom right fall
    # into shadow, so the liquid reads as a ball rather than a disc.
    lx, ly, lz = -0.42, 0.5, 0.76
    norm = (lx * lx + ly * ly + lz * lz) ** 0.5
    lambert = np.clip((x * lx + y * ly + z * lz) / norm, 0, 1)
    lit = (0.18 + 0.82 * z ** 0.6) * (0.72 + 0.28 * lambert)
    save_rgba(OUT / "globe-shade.png", np.zeros_like(lit), np.clip(1 - lit, 0, 1) * (cover > 0))

    # Rim: a thin band of light just inside the edge, bright at the bottom (light through the
    # liquid) and faint at the top.
    r = np.sqrt(x * x + y * y)
    band = np.clip((r - 0.74) / 0.22, 0, 1) ** 2.2 * np.clip((1.0 - r) / 0.05, 0, 1)
    bottom = np.clip(0.5 - 0.5 * y / np.maximum(r, 1e-6), 0, 1) ** 1.6
    rim = band * (0.18 + 0.82 * bottom)
    save_rgba(OUT / "globe-rim.png", np.ones_like(rim), normalise(rim, 0, 100))

    save_rgba(OUT / "globe-mask.png", np.ones_like(cover), cover)

    # Surface strips, seamless along u. The glow keeps D3's ragged lower fringe; the shimmer is
    # cut to a smooth fade so it can scroll without dragging the fringe with it.
    alpha = np.asarray(load("health_hotline_alpha"), dtype=np.float64)[..., 3][:40]
    # Mirrored first, so only the u seam is removed and the fade keeps its shape down the strip.
    alpha = periodic(np.vstack([alpha, alpha[::-1]]))[:40]
    glow = np.asarray(Image.fromarray(alpha.astype(np.float32), "F").resize((256, 32), Image.LANCZOS))
    glow = np.clip(glow / 255, 0, 1)
    save_rgba(OUT / "surface-glow.png", np.ones_like(glow), glow)
    fade = glow.mean(axis=1, keepdims=True) / max(1e-6, glow.mean(axis=1).max())
    sh = np.asarray(load("health_hotline_liquid").convert("L"), dtype=np.float64)
    sh = normalise(periodic_resize(periodic(sh), 256))[:64]
    sh = np.asarray(Image.fromarray(sh.astype(np.float32), "F").resize((256, 32), Image.LANCZOS))
    save_rgba(OUT / "surface-shimmer.png", np.clip(sh, 0, 1), np.repeat(fade, 256, axis=1))

    m = 32
    c = (np.arange(m) + 0.5) / m * 2 - 1
    mx, my = np.meshgrid(c, c)
    rr = mx * mx + my * my
    mote = np.exp(-rr * 9) * 0.75 + np.exp(-rr * 40) * 0.5
    save_rgba(OUT / "mote.png", np.ones_like(mote), np.clip(mote, 0, 1))


def hotline() -> None:
    # The source is a bright edge fading down over ~32 rows (the rest is DXT wrap noise).
    # Keep that fade only: the band's top edge sits on the liquid surface and glows downward.
    alpha = load("health_hotline_alpha").split()[3].crop((0, 0, 128, 40)).resize((256, 32), Image.LANCZOS)
    white = Image.new("L", (256, 32), 255)
    Image.merge("RGBA", (white, white, white, alpha)).save(OUT / "hotline.png")


def xp_fills() -> None:
    sheet = load("2DUIBottomBar")
    strips = {"xp-orange": (9, 9, 753, 17), "xp-blue": (771, 9, 1515, 17), "xp-gold": (9, 35, 753, 43)}
    # Stretched to 1024 wide so a StatusBar can use the whole texture; the rail draws it back at 744.
    for name, box in strips.items():
        sheet.crop(box).resize((1024, 8), Image.LANCZOS).save(OUT / f"{name}.png")
    # Neutral copy of the orange strip for fills tinted by vertex color (reputation).
    orange = sheet.crop(strips["xp-orange"]).resize((1024, 8), Image.LANCZOS)
    lum = ImageEnhance.Contrast(orange.convert("L")).enhance(1.3)
    lo, hi = lum.getextrema()
    lum = lum.point(lambda v: int(255 * (v - lo) / max(1, hi - lo)))
    Image.merge("RGBA", (lum, lum, lum, orange.split()[3])).save(OUT / "xp-white.png")


def menu() -> None:
    sheet = load("2DUIBottomBar")
    atlas = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    for i, (_, *states) in enumerate(MENU_CELLS):
        for row, cx in enumerate(states):
            cell = sheet.crop((cx - CELL_W // 2, 58, cx + CELL_W // 2, 58 + CELL_H))
            atlas.alpha_composite(cell, (i * CELL_W, row * CELL_H))
    # Seventh column: the bag button, D3's coin sack on the sword's plates.
    sack = coin_sack()
    for row, cx in enumerate(MENU_CELLS[0][1:]):
        cell = blank_plate(sheet.crop((cx - CELL_W // 2, 58, cx + CELL_W // 2, 58 + CELL_H)))
        # Pressed plates are drawn smaller in D3, so the icon shrinks with them.
        icon = sack if row < 2 else sack.resize((int(sack.width * 0.9), int(sack.height * 0.9)), Image.LANCZOS)
        cell.alpha_composite(icon, ((CELL_W - icon.width) // 2, (CELL_H - icon.height) // 2 + 1))
        atlas.alpha_composite(cell, (len(MENU_CELLS) * CELL_W, row * CELL_H))
    # Eighth column: the flyout button, D3's tome on the sword's plates.
    book = tome()
    for row, cx in enumerate(MENU_CELLS[0][1:]):
        cell = blank_plate(sheet.crop((cx - CELL_W // 2, 58, cx + CELL_W // 2, 58 + CELL_H)))
        icon = book if row < 2 else book.resize((int(book.width * 0.9), int(book.height * 0.9)), Image.LANCZOS)
        cell.alpha_composite(icon, ((CELL_W - icon.width) // 2, (CELL_H - icon.height) // 2 + 1))
        atlas.alpha_composite(cell, ((len(MENU_CELLS) + 1) * CELL_W, row * CELL_H))
    atlas.save(OUT / "menu.png")


def blank_plate(cell: Image.Image) -> Image.Image:
    """Paint the icon out of a menu plate: each row of the plate's middle is re-drawn as a
    blend between two icon-free columns, which keeps the plate's vertical shading."""
    out = cell.copy()
    px = out.load()
    left, right = 10, 29
    for y in range(6, CELL_H - 6):
        a, b = px[left, y], px[right, y]
        for x in range(left + 1, right):
            t = (x - left) / (right - left)
            px[x, y] = tuple(int(a[k] * (1 - t) + b[k] * t) for k in range(4))
    return out


def tome() -> Image.Image:
    """The pentagram tome from the spellbook tab plate (2DUITabs, selected cell), cut off its red
    plate and re-toned to the embossed gold of the other menu icons, about 36 px tall. Used
    on the flyout button (Spellbook & Panels)."""
    import numpy as np
    from scipy import ndimage

    sheet = np.array(load("2DUITabs")).astype(float)
    row, col = divmod(TAB_ICONS[0] * 3 + 1, 19)
    cell = sheet[row * 151:row * 151 + 151, col * 103:col * 103 + 100]
    r, g, b, a = (cell[..., i] for i in range(4))
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    # The book's four corners in the cell (it sits a little tilted on the plate).
    from PIL import ImageDraw
    outline = Image.new("L", (cell.shape[1], cell.shape[0]), 0)
    ImageDraw.Draw(outline).polygon([(28, 46), (68, 44.5), (70, 103), (29.5, 104)], fill=255)
    book = np.array(outline) > 127
    return gold_icon(cell, book, fit=(21, 31))


def gold_icon(cell: "np.ndarray", mask: "np.ndarray", fit=(22, 30)) -> Image.Image:
    """Re-tone the masked pixels of a 2DUITabs cell to the menu icons' embossed gold and fit
    them to the plate's open middle."""
    import numpy as np

    from scipy import ndimage

    r, g, b = cell[..., 0], cell[..., 1], cell[..., 2]
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    lo, hi = np.percentile(lum[mask], 2), np.percentile(lum[mask], 98)
    # Clipped to 255: an overflow wraps the red channel and leaves green specks.
    v = np.clip(np.clip((lum - lo) / max(1, hi - lo), 0, 1) ** 1.2 * 215 + 62, 0, 255)
    out = np.zeros(cell.shape, dtype=np.uint8)
    out[..., 0] = v
    out[..., 1] = np.clip(v * 0.76, 0, 255)
    out[..., 2] = np.clip(v * 0.32, 0, 255)
    out[..., 3] = np.where(mask, 255, 0)
    # A dark rim under the icon, as the embossed menu icons have.
    rim = ndimage.binary_dilation(mask, iterations=2) & ~mask
    out[rim] = (34, 20, 8, 200)
    img = Image.fromarray(out, "RGBA")
    img = img.crop(img.getbbox())
    scale = min(fit[1] / img.height, fit[0] / img.width)
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)


def tab_icon(icon: int, hull: bool = False) -> Image.Image:
    """An icon lifted off its red 2DUITabs plate (selected cell): everything that isn't the red
    background, cleaned up; hull fills the outline solid (the chest's dark wood reads as red)."""
    import numpy as np
    from scipy import ndimage

    sheet = np.array(load("2DUITabs")).astype(float)
    row, col = divmod(icon * 3 + 1, 19)
    cell = sheet[row * 151:row * 151 + 151, col * 103:col * 103 + 100]
    r, g, b, a = (cell[..., i] for i in range(4))
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    red = (r > 1.6 * g) & (r > 1.6 * b) & (lum < 120)
    mask = (~red) & (a > 200) & (lum > 22)
    inner = np.zeros_like(mask)
    inner[24:-24, 18:-24] = True
    mask = ndimage.binary_opening(mask & inner, iterations=1)
    lab, n = ndimage.label(mask)
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    mask = np.isin(lab, [i + 1 for i, size in enumerate(sizes) if size >= max(25, 0.1 * sizes.max())])
    mask = ndimage.binary_fill_holes(ndimage.binary_closing(mask, iterations=1))
    if hull:
        from scipy.spatial import ConvexHull
        from PIL import ImageDraw
        ys, xs = np.nonzero(mask)
        pts = np.column_stack([xs, ys])
        poly = [tuple(pts[i]) for i in ConvexHull(pts).vertices]
        outline = Image.new("L", (mask.shape[1], mask.shape[0]), 0)
        ImageDraw.Draw(outline).polygon(poly, fill=255)
        mask = np.array(outline) > 127
    return gold_icon(cell, mask)


# The flyout's buttons (Lua: ns.Art.FLYOUT_CELLS): the same menu plates with gold icons.
# Panels a client lacks are left out in Lua; their cells stay in the atlas.
FLYOUT_ICONS = ["spellbook", "professions", "collections", "achievements", "groupfinder", "pvp",
                "legacy", "currency", "reputation"]


def menu_flyout() -> None:
    sheet = load("2DUIBottomBar")
    icons = {
        "spellbook": tome(),
        "professions": tab_icon(11),
        "collections": tab_icon(19, hull=True),
        "achievements": tab_icon(25),
        "groupfinder": tab_icon(8),
        "pvp": None,  # D3's own sword plates (the menu's old character button)
        "legacy": tab_icon(24),  # the rising arrow off the "ascend" plate
        "currency": tab_icon(6),  # gem
        "reputation": tab_icon(15),  # signet ring
    }
    atlas = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    for i, key in enumerate(FLYOUT_ICONS):
        for row, cx in enumerate(MENU_CELLS[0][1:]):
            plate = sheet.crop((cx - CELL_W // 2, 58, cx + CELL_W // 2, 58 + CELL_H))
            if icons[key] is None:
                atlas.alpha_composite(plate, (i * CELL_W, row * CELL_H))
                continue
            cell = blank_plate(plate)
            icon = icons[key]
            if row == 2:  # pressed plates are drawn smaller
                icon = icon.resize((max(1, int(icon.width * 0.9)), max(1, int(icon.height * 0.9))), Image.LANCZOS)
            cell.alpha_composite(icon, ((CELL_W - icon.width) // 2, (CELL_H - icon.height) // 2 + 1))
            atlas.alpha_composite(cell, (i * CELL_W, row * CELL_H))
    atlas.save(OUT / "menu-flyout.png")


def coin_sack() -> Image.Image:
    """The gold coin sack from the inventory window's medallion (x 279-323, y 52-108), lifted
    off its blue glass inside an ellipse that leaves the medallion's gold ring out, and
    re-toned to the embossed gold of the other menu icons, about 38 px tall."""
    sheet = load("2DUIInventoryGrid")
    x0, y0, x1, y1 = 279, 52, 324, 109
    cx, cy, rx, ry = 301.5, 81, 22.5, 28.5
    src = sheet.crop((x0, y0, x1, y1)).load()
    out = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    opx = out.load()
    for y in range(y1 - y0):
        for x in range(x1 - x0):
            if ((x + x0 - cx) / rx) ** 2 + ((y + y0 - cy) / ry) ** 2 > 1:
                continue
            r, g, b, a = src[x, y]
            tie = r > 170 and g > 170 and b > 140
            if r - b > 45 or tie:
                lum = 0.3 * r + 0.59 * g + 0.11 * b
                lum = min(255, lum * 1.18)
                alpha = 255 if tie else min(255, int((r - b - 45) * 5))
                opx[x, y] = (int(lum), int(lum * 0.76), int(lum * 0.32), min(a, alpha))
    out = out.crop(out.getbbox())
    scale = 38 / out.height
    return out.resize((max(1, int(out.width * scale)), 38), Image.LANCZOS)


def glow() -> None:
    load("bottomBar_buttonFX_frameGlow").resize((256, 256), Image.LANCZOS).save(OUT / "button-glow.png")


# The Demon Hunter console is the standard one plus a blade splitting the right globe.
# Only the pixels that differ are kept, drawn over the glass when the globe is split.
BLADE_X0, BLADE_W = 1329, 64


def blade() -> None:
    plain = load_frame("BottomBar_GameRes")
    dh = load_frame("BottomBar_GameRes_DH")
    box = (BLADE_X0, 0, BLADE_X0 + BLADE_W, plain.height)
    a, b = plain.crop(box), dh.crop(box)
    out = Image.new("RGBA", b.size, (0, 0, 0, 0))
    apx, bpx, opx = a.load(), b.load(), out.load()
    for y in range(b.height):
        for x in range(b.width):
            if sum(abs(i - j) for i, j in zip(apx[x, y], bpx[x, y])) > 20:
                opx[x, y] = bpx[x, y]
    # Drop stray glass-highlight specks: keep pixels within 2px of solid blade.
    solid = [[opx[x, y][3] > 200 for y in range(out.height)] for x in range(out.width)]
    for y in range(out.height):
        for x in range(out.width):
            if opx[x, y][3] and not any(
                solid[i][j]
                for i in range(max(0, x - 2), min(out.width, x + 3))
                for j in range(max(0, y - 2), min(out.height, y + 3))
            ):
                opx[x, y] = (0, 0, 0, 0)
    pad(out, (64, 256)).save(OUT / "blade.png")


def liquid_halves() -> None:
    whole = Image.open(OUT / "liquid.png")
    whole.crop((0, 0, 128, 256)).save(OUT / "liquid-left.png")
    whole.crop((128, 0, 256, 256)).save(OUT / "liquid-right.png")


# Socket hover / press glow. The button maps to the inner 96x96 of a 128x128 texture, so the
# 16 px margin carries the outer glow and the rim sits exactly on the socket edge.
GLOW_SIZE, GLOW_MARGIN = 128, 16


def socket_glow() -> None:
    import math
    n, m = GLOW_SIZE, GLOW_MARGIN
    inner = n - 2 * m

    def dist(x, y):
        # Signed distance to the rim of the inner box (negative inside), rounded corners.
        cx = min(max(x + 0.5, m + 3), n - m - 3)
        cy = min(max(y + 0.5, m + 3), n - m - 3)
        d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) - 3
        if d < 0:
            d = -min(x + 0.5 - m, n - m - x - 0.5, y + 0.5 - m, n - m - y - 0.5)
        return d

    def build(rim, inner_glow, outer_glow, fill, colour):
        out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        px = out.load()
        for y in range(n):
            for x in range(n):
                d = dist(x, y)
                a = 0.0
                if -1.6 <= d <= 1.6:
                    a = rim
                elif d < 0:
                    a = inner_glow * max(0.0, 1 + d / 9) ** 2 + fill
                else:
                    a = outer_glow * max(0.0, 1 - d / m) ** 2
                a = min(1.0, a)
                if a > 0:
                    px[x, y] = (*colour, int(255 * a))
        return out

    build(1.0, 0.45, 0.6, 0.0, (255, 214, 120)).save(OUT / "socket-hover.png")
    build(1.0, 0.75, 0.85, 0.18, (255, 190, 90)).save(OUT / "socket-press.png")


# Bag window, from D3's inventory window (2DUIInventoryGrid, left panel, 600 px wide):
#   header 0-155 (stained glass, coin-sack medallion, close X), body band 640-940 (plain dark
#   stone between the side borders, stretched vertically), footer 1000-1207 (stone plate).
# bag-frame.png stacks them in a 1024x1024 atlas at y 0, 155 and 455.
BAG_PIECES = (("header", 0, 155), ("body", 640, 940), ("footer", 1000, 1207))


def bag_frame() -> None:
    sheet = load("2DUIInventoryGrid")
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    y = 0
    for _, top, bottom in BAG_PIECES:
        atlas.alpha_composite(sheet.crop((0, top, 600, bottom)), (0, y))
        y += bottom - top
    atlas.save(OUT / "bag-frame.png")


def bank_frame() -> None:
    # The bank is D3's stash: its header (treasure-chest medallion) has the same 600x155
    # layout as the inventory's, so it takes the inventory body and footer below it.
    inv = load("2DUIInventoryGrid")
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    atlas.alpha_composite(load("2DUIStash").crop((0, 0, 600, 155)), (0, 0))
    y = 155
    for _, top, bottom in BAG_PIECES[1:]:
        atlas.alpha_composite(inv.crop((0, top, 600, bottom)), (0, y))
        y += bottom - top
    atlas.save(OUT / "bank-frame.png")


# Item cells (64x64 each, 512x64 atlas), from the same sheet. Order matches Bags.lua:
# empty, uncommon (D3 set green), rare (magic blue), epic (purple), legendary (orange),
# heirloom/artifact (rare yellow), new-item frame (white).
BAG_CELLS = (
    (1483, 150, 1544, 210),  # empty: dark stone
    (1623, 627, 1678, 687),  # uncommon: green (stops short of the cream frame at 1683)
    (1343, 627, 1403, 687),  # rare: blue
    (1693, 150, 1752, 210),  # epic: purple
    (1413, 627, 1473, 687),  # legendary: orange
    (1623, 150, 1682, 210),  # heirloom / artifact: yellow
    (1411, 148, 1478, 213),  # new item: white frame, whole
)


def bag_cells() -> None:
    sheet = load("2DUIInventoryGrid")
    atlas = Image.new("RGBA", (512, 64), (0, 0, 0, 0))
    for i, box in enumerate(BAG_CELLS):
        atlas.alpha_composite(sheet.crop(box).resize((64, 64), Image.LANCZOS), (i * 64, 0))
    atlas.save(OUT / "bag-cells.png")


def d3_button() -> None:
    # A plain framed plate from 2DUIButtons, for the bag window's text buttons.
    pad(load("2DUIButtons").crop((588, 210, 708, 262)), (128, 64)).save(OUT / "d3-button.png")


# Secondary-resource pips (combo points etc.): D3 item sockets with octagon-cut gems.
# pips.png, 64 px cells: socket (gold ring over a dark well), amethyst, emerald, ruby, topaz,
# diamond, then a soft round glow for the sparkle when a gem is set.
PIP_GEMS = ((0, 14), (1, 2), (1, 21), (2, 8), (2, 27))  # (row, col) in 2DInventoryGemsIcons


def pips() -> None:
    atlas = Image.new("RGBA", (512, 64), (0, 0, 0, 0))
    # Socket: dark well with a soft inner shadow, D3's gold socket ring on top.
    well = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(well)
    for i in range(26, 0, -1):
        shade = int(8 + 22 * (i / 26) ** 2)
        draw.ellipse((32 - i, 32 - i, 32 + i, 32 + i), fill=(shade, shade - 3, shade - 6, 255))
    # The socket image has wide transparent margins; crop to the ring so it frames the cell.
    raw = load("2DInventorySockets")
    ring = raw.crop(raw.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()).resize((64, 64), Image.LANCZOS)
    well.alpha_composite(ring)
    atlas.alpha_composite(well, (0, 0))
    sheet = load("2DInventoryGemsIcons")
    for i, (row, col) in enumerate(PIP_GEMS):
        gem = sheet.crop((col * 64, row * 64, col * 64 + 64, row * 64 + 64))
        atlas.alpha_composite(gem, ((i + 1) * 64, 0))
    glow = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    gpx = glow.load()
    for y in range(64):
        for x in range(64):
            d = ((x - 31.5) ** 2 + (y - 31.5) ** 2) ** 0.5 / 32
            if d < 1:
                gpx[x, y] = (255, 240, 210, int(255 * (1 - d) ** 2))
    atlas.alpha_composite(glow, (6 * 64, 0))
    # Ring alone, drawn over the small liquid globes.
    atlas.alpha_composite(ring, (7 * 64, 0))
    atlas.save(OUT / "pips.png")


# Secondary-resource frames, from D3's own painted art:
#   pip-horn.png    the horned skull ring from the paragon/prestige portrait frames
#                   (2DUIPrestige x 1465-1550, y 102-187), pasted so its 42 px hole is centred
#                   on a 128 px canvas; the Lua rotates it so the skull meets the globe rim.
#   pip-sockets.png Kanai's Cube bronze sockets (2DUIMedallion01), centres cut out so the
#                   liquid shows: black, orange, green, red, blue rims, 64 px cells.
HORN_BOX, HORN_HOLE = (1465, 102, 1550, 187), (42, 38)
SOCKET_XS = ((312, 5), (362, 5), (412, 5), (462, 5), (312, 55))


def pip_frames() -> None:
    import math
    ring = load("2DUIPrestige").crop(HORN_BOX)
    horn = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    horn.alpha_composite(ring, (64 - HORN_HOLE[0], 64 - HORN_HOLE[1]))
    horn.save(OUT / "pip-horn.png")

    sheet = load("2DUIMedallion01")
    atlas = Image.new("RGBA", (512, 64), (0, 0, 0, 0))
    for i, (x, y) in enumerate(SOCKET_XS):
        sock = sheet.crop((x, y, x + 40, y + 40))
        px = sock.load()
        for yy in range(40):
            for xx in range(40):
                d = math.hypot(xx - 19.5, yy - 19.5)
                r, g, b, a = px[xx, yy]
                # Open the dark centre; keep the bronze collar and the coloured rim.
                if d < 12.5 or (d < 15 and r + g + b < 70):
                    px[xx, yy] = (0, 0, 0, 0)
        atlas.alpha_composite(sock.resize((64, 64), Image.LANCZOS), (i * 64, 0))
    atlas.save(OUT / "pip-sockets.png")


# Target portrait frames: D3's own hero portrait frames (2DUIPrestige, the paragon tiers), one
# per target rank like the plate's frames: silver laurel and ram skull (normal), gold laurel and
# red banner (elite, rare), the winged demon (boss). Each is pasted so its round hole (39 px,
# D3's own size at 1080p) is centred in a 128 px cell; the Lua masks the WoW portrait into it.
#   target-rings.png 512x128: cells 0 normal, 1 elite, 2 boss
TARGET_RINGS = (
    (1254, 101, 1344, 190),  # normal: silver laurel, ram skull
    (940, 99, 1034, 188),    # elite / rare: gold laurel, red banner, horned skull
    (836, 99, 930, 199),     # boss: winged demon
)


def ring_hole(frame: Image.Image) -> tuple:
    # Flood the transparent hole from the frame's middle; returns its centre.
    alpha = frame.getchannel("A")
    w, h = frame.size
    sx, sy = w // 2, h // 2
    while alpha.getpixel((sx, sy)) >= 40:
        sy += 1
    seen, stack, xs, ys = {(sx, sy)}, [(sx, sy)], [], []
    while stack:
        x, y = stack.pop()
        xs.append(x)
        ys.append(y)
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and alpha.getpixel(n) < 40:
                seen.add(n)
                stack.append(n)
    return (min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2


def target_rings() -> None:
    sheet = load("2DUIPrestige")
    atlas = Image.new("RGBA", (512, 128), (0, 0, 0, 0))
    for i, box in enumerate(TARGET_RINGS):
        frame = sheet.crop(box)
        cx, cy = ring_hole(frame)
        x, y = i * 128 + 64 - round(cx), 64 - round(cy)
        atlas.alpha_composite(frame, (x, y))
        bb = frame.getbbox()
        print(f"  ring {i}: hole centre {cx},{cy}; art spans x {bb[0] - cx:+.1f}..{bb[2] - cx:+.1f}, y {bb[1] - cy:+.1f}..{bb[3] - cy:+.1f}")
    atlas.save(OUT / "target-rings.png")


def shimmer() -> None:
    # D3's surface texture as a seamless luminance tile; scrolled inside the surface band.
    lum = load("health_hotline_liquid").convert("L")
    lo, hi = lum.getextrema()
    lum = wrap_blend(lum.point(lambda v: int(255 * (v - lo) / max(1, hi - lo))))
    Image.merge("RGBA", (lum, lum, lum, Image.new("L", lum.size, 255))).save(OUT / "liquid-shimmer.png")


# D3's skill timer: a tab on a socket while the skill's effect is up, with a bar inside that
# drains as it runs out. 2DUIBottomBar names these BuffDurationFrame (steel tab),
# BuffDurationFrameOnMouse (gold tab, the mouse pair), BuffDurationBarFill (green) and
# BuffDurationBarFill_Yellow; GameHUDPC.ui gives every skill slot both fills. Each tab is 59x19; its top 8 rows tuck behind the socket,
# so only rows 8-18 are kept. The fill sits 2 px in and 1 px down from the kept part.
#   skill-timer.png 128x32: steel tab (0,0 59x11), gold tab (64,0 59x11),
#   amber fill (0,16 55x9), green fill (64,16 55x9)
def skill_timer() -> None:
    sheet = load("2DUIBottomBar")
    atlas = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    atlas.paste(sheet.crop((1828, 60, 1887, 71)), (0, 0))
    atlas.paste(sheet.crop((1905, 60, 1964, 71)), (64, 0))
    atlas.paste(sheet.crop((1753, 62, 1808, 71)), (0, 16))
    atlas.paste(sheet.crop((1830, 91, 1885, 100)), (64, 16))
    atlas.save(OUT / "skill-timer.png")


def socket() -> None:
    frame = load("BottomBar_GameRes")
    pad(frame.crop((336, 104, 412, 184)), (128, 128)).save(OUT / "socket.png")


# Addon icon (TOC IconTexture + minimap button): D3's red portrait orb inside a prestige
# portrait frame from 2DUIPrestige, both native art. The frame is centred on its hole, the
# orb sized to fill the hole, and the result padded so LibDBIcon's 5% texcoord inset only
# trims transparency. TGA, since the TOC icon loader is not known to take PNG on this client.
ICON_FRAMES = {
    "gold": (940, 99, 1034, 187),     # gold laurel, red banner, horned skull
    "iron": (1465, 102, 1550, 187),   # iron laurel, ram skull (same ring as pip-horn)
    "bronze": (1673, 102, 1758, 188), # bronze spiked ring, small skull
}
ICON_FRAME = "gold"
ICON_ORB = (1062, 244, 1123, 305)


def icon() -> None:
    sheet = load("2DUIPrestige")
    frame = sheet.crop(ICON_FRAMES[ICON_FRAME])
    alpha = frame.getchannel("A")
    w, h = frame.size
    # Flood the transparent hole from the frame's centre to find its centre and size.
    seen, stack, xs, ys = {(w // 2, h // 2)}, [(w // 2, h // 2)], [], []
    while stack:
        x, y = stack.pop()
        xs.append(x)
        ys.append(y)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and alpha.getpixel((nx, ny)) < 40:
                seen.add((nx, ny))
                stack.append((nx, ny))
    hx, hy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    d = max(max(xs) - min(xs), max(ys) - min(ys)) + 7
    orb = sheet.crop(ICON_ORB).resize((d, d), Image.LANCZOS)
    c = max(w, h) + 4
    canvas = Image.new("RGBA", (c * 2, c * 2), (0, 0, 0, 0))
    canvas.alpha_composite(orb, (c - d // 2, c - d // 2))
    canvas.alpha_composite(frame, (c - round(hx), c - round(hy)))
    box = canvas.getbbox()
    r = max(abs(box[0] - c), abs(box[2] - c), abs(box[1] - c), abs(box[3] - c))
    r = int(r * 1.08)  # padding for the texcoord inset
    canvas = canvas.crop((c - r, c - r, c + r, c + r)).resize((64, 64), Image.LANCZOS)
    canvas.save(OUT / "icon.tga")


# 2DUITabs: 19 columns at a 103 px pitch, rows every 151 px; each icon is three cells in a row
# (normal, selected, dim). The flyout's icons are lifted off the selected cells (tab_icon).
TAB_ICONS = [27, 11, 19, 25, 8, 17]  # tome, hammer, chest, star, eye, crossed swords


# unit-frames.png pieces: name -> (source sheet, source box, atlas position). Lua mirrors the
# atlas boxes in ns.Art.UNIT (with each frame's bar interior).
UNIT_PIECES = {
    "boss": ("2DUIEnemyHPbar", (515, 0, 1006, 87), (0, 0)),
    "elite": ("2DUIEnemyHPbar", (1023, 0, 1448, 47), (500, 0)),
    "normal": ("2DUIEnemyHPbar", (6, 102, 300, 143), (0, 92)),
    "fill": ("2DUIEnemyHPbar", (311, 101, 561, 118), (300, 92)),
    "party": ("2DUIPartyUI", (0, 48, 106, 100), (0, 140)),
    "partyGold": ("2DUIPartyUI", (106, 48, 212, 100), (110, 140)),
    # D3's thin progress bar (2DUIControls), empty, for the target's cast bar.
    "cast": ("2DUIControls", (1022, 57, 1318, 71), (0, 200)),
}


# Each frame's dark bar slot (relative to the piece), cut out so the health bar drawn under the
# frame shows through. Same rects as ns.Art.UNIT[...].bar.
UNIT_SLOTS = {
    "boss": (76, 25, 339, 19),
    "elite": (43, 17, 339, 17),
    "normal": (21, 11, 252, 18),
    "party": (18, 29, 70, 10),
    "partyGold": (18, 29, 70, 10),
    "cast": (3, 2, 290, 10),
}


def levelled(strip: Image.Image, ends: float = 0.88, smooth: int = 31) -> Image.Image:
    # Even out a strip's lighting along its length: divide each column by the strip's smoothed
    # brightness there, then light it flat with a gentle fall to `ends` at the very ends. The
    # grain and the highlight line (both vertical detail) survive untouched.
    import math
    w, h = strip.size
    px = strip.load()
    col = [sum(sum(px[x, y][:3]) for y in range(h)) / (3 * h) for x in range(w)]
    half = smooth // 2
    sm = []
    for x in range(w):
        lo, hi = max(0, x - half), min(w, x + half + 1)
        sm.append(max(1.0, sum(col[lo:hi]) / (hi - lo)))
    # The level to light everything at: the strip's own lit middle.
    mid = sorted(sm)[int(len(sm) * 0.8)]
    out = strip.copy()
    po = out.load()
    for x in range(w):
        t = min(x, w - 1 - x) / (w * 0.12)  # 0 at the ends, 1 from 12% in
        shape = ends + (1 - ends) * (0.5 - 0.5 * math.cos(math.pi * min(1.0, t)))
        gain = mid * shape / sm[x]
        for y in range(h):
            r, g, b, a = po[x, y]
            po[x, y] = (min(255, int(r * gain)), min(255, int(g * gain)), min(255, int(b * gain)), a)
    return out


def unit_gloss() -> None:
    # unit-gloss.png 8x32: drawn over the whole bar (well and fill) to make it read as a glass
    # tube, as the globes do: an inner shadow under the frame's top and bottom lip, and a soft
    # white band across the upper third. Alpha only; stretched to the bar's slot.
    img = Image.new("RGBA", (8, 32), (0, 0, 0, 0))
    px = img.load()
    for y in range(32):
        t = (y + 0.5) / 32
        # Shadow: strongest at the top lip, a lighter one at the bottom.
        top = max(0.0, 1 - t / 0.2) ** 1.6 * 0.62
        bottom = max(0.0, 1 - (1 - t) / 0.16) ** 1.6 * 0.5
        shade = max(top, bottom)
        # Glass: a band peaking a quarter of the way down.
        import math
        gloss = math.exp(-((t - 0.27) / 0.09) ** 2) * 0.16
        if gloss > shade:
            v = (255, 255, 255, int(255 * gloss))
        else:
            v = (0, 0, 0, int(255 * shade))
        for x in range(8):
            px[x, y] = v
    img.save(OUT / "unit-gloss.png")


def unit_glow() -> None:
    # unit-glow.png 64x32, drawn ADD at the fill's right end. Two white sprites, each 18 wide
    # with the edge at x=14 (14 px back into the fill, 4 ahead): the red bloom at x 0-18 and
    # the thin hot core at x 32-50, tinted separately so the bloom can follow the fill colour.
    import math
    img = Image.new("RGBA", (64, 32), (0, 0, 0, 255))
    px = img.load()
    back = 14
    for x in range(18):
        d = x - back + 0.5
        bloom = math.exp(-(d / 6.0) ** 2) if d <= 0 else math.exp(-(d / 1.6) ** 2)
        core = math.exp(-(d / 0.9) ** 2)
        for y in range(32):
            v = 1 - abs((y + 0.5) / 32 * 2 - 1)
            v = 0.35 + 0.65 * v ** 0.6  # strongest mid-bar, still reaching the lips
            b = int(255 * min(1.0, bloom * v))
            c = int(255 * min(1.0, core * v))
            px[x, y] = (b, b, b, 255)
            px[32 + x, y] = (c, c, c, 255)
    img.save(OUT / "unit-glow.png")


def unit_frames() -> None:
    atlas = Image.new("RGBA", (1024, 256), (0, 0, 0, 0))
    for name, (src, box, pos) in UNIT_PIECES.items():
        piece = load(src).crop(box)
        slot = UNIT_SLOTS.get(name)
        if slot:
            x, y, w, h = slot
            px = piece.load()
            for j in range(y, y + h):
                for i in range(x, x + w):
                    r, g, b, a = px[i, j]
                    # The dark slot goes clear; its glass sheen stays as a faint highlight over
                    # the fill, and the gold or silver rim pixels stay solid.
                    m = max(r, g, b)
                    if m < 110:
                        px[i, j] = (r, g, b, min(a, max(0, (m - 30) * 2)))
        atlas.alpha_composite(piece, pos)
    # Neutral copy of the red fill, tinted by vertex color (friendly green, pet health).
    red = load("2DUIEnemyHPbar").crop(UNIT_PIECES["fill"][1])
    lum = red.split()[0].point(lambda v: min(255, int(v * 1.05)))
    white = Image.merge("RGBA", (lum, lum, lum, red.split()[3]))
    atlas.alpha_composite(white, (560, 92))
    atlas.save(OUT / "unit-frames.png")
    # StatusBars rewrite their fill's texcoords, so the fills also go out as whole files. These
    # use D3's wider red strip (340 px, x 1462-1802) so a stretched bar stays sharp. D3 lights
    # that strip in the middle and lets both ends fall to near black; a StatusBar crops rather
    # than stretches, so a low bar would show only the dark end. levelled() evens it out.
    wide = levelled(load("2DUIEnemyHPbar").crop((1462, 32, 1802, 49)))
    wide.resize((512, 16), Image.LANCZOS).save(OUT / "unit-fill.png")
    wl = wide.split()[0].point(lambda v: min(255, int(v * 1.05)))
    Image.merge("RGBA", (wl, wl, wl, wide.split()[3])).resize((512, 16), Image.LANCZOS).save(OUT / "unit-fill-white.png")
    # The empty well under the bar: D3's matching dark strip (same 17 rows, right above the
    # red one), so missing health is shaded, never see-through.
    well = levelled(load("2DUIEnemyHPbar").crop((1462, 5, 1802, 22)))
    well.resize((512, 16), Image.LANCZOS).save(OUT / "unit-well.png")
    unit_gloss()
    unit_glow()
    # The cast bar's glowing orange fill, from the same control filled (x 717-1006).
    load("2DUIControls").crop((717, 59, 1006, 69)).resize((512, 16), Image.LANCZOS).save(OUT / "cast-fill.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for step in (frame_and_glass, liquid, liquid_halves, animated_liquid, hotline, xp_fills, menu, glow, blade, socket_glow, bag_frame, bank_frame, bag_cells, d3_button, pips, pip_frames, shimmer, socket, skill_timer, icon, unit_frames, menu_flyout, target_rings):
        step()
        print("built", step.__name__)


if __name__ == "__main__":
    main()
