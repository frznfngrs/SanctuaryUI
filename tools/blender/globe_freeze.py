"""The frozen globe (Freeze.lua): crystallised ice over the health globe, rendered in full colour
with alpha (not white-for-ADD like the shields: frost has to cover the liquid, not light it).

Run headless:
  blender -b --factory-startup -P tools/blender/globe_freeze.py -- --mode hold --out DIR \
      [--size 1024] [--samples 96] [--only 0,8]

Modes:
  hold     one still: the finished crust, exactly the globe's square
  glint    three stills: the same crust lit by one small hard light from three places, for the
           travelling glints (luminance, added)
  grow     25 frames: blades run in from the rim, then the plates crystallise rim to centre
  shatter  25 frames x 3 sub-frames: the crust bursts off the globe; a wider view (HALF_SHATTER)

World units: the globe's radius is 1. The camera looks along -Y from +Y, ortho; the screen's right
is -X and up is +Z. tools/build_freeze_art.py packs the frames into the addon's sheets.
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
import numpy as np

HALF_SHATTER = 1.7
GROW_FRAMES = 25
SHATTER_FRAMES = 25
SHATTER_SUBS = 3
DOME = 0.34  # the crust's rise toward the camera at the centre


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--only", default="")
    return p.parse_args(argv)


def setup(size, samples, half):
    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.cycles.seed = 11
    scene.cycles.use_animated_seed = False
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 10
    scene.cycles.transmission_bounces = 10
    scene.cycles.glossy_bounces = 6
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.render.film_transparent = True
    scene.cycles.film_transparent_glass = True
    scene.cycles.film_transparent_roughness = 1.0
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("cold")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.30, 0.46, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = half * 2
    obj = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(obj)
    obj.location = (0, 8, 0)
    obj.rotation_euler = (math.radians(90), 0, math.radians(180))
    scene.camera = obj
    return scene


def light(name, loc, energy, size, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    # Aim at the globe.
    d = -np.array(loc, float)
    d /= np.linalg.norm(d)
    obj.rotation_euler = (math.acos(-d[2]) if abs(d[2]) < 1 else 0, 0, math.atan2(d[0], -d[1]))
    obj.rotation_mode = "XYZ"
    track = obj.constraints.new("TRACK_TO")
    target = bpy.data.objects.get("aim")
    if not target:
        target = bpy.data.objects.new("aim", None)
        bpy.context.collection.objects.link(target)
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    return obj


def world_of(x, z, y=0.0):
    """Screen x (right), z (up), height toward the camera -> world."""
    return (-x, y, z)


def dome(x, z):
    r2 = x * x + z * z
    return DOME * math.sqrt(max(0.0, 1.0 - 0.9 * min(r2, 1.1)))


# ---------------------------------------------------------------------------------------------
# The crust's layout: Voronoi plates, small at the rim and large in the middle, and a ring of
# crystal blades lying in from the rim.

def clip_poly(poly, n, d):
    """Keep the side of the polygon where p.n <= d."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        da, db = a @ n - d, b @ n - d
        if da <= 0:
            out.append(a)
        if (da < 0) != (db < 0) and da != db:
            out.append(a + (b - a) * (da / (da - db)))
    return out


def area(poly):
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * abs(float(x @ np.roll(y, -1) - y @ np.roll(x, -1)))


def plates(rng):
    """Shattered-glass shards: the disc cut again and again by straight cracks, each across a
    piece's long axis give or take, until the pieces are small enough for where they sit (small
    at the rim, large in the middle). Straight cuts give the long angular shards Voronoi can't."""
    disc = np.array([[math.cos(t), math.sin(t)] for t in np.linspace(0, 2 * math.pi, 72, endpoint=False)])
    todo, done = [disc], []
    while todo:
        poly = todo.pop()
        c = poly.mean(axis=0)
        r = float(np.linalg.norm(c))
        target = (0.085 - 0.066 * min(1.0, r) ** 1.6) * rng.uniform(0.55, 1.5)
        if area(poly) <= target or len(poly) < 3:
            done.append(poly)
            continue
        # Long axis from the points' spread; cut across it, off-square.
        d = poly - c
        w, v = np.linalg.eigh(d.T @ d)
        long_axis = v[:, 1]
        ang = math.atan2(long_axis[1], long_axis[0]) + math.pi / 2 + rng.normal(0, 0.5)
        n = np.array([math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2)])
        through = c + d[rng.integers(len(d))] * rng.uniform(0.0, 0.3)
        k = float(through @ n)
        a_side, b_side = clip_poly(list(poly), n, k), clip_poly(list(poly), -n, -k)
        if len(a_side) < 3 or len(b_side) < 3:
            done.append(poly)
            continue
        todo.append(np.array(a_side))
        todo.append(np.array(b_side))
    cells = []
    for poly in done:
        if area(poly) < 0.0012:
            continue
        c = poly.mean(axis=0)
        gap = 0.006 + 0.006 * rng.uniform()
        shrunk = c + (poly - c) * (1 - gap / max(0.04, np.linalg.norm(poly - c, axis=1).mean()))
        cells.append(dict(poly=shrunk, c=c))
    return cells


