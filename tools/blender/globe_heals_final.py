"""Still of the shipped heal looks, composited from the real sheets in SanctuaryUI/Art with the
numbers GlobeAura.lua draws them with (a check on the art, not a capture from the client). The
cast-time looks run on a mock clock, as globe_heals.py does.

    python globe_heals_final.py OUT.png
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
import globe_heals as gh  # noqa: E402
import globe_surge_concepts as sc  # noqa: E402
import globe_surge_final as sf  # noqa: E402

ART = os.path.join(os.path.dirname(__file__), "..", "..", "SanctuaryUI", "Art")


def rgba(name):
    return np.asarray(Image.open(os.path.join(ART, name)).convert("RGBA")).astype(np.float32) / 255


class Shipped(gh.Lib):
    """gh.Lib's interface, read back from the sheets the addon ships."""

    def __init__(self):
        a = rgba("heal-vines.png")[..., 3]
        self.d = {"vines": np.stack([a[y * 256:(y + 1) * 256, x * 256:(x + 1) * 256] for y in range(4) for x in range(4)])}
        leaf = rgba("heal-leaf.png")[..., 3]
        k = 128
        crop = int(round(k * 0.354)) * 2
        pad = (k - crop) // 2
        self.d["leaf"] = np.stack([leaf[y * k + pad:y * k + pad + crop, x * k + pad:x * k + pad + crop] for y in range(4) for x in range(4)])
        halo = rgba("heal-halo.png")[..., 3]
        self.d["halo_core"], self.d["halo_glow"] = halo[:256], halo[256:]
        rings = rgba("heal-rings.png")[..., 3]
        self.d["ring_core"], self.d["ring_band"] = rings[:64], rings[64:]
        self.d["drop"] = rgba("heal-drop.png")[..., 3]
        self.d["dome"] = rgba("heal-dome.png")[..., 3]
        beam = rgba("heal-beam.png")[..., 3]
        self.d["beam_core"], self.d["beam_glow"] = beam[:, :128], beam[:, 128:]
        veil = rgba("heal-veil.png")[..., 3]
        self.d["veil"] = np.stack([veil[y * 128:(y + 1) * 128, x * 256:(x + 1) * 256] for y in range(4) for x in range(8)])
        m = rgba("heal-mound.png")
        cell = lambda arr, row, x: arr[row * 128:(row + 1) * 128, x * 256:(x + 1) * 256]
        self.d["mound"] = np.stack([cell(m[..., 3], y, x) for y in range(2) for x in range(8)])
        self.d["mound_shade"] = np.stack([cell(m[..., 0], y, x) for y in range(2) for x in range(8)])
        self.d["mound_edge"] = np.stack([cell(m[..., 3], y + 2, x) for y in range(2) for x in range(8)])


def d_rain(p, L, t, env):
    """DRAW.rain: the saturated glow is cut well back (blue on red reads pink); nothing in the liquid."""
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    H = 0.58 * g
    period, fall = 5.2, 0.36
    lanes = [-0.62, 0.18, -0.25, 0.62, 0.42, -0.5, 0.05, -0.08]

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.14 * env)
        fxc.stamp(c, sf.stretched(art, 1.0, 0.08), cx, surf, g, sat, 0.1 * env, mask=gm)
        for i in range(8):
            q = (t / period + i / 8 + gh.hash1(i * 4.1) * 0.05) % 1
            x = lanes[i] * g * 0.34
            if q < fall:
                f = q / fall
                y = surf - H * (1 - f ** 1.45)
                a = gh.s1(f / 0.3) * env
                gh.stamp_rect(c, L["drop"], cx + x, y - g * 0.035, g * 0.04, g * 0.08, hot, 0.95 * a, mask=gm)
                fxc.stamp(c, art.mote, cx + x, y, g * 0.1, sat, 0.45 * a, mask=gm)
            else:
                rq = (q - fall) / (1 - fall)
                w = g * (0.08 + 0.72 * (1 - (1 - rq) ** 2.2))
                a = (1 - rq) ** 1.6 * env
                gh.stamp_rect(c, L["ring_band"], cx + x, surf, w, w * 0.25, sat, 0.22 * a, mask=gm)
                gh.stamp_rect(c, L["ring_core"], cx + x, surf, w, w * 0.25, hot, 0.62 * a, mask=gm)
                if rq > 0.12:
                    gh.stamp_rect(c, L["ring_core"], cx + x, surf, w * 0.55, w * 0.1375, hot, 0.34 * (1 - rq) ** 2 * env, mask=gm)
                if rq < 0.25:
                    fxc.stamp(c, art.mote, cx + x, surf, g * 0.14, hot, 0.8 * (1 - rq / 0.25) ** 1.4 * env, mask=gm)

    return p.finish(t, lambda c: None, lambda lq: lq, front)


