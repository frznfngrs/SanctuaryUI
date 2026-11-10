"""Target frame, Slab style (ns.Art.TARGET_STYLES.slab in SanctuaryUI/Art.lua): the party Slab
(party_lib.slab_build) at the target frame's size, so the two match. Stone and metal render
apart as for the party; build_hud_art.py's target_slab step paints the metal once per rank
(iron, steel, gold, ember-worn black) and lays it over the stone.

  blender -b --factory-startup -P target_slab.py -- job.json

The job gives geo (size, socket, health, power as x, y, w, h; cap; margin) and out / tex.
Writes <out>/tslab-stone.png and tslab-{lit,norm,data}.png, the slab plus margin on every side.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import party_lib as L  # noqa: E402

job = L.args()
G = job["geo"]
OUT, TEX = job["out"], job["tex"]
GRUNGE = os.path.join(TEX, "grunge.png")
STONE_TEX = os.path.join(TEX, "stone.png")
TOP = 6.0  # the slab's top face, as the party's

L.setup(job.get("samples", 160))
FLOOR = L.groove_floor(GRUNGE)
SHADOW_METAL = L.groove_floor(GRUNGE)

w, h = G["size"]
m = G["margin"]
cw, ch = w + 2 * m, h + 2 * m
L.clear_meshes()
slab, floors, metal = L.slab_build(G, G["cap"], 7, False, TOP)
# Stone: the metal still casts its shadows on it but isn't drawn.
L.assign([slab], L.stone(STONE_TEX, w, h))
L.assign(floors, FLOOR)
L.assign(metal, SHADOW_METAL)
for o in metal:
    o.visible_camera = False
L.render(os.path.join(OUT, "tslab-stone.png"), w / 2, h / 2, cw, ch)
# Metal passes: the stone and floors still occlude and shade it but aren't drawn.
for o in metal:
    o.visible_camera = True
for o in [slab] + floors:
    o.visible_camera = False
L.render_passes(os.path.join(OUT, "tslab"), w / 2, h / 2, cw, ch, metal, [])
