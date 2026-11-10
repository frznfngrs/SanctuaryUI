"""Shared Blender helpers for the party frame art (run inside Blender, see party_globes.py).

Units: one Blender unit is one UI unit. Pieces are modelled in UI space, x right and y DOWN
(as the contract in SanctuaryUI/PartyArt.lua is written); P() flips y for Blender. Renders are
orthographic, top-down, 2 px per unit, transparent background, lit from the top-left like D3.
"""
import json
import math
import random
import sys

import bmesh
import bpy
from mathutils import Vector

PPU = 2  # render pixels per UI unit (the art is 2x)


def args():
    """The JSON job after Blender's `--`: {out, tex, geo, ...}."""
    return json.load(open(sys.argv[sys.argv.index("--") + 1]))


def P(x, y, z=0.0):
    return Vector((x, -y, z))


# ---------------------------------------------------------------------------
# Scene


def setup(samples=128):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "CUDA"
        prefs.get_devices()
        cuda = [d for d in prefs.devices if d.type == "CUDA"]
        for d in prefs.devices:
            d.use = d.type == "CUDA"
        sc.cycles.device = "GPU" if cuda else "CPU"
    except Exception:  # no GPU: CPU is slower, same result
        sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_percentage = 100
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.16, 0.16, 0.17, 1)
    bg.inputs[1].default_value = 1.0
    target = bpy.data.objects.new("light_target", None)
    sc.collection.objects.link(target)
    # D3's key light: warm, from the top-left and fairly high; a cool rim from the bottom-right.
    _sun("key", (-110, 120, 150), 6.0, 5, (1.0, 0.93, 0.82), target)
    _sun("rim", (120, -90, 60), 0.7, 25, (0.62, 0.72, 1.0), target)
    return sc


def _sun(name, loc, energy, angle, color, target):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.angle = math.radians(angle)
    ld.color = color
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(loc)
    t = o.constraints.new("TRACK_TO")
    t.target = target
    t.track_axis = "TRACK_NEGATIVE_Z"
    t.up_axis = "UP_Y"
    return o


def render(path, cx, cy, w, h):
    """Render the cell w x h units centred on (cx, cy) (UI space) to path, at PPU."""
    sc = bpy.context.scene
    cam = sc.camera
    if cam is None:
        cd = bpy.data.cameras.new("cam")
        cd.type = "ORTHO"
        cam = bpy.data.objects.new("cam", cd)
        sc.collection.objects.link(cam)
        sc.camera = cam
    cam.data.ortho_scale = max(w, h)
    cam.location = P(cx, cy, 300)
    cam.rotation_euler = (0, 0, 0)
    cam.data.clip_end = 1000
    sc.render.resolution_x = int(round(w * PPU))
    sc.render.resolution_y = int(round(h * PPU))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def clear_meshes():
    for o in list(bpy.data.objects):
        if o.type in ("MESH", "CURVE"):
            bpy.data.objects.remove(o, do_unlink=True)


# ---------------------------------------------------------------------------
# Materials for what Blender shades itself: D3's stone and the groove floors. The metal is
# painted by the build from passes (render_passes below).


def _img(nodes, path, extension="REPEAT"):
    n = nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(path, check_existing=True)
    n.image.colorspace_settings.name = "sRGB"
    n.extension = extension
    return n


def _grunge(nt, tex, scale):
    n, l = nt.nodes, nt.links
    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    l.new(tc.outputs["Object"], mp.inputs["Vector"])
    im = _img(n, tex)
    l.new(mp.outputs["Vector"], im.inputs["Vector"])
    bw = n.new("ShaderNodeRGBToBW")
    l.new(im.outputs["Color"], bw.inputs["Color"])
    # Stretch D3's dark stone to 0..1.
    st = n.new("ShaderNodeMapRange")
    st.inputs["From Min"].default_value = 0.02
    st.inputs["From Max"].default_value = 0.22
    l.new(bw.outputs["Val"], st.inputs["Value"])
    return st.outputs["Result"], tc