def d_pulse(p, L, t, env):
    """DRAW.pulse at a 3 s tick: a broad wave rising in the liquid, the surface answering."""
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    gm = [(art.gmask, cx, cy, g)]
    lv = p.level_row(t)
    D = 0.62 * g
    period, rise, flash = 3.0, min(1.15, 3.0 * 0.55), min(0.9, 3.0 * 0.45)
    done = int(t // period)
    since = t - done * period
    rising = 1 - (period - since) / rise if period - since <= rise else None
    flashing = since / flash if done >= 1 and since < flash else None

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.1 * env)
        if flashing is not None:
            a = flashing
            ca = (1 - a) ** 1.4 * env
            ww = g * (0.55 + 0.45 * a)
            fxc.stamp(c, sf.stretched(art, 1.0, 0.09), cx, surf, ww, sat, 0.9 * ca, mask=gm)
            fxc.stamp(c, sf.stretched(art, 1.0, 0.04), cx, surf, ww * 0.65, hot, 1.1 * ca, mask=gm)
            fxc.stamp(c, L["dome"], cx, surf - g * 0.05, g * 0.8, sat, 0.42 * ca * (1 - a), mask=gm)
            rw = g * (0.25 + 0.7 * (1 - (1 - a) ** 2))
            gh.stamp_rect(c, L["ring_band"], cx, surf, rw, rw * 0.25, sat, 0.4 * ca, mask=gm)
            gh.stamp_rect(c, L["ring_core"], cx, surf, rw * 0.98, rw * 0.245, hot, 0.65 * ca, mask=gm)
            fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.28 * ca)

    def in_liquid(lq):
        if rising is None:
            return lq
        tmp = np.zeros_like(lq)
        y = lv + D * (1 - rising)
        fade = gh.s1(rising / 0.25) * env
        fxc.stamp(tmp, sf.stretched(art, 1.0, 0.42 / 1.35), g / 2, y, g * 1.35, sat, 0.75 * fade)
        fxc.stamp(tmp, sf.stretched(art, 1.0, 0.16 / 1.1), g / 2, y, g * 1.1, hot, 0.55 * fade)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, lambda c: None, in_liquid, front)


