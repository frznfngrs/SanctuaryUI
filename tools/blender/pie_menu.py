"""Pie menu art (SanctuaryUI/PieMenu.lua): the iron band, a slice's round socket in iron and
gold, the hub's rim and a boundary stud. Shapes and materials come from target_styles.py.

  blender -b --factory-startup -P pie_menu.py -- out_dir [samples]

Writes band.png, socket-iron.png, socket-gold.png, hub.png and stud.png, transparent;
tools/build_pie_art.py packs them. Sizes in UI units are the contract with PieMenu.lua.
"""
import math
import os

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "target_styles.py")
exec(compile(open(SRC).read().split("\nPIECES = {")[0], SRC, "exec"))

RADIUS = 112  # the sockets' centres


def ring(name, r_in, r_out, h, groove=True):
    w = r_out - r_in
    prof = [(r_in, 0), (r_in, h * .55), (r_in + .9, h)]
    if groove:
        prof += [(r_in + w * .36, h), (r_in + w * .42, h * .62), (r_in + w * .58, h * .62), (r_in + w * .64, h)]
    prof += [(r_out - 1.2, h), (r_out - .3, h * .5), (r_out, 0)]
    return lathe(name, 0, 0, prof, 256)


def band():
    return [], [ring("band", RADIUS - 10, RADIUS + 10, 3.6)], 256, 2


def socket():
    o = [ring("rim", 26, 34, 6.5, groove=False),
         lathe("lip", 0, 0, [(24.6, 0), (24.6, 3.2), (26.4, 4.4), (26.4, 0)], 256)]
    return [], o, 80, 3.2


def hub():
    o = [ring("hrim", 47, 58, 7.5)]
    for i in range(12):
        t = 2 * math.pi * (i + .5) / 12
        o.append(rivet(52.5 * math.cos(t), 52.5 * math.sin(t), 1.5, 7.3))
    for ang in (45, 135, 225, 315):
        o.append(spike(0, 0, ang, 56, 15, 4.6, 4.6))
    # A dark floor under the glass the build paints, so the rim's inner wall is shaded.
    return [lathe("face", 0, 0, [(.01, 1.5), (47.5, 1.5), (47.5, 0)], 160)], o, 160, 3.2


def stud():
    return [], [lathe("s", 0, 0, [(.01, 4.6), (2.2, 4.4), (3.6, 3.2), (4.6, 1), (4.6, 0)], 64)], 16, 4


setup()
FLOOR = floor_mat()
M = {k: metal("m_" + k, v["col"], v["wear"], rough=v["rough"]) for k, v in RANKS.items() if k != "boss"}
for name, build, rank in (("band", band, "normal"), ("socket-iron", socket, "normal"), ("socket-gold", socket, "elite"),
                          ("hub", hub, "normal"), ("stud", stud, "normal")):
    clear()
    floors, metals, box, PPU = build()
    assign(floors, FLOOR)
    assign(metals, M[rank])
    render(os.path.join(OUT, name + ".png"), -box / 2, -box / 2, box, box)