def _ao(nt, distance, lo):
    n, l = nt.nodes, nt.links
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = distance
    ao.samples = 16
    mr = n.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = lo
    l.new(ao.outputs["AO"], mr.inputs["Value"])
    return mr.outputs["Result"]


def _mix(nt, fac, a, b):
    n, l = nt.nodes, nt.links
    m = n.new("ShaderNodeMix")
    m.data_type = "RGBA"
    if isinstance(fac, (int, float)):
        m.inputs["Factor"].default_value = fac
    else:
        l.new(fac, m.inputs["Factor"])
    for sock, v in (("A", a), ("B", b)):
        if isinstance(v, tuple):
            m.inputs[sock].default_value = v + (1,) if len(v) == 3 else v
        else:
            l.new(v, m.inputs[sock])
    return m.outputs["Result"]


def _multiply(nt, col, fac):
    n, l = nt.nodes, nt.links
    m = n.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = "MULTIPLY"
    m.inputs["Factor"].default_value = 1.0
    l.new(col, m.inputs["A"])
    comb = n.new("ShaderNodeCombineColor")
    for i in range(3):
        l.new(fac, comb.inputs[i])
    l.new(comb.outputs["Color"], m.inputs["B"])
    return m.outputs["Result"]


def groove_floor(tex):
    """Near-black gritty floor of a cut groove."""
    m = bpy.data.materials.new("floor")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    g, _ = _grunge(nt, tex, 0.05)
    col = _mix(nt, g, (0.004, 0.004, 0.005), (0.018, 0.017, 0.017))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


def stone(tex, w, h, bright=1.0):
    """D3's cracked stone (a crop of the inventory panel) laid over a w x h slab top."""
    m = bpy.data.materials.new("stone")
    m.use_nodes = True
    nt = m.node_tree
    n, l = nt.nodes, nt.links
    bsdf = n["Principled BSDF"]
    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    # Object coords: x 0..w, y 0..-h. Map to UV 0..1 (y flipped back).
    mp.inputs["Scale"].default_value = (1.0 / w, 1.0 / h, 1)
    mp.inputs["Location"].default_value = (0, 1, 0)
    l.new(tc.outputs["Object"], mp.inputs["Vector"])
    im = _img(n, tex, "MIRROR")
    l.new(mp.outputs["Vector"], im.inputs["Vector"])
    gain = n.new("ShaderNodeMix")
    gain.data_type = "RGBA"
    gain.blend_type = "MULTIPLY"
    gain.inputs["Factor"].default_value = 1
    l.new(im.outputs["Color"], gain.inputs["A"])
    gain.inputs["B"].default_value = (2.4 * bright, 2.28 * bright, 2.1 * bright, 1)
    col = _multiply(nt, gain.outputs["Result"], _ao(nt, 3.0, 0.2))
    l.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.82
    bw = n.new("ShaderNodeRGBToBW")
    l.new(im.outputs["Color"], bw.inputs["Color"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.5
    l.new(bw.outputs["Val"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


# ---------------------------------------------------------------------------
# Shapes


def link(me, name):
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def lathe(name, cx, cy, profile, steps=192, a0=0.0, a1=360.0):
    """Spin an (r, z) profile round (cx, cy): a ring with a shaped cross-section."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    full = (a1 - a0) >= 360
    n = steps if full else steps + 1
    rings = []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * ca, r * sa, z)) for r, z in profile])
    m = len(profile)
    for i in range(steps):
        A, B = rings[i], rings[(i + 1) % n] if full else rings[i + 1]
        for j in range(m - 1):
            bm.faces.new((A[j], B[j], B[j + 1], A[j + 1]))
    if not full:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(me, name)
    o.location = P(cx, cy)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def prism(name, outline, z0, z1):
    """Extrude a closed outline (list of (x, y) in UI space) from z0 to z1."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bot = [bm.verts.new((x, -y, z0)) for x, y in outline]
    top = [bm.verts.new((x, -y, z1)) for x, y in outline]
    k = len(outline)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return link(me, name)


def sector_outline(cx, cy, r0, r1, a0, a1, steps=96):
    """Annular sector; angles in degrees, 0 = right, positive = up on screen."""
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r1 * math.cos(a), cy - r1 * math.sin(a)))
    for i in range(steps, -1, -1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r0 * math.cos(a), cy - r0 * math.sin(a)))
    return pts


def rect_outline(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def bevel(o, width, segments=3, angle=35):
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return m


def subtract(target, cutter):
    m = target.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.solver = "EXACT"
    m.object = cutter
    cutter.hide_render = True
    return m


def rivet(name, x, y, r, z):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=P(x, y, z), segments=32, ring_count=16)
    o = bpy.context.active_object
    o.name = name
    o.scale.z = 0.55
    bpy.ops.object.shade_smooth()
    return o


def spike(name, cx, cy, ang, r0, length, width, height):
    """A short forged spike pointing out from (cx, cy) at ang (degrees, 0 right, up positive)."""
    a = math.radians(ang)
    ux, uy = math.cos(a), -math.sin(a)  # UI space, y down
    px, py = -uy, ux
    bx, by = cx + ux * r0, cy + uy * r0
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    v0 = bm.verts.new((bx + px * width, -(by + py * width), 0))
    v1 = bm.verts.new((bx - px * width, -(by - py * width), 0))
    v2 = bm.verts.new((bx + ux * length, -(by + uy * length), 0.3))
    v3 = bm.verts.new((bx + ux * length * 0.3, -(by + uy * length * 0.3), height))
    for f in ((v0, v1, v3), (v1, v2, v3), (v2, v0, v3), (v0, v2, v1)):
        bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(me, name)
    bevel(o, 0.3, 2, 30)
    return o


def assign(objs, mat):
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)


