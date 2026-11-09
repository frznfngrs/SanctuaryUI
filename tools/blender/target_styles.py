"""Target frame styles (TargetPlate.lua): the frames and their small parts, modelled here with
procedural materials. Rects and boxes match ns.Art.TARGET_STYLES in SanctuaryUI/Art.lua.

  blender -b --factory-startup -P target_styles.py -- out_dir [samples]

Writes <piece>-<rank>.png, 2 px per UI unit, transparent. tools/build_target_styles.py packs them.
UI space: x right, y down; see P().
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
OUT = a[0]
SAMPLES = int(a[1]) if len(a) > 1 else 128
os.makedirs(OUT, exist_ok=True)
PPU = 2


def P(x, y, z=0.0):
    return Vector((x, -y, z))


def setup():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = "CUDA"
        pr.get_devices()
        for d in pr.devices:
            d.use = d.type == "CUDA"
        sc.cycles.device = "GPU"
    except Exception:
        sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    n, l = nt.nodes, nt.links
    # A dark room with a bright patch up and left, so metal has something to reflect.
    tc = n.new("ShaderNodeTexCoord")
    dot = n.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = Vector((-0.5, 0.45, 0.74)).normalized()
    l.new(tc.outputs["Generated"], dot.inputs[0])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[0].color = (0.012, 0.012, 0.015, 1)
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = (0.42, 0.38, 0.33, 1)
    l.new(dot.outputs["Value"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], n["Background"].inputs[0])
    t = bpy.data.objects.new("t", None)
    sc.collection.objects.link(t)
    sun("key", (-110, 120, 150), 2.3, 5, (1.0, 0.92, 0.8), t)
    sun("rim", (120, -90, 60), 0.35, 25, (0.6, 0.7, 1.0), t)
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def sun(name, loc, e, ang, col, t):
    d = bpy.data.lights.new(name, "SUN")
    d.energy, d.angle, d.color = e, math.radians(ang), col
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(loc)
    c = o.constraints.new("TRACK_TO")
    c.target, c.track_axis, c.up_axis = t, "TRACK_NEGATIVE_Z", "UP_Y"


def render(path, x0, y0, w, h):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = int(w * PPU), int(h * PPU)
    sc.render.resolution_percentage = 100
    cam = sc.camera
    cam.data.ortho_scale = max(w, h)
    cam.location = P(x0 + w / 2, y0 + h / 2, 200)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def clear():
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)


def noise(nt, scale, detail=8, rough=0.6, stretch=None):
    n, l = nt.nodes, nt.links
    tc = n.new("ShaderNodeTexCoord")
    tex = n.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = detail
    tex.inputs["Roughness"].default_value = rough
    if stretch:
        mp = n.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        l.new(tc.outputs["Object"], mp.inputs["Vector"])
        l.new(mp.outputs["Vector"], tex.inputs["Vector"])
    else:
        l.new(tc.outputs["Object"], tex.inputs["Vector"])
    return tex.outputs["Fac"]


def crack(nt, scale):
    """Voronoi distance to edge: 0 on a crack line, growing away from it."""
    n, l = nt.nodes, nt.links
    tc = n.new("ShaderNodeTexCoord")
    warp = n.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = scale * 2.2
    warp.inputs["Detail"].default_value = 6
    add = n.new("ShaderNodeVectorMath")
    add.operation = "SCALE"
    add.inputs["Scale"].default_value = 3.0 / scale
    l.new(warp.outputs["Color"], add.inputs[0])
    plus = n.new("ShaderNodeVectorMath")
    l.new(tc.outputs["Object"], plus.inputs[0])
    l.new(add.outputs[0], plus.inputs[1])
    v = n.new("ShaderNodeTexVoronoi")
    v.feature = "DISTANCE_TO_EDGE"
    v.inputs["Scale"].default_value = scale
    l.new(plus.outputs[0], v.inputs["Vector"])
    return v.outputs["Distance"]


def ramp(nt, val, lo, hi, a=(0, 0, 0), b=(1, 1, 1)):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position, r.color_ramp.elements[1].position = lo, hi
    r.color_ramp.elements[0].color = (*a, 1)
    r.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(val, r.inputs["Fac"])
    return r.outputs["Color"]


def mix(nt, fac, a, b, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    if isinstance(fac, (int, float)):
        m.inputs["Factor"].default_value = fac
    else:
        nt.links.new(fac, m.inputs["Factor"])
    for s, v in (("A", a), ("B", b)):
        if isinstance(v, tuple):
            m.inputs[s].default_value = (*v, 1)
        else:
            nt.links.new(v, m.inputs[s])
    return m.outputs["Result"]


def metal(name, col, wear, dirt=(0.05, 0.04, 0.035), rough=0.42, ember=None):
    """Forged metal: pitted, dirty in the recesses, worn bright on edges."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, l = nt.nodes, nt.links
    b = n["Principled BSDF"]
    b.inputs["Metallic"].default_value = 1.0
    big = noise(nt, 0.09, 7, 0.62)
    fine = noise(nt, 1.1, 8, 0.7)
    # Recess dirt from AO; edge wear from a tight inverted AO.
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 2.2
    ao.samples = 12
    edge = n.new("ShaderNodeAmbientOcclusion")
    edge.inside = True
    edge.inputs["Distance"].default_value = 0.8
    edge.samples = 8
    base = mix(nt, ramp(nt, big, 0.36, 0.66), col, tuple(c * 0.55 for c in col))
    base = mix(nt, ramp(nt, fine, 0.5, 0.72), base, tuple(c * 0.45 for c in col))
    wfac = ramp(nt, edge.outputs["AO"], 0.5, 0.97, (1, 1, 1), (0, 0, 0))
    wmul = mix(nt, 1.0, wfac, ramp(nt, fine, 0.3, 0.5), "MULTIPLY")
    base = mix(nt, wmul, base, wear)
    base = mix(nt, ramp(nt, ao.outputs["AO"], 0.15, 0.85, (1, 1, 1), (0, 0, 0)), base, dirt)
    l.new(base, b.inputs["Base Color"])
    rmix = mix(nt, ramp(nt, fine, 0.3, 0.75), (rough - 0.12,) * 3, (rough + 0.3,) * 3)
    l.new(rmix, b.inputs["Roughness"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.65
    bump.inputs["Distance"].default_value = 0.35
    bmix = mix(nt, 0.5, ramp(nt, fine, 0.25, 0.8), ramp(nt, big, 0.3, 0.7))
    l.new(bmix, bump.inputs["Height"])
    l.new(bump.outputs["Normal"], b.inputs["Normal"])
    if ember:
        cr_ = ramp(nt, crack(nt, 0.11), 0.0, 0.028, (1, 1, 1), (0, 0, 0))
        fac = mix(nt, 1.0, cr_, ramp(nt, big, 0.53, 0.64), "MULTIPLY")
        l.new(mix(nt, fac, (0, 0, 0), ember), b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 3.2
    return m


def stone(name="stone", tint=(0.105, 0.095, 0.082)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, l = nt.nodes, nt.links
    b = n["Principled BSDF"]
    big = noise(nt, 0.05, 9, 0.62)
    mid = noise(nt, 0.28, 9, 0.7)
    cr = ramp(nt, crack(nt, 0.055), 0.0, 0.04, (0.3, 0.28, 0.26), (1, 1, 1))
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 4.0
    ao.samples = 12
    col = mix(nt, ramp(nt, big, 0.3, 0.72), tuple(c * 0.7 for c in tint), tuple(c * 1.25 for c in tint))
    col = mix(nt, ramp(nt, mid, 0.42, 0.68), col, tuple(c * 0.72 for c in tint))
    col = mix(nt, 1.0, col, cr, "MULTIPLY")
    col = mix(nt, 1.0, col, ramp(nt, ao.outputs["AO"], 0.0, 0.9, (0.15,) * 3, (1, 1, 1)), "MULTIPLY")
    l.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.88
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.9
    h = mix(nt, 1.0, mix(nt, 0.55, ramp(nt, mid, 0.25, 0.8), ramp(nt, big, 0.3, 0.7)), cr, "MULTIPLY")
    l.new(h, bump.inputs["Height"])
    l.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def floor_mat():
    m = bpy.data.materials.new("floor")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.006, 0.006, 0.007, 1)
    b.inputs["Roughness"].default_value = 0.95
    b.inputs["Specular IOR Level"].default_value = 0.0
    return m


RANKS = {
    "normal": dict(col=(0.1, 0.092, 0.085), wear=(0.62, 0.58, 0.52), rough=0.5),
    "rare": dict(col=(0.2, 0.235, 0.29), wear=(0.78, 0.86, 1.0), rough=0.36),
    "elite": dict(col=(0.42, 0.24, 0.05), wear=(1.0, 0.76, 0.34), rough=0.34),
    "boss": dict(col=(0.03, 0.022, 0.022), wear=(0.42, 0.14, 0.07), rough=0.45, ember=(1.0, 0.22, 0.02)),
}


def link(me, name):
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def prism(name, pts, z0, z1):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bot = [bm.verts.new((x, -y, z0)) for x, y in pts]
    top = [bm.verts.new((x, -y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    k = len(pts)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return link(me, name)


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def bevel(o, w, seg=3, ang=35):
    m = o.modifiers.new("b", "BEVEL")
    m.width, m.segments, m.limit_method = w, seg, "ANGLE"
    m.angle_limit = math.radians(ang)
    return o


def cut(t, c):
    m = t.modifiers.new("c", "BOOLEAN")
    m.operation, m.solver, m.object = "DIFFERENCE", "EXACT", c
    c.hide_render = True
    c.hide_viewport = True
    return t


def lathe(name, cx, cy, prof, steps=160):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        rings.append([bm.verts.new((r * math.cos(t), r * math.sin(t), z)) for r, z in prof])
    for i in range(steps):
        A, B = rings[i], rings[(i + 1) % steps]
        for j in range(len(prof) - 1):
            bm.faces.new((A[j], B[j], B[j + 1], A[j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(me, name)
    o.location = P(cx, cy)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def rivet(x, y, r, z):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=P(x, y, z), segments=24, ring_count=12)
    o = bpy.context.active_object
    o.scale.z = 0.55
    bpy.ops.object.shade_smooth()
    return o


def spike(cx, cy, ang, r0, length, width, h):
    """Forged tapered spike out from (cx, cy), angle in degrees, 0 right, 90 up."""
    t = math.radians(ang)
    ux, uy = math.cos(t), -math.sin(t)
    px, py = -uy, ux
    bx, by = cx + ux * r0, cy + uy * r0
    me = bpy.data.meshes.new("spike")
    bm = bmesh.new()
    v = [bm.verts.new((bx + px * width, -(by + py * width), 0)),
         bm.verts.new((bx - px * width, -(by - py * width), 0)),
         bm.verts.new((bx + ux * length, -(by + uy * length), 0.4)),
         bm.verts.new((bx + ux * length * 0.28, -(by + uy * length * 0.28), h))]
    for f in ((v[0], v[1], v[3]), (v[1], v[2], v[3]), (v[2], v[0], v[3]), (v[0], v[2], v[1])):
        bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return bevel(link(me, "spike"), 0.35, 2, 25)


def horn(cx, cy, flip, length=26, base=6, rise=1.0):
    """A curved horn sweeping up and out from (cx, cy). flip = -1 mirrors it leftwards."""
    pts_o, pts_i = [], []
    n = 22
    for i in range(n + 1):
        t = i / n
        a = math.radians(160 - 150 * t)
        rad = length
        x = cx + flip * (rad * (1 + math.cos(a)) * 0.62)
        y = cy - rise * rad * math.sin(a) * 0.95 - t * 6
        w = base * (1 - t) ** 0.8 + 0.15
        nx, ny = math.cos(a), -math.sin(a)
        pts_o.append((x + flip * nx * w, y + ny * w))
        pts_i.append((x - flip * nx * w, y - ny * w))
    o = prism("horn", pts_o + pts_i[::-1], 0, 5)
    return bevel(o, 1.5, 4, 25)


def assign(objs, mat):
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)


def frame_rect(name, r, out_by, z0, z1, in_by=0.0):
    x0, y0, x1, y1 = r
    o = prism(name, rect(x0 - out_by, y0 - out_by, x1 + out_by, y1 + out_by), z0, z1)
    h = prism(name + "h", rect(x0 - in_by, y0 - in_by, x1 + in_by, y1 + in_by), z0 - 3, z1 + 3)
    return cut(o, h)


def pit(mesh, r, depth, z, by=0.8):
    """Cut a recess into mesh and return its dark floor."""
    x0, y0, x1, y1 = r
    cut(mesh, prism("pit", rect(x0 - by, y0 - by, x1 + by, y1 + by), z - depth, z + 6))
    return prism("floor", rect(x0 - by - 0.2, y0 - by - 0.2, x1 + by + 0.2, y1 + by + 0.2), z - depth - 0.6, z - depth + 0.05)


def lintel(rank):
    """A: carved stone slab, sibling of the party Slab. 340 x 72. Rect list lives in compose."""
    w, h, top = 340, 72, 7.0
    slab = prism("slab", rect(0, 0, w, h), 0, top)
    floors = []
    random.seed(11)
    for r, d in (((8, 8, 64, 64), 3.2), ((76, 10, 330, 36), 2.6), ((76, 41, 330, 47), 1.6), ((76, 51, 330, 65), 2.0)):
        floors.append(pit(slab, r, d, top))
    for _ in range(8):
        s = random.uniform(1.2, 2.6)
        side = random.choice("tb")
        x, y = random.uniform(16, w - 16), 0 if side == "t" else h
        c = prism("chip", rect(x - s, y - s, x + s, y + s), top - s * 0.8, top + 4)
        c.rotation_euler = (random.uniform(-.5, .5), random.uniform(-.5, .5), random.uniform(0, 3))
        cut(slab, c)
    bevel(slab, 1.4, 3, 40)
    metal_objs = []
    rim_z = top + 2.8
    metal_objs.append(bevel(frame_rect("rim", (8, 8, 64, 64), 2.6, top - .6, rim_z), .65, 3, 40))
    for r in ((76, 10, 330, 36), (76, 41, 330, 47), (76, 51, 330, 65)):
        metal_objs.append(bevel(frame_rect("lip", r, 1.5, top - .5, top + 1.4, .3), .35, 2, 40))
    cap = 11
    for cx, cy in ((0, 0), (w - cap, 0), (0, h - cap), (w - cap, h - cap)):
        metal_objs.append(bevel(prism("cap", rect(cx, cy, cx + cap, cy + cap), top - .4, rim_z + .6), .7, 3, 40))
        metal_objs.append(rivet(cx + cap / 2, cy + cap / 2, 1.9, rim_z + .6))
    if rank == "elite" or rank == "rare":
        for x, ang in ((12, 118), (w - 12, 62)):
            metal_objs.append(spike(x, 3, ang, 0, 14, 4, 4))
    if rank == "boss":
        metal_objs += [horn(10, 6, -1, 22, 5), horn(w - 10, 6, 1, 22, 5)]
        metal_objs.append(spike(w / 2, 2, 90, 0, 12, 5, 4))
    return [slab], floors, metal_objs, (-34, -34, w + 68, h + 44)


def castrail(rank, w=178):
    """A cast bar's own small frame, shown only while something is casting."""
    h, top = 18, 5.0
    a_ = prism("r", [(0, 0), (w, 0), (w + 6, h / 2), (w, h), (0, h), (-6, h / 2)], 0, top)
    floors = [pit(a_, (4, 3.5, w - 4, h - 3.5), 1.6, top, .4)]
    objs = [bevel(a_, 1.0, 3, 35)]
    return [], floors, objs, (-10, -4, w + 20, h + 8)


def rank_marks(objs, rank, xl, xr, y):
    if rank in ("elite", "rare"):
        objs.append(spike(xl, y, 118, 0, 14, 4, 4))
        objs.append(spike(xr, y, 62, 0, 14, 4, 4))
    if rank == "boss":
        objs += [horn(xl, y + 3, -1, 20, 5), horn(xr, y + 3, 1, 20, 5)]


def slim(rank):
    """Slim Lintel: the party Slab's proportions at target size, 300 x 54."""
    w, h, top = 300, 54, 6.0
    slab = prism("slab", rect(0, 0, w, h), 0, top)
    floors = []
    grooves = [((6, 6, 48, 48), 3.0), ((56, 7, 292, 33), 2.6), ((56, 38, 292, 45), 1.6)]
    for r, d in grooves:
        floors.append(pit(slab, r, d, top))
    random.seed(21)
    for _ in range(6):
        q = random.uniform(1.0, 2.2)
        side = random.choice("tb")
        x, y = random.uniform(14, w - 14), 0 if side == "t" else h
        c = prism("chip", rect(x - q, y - q, x + q, y + q), top - q * .8, top + 4)
        c.rotation_euler = (random.uniform(-.5, .5), random.uniform(-.5, .5), random.uniform(0, 3))
        cut(slab, c)
    bevel(slab, 1.2, 3, 40)
    objs = []
    rim_z = top + 2.4
    objs.append(bevel(frame_rect("rim", (6, 6, 48, 48), 2.2, top - .6, rim_z), .55, 3, 40))
    for r in ((56, 7, 292, 33), (56, 38, 292, 45)):
        objs.append(bevel(frame_rect("lip", r, 1.3, top - .5, top + 1.3, .3), .35, 2, 40))
    cap = 8
    for cx, cy in ((0, 0), (w - cap, 0), (0, h - cap), (w - cap, h - cap)):
        objs.append(bevel(prism("cap", rect(cx, cy, cx + cap, cy + cap), top - .4, rim_z + .5), .6, 3, 40))
        objs.append(rivet(cx + cap / 2, cy + cap / 2, 1.4, rim_z + .5))
    rank_marks(objs, rank, 8, w - 8, 2)
    return [slab], floors, objs, (-34, -34, w + 68, h + 44)


def bracket(rank):
    """Forged Bracket: all iron, a ring portrait gripping the end of a heavy bar."""
    cx, cy, rr, top = 34, 34, 34, 6.0
    objs, floors = [], []
    # Starts under the ring, clear of the portrait hole (the model can't cover it all).
    plate = prism("plate", [(62, 14), (318, 14), (334, 35), (318, 58), (62, 58)], 0, top)
    health, power = (74, 21, 310, 45), (74, 48, 296, 53)
    floors.append(pit(plate, health, 2.6, top))
    floors.append(pit(plate, power, 1.5, top, .5))
    bevel(plate, 1.4, 3, 35)
    objs.append(plate)
    objs.append(bevel(frame_rect("lip", health, 1.5, top - .5, top + 1.4, .3), .35, 2, 40))
    objs.append(bevel(frame_rect("lip", power, 1.0, top - .4, top + 1.0, .2), .3, 2, 40))
    for x, y in ((316, 18), (316, 54), (70, 18), (70, 54)):
        objs.append(rivet(x, y, 1.7, top + .4))
    objs += bracket_ring_objs(rank)
    floors.append(lathe("hole", cx, cy, [(.01, 3), (rr - 7.5, 3)]))
    return [], floors, objs, (-34, -34, 402, 112)


def tablet(rank):
    """Tablet: a name tab sits on the plate, so the bar is left clear for health."""
    objs, floors = [], []
    top = 6.0
    tab = prism("tab", [(82, 0), (246, 0), (258, 18), (70, 18)], 0, top - 1)
    bevel(tab, 1.0, 3, 35)
    objs.append(tab)
    plate = prism("plate", rect(0, 14, 330, 66), 0, top)
    health, power = (76, 20, 322, 46), (76, 50, 322, 56)
    floors.append(pit(plate, health, 2.6, top))
    floors.append(pit(plate, power, 1.5, top, .5))
    floors.append(pit(plate, (10, 8, 62, 60), 3.0, top))
    bevel(plate, 1.3, 3, 35)
    objs.append(plate)
    objs.append(bevel(frame_rect("lip", health, 1.5, top - .5, top + 1.4, .3), .35, 2, 40))
    objs.append(bevel(frame_rect("lip", power, 1.0, top - .4, top + 1.0, .2), .3, 2, 40))
    frame = bevel(frame_rect("rim", (10, 8, 62, 60), 3.0, top - .6, top + 3.2), .65, 3, 40)
    objs.append(frame)
    for x, y in ((326, 18), (326, 62), (68, 18), (68, 62)):
        objs.append(rivet(x, y, 1.7, top + .4))
    rank_marks(objs, rank, 10, 322, 13)
    return [], floors, objs, (-34, -34, 398, 122)


def tot(rank):
    """Target of target: a small ring and bar, the same for every concept."""
    objs, floors = [], []
    cx, cy, rr = 15, 15, 15
    objs.append(lathe("r", cx, cy, [(rr - 3.5, 1), (rr - 3.5, 8), (rr - 2.3, 10), (rr - .7, 10), (rr + .5, 8), (rr + 1, 1)]))
    floors.append(lathe("h", cx, cy, [(.01, 1.5), (rr - 3, 1.5)]))
    a_ = prism("a", [(28, 8), (104, 8), (110, 15), (104, 22), (28, 22)], 0, 4)
    floors.append(pit(a_, (32, 11, 102, 19), 1.4, 4, .4))
    objs.append(bevel(a_, .8, 2, 35))
    return [], floors, objs, (-4, -4, 120, 38)


def badge(rank):
    """Level stud."""
    objs = [lathe("b", 0, 0, [(.01, 5.4), (6, 5.4), (7.4, 4.8), (9, 3.4), (10, 1), (10, 0)])]
    bevel(objs[0], .4, 2, 30)
    return [], [], objs, (-12, -12, 24, 24)


def bracket_ring_objs(rank):
    """The Forged Bracket's portrait ring, with its studs and rank ornaments."""
    cx, cy, rr = 34, 34, 34
    objs = [lathe("ring", cx, cy, [(rr - 8, 2), (rr - 8, 13), (rr - 6, 16), (rr - 2, 16.5), (rr, 14.5), (rr + 2, 9), (rr + 2, 2)])]
    for i in range(8):
        t = 2 * math.pi * (i + .5) / 8
        objs.append(rivet(cx + (rr - 3.2) * math.cos(t), cy + (rr - 3.2) * math.sin(t), 1.7, 16.8))
    if rank in ("elite", "rare"):
        for ang in (60, 120, 90):
            objs.append(spike(cx, cy, ang, rr - 1, 14, 5, 5))
    if rank == "boss":
        objs += [horn(cx - 26, cy - 22, -1, 24, 6), horn(cx + 26, cy - 22, 1, 24, 6)]
    return objs


def bracket_ring(rank):
    """The ring alone, drawn above the portrait so it hides the square model's corners."""
    return [], [], bracket_ring_objs(rank), (-36, -36, 140, 140)


PIECES = {
    "lintel": lintel, "slim": slim, "bracket": bracket, "tablet": tablet,
    "bracket_ring": bracket_ring, "castrail": lambda rank: castrail(rank, 236), "tot": tot, "badge": badge,
}

setup()
FLOOR = floor_mat()
STONE = stone()
METAL = {k: metal("m_" + k, v["col"], v["wear"], rough=v["rough"], ember=v.get("ember")) for k, v in RANKS.items()}
for name, build in PIECES.items():
    for rank in RANKS:
        clear()
        stones, floors, metals, box = build(rank)[:4]
        assign(stones, STONE)
        assign(floors, FLOOR)
        assign(metals, METAL[rank])
        render(os.path.join(OUT, "%s-%s.png" % (name, rank)), *box)
