"""Party frames, Globes style: the forged iron bezel round a member's health globe (with the
resource crescent cut into its right side), the portrait medallion and the pet's bezel, each
in iron and gold. Geometry comes from the contract (SanctuaryUI/PartyArt.lua) via the job.

  blender -b --factory-startup -P party_globes.py -- job.json

Writes <out>/globes-{bezel,medallion,pet}-{lit,data}.png (see party_lib.render_passes), each
exactly its cell at 2x; the build paints them iron and gold.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import party_lib as L  # noqa: E402

job = L.args()
G = job["geo"]["globes"]
OUT, TEX = job["out"], job["tex"]

# How far the art's inner edge runs over the liquid (or portrait) underneath.
COVER = 0.6


def band_profile(r_in, r_out, h):
    """A forged band: chamfered inner lip, a flat top with one incised line, a chamfer down to
    the outer edge. (r, z) pairs, inside to outside."""
    w = r_out - r_in
    return [
        (r_in, 0.0), (r_in, h * 0.62), (r_in + 0.55, h), (r_in + w * 0.3, h),
        (r_in + w * 0.34, h * 0.78), (r_in + w * 0.38, h), (r_out - 1.0, h),
        (r_out - 0.25, h * 0.5), (r_out, 0.0),
    ]


def ring_piece(name, cx, cy, hole_r, out_r, h):
    return L.lathe(name, cx, cy, band_profile(hole_r - COVER, out_r, h))


def crescent(geo):
    """The groove's inside from the contract's bounding box: radii and half-angle."""
    cx, cy = geo["size"][0] / 2, geo["size"][1] / 2
    rx, ry, rw, rh = geo["resource"]
    ro = rx + rw - cx
    half = math.degrees(math.asin((rh / 2) / ro))
    ri = (rx - cx) / math.cos(math.radians(half))
    return cx, cy, ri, ro, half


def build_bezel():
    geo = G["bezel"]
    cx, cy, d = geo["globe"]
    hole = d / 2
    band_out = hole + 4.6
    objs = [ring_piece("band", cx, cy, hole, band_out, 3.0)]
    floor = []
    gcx, gcy, ri, ro, half = crescent(geo)
    # The rail: a curved block outside the band, the groove cut right through it, a dark floor
    # (slightly larger than the groove, so the walls meet it) underneath.
    rail = L.prism("rail", L.sector_outline(cx, cy, band_out - 0.6, ro + 1.9, -(half + 6), half + 6), 0, 2.9)
    cut = L.prism("groove", L.sector_outline(cx, cy, ri, ro, -half, half), -2, 10)
    L.subtract(rail, cut)
    L.bevel(rail, 0.5, 3, 40)
    objs.append(rail)
    floor.append(L.prism("floor", L.sector_outline(cx, cy, ri - 0.4, ro + 0.4, -half - 1, half + 1), 0, 1.0))
    mid = (ri + ro) / 2
    for a in (half + 3.2, -(half + 3.2)):
        objs.append(L.rivet("cap", cx + mid * math.cos(math.radians(a)), cy - mid * math.sin(math.radians(a)), 1.25, 2.9))
    rr = hole + 2.6
    for a in (90, 182, -112):
        objs.append(L.rivet("rivet", cx + rr * math.cos(math.radians(a)), cy - rr * math.sin(math.radians(a)), 0.95, 2.9))
    objs.append(L.spike("spike", cx, cy, -90, band_out - 1.2, 8.2, 2.6, 2.6))
    objs.append(L.spike("spikeL", cx, cy, -62, band_out - 1.2, 4.5, 1.7, 1.9))
    return objs, floor, (cx, cy) + tuple(geo["size"])


def build_medallion():
    geo = G["medallion"]
    cx, cy, d = geo["hole"]
    hole = d / 2
    out = hole + 4.0
    objs = [ring_piece("mring", cx, cy, hole, out, 2.8)]
    objs.append(L.spike("mspike", cx, cy, 128, out - 1.0, 6.0, 2.2, 2.2))
    objs.append(L.spike("mspike2", cx, cy, 158, out - 1.0, 3.6, 1.4, 1.6))
    rr = hole + 2.2
    for a in (40, 250, 320):
        objs.append(L.rivet("mrivet", cx + rr * math.cos(math.radians(a)), cy - rr * math.sin(math.radians(a)), 0.8, 2.6))
    return objs, [], (cx, cy) + tuple(geo["size"])


def build_pet():
    geo = G["pet"]
    cx, cy, d = geo["globe"]
    hole = d / 2
    out = hole + 4.0
    objs = [ring_piece("pring", cx, cy, hole, out, 2.7)]
    objs.append(L.spike("pspike", cx, cy, -90, out - 1.0, 5.2, 2.0, 2.0))
    rr = hole + 2.2
    for a in (90, 210, 330):
        objs.append(L.rivet("privet", cx + rr * math.cos(math.radians(a)), cy - rr * math.sin(math.radians(a)), 0.8, 2.6))
    return objs, [], (cx, cy) + tuple(geo["size"])


L.setup(job.get("samples", 128))

for name, build in (("bezel", build_bezel), ("medallion", build_medallion), ("pet", build_pet)):
    L.clear_meshes()
    objs, floor, (cx, cy, w, h) = build()
    L.render_passes(os.path.join(OUT, "globes-%s" % name), w / 2, h / 2, w, h, objs, floor)