def clay():
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.22, 0.22, 0.22, 1)
    b.inputs["Roughness"].default_value = 0.45
    b.inputs["Metallic"].default_value = 0.0
    return m


def _emission(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for node in list(nt.nodes):
        if node.type == "BSDF_PRINCIPLED":
            nt.nodes.remove(node)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(emit.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    return m, nt, emit


def normal_material():
    m, nt, emit = _emission("norm")
    n, l = nt.nodes, nt.links
    bev = n.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.3
    half = n.new("ShaderNodeVectorMath")
    half.operation = "MULTIPLY_ADD"
    half.inputs[1].default_value = (0.5, 0.5, 0.5)
    half.inputs[2].default_value = (0.5, 0.5, 0.5)
    l.new(bev.outputs["Normal"], half.inputs[0])
    l.new(half.outputs["Vector"], emit.inputs["Color"])
    return m


def data_material(is_metal):
    m, nt, emit = _emission("data_metal" if is_metal else "data_floor")
    n, l = nt.nodes, nt.links
    comb = n.new("ShaderNodeCombineColor")
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 2.0
    ao.samples = 16
    l.new(ao.outputs["AO"], comb.inputs[0])
    comb.inputs[1].default_value = 1.0 if is_metal else 0.0
    l.new(comb.outputs["Color"], emit.inputs["Color"])
    return m


_PASS_MATS = {}


def render_passes(prefix, cx, cy, w, h, metal, floors):
    if not _PASS_MATS:
        _PASS_MATS.update(clay=clay(), norm=normal_material(), dm=data_material(True), df=data_material(False))
    sc = bpy.context.scene
    assign(metal + floors, _PASS_MATS["clay"])
    render(prefix + "-lit.png", cx, cy, w, h)
    sc.view_settings.view_transform = "Raw"
    sc.cycles.use_denoising = False
    assign(metal + floors, _PASS_MATS["norm"])
    render(prefix + "-norm.png", cx, cy, w, h)
    assign(metal, _PASS_MATS["dm"])
    assign(floors, _PASS_MATS["df"])
    render(prefix + "-data.png", cx, cy, w, h)
    sc.view_settings.view_transform = "Standard"
    sc.cycles.use_denoising = True


# The Slab: shared by party_slab.py and target_slab.py.
def slab_grow(rect, by):
    x, y, w, h = rect
    return (x - by, y - by, x + w + by, y + h + by)


def slab_frame(name, rect, out_by, in_by, z0, z1):
    """A rectangular rim: rect grown by out_by, with rect grown by in_by (negative shrinks)
    cut out of it."""
    o = prism(name, rect_outline(*slab_grow(rect, out_by)), z0, z1)
    hole = prism(name + "_hole", rect_outline(*slab_grow(rect, in_by)), z0 - 2, z1 + 2)
    subtract(o, hole)
    return o


def slab_build(geo, cap, seed, small, TOP=6.0):
    """The party Slab (party_slab.py), also drawn at target size (target_slab.py): a stone slab
    with the socket and grooves cut in, and its metal: socket rim, groove lips, corner caps.
    Returns slab, groove floors, metal objects."""
    w, h = geo["size"]
    random.seed(seed)
    slab = prism("slab", rect_outline(0, 0, w, h), 0, TOP)
    floors = []
    # Recesses: a little larger than the openings, so the lips overhang their walls.
    recesses = [(geo["socket"], 1.0, 3.2), (geo["health"], 0.9, 2.6)]
    if "power" in geo:
        recesses.append((geo["power"], 0.8, 2.0))
    for rect, by, depth in recesses:
        subtract(slab, prism("recess", rect_outline(*slab_grow(rect, by)), TOP - depth, TOP + 5))
        floors.append(prism("floor", rect_outline(*slab_grow(rect, by + 0.2)), TOP - depth - 0.6, TOP - depth + 0.05))
    # Chipped edges: a few bites out of the rim, deterministic.
    for _ in range(4 if small else 7):
        side = random.choice("tblr")
        s = random.uniform(0.9, 1.8 if small else 2.4)
        if side in "tb":
            x, y = random.uniform(cap + 3, w - cap - 3), (0 if side == "t" else h)
        else:
            x, y = (0 if side == "l" else w), random.uniform(cap + 2, h - cap - 2)
        chip = prism("chip", rect_outline(x - s, y - s, x + s, y + s), TOP - s * 0.8, TOP + 4)
        chip.rotation_euler = (random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0, 3))
        subtract(slab, chip)
    bevel(slab, 0.9 if small else 1.3, 3, 40)

    metal = []
    rim_h = TOP + (2.0 if small else 2.5)
    rim = slab_frame("socket_rim", geo["socket"], 1.6 if small else 2.4, 0.0, TOP - 0.6, rim_h)
    bevel(rim, 0.45 if small else 0.6, 3, 40)
    metal.append(rim)
    grooves = [(geo["health"], 1.2 if small else 1.3)]
    if "power" in geo:
        grooves.append((geo["power"], 1.0))
    for rect, out_by in grooves:
        lip = slab_frame("lip", rect, out_by + 0.35, 0.35, TOP - 0.5, TOP + 1.3)
        bevel(lip, 0.35, 2, 40)
        metal.append(lip)
    # Corner caps: square plates bent over the corners, a rivet in each.
    for cx, cy in ((0, 0), (w - cap, 0), (0, h - cap), (w - cap, h - cap)):
        c = prism("cap", rect_outline(cx, cy, cx + cap, cy + cap), TOP - 0.4, rim_h + 0.5)
        bevel(c, 0.6, 3, 40)
        metal.append(c)
        metal.append(rivet("capr", cx + cap / 2, cy + cap / 2, cap * 0.16, rim_h + 0.5))
    return slab, floors, metal
