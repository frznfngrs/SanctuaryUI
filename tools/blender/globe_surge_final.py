"""Still of the shipped surge styles, composited from the real sheets in SanctuaryUI/Art with the
numbers GlobeAura.lua draws them with (a check on the art, not a capture from the client).

    python globe_surge_final.py OUT.png
"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import globe_compare as gc  # noqa: E402
import globe_fx_compare as fxc  # noqa: E402
import globe_surge_concepts as sc  # noqa: E402

ART = os.path.join(os.path.dirname(__file__), "..", "..", "SanctuaryUI", "Art")
sc.TINTS.update({"water": ((0.2, 0.6, 1.0), (0.7, 0.9, 1.0)), "nature": ((0.35, 0.9, 0.3), (0.8, 1.0, 0.7)), "holy": ((1.0, 0.62, 0.14), (1.0, 0.88, 0.55)), "hearth": ((1.0, 0.55, 0.25), (1.0, 0.85, 0.6))})
sc.LIQUID.update({"water": np.array([0.18, 0.36, 1.0], np.float32), "nature": sc.LIQUID["blood"], "holy": sc.LIQUID["blood"], "hearth": sc.LIQUID["blood"]})


class Flip:
    def __init__(self, file, cw, ch, cols, frames, seconds, row=0):
        self.a = np.asarray(Image.open(os.path.join(ART, file)).convert("RGBA"))[..., 3].astype(np.float32) / 255
        self.cw, self.ch, self.cols, self.frames, self.seconds, self.row = cw, ch, cols, frames, seconds, row

    def cell(self, i):
        y, x = divmod(i, self.cols)
        y += self.row
        return self.a[y * self.ch:(y + 1) * self.ch, x * self.cw:(x + 1) * self.cw]

    def at(self, t):
        pos = (t / self.seconds) % 1 * self.frames
        i = int(pos)
        f = pos - i
        return self.cell(i) * (1 - f) + self.cell((i + 1) % self.frames) * f


RAYS = Flip("surge-inhale-rays.png", 256, 256, 8, 32, 3.6)
COL = Flip("surge-pour-column.png", 128, 256, 16, 32, 3)
GLOW = Flip("surge-pour-column.png", 128, 256, 16, 32, 3, 2)
UNDER = Flip("surge-pour-under.png", 256, 128, 8, 32, 3)
BODY = Flip("surge-upwell-body.png", 256, 256, 8, 32, 3)
CORE = Flip("surge-upwell-core.png", 256, 256, 8, 32, 3)
STREAK = np.asarray(Image.open(os.path.join(ART, "surge-streak.png")).convert("RGBA"))[..., 3].astype(np.float32) / 255


def square(img, top=False):
    """Pad a cell to a square (the stamps are square), centred, or hung from the top."""
    h, w = img.shape
    n = max(h, w)
    out = np.zeros((n, n), np.float32)
    y = 0 if top else (n - h) // 2
    x = (n - w) // 2
    out[y:y + h, x:x + w] = img
    return out


def stretched(art, w, h):
    """The mote drawn w by h of its square."""
    n = 256
    m = art.mote[..., 3] * art.mote[..., :3].mean(2) if art.mote.ndim == 3 else art.mote
    img = cv2.resize(m, (max(1, int(n * w)), max(1, int(n * h))), interpolation=cv2.INTER_AREA)
    return square(img) if img.shape[0] != img.shape[1] else img


def mixed(sat, hot, a, b):
    return tuple(min(1.0, s * a + h * b) for s, h in zip(sat, hot))


def hash1(n):
    x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)


def draw(p, style, t, calm=0.0, rank_weight=1.0):
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    size = g * 2
    sat, hot = p.sat, p.hot
    lv = p.level_row(t)
    surface = p.globe_rect[1] + lv
    r = g / 2
    k = rank_weight
    weight = sc.weight_mask(art, p)
    gm = [(art.gmask, cx, cy, g * 1.0)]
    breath = 0.86 + 0.14 * math.sin(t * 2 * math.pi / 2.2)
    light = {"inhale": (0.98, 0.42, 0.42), "pour": (0.7, 0.22, 0.22), "upwell": (0.9, 0.34, 0.4)}[style]

    def behind(c):
        fxc.stamp(c, art.corona, cx, cy, size * light[0], sat, light[1] * breath, mask=weight)
        if style == "inhale":
            fxc.stamp(c, RAYS.at(t), cx, cy, size * 1.02, sat, min(1, 1.15 * k), mask=weight)
            for i in range(1, 25):
                q = (t / 3 * (1 + i % 2) + hash1(i * 3.1)) % 1
                a0 = math.radians(14 + 152 * hash1(i * 7.7))
                curl = (hash1(i * 5.3) - 0.5) * 0.5
                speed = 0.8 + 0.5 * hash1(i * 2.9)
                travel = q / 0.88
                if travel >= 1:
                    continue

                def at(pp):
                    d = 2.15 - 1.15 * pp ** 2.2
                    a = a0 + curl * (d - 1) ** 2
                    return math.cos(a) * d * r, math.sin(a) * d * r
                hx, hy = at(travel)
                tx, ty = at(max(0, travel - 0.2 * speed))
                length = max(1, math.hypot(tx - hx, ty - hy))
                fxc.stamp(c, STREAK, cx + (hx + tx) / 2, cy - (hy + ty) / 2, length / 0.78, hot,
                          min(1, travel / 0.25) * (0.65 + 0.35 * speed) * k * 1.2, angle=math.atan2(ty - hy, tx - hx) - math.pi / 2, mask=weight)

    def in_liquid(lq):
        if style == "pour":
            col = mixed(sat, hot, 0.8, 0.4)
            add = p.stamp_in(lq, square(UNDER.at(t), top=True), lv - 0.05 * g + 0.6 * g, col, min(1, 1.05 * k * (1 - 0.65 * calm)), g * 1.2)
            return lq + add * p.rows(t, True)
        if style == "upwell":
            a = p.stamp_in(lq, BODY.at(t), g / 2, mixed(sat, hot, 0.85, 0.25), min(1, 0.7 * k))
            b = p.stamp_in(lq, CORE.at(t), g / 2, hot, min(1, 0.55 * k))
            return lq + (a + b) * p.rows(t, True)
        return lq

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, min(1, light[2] * breath))
        if style == "inhale":
            for i in range(1, 25):
                q = (t / 3 * (1 + i % 2) + hash1(i * 3.1)) % 1
                travel = q / 0.88
                if travel < 1:
                    continue
                a0 = math.radians(14 + 152 * hash1(i * 7.7))
                fxc.stamp(c, art.mote, cx + math.cos(a0) * 0.97 * r, cy - math.sin(a0) * 0.97 * r, r * 0.55, hot, math.exp(-(travel - 1) / 0.055) * 0.95 * k, mask=gm)
        if style == "pour":
            H = c.shape[0]
            layer = np.zeros_like(c)
            fxc.stamp(layer, square(GLOW.at(t)), cx, cy, g, sat, min(1, 1.25 * k * (1 - 0.55 * calm)))
            fxc.stamp(layer, square(COL.at(t)), cx, cy, g, hot, min(1, 1.2 * k * (1 - 0.5 * calm)))
            rows = np.arange(H, dtype=np.float32) + 0.5
            keep = np.clip(surface - rows + 1, 0, 1)[..., None, None]
            top_keep = np.clip(rows - (cy - r) + 1, 0, 1)[..., None, None]
            c[:] = np.clip(c + layer * keep * top_keep, 0, 1)
            fxc.stamp(c, stretched(art, 0.85, 0.07), cx, surface, g, hot, 0.95 * k * (1 - 0.4 * calm), mask=gm)
            fxc.stamp(c, stretched(art, 0.24, 0.2), cx, surface - 0.04 * g, g, hot, 0.9 * k * (1 - 0.4 * calm), mask=gm)
            for i in range(1, 15):
                q = (t / 3 * (1 + i % 2) + hash1(i * 4.3)) % 1
                vx = (hash1(i * 6.1) - 0.5) * 0.9
                vy = 0.32 + 0.5 * hash1(i * 2.7)
                x, y = vx * q * 0.75, vy * q - 0.83 * q * q
                if y >= -0.005 and calm < 0.98:
                    fxc.stamp(c, art.mote, cx + x * g, surface - y * g, g * (0.035 + 0.025 * hash1(i * 9.1)), hot, (1 - q) ** 0.7 * 0.95 * k * (1 - calm), mask=gm)
        if style == "upwell":
            pulse = 0.78 + 0.22 * math.sin(t * 2 * math.pi * 2 / 3)
            fxc.stamp(c, stretched(art, 1.0, 0.2 / 1.15), cx, surface, g * 1.15, sat, pulse * k, mask=gm)
            fxc.stamp(c, stretched(art, 1.0, 0.06 / 0.6), cx, surface, g * 0.6, hot, pulse * 1.15 * k, mask=gm)

    return p.finish(t, behind, in_liquid, front)


def main(out):
    art = fxc.Art()
    panels = {}

    def panel(tint):
        if tint not in panels:
            panels[tint] = sc.Panel(art, 180, tint)
        return panels[tint]

    scenes = [("Pour: drink, 60%", "pour", "water", 0.6, 0), ("Pour: drink, 20%", "pour", "water", 0.2, 0), ("Pour: settled", "pour", "water", 0.6, 1),
              ("Inhale: bloodrage, 60%", "inhale", "blood", 0.6, 0), ("Inhale: innervate", "inhale", "water", 0.35, 0),
              ("Upwell: renew, 60%", "upwell", "holy", 0.6, 0), ("Upwell: rejuvenation, 20%", "upwell", "nature", 0.2, 0), ("Upwell: 10% fill", "upwell", "nature", 0.1, 0)]
    tiles = []
    for label, style, tint, level, calm in scenes:
        sc.fill = lambda t, lv=level: lv  # noqa: B023
        p = panel(tint)
        p.cached_t = None
        img = p.crop(draw(p, style, 2.3, calm))
        tiles.append(gc.label(np.pad(img, ((26, 0), (0, 8), (0, 0)), constant_values=0.07), label, (6, 2), size=18))
    rows = [np.hstack(tiles[i:i + 4]) for i in range(0, len(tiles), 4)]
    Image.fromarray((np.clip(np.vstack(rows), 0, 1) * 255).astype(np.uint8)).save(out)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1])