def new_object(name, verts, faces, pivot, mat, smooth_angle=None):
    mesh = bpy.data.meshes.new(name)
    local = [tuple(np.array(v) - pivot) for v in verts]
    mesh.from_pydata(local, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    # Where each point rests on the globe, for the frost that thickens to the rim.
    attr = mesh.attributes.new("rest", "FLOAT_VECTOR", "POINT")
    attr.data.foreach_set("vector", np.array(verts, np.float32).ravel())
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    obj.location = tuple(pivot)
    bpy.context.collection.objects.link(obj)
    return obj


def build_plate(i, cell, rng, mat):
    poly, c = cell["poly"], cell["c"]
    n = len(poly)
    rc = float(np.linalg.norm(c))
    thick = rng.uniform(0.06, 0.17) * (1.0 - 0.25 * rc)
    tilt = rng.normal(0, 0.30, 2) * (0.6 + 0.6 * rc)
    base = dome(c[0], c[1])
    bottom, top = [], []
    for p in poly:
        yb = dome(p[0], p[1]) - 0.01
        yt = base + thick + float(tilt @ (p - c))
        yt = max(yt, yb + 0.035)
        bottom.append(world_of(p[0], p[1], yb))
        top.append(world_of(p[0], p[1], yt))
    verts = bottom + top
    faces = [tuple(range(n - 1, -1, -1))]
    for k in range(n):
        k2 = (k + 1) % n
        faces.append((k, k2, n + k2, n + k))
    if rng.uniform() < 0.62 and n >= 4:
        # A cut-crystal top: facets meeting at a ridge point off the middle.
        w = rng.dirichlet(np.ones(n) * 1.3)
        apex2 = (poly * w[:, None]).sum(axis=0)
        apex2 = c + (apex2 - c) * 0.9
        ya = base + thick + float(tilt @ (apex2 - c)) + rng.uniform(0.03, 0.09)
        verts.append(world_of(apex2[0], apex2[1], ya))
        for k in range(n):
            faces.append((n + k, n + (k + 1) % n, 2 * n))
    else:
        faces.append(tuple(range(n, 2 * n)))
    # Grows from its rim-side corner, and that is what it hinges on when it breaks off.
    far = poly[np.argmax(np.linalg.norm(poly, axis=1))]
    pivot = np.array(world_of(far[0], far[1], dome(far[0], far[1])))
    obj = new_object(f"plate{i:03d}", verts, faces, pivot, mat)
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = 0.008
    bev.segments = 2
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(25)
    return dict(obj=obj, kind="plate", r=rc, c=c, pivot=pivot, seed=rng.uniform(0, 1000))


def build_blade(i, ang, rng, mat, scale=1.0):
    length = rng.uniform(0.16, 0.5) * scale
    width = rng.uniform(0.05, 0.11) * (0.6 + 0.8 * length)
    rise = rng.uniform(0.05, 0.12)
    lean = rng.normal(0, 0.28)
    out = np.array([math.cos(ang), math.sin(ang)])
    side = np.array([-out[1], out[0]])
    inward = -(out * math.cos(lean) + side * math.sin(lean))
    b0 = out * 1.03
    tip = b0 + inward * length
    shoulder = b0 + inward * length * rng.uniform(0.18, 0.34)

    def on(p, lift=0.0):
        return world_of(p[0], p[1], dome(p[0], p[1]) + lift)
    verts = [on(b0 - side * width * 0.5), on(b0 + side * width * 0.5), on(b0, rise * 0.8),
             on(shoulder - side * width * 0.62), on(shoulder + side * width * 0.62), on(shoulder, rise), on(tip, 0.012)]
    faces = [(0, 2, 5, 3), (2, 1, 4, 5), (3, 5, 6), (5, 4, 6), (0, 3, 6, 4, 1), (0, 1, 2)]
    pivot = np.array(on(b0))
    obj = new_object(f"blade{i:03d}", verts, faces, pivot, mat)
    return dict(obj=obj, kind="blade", r=1.0, c=b0, pivot=pivot, seed=rng.uniform(0, 1000), dir=inward)


def build_membrane(mat):
    """A thin skin of rime on the glass itself, under the plates: it shows in the cracks."""
    rings, segs = 40, 96
    verts, faces = [(0.0, dome(0, 0) - 0.02, 0.0)], []
    for i in range(1, rings + 1):
        r = i / rings * 1.0
        for k in range(segs):
            a = k / segs * 2 * math.pi
            x, z = r * math.cos(a), r * math.sin(a)
            verts.append(world_of(x, z, dome(x, z) - 0.02))
    for k in range(segs):
        faces.append((0, 1 + k, 1 + (k + 1) % segs))
    for i in range(1, rings):
        a0, b0 = 1 + (i - 1) * segs, 1 + i * segs
        for k in range(segs):
            k2 = (k + 1) % segs
            faces.append((a0 + k, b0 + k, b0 + k2, a0 + k2))
    obj = new_object("membrane", verts, faces, np.zeros(3), mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# ---------------------------------------------------------------------------------------------
# Materials.

def ice_material(name, frost_bias, clear_ior=1.31):
    """Glass with rime on it: clear where the frost factor is low, white and rough where high.
    The factor is noise plus how near the rim the point rests, so the edge is frosted solid and
    the middle stays a window onto the liquid."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    N, L = t.nodes.new, t.links.new
    out = N("ShaderNodeOutputMaterial")
    rest = N("ShaderNodeAttribute")
    rest.attribute_name = "rest"
    length = N("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    sep = N("ShaderNodeSeparateXYZ")
    L(rest.outputs["Vector"], sep.inputs[0])
    flat = N("ShaderNodeCombineXYZ")
    L(sep.outputs["X"], flat.inputs["X"])
    L(sep.outputs["Z"], flat.inputs["Z"])
    L(flat.outputs[0], length.inputs[0])

    noise = N("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.5
    noise.inputs["Detail"].default_value = 6
    noise.inputs["Roughness"].default_value = 0.62
    L(rest.outputs["Vector"], noise.inputs["Vector"])
    fine = N("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 46
    fine.inputs["Detail"].default_value = 4
    L(rest.outputs["Vector"], fine.inputs["Vector"])
    crackle = N("ShaderNodeTexVoronoi")
    crackle.feature = "DISTANCE_TO_EDGE"
    crackle.inputs["Scale"].default_value = 19
    L(rest.outputs["Vector"], crackle.inputs["Vector"])

    # frost = smoothstep(rim ramp + noise)
    ramp = N("ShaderNodeMapRange")
    ramp.interpolation_type = "SMOOTHERSTEP"
    ramp.inputs["From Min"].default_value = 0.66
    ramp.inputs["From Max"].default_value = 1.02
    ramp.inputs["To Max"].default_value = 0.62
    L(length.outputs["Value"], ramp.inputs["Value"])
    mix1 = N("ShaderNodeMath")
    mix1.operation = "MULTIPLY_ADD"  # noise * 0.9 + ramp
    L(noise.outputs["Fac"], mix1.inputs[0])
    mix1.inputs[1].default_value = 0.8
    L(ramp.outputs[0], mix1.inputs[2])
    frost = N("ShaderNodeMapRange")
    frost.interpolation_type = "SMOOTHSTEP"
    frost.inputs["From Min"].default_value = 0.72 - frost_bias
    frost.inputs["From Max"].default_value = 1.25 - frost_bias
    L(mix1.outputs[0], frost.inputs["Value"])

    # Hairline frost along the crackle's edges, everywhere.
    vein = N("ShaderNodeMapRange")
    # The floor: ice is never water-clear. A little milk in it everywhere lets each facet take
    # the light at its own angle, which is what reads as crystal.
    vein.inputs["From Min"].default_value = 0.0
    vein.inputs["From Max"].default_value = 1.0
    vein.inputs["To Min"].default_value = 0.04
    vein.inputs["To Max"].default_value = 0.17
    L(noise.outputs["Fac"], vein.inputs["Value"])
    fac = N("ShaderNodeMath")
    fac.operation = "MAXIMUM"
    L(frost.outputs[0], fac.inputs[0])
    L(vein.outputs[0], fac.inputs[1])

    glass = N("ShaderNodeBsdfGlass")
    glass.distribution = "GGX"
    glass.inputs["Color"].default_value = (0.80, 0.93, 1.0, 1)
    glass.inputs["IOR"].default_value = clear_ior
    rough = N("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.01
    rough.inputs["To Max"].default_value = 0.09
    L(fine.outputs["Fac"], rough.inputs["Value"])
    L(rough.outputs[0], glass.inputs["Roughness"])

    rime = N("ShaderNodeBsdfPrincipled")
    rime.inputs["Base Color"].default_value = (0.50, 0.80, 1.0, 1)
    rime.inputs["Roughness"].default_value = 0.22
    rime.inputs["Subsurface Weight"].default_value = 0.6
    rime.inputs["Subsurface Radius"].default_value = (0.08, 0.12, 0.16)
    rime.inputs["Coat Weight"].default_value = 1.0
    rime.inputs["Coat Roughness"].default_value = 0.04

    bump = N("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.02
    bh = N("ShaderNodeMath")
    bh.operation = "ADD"
    L(fine.outputs["Fac"], bh.inputs[0])
    L(crackle.outputs["Distance"], bh.inputs[1])
    L(bh.outputs[0], bump.inputs["Height"])
    L(bump.outputs[0], rime.inputs["Normal"])
    gb = N("ShaderNodeBump")
    gb.inputs["Strength"].default_value = 0.06
    gb.inputs["Distance"].default_value = 0.02
    L(noise.outputs["Fac"], gb.inputs["Height"])
    L(gb.outputs[0], glass.inputs["Normal"])

    mix = N("ShaderNodeMixShader")
    L(fac.outputs[0], mix.inputs["Fac"])
    L(glass.outputs[0], mix.inputs[1])
    L(rime.outputs[0], mix.inputs[2])
    L(mix.outputs[0], out.inputs["Surface"])
    return m


def membrane_material():
    m = bpy.data.materials.new("membrane")
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    N, L = t.nodes.new, t.links.new
    out = N("ShaderNodeOutputMaterial")
    rest = N("ShaderNodeAttribute")
    rest.attribute_name = "rest"
    sep = N("ShaderNodeSeparateXYZ")
    L(rest.outputs["Vector"], sep.inputs[0])
    flat = N("ShaderNodeCombineXYZ")
    L(sep.outputs["X"], flat.inputs["X"])
    L(sep.outputs["Z"], flat.inputs["Z"])
    length = N("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    L(flat.outputs[0], length.inputs[0])
    noise = N("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9
    noise.inputs["Detail"].default_value = 7
    noise.inputs["Roughness"].default_value = 0.7
    L(rest.outputs["Vector"], noise.inputs["Vector"])
    # Coverage: light in the middle, solid at the rim, and nothing inside the growth front.
    ramp = N("ShaderNodeMapRange")
    ramp.interpolation_type = "SMOOTHERSTEP"
    ramp.inputs["From Min"].default_value = 0.2
    ramp.inputs["From Max"].default_value = 1.0
    ramp.inputs["To Min"].default_value = 0.03
    ramp.inputs["To Max"].default_value = 0.6
    L(length.outputs["Value"], ramp.inputs["Value"])
    cover = N("ShaderNodeMath")
    cover.operation = "MULTIPLY_ADD"
    L(noise.outputs["Fac"], cover.inputs[0])
    cover.inputs[1].default_value = 0.3
    L(ramp.outputs[0], cover.inputs[2])
    front = N("ShaderNodeMapRange")  # 1 outside the front radius, 0 inside; "front" is animated
    front.name = "front"
    front.interpolation_type = "SMOOTHSTEP"
    front.inputs["From Min"].default_value = -0.2
    front.inputs["From Max"].default_value = -0.02
    L(length.outputs["Value"], front.inputs["Value"])
    amount = N("ShaderNodeMath")
    amount.name = "amount"
    amount.operation = "MULTIPLY"
    amount.inputs[1].default_value = 1.0
    L(front.outputs[0], amount.inputs[0])
    fac = N("ShaderNodeMath")
    fac.operation = "MULTIPLY"
    fac.use_clamp = True
    L(cover.outputs[0], fac.inputs[0])
    L(amount.outputs[0], fac.inputs[1])
    clear = N("ShaderNodeBsdfTransparent")
    rime = N("ShaderNodeBsdfPrincipled")
    rime.inputs["Base Color"].default_value = (0.80, 0.91, 1.0, 1)
    rime.inputs["Roughness"].default_value = 0.6
    rime.inputs["Subsurface Weight"].default_value = 0.5
    rime.inputs["Subsurface Radius"].default_value = (0.1, 0.14, 0.2)
    bump = N("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    bump.inputs["Distance"].default_value = 0.02
    L(noise.outputs["Fac"], bump.inputs["Height"])
    L(bump.outputs[0], rime.inputs["Normal"])
    mix = N("ShaderNodeMixShader")
    L(fac.outputs[0], mix.inputs["Fac"])
    L(clear.outputs[0], mix.inputs[1])
    L(rime.outputs[0], mix.inputs[2])
    L(mix.outputs[0], out.inputs["Surface"])
    return m


def set_front(mat, radius, amount=1.0):
    """The rime skin exists outside `radius` (of the globe); amount fades all of it."""
    node = mat.node_tree.nodes["front"]
    node.inputs["From Min"].default_value = radius - 0.16
    node.inputs["From Max"].default_value = radius
    mat.node_tree.nodes["amount"].inputs[1].default_value = amount


# ---------------------------------------------------------------------------------------------

def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def out_back(x):
    """Eases out with a small overshoot: a crystal snaps to size."""
    x = min(1.0, max(0.0, x))
    c1, c3 = 1.2, 2.2
    return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2


def build_scene(rng):
    ice = ice_material("ice", 0.0)
    blade_ice = ice_material("blade_ice", 0.16)
    skin = membrane_material()
    parts = [build_plate(i, cell, rng, ice) for i, cell in enumerate(plates(rng))]
    n_blades = 54
    for i in range(n_blades):
        ang = (i + rng.uniform(-0.35, 0.35)) / n_blades * 2 * math.pi
        parts.append(build_blade(i, ang, rng, blade_ice, 1.0 if i % 3 else 0.55))
    membrane = build_membrane(skin)
    return parts, membrane, skin


def studio():
    # The console's light comes from the top left. A long strip gives the facets a line to catch.
    light("key", world_of(-3.2, 3.6, 4.5), 620, 1.4, (1.0, 0.98, 0.95))
    light("strip", world_of(-0.5, 4.5, 2.0), 260, 0.5, (0.85, 0.93, 1.0)).data.shape = "RECTANGLE"
    bpy.data.objects["strip"].data.size_y = 5.0
    light("fill", world_of(3.5, -2.5, 3.0), 160, 4.0, (0.5, 0.72, 1.0))
    light("kick", world_of(2.5, 3.0, 1.2), 120, 1.0, (0.7, 0.85, 1.0))
    # Small and hard, for the pin-sharp glints off single facets.
    light("spark", world_of(-1.6, 2.2, 6.0), 520, 0.12, (1.0, 1.0, 1.0))
    light("spark2", world_of(1.2, 0.6, 6.5), 260, 0.1, (0.8, 0.92, 1.0))


def pose_grow(parts, membrane_mat, g):
    """g 0..1: blades first, then plates from the rim inward, the rime skin closing behind."""
    for p in parts:
        obj = p["obj"]
        jitter = (p["seed"] % 1.0)
        if p["kind"] == "blade":
            s = out_back((g - 0.02 - 0.2 * jitter) / 0.26)
            obj.scale = (max(s, 1e-4),) * 3
        else:
            start = 0.16 + 0.56 * (1 - p["r"]) ** 0.85 + 0.07 * jitter
            s = out_back((g - start) / 0.17)
            obj.scale = (max(s, 1e-4), max(s, 1e-4), max(s, 1e-4))
        obj.hide_render = obj.scale[0] < 1e-3
    set_front(membrane_mat, 1.05 - 1.25 * smooth((g - 0.08) / 0.84))


def quat_axis(axis, angle):
    axis = np.array(axis, float)
    axis /= np.linalg.norm(axis)
    s = math.sin(angle / 2)
    return (math.cos(angle / 2), axis[0] * s, axis[1] * s, axis[2] * s)


def pose_shatter(parts, membrane_mat, t, rng_state):
    """t in seconds (0..0.9). A beat of cracking in place, then everything leaves: out from the
    centre, tumbling, with gravity. Ortho, so pieces thrown at the viewer grow instead."""
    for p, k in zip(parts, rng_state):
        obj = p["obj"]
        obj.hide_render = False
        obj.rotation_mode = "QUATERNION"
        c = p["c"]
        r = float(np.linalg.norm(c))
        radial = c / r if r > 1e-3 else np.array([math.cos(k["a"]), math.sin(k["a"])])
        tt = max(0.0, t - 0.05 - 0.05 * (1 - p["r"]))  # the rim lets go last by a hair
        speed = k["speed"] * (0.8 + 0.9 * (1 - p["r"]))
        ease = 1 - math.exp(-tt * 5.0)
        dist = speed * ease * 0.42 + speed * tt * 0.55
        x = radial[0] * dist + k["side"] * tt
        z = radial[1] * dist + k["up"] * tt - 2.3 * tt * tt
        toward = k["toward"] * tt
        pre = min(1.0, t / 0.05)  # the crack: a small shove before it flies
        shove = 0.018 * pre
        obj.location = tuple(p["pivot"] + np.array(world_of(x + radial[0] * shove, z + radial[1] * shove, toward * 0.6)))
        obj.rotation_quaternion = quat_axis(k["axis"], k["spin"] * tt + 0.05 * pre * k["twist"])
        s = (1 + 0.5 * toward) * (1 - 0.45 * smooth((tt - 0.35) / 0.5))
        obj.scale = (s, s, s)
    set_front(membrane_mat, -0.3, max(0.0, 1 - t / 0.07))


def main():
    a = args()
    os.makedirs(a.out, exist_ok=True)
    only = {int(x) for x in a.only.split(",") if x != ""}
    rng = np.random.default_rng(3)
    half = HALF_SHATTER if a.mode == "shatter" else 1.0
    scene = setup(a.size, a.samples, half)
    parts, membrane, skin = build_scene(rng)

    def render(name):
        scene.render.filepath = os.path.join(a.out, name)
        bpy.ops.render.render(write_still=True)

    if a.mode == "hold":
        studio()
        set_front(skin, -0.3)
        render("hold.png")
    elif a.mode == "glint":
        set_front(skin, -0.3)
        scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
        spots = [(-2.6, 2.4, 3.2), (0.4, 3.4, 3.0), (2.8, 1.0, 3.2)]
        lamp = light("glint", world_of(*spots[0]), 420, 0.22)
        for i, spot in enumerate(spots):
            if only and i not in only:
                continue
            lamp.location = world_of(*spot)
            render(f"glint{i}.png")
    elif a.mode == "grow":
        studio()
        for i in range(GROW_FRAMES):
            if only and i not in only:
                continue
            pose_grow(parts, skin, i / (GROW_FRAMES - 1))
            render(f"f{i:03d}.png")
    elif a.mode == "shatter":
        studio()
        krng = np.random.default_rng(21)
        state = [dict(a=krng.uniform(0, 6.283), speed=krng.uniform(1.1, 2.6), side=krng.normal(0, 0.25),
                      up=krng.uniform(-0.1, 0.9), toward=krng.uniform(-0.2, 1.0), axis=krng.normal(0, 1, 3),
                      spin=krng.uniform(3, 11) * krng.choice([-1, 1]), twist=krng.normal(0, 1)) for _ in parts]
        seconds = 0.9
        for i in range(SHATTER_FRAMES):
            if only and i not in only:
                continue
            for sub in range(SHATTER_SUBS):
                t = (i + sub / SHATTER_SUBS * 0.7) / (SHATTER_FRAMES - 1) * seconds
                pose_shatter(parts, skin, t, state)
                render(f"f{i:03d}_{sub}.png")
    else:
        raise SystemExit("unknown mode " + a.mode)


main()
