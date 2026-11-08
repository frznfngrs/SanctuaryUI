"""Party frames, Slab style (the Slim slab): a thin slab of D3's cracked stone per member, the
portrait socket and the two grooves cut into it, and the metal that binds it (corner caps,
socket rim, groove lips) in iron and gold. Stone and metal are separate layers so the stone's
opacity can go down to the Ghost look. Geometry comes from the contract via the job.

  blender -b --factory-startup -P party_slab.py -- job.json

Writes <out>/slab-{member,pet}-stone.png and slab-{member,pet}-{lit,data}.png for the metal
(see party_lib.render_passes), each exactly its cell at 2x; the build paints the metal.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import party_lib as L  # noqa: E402

job = L.args()
S = job["geo"]["slab"]
OUT, TEX = job["out"], job["tex"]
GRUNGE = os.path.join(TEX, "grunge.png")
STONE_TEX = os.path.join(TEX, "stone.png")

TOP = 6.0  # the slab's top face


def grow(rect, by):
    x, y, w, h = rect
    return (x - by, y - by, x + w + by, y + h + by)


def frame(name, rect, out_by, in_by, z0, z1):
    """A rectangular rim: rect grown by out_by, with rect grown by in_by (negative shrinks)
    cut out of it."""
    o = L.prism(name, L.rect_outline(*grow(rect, out_by)), z0, z1)
    hole = L.prism(name + "_hole", L.rect_outline(*grow(rect, in_by)), z0 - 2, z1 + 2)
    L.subtract(o, hole)
    return o


def build(geo, cap, seed, small):
    w, h = geo["size"]
    random.seed(seed)
    slab = L.prism("slab", L.rect_outline(0, 0, w, h), 0, TOP)
    floors = []
    # Recesses: a little larger than the openings, so the lips overhang their walls.
    recesses = [(geo["socket"], 1.0, 3.2), (geo["health"], 0.9, 2.6)]
    if "power" in geo:
        recesses.append((geo["power"], 0.8, 2.0))
    for rect, by, depth in recesses:
        L.subtract(slab, L.prism("recess", L.rect_outline(*grow(rect, by)), TOP - depth, TOP + 5))
        floors.append(L.prism("floor", L.rect_outline(*grow(rect, by + 0.2)), TOP - depth - 0.6, TOP - depth + 0.05))
    # Chipped edges: a few bites out of the rim, deterministic.
    for _ in range(4 if small else 7):
        side = random.choice("tblr")
        s = random.uniform(0.9, 1.8 if small else 2.4)
        if side in "tb":
            x, y = random.uniform(cap + 3, w - cap - 3), (0 if side == "t" else h)
        else:
            x, y = (0 if side == "l" else w), random.uniform(cap + 2, h - cap - 2)
        chip = L.prism("chip", L.rect_outline(x - s, y - s, x + s, y + s), TOP - s * 0.8, TOP + 4)
        chip.rotation_euler = (random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0, 3))
        L.subtract(slab, chip)
    L.bevel(slab, 0.9 if small else 1.3, 3, 40)

    metal = []
    rim_h = TOP + (2.0 if small else 2.5)
    rim = frame("socket_rim", geo["socket"], 1.6 if small else 2.4, 0.0, TOP - 0.6, rim_h)
    L.bevel(rim, 0.45 if small else 0.6, 3, 40)
    metal.append(rim)
    grooves = [(geo["health"], 1.2 if small else 1.3)]
    if "power" in geo:
        grooves.append((geo["power"], 1.0))
    for rect, out_by in grooves:
        lip = frame("lip", rect, out_by + 0.35, 0.35, TOP - 0.5, TOP + 1.3)
        L.bevel(lip, 0.35, 2, 40)
        metal.append(lip)
    # Corner caps: square plates bent over the corners, a rivet in each.
    for cx, cy in ((0, 0), (w - cap, 0), (0, h - cap), (w - cap, h - cap)):
        c = L.prism("cap", L.rect_outline(cx, cy, cx + cap, cy + cap), TOP - 0.4, rim_h + 0.5)
        L.bevel(c, 0.6, 3, 40)
        metal.append(c)
        metal.append(L.rivet("capr", cx + cap / 2, cy + cap / 2, cap * 0.16, rim_h + 0.5))
    return slab, floors, metal


L.setup(job.get("samples", 128))
FLOOR = L.groove_floor(GRUNGE)
SHADOW_METAL = L.groove_floor(GRUNGE)

for name, cap, seed, small in (("member", 8.0, 5, False), ("pet", 5.0, 9, True)):
    geo = S[name]
    w, h = geo["size"]
    L.clear_meshes()
    slab, floors, metal = build(geo, cap, seed, small)
    # Stone: the metal still casts its shadows on it but isn't drawn.
    L.assign([slab], L.stone(STONE_TEX, w, h))
    L.assign(floors, FLOOR)
    L.assign(metal, SHADOW_METAL)
    for o in metal:
        o.visible_camera = False
    L.render(os.path.join(OUT, "slab-%s-stone.png" % name), w / 2, h / 2, w, h)
    # Metal passes: the stone and floors still occlude and shade it but aren't drawn.
    for o in metal:
        o.visible_camera = True
    for o in [slab] + floors:
        o.visible_camera = False
    L.render_passes(os.path.join(OUT, "slab-%s" % name), w / 2, h / 2, w, h, metal, [])
