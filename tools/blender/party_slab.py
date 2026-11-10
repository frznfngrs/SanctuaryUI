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


def build(geo, cap, seed, small):
    return L.slab_build(geo, cap, seed, small, TOP)


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
