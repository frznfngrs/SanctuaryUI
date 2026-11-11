"""Minimap art (SanctuaryUI/Map.lua): the forged ring of the Scrying globe style. Shapes and
materials come from target_styles.py, as the pie menu's do.

  blender -b --factory-startup -P minimap_ring.py -- out_dir [samples]

Writes ring.png, transparent; tools/build_minimap_art.py packs it. The glass sits inside
radius 100 of a 256-unit box: that is the contract with Map.lua.
"""
import math
import os

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "target_styles.py")
exec(compile(open(SRC).read().split("\nPIECES = {")[0], SRC, "exec"))

R_IN, R_OUT = 100, 116


def ring():
    w = R_OUT - R_IN
    h = 8.5
    prof = [(R_IN, 0), (R_IN, h * .5), (R_IN + 1.4, h), (R_IN + w * .34, h), (R_IN + w * .40, h * .6),
            (R_IN + w * .60, h * .6), (R_IN + w * .66, h), (R_OUT - 1.6, h), (R_OUT - .4, h * .5), (R_OUT, 0)]
    o = [lathe("ring", 0, 0, prof, 320)]
    for i in range(24):
        if i % 6 == 0:
            continue  # the cardinal points carry spikes
        t = 2 * math.pi * i / 24
        o.append(rivet((R_IN + w * .5) * math.cos(t), (R_IN + w * .5) * math.sin(t), 1.7, h * .62))
    for ang in (0, 90, 180, 270):
        o.append(spike(0, 0, ang, R_OUT - 3, 12, 6, 5.2))
    return [], o, 256, 2


setup()
FLOOR = floor_mat()
M = metal("m_ring", RANKS["normal"]["col"], RANKS["normal"]["wear"], rough=RANKS["normal"]["rough"])
clear()
floors, metals, box, PPU = ring()
assign(floors, FLOOR)
assign(metals, M)
render(os.path.join(OUT, "ring.png"), -box / 2, -box / 2, box, box)
