"""The tally of claw slashes Reckless Swings burns into the rage globe (Reckless.lua).

    python tools/build_reckless_art.py [--out SanctuaryUI/Art]

Needs numpy, opencv and pillow. Writes reckless-marks.png, 2048 x 1024: eight cells of 512, each
the globe's square with one slash in place. Top row: the four slashes' glow (the wide ember
light). Bottom row: their cores (the thin white-hot cut). White, with the light in the alpha, for
ADD; Reckless.lua tints them.
"""
import argparse
import math
import os

import cv2
import numpy as np
from PIL import Image

CELL = 512
SS = 4  # drawn this many times larger, then reduced
MARKS = 4
ALONG = np.array([-0.40, 0.92])  # the stroke runs from the upper right down to the lower left
ALONG /= np.linalg.norm(ALONG)
PERP = np.array([ALONG[1], -ALONG[0]])
SPACING = 0.150  # between slashes, of the globe
CENTRE_X = -0.05  # left of the middle: the angel stands over the globe's right side
LENGTHS = [0.50, 0.66, 0.62, 0.46]
SHIFT = [0.03, -0.02, 0.025, -0.01]  # along the stroke, so the ends don't line up


def centreline(k, n=220):
    c = np.array([0.5 + CENTRE_X, 0.5]) + PERP * (k - (MARKS - 1) / 2) * SPACING + ALONG * SHIFT[k]
    s = np.linspace(0, 1, n)
    bow = 0.022 * (1 if k % 2 == 0 else 0.6)
    pts = c[None] + ALONG[None] * ((s - 0.5) * LENGTHS[k])[:, None] + PERP[None] * (bow * np.sin(math.pi * s) - bow * 0.6)[:, None]
    return s, pts


def stroke(k, width, rng, ragged):
    """A claw cut: it bites in fast, is widest a third of the way down and drags out to a point."""
    n = CELL * SS
    img = np.zeros((n, n), np.float32)
    s, pts = centreline(k)
    profile = s ** 0.55 * (1 - s) ** 1.25
    profile /= profile.max()
    noise = np.interp(s, np.linspace(0, 1, 24), rng.uniform(-1, 1, 24))
    w = width * profile * (1 + ragged * noise)
    left = pts + PERP[None] * w[:, None]
    right = pts - PERP[None] * w[:, None] * 0.8
    poly = np.concatenate([left, right[::-1]]) * n
    cv2.fillPoly(img, [poly.astype(np.int32)], 1.0, cv2.LINE_AA)
    return img, pts


def flecks(k, rng):
    """Embers flung off the end of the stroke."""
    n = CELL * SS
    img = np.zeros((n, n), np.float32)
    _, pts = centreline(k)
    tip = pts[-1]
    for _ in range(11):
        d = rng.uniform(-0.02, 0.085)
        off = rng.normal(0, 0.016 + 0.2 * max(d, 0))
        p = (tip + ALONG * d + PERP * off) * n
        r = rng.uniform(0.0016, 0.0048) * n * (1 - 0.5 * max(d, 0) / 0.085)
        cv2.circle(img, (int(p[0]), int(p[1])), max(1, int(r)), float(rng.uniform(0.5, 1.0)), -1, cv2.LINE_AA)
    return img


def down(img):
    return cv2.resize(img, (CELL, CELL), interpolation=cv2.INTER_AREA)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "SanctuaryUI", "Art"))
    a = p.parse_args()
    sheet = np.zeros((CELL * 2, CELL * MARKS), np.float32)
    g = (np.arange(CELL, dtype=np.float32) + 0.5) / CELL * 2 - 1
    xx, yy = np.meshgrid(g, g)
    inside = np.clip((0.97 - np.hypot(xx, yy)) / 0.08, 0, 1)
    for k in range(MARKS):
        rng = np.random.default_rng(40 + k)
        body, _ = stroke(k, 0.026, rng, 0.28)
        cut, _ = stroke(k, 0.0085, np.random.default_rng(40 + k), 0.2)
        sparks = flecks(k, rng)
        body, cut, sparks = down(body), down(cut), down(sparks)
        glow = (body * 0.55 + cv2.GaussianBlur(body, (0, 0), 5) * 0.75 + cv2.GaussianBlur(body, (0, 0), 16) * 0.5
                + sparks * 0.5 + cv2.GaussianBlur(sparks, (0, 0), 4) * 0.8)
        core = cut + cv2.GaussianBlur(cut, (0, 0), 1.6) * 0.6 + sparks * 0.9
        sheet[:CELL, k * CELL:(k + 1) * CELL] = np.clip(glow, 0, 1) * inside
        sheet[CELL:, k * CELL:(k + 1) * CELL] = np.clip(core, 0, 1) * inside
    alpha = (np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8)
    white = np.full_like(alpha, 255)
    path = os.path.join(a.out, "reckless-marks.png")
    Image.merge("RGBA", [Image.fromarray(white)] * 3 + [Image.fromarray(alpha)]).save(path, optimize=True)
    print(path, sheet.shape[1], "x", sheet.shape[0])


if __name__ == "__main__":
    main()
