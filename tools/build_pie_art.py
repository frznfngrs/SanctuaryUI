#!/usr/bin/env python3
"""Pack the pie menu renders (tools/blender/pie_menu.py) into SanctuaryUI/Art and draw its lights.

  blender -b --factory-startup -P tools/blender/pie_menu.py -- <work> [samples]
  python3 tools/build_pie_art.py <work>

Needs Pillow and numpy. Writes pie-band, pie-sockets (iron | gold), pie-hub, pie-stud, and the
drawn pie-beam, pie-pointer, pie-glow and pie-back. Sizes are the contract with PieMenu.lua.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SanctuaryUI" / "Art"
AMBER = (255, 160, 48)


def shade(im, k):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    a[..., :3] *= k
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def polar(size):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    dx, dy = (x - c) / c, (c - y) / c
    return np.hypot(dx, dy), np.degrees(np.arctan2(dy, dx)), dx, dy


def light(alpha, color=AMBER):
    a = np.zeros(alpha.shape + (4,), np.float32)
    a[..., 0], a[..., 1], a[..., 2] = color
    a[..., 3] = alpha.clip(0, 1) * 255
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def hub(work):
    """The rim render with a dark glass face painted into it (face radius 47.5 of an 80 half)."""
    im = np.asarray(Image.open(work / "hub.png").convert("RGBA")).astype(np.float32)
    r, _, dx, dy = polar(im.shape[0])
    R = 47.5 / 80
    inside = ((R - r) / 0.006).clip(0, 1)
    q = (r / R).clip(0, 1)
    glass = np.zeros_like(im)
    glass[..., 0], glass[..., 1], glass[..., 2] = 9, 10, 14
    # Lighter toward the lower right, where a globe's glass catches the room.
    lift = ((dx - dy) / R * 0.5 + 0.5).clip(0, 1) * q ** 2
    glass[..., :3] += lift[..., None] * np.array([16, 19, 26], np.float32)
    glass[..., :3] *= (1 - 0.55 * q ** 6)[..., None]  # the rim's shadow on the glass
    # The highlight: a soft crescent up and left.
    hx, hy = dx / R + 0.36, dy / R - 0.44
    spot = np.exp(-((hx / 0.42) ** 2 + (hy / 0.2) ** 2))
    glass[..., :3] += spot[..., None] * np.array([58, 64, 76], np.float32)
    glass[..., 3] = 240
    k = inside[..., None]
    out = im * (1 - k) + glass * k
    out[..., 3] = np.maximum(im[..., 3] * (1 - inside), glass[..., 3] * inside)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")


def beam():
    """A soft cone of light pointing up, drawn over a 360-unit box: PieMenu.lua turns it toward
    the slice. Quiet on purpose: the gold socket and the pointer carry the selection."""
    r, ang, _, _ = polar(256)
    u = r * 180  # UI units from the centre
    d = (ang - 90 + 180) % 360 - 180
    cone = np.exp(-(d / 15.0) ** 2)
    rise = ((u - 60) / 45).clip(0, 1) ** 1.5
    fall = ((176 - u) / 60).clip(0, 1) ** 1.5
    return light(cone * rise * fall * 0.8)


def pointer():
    s = 4
    im = Image.new("RGBA", (64 * s, 64 * s), (0, 0, 0, 0))
    pts = [(32 * s, 8 * s), (48 * s, 50 * s), (32 * s, 43 * s), (16 * s, 50 * s)]
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(pts, fill=AMBER + (255,))
    glow = glow.filter(ImageFilter.GaussianBlur(5 * s))
    a = np.asarray(glow).astype(np.float32)
    a[..., 3] *= 0.8
    a[..., 0], a[..., 1], a[..., 2] = AMBER  # no dark fringe where the blur fades out
    im = Image.fromarray(a.astype(np.uint8), "RGBA")
    ImageDraw.Draw(im).polygon(pts, fill=(255, 218, 140, 255), outline=(84, 44, 10, 255), width=s)
    return im.resize((64, 64), Image.LANCZOS)


def main(work: Path) -> None:
    shade(Image.open(work / "band.png"), 0.62).save(OUT / "pie-band.png", optimize=True)
    sockets = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    sockets.paste(shade(Image.open(work / "socket-iron.png"), 0.8), (0, 0))
    sockets.paste(Image.open(work / "socket-gold.png").convert("RGBA"), (256, 0))
    sockets.save(OUT / "pie-sockets.png", optimize=True)
    hub(work).save(OUT / "pie-hub.png", optimize=True)
    Image.open(work / "stud.png").convert("RGBA").save(OUT / "pie-stud.png", optimize=True)
    beam().save(OUT / "pie-beam.png", optimize=True)
    pointer().save(OUT / "pie-pointer.png", optimize=True)
    r, _, _, _ = polar(128)
    light(((1 - r) / 0.55).clip(0, 1) ** 2 * 0.9).save(OUT / "pie-glow.png", optimize=True)
    r, _, _, _ = polar(256)
    light(((1 - r) / 0.24).clip(0, 1) * 0.5, (0, 0, 0)).save(OUT / "pie-back.png", optimize=True)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