def d_embers(p, L, t, env):
    """DRAW.embers: sparks with a trail, guttering on their own, dying at different heights."""
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    r = g / 2
    sat, hot = p.sat, p.hot
    gm = [(art.gmask, cx, cy, g)]
    lanes = [-0.15, 0.3, -0.5, 0.05, 0.62, -0.32, 0.45, -0.7, 0.18, -0.05, 0.75, -0.6, 0.0]
    tail = L["drop"][::-1]

    def front(c):
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.14 * env)
        for i in range(1, 14):
            sp = 1 + (i % 3 == 0) * 0.35
            q = (t * sp / 10 + gh.hash1(i * 5.7)) % 1
            y = cy + r * 0.86 - q * r * 1.74
            chord = math.sqrt(max(0.03, 1 - ((cy - y) / r) ** 2))
            x = cx + lanes[i - 1] * 0.72 * r * chord + math.sin(q * 9 + i * 1.9) * r * 0.06
            die = 0.55 + 0.4 * gh.hash1(i * 2.9)
            fade = gh.s1(q / 0.14) * (1 - gh.s1((q - die) / (1 - die)))
            gutter = 0.72 + 0.28 * math.sin(t * (1.1 + gh.hash1(i)) * 3 + i) * math.sin(t * 5 + i * 3)
            size = g * (0.07 + 0.04 * gh.hash1(i * 2.1))
            lit = fade * gutter * env
            gh.stamp_rect(c, tail, x, y + size * 1.15, size * 0.4, size * 3.1, gh.mix(sat, hot, 0.6, 0.4), 0.7 * lit, mask=gm)
            fxc.stamp(c, art.mote, x, y, size * 3.0, sat, 0.34 * lit, mask=gm)
            fxc.stamp(c, art.mote, x, y, size * 1.05, hot, 0.9 * lit, mask=gm)

    return p.finish(t, lambda c: None, lambda lq: lq, front)


def mound_rise(q):
    return math.sin(min(1, q / 0.7) * math.pi * 0.5) ** 0.75 * (1 - gh.s1((q - 0.55) / 0.45))


def d_surge(p, L, t, env):
    """HEAL_DRAW.mound: one stepped frame in the liquid's colour, its edge lit ADD, the height eased."""
    art, g, cx, cy = p.art, p.globe, p.cx, p.cy
    sat, hot = p.sat, p.hot
    surf = p.globe_rect[1] + p.level_row(t)
    age = gh.shot_age(t)
    q = age / 1.15
    gm = [(art.gmask, cx, cy, g)]
    live = q < 1

    def front(c):
        if not live:
            return
        u = g * 0.42
        i = min(15, int(q * 16))
        at, here = mound_rise((i + 0.5) / 16), mound_rise(q)
        keep = max(0.8, min(1.25, here / at)) if at > 0.02 else 1.0
        w = g * 1.15
        h = u * 1.12 * keep
        cover, shade, edge = L["mound"][i], L["mound_shade"][i], L["mound_edge"][i]
        ww, hh = int(w), int(h)
        x0, y0 = int(cx - w / 2), int(surf + u * 0.12 - h)
        lift = cv2.resize(cover, (ww, hh), interpolation=cv2.INTER_LINEAR)
        body = cv2.resize(shade, (ww, hh), interpolation=cv2.INTER_LINEAR)
        lit = cv2.resize(edge, (ww, hh), interpolation=cv2.INTER_LINEAR)
        cx0, cy0 = max(0, x0), max(0, y0)
        lift, body, lit = (a[cy0 - y0:, cx0 - x0:][:c.shape[0] - cy0, :c.shape[1] - cx0] for a in (lift, body, lit))
        hh2, ww2 = lift.shape
        m = fxc.stamp_sample(art.gmask, cx0, cy0, ww2, hh2, cx, cy, g)
        a = (lift * m)[..., None]
        patch = c[cy0:cy0 + hh2, cx0:cx0 + ww2]
        patch = patch * (1 - a) + p.color[None, None] * body[..., None] * a
        patch = np.clip(patch + (lit * m)[..., None] * np.array(gh.mix(sat, hot, 0.8, 0.3), np.float32) * 0.42, 0, 1)
        c[cy0:cy0 + hh2, cx0:cx0 + ww2] = patch
        rise = math.sin(min(q / 0.45, 1) * math.pi * 0.5)
        fall = 1 - gh.s1((q - 0.3) / 0.7)
        fxc.stamp(c, art.grim[::-1], cx, cy, g, hot, 0.26 * rise * fall)
        fxc.stamp(c, art.corona, cx, surf - u * 0.3, g * 0.9, sat, 0.12 * rise * fall, mask=gm)

    def in_liquid(lq):
        tmp = np.zeros_like(lq)
        if live:
            lv = p.level_row(t)
            rise = math.sin(min(q / 0.45, 1) * math.pi * 0.5)
            fall = 1 - gh.s1((q - 0.25) / 0.6)
            fxc.stamp(tmp, sf.stretched(art, 0.85, 0.5), g / 2, lv, g * 1.05, sat, 0.22 * rise * fall)
        return lq + tmp * p.rows(t, True)

    return p.finish(t, lambda c: None, in_liquid, front)


OPTIONS = [
    {"name": "Halo", "fn": gh.d_halo, "tint": "holy", "hot": True, "t": 4.6, "for": "Renew"},
    {"name": "Bloom", "fn": gh.d_bloom, "tint": "nature", "hot": True, "t": 4.6, "for": "Rejuvenation"},
    {"name": "Vines", "fn": gh.d_vines, "tint": "nature", "hot": True, "t": 9.6, "for": "Regrowth"},
    {"name": "Veil", "fn": gh.d_veil, "tint": "nature", "hot": True, "t": 4.6, "for": "Frenzied Regeneration"},
    {"name": "Rain", "fn": d_rain, "tint": "water", "hot": True, "t": 5.0, "for": "Mana Tide (also on mana)"},
    {"name": "Pulse", "fn": d_pulse, "tint": "holy", "hot": True, "t": 3.4, "for": "tick look", "t2": 2.7},
    {"name": "Embers", "fn": d_embers, "tint": "nature", "hot": True, "t": 4.6, "for": "spark look"},
    {"name": "Mend", "fn": gh.d_mend, "tint": "holy", "hot": False, "t": 1.1, "for": "fast heals"},
    {"name": "Benediction", "fn": gh.d_benediction, "tint": "holy", "hot": False, "t": 1.05, "for": "big heals, Lay on Hands"},
    {"name": "Surge", "fn": d_surge, "tint": "holy", "hot": False, "t": 1.25, "for": "potions (a choice)"},
]


def build_board():
    b = gh.Board.__new__(gh.Board)
    b.art = fxc.Art()
    b.L = Shipped()
    b.panels = {}
    return b


def main(out):
    b = build_board()
    rows = [gc.label(np.full((42, 1880, 3), 0.075, np.float32), "Shipped heal looks, from the sheets in SanctuaryUI/Art with GlobeAura.lua's numbers: real size at 60% and 20%, zoomed", (8, 8), size=22)]
    for o in OPTIONS:
        t = o["t"]
        extra = o.get("t2")
        title = f"{o['name']}  ({o['for']})"
        if extra is not None:
            tiles = [b.tile(o, gh.REAL, 0.6, extra, title=f"{o['name']} rising 60%"), b.tile(o, gh.REAL, 0.6, t, title=f"{o['name']} tick 60%"),
                     b.tile(o, gh.REAL, 0.2, t, title=f"{o['name']} tick 20%"), b.tile(o, 230, 0.6, extra, title=f"{o['name']} rising zoom"), b.tile(o, 230, 0.6, t, title=f"{o['name']} tick zoom")]
        else:
            tiles = [b.tile(o, gh.REAL, 0.6, t, title=title), b.tile(o, gh.REAL, 0.2, t, title=f"{o['name']} 20%"),
                     b.tile(o, 230, 0.6, t, title=f"{o['name']} 60% zoomed"), b.tile(o, 230, 0.2, t, title=f"{o['name']} 20% zoomed")]
        H = max(t_.shape[0] for t_ in tiles)
        for i, tl in enumerate(tiles):
            tiles[i] = np.pad(tl, ((0, H - tl.shape[0]), (0, 2), (0, 0)), constant_values=0.075)
        rows.append(np.hstack(tiles))
    W = max(r.shape[1] for r in rows)
    sheet = np.vstack([np.pad(a, ((0, 0), (0, W - a.shape[1]), (0, 0)), constant_values=0.075) for a in rows])
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(out, optimize=True)
    print(out, sheet.shape)


if __name__ == "__main__":
    main(sys.argv[1])
