"""Pre-rendered globe effects (prototype): a crystal shell, its shatter and hit, and a surge.

Run headless:
  blender -b --factory-startup -P tools/blender/globe_fx.py -- --mode shell --out DIR \
      [--frames 32] [--size 512] [--samples 64] [--only 0,8]

Modes:
  shell    seamless loop: a faceted glass dome, facets flashing as lights circle it
  shatter  one-shot: cracks run from the blow along the seams, the dome flies apart in 3D
  hit      one-shot: light runs along the seams from the blow and dies, nothing moves
  swirl    seamless loop: a five-fold vortex of light pouring into the globe

All of it renders white on black for ADD, so the game tints it. The dome is real geometry: the
convex solid whose faces are tangent to the sphere at scattered points, so neighbouring facets
share edges exactly. Each face is one shard. World units: the globe's radius is 1.
"""
import argparse
import math
import os
import random
import sys

import bpy
import numpy as np

BLOW_SHATTER = (0.0, 0.95, 0.31)  # front of the dome, a little high: reads as centred
BLOW_HIT = (0.42, 0.78, 0.46)  # upper right of the front; the game mirrors it with texcoords
SHATTER_SECONDS = 0.9
HIT_SECONDS = 0.45
INNER = 0.93  # inner face of the shell, of the outer
SEAM_R = 0.0038  # half width of the seam bars


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True, choices=["shell", "shatter", "hit", "swirl"])
    p.add_argument("--out", required=True)
    p.add_argument("--frames", type=int, default=0)
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--only", default="")
    p.add_argument("--seconds", type=float, default=0.0)
    return p.parse_args(argv)


def gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    scene.cycles.device = "GPU"


def setup_scene(size, samples):
    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    scene.render.engine = "CYCLES"
    gpu(scene)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 16
    scene.cycles.glossy_bounces = 10
    scene.cycles.transmission_bounces = 16
    scene.cycles.transparent_max_bounces = 16
    scene.cycles.volume_bounces = 0
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "16"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.film_transparent = False
    return scene


def camera(scene, half):
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = half * 2
    obj = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(obj)
    obj.location = (0, 8, 0)
    obj.rotation_euler = (math.radians(90), 0, math.radians(180))
    scene.camera = obj


def polyhedron(n, seed):
    """Convex solid with faces tangent to the unit sphere at n jittered points."""
    rng = random.Random(seed)
    golden = math.pi * (3 - math.sqrt(5))
    seeds = []
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(max(0, 1 - y * y))
        a = golden * i
        v = np.array([math.cos(a) * r, y, math.sin(a) * r])
        v = v + np.array([rng.uniform(-1, 1) for _ in range(3)]) * (1.5 / math.sqrt(n)) * 1.05
        seeds.append(v / np.linalg.norm(v))
    seeds = np.array(seeds)
    polys = []
    for i, s in enumerate(seeds):
        up = np.array([0.0, 0.0, 1.0]) if abs(s[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        u = np.cross(up, s)
        u /= np.linalg.norm(u)
        v = np.cross(s, u)
        poly = [s + u * a + v * b for a, b in ((-4, -4), (4, -4), (4, 4), (-4, 4))]
        for j, t in enumerate(seeds):
            if j == i:
                continue
            kept = []
            for k, a in enumerate(poly):
                b = poly[(k + 1) % len(poly)]
                da, db = a.dot(t) - 1, b.dot(t) - 1
                if da <= 0:
                    kept.append(a)
                if (da < 0) != (db < 0):
                    kept.append(a + (b - a) * (da / (da - db)))
            poly = kept
        polys.append(poly)
    top = max(np.linalg.norm(p) for poly in polys for p in poly)
    return [[p / top for p in poly] for poly in polys], seeds


class Dome:
    """One mesh holding every shard: glass faces and thin emissive seam bars."""

    def __init__(self, n=96, seed=41):
        polys, self.seeds = polyhedron(n, seed)
        verts, faces, mats = [], [], []
        shard_of, kind = [], []
        self.centroid = []
        for idx, poly in enumerate(polys):
            c = sum(poly) / len(poly)
            self.centroid.append(c)
            base = len(verts)
            m = len(poly)
            for p in poly:
                verts.append(p)
                shard_of.append(idx)
                kind.append(0)
            for p in poly:
                verts.append(p * INNER)
                shard_of.append(idx)
                kind.append(0)
            faces.append(tuple(base + k for k in range(m)))
            mats.append(0)
            faces.append(tuple(base + m + k for k in reversed(range(m))))
            mats.append(0)
            for k in range(m):
                k2 = (k + 1) % m
                faces.append((base + k2, base + k, base + m + k, base + m + k2))
                mats.append(0)
            # Seam bars: a thin box along each edge of the outer face, set just outside it.
            for k in range(m):
                a, b = poly[k], poly[(k + 1) % m]
                d = (b - a) / max(np.linalg.norm(b - a), 1e-6)
                n1 = (a + b) / np.linalg.norm(a + b)
                n2 = np.cross(d, n1)
                b0 = len(verts)
                for p in (a, b):
                    for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
                        verts.append(p * 1.004 + (n1 * sx + n2 * sy) * SEAM_R)
                        shard_of.append(idx)
                        kind.append(1)
                for q in range(4):
                    q2 = (q + 1) % 4
                    faces.append((b0 + q, b0 + q2, b0 + 4 + q2, b0 + 4 + q))
                    mats.append(1)
        self.rest = np.array(verts)
        self.shard_of = np.array(shard_of)
        self.kind = np.array(kind)
        self.centroid = np.array(self.centroid)
        self.mesh = bpy.data.meshes.new("dome")
        self.mesh.from_pydata([tuple(v) for v in verts], [], faces)
        self.mesh.validate(clean_customdata=False)
        for p, m in zip(self.mesh.polygons, mats):
            p.material_index = m
            p.use_smooth = False
        self.fx = self.mesh.attributes.new("fx", "FLOAT", "POINT")
        self.obj = bpy.data.objects.new("dome", self.mesh)
        bpy.context.collection.objects.link(self.obj)

    def set_fx(self, values):
        self.fx.data.foreach_set("value", np.asarray(values, dtype=np.float32))
        self.mesh.update()

    def set_co(self, co):
        self.mesh.vertices.foreach_set("co", np.asarray(co, dtype=np.float32).ravel())
        self.mesh.update()


def materials(dome, glass=True):
    def attr_node(tree):
        n = tree.nodes.new("ShaderNodeAttribute")
        n.attribute_name = "fx"
        return n

    face = bpy.data.materials.new("glass")
    face.use_nodes = True
    t = face.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputMaterial")
    add = t.nodes.new("ShaderNodeAddShader")
    if glass:
        g = t.nodes.new("ShaderNodeBsdfGlass")
        g.inputs["IOR"].default_value = 1.55
        g.inputs["Roughness"].default_value = 0.02
        t.links.new(g.outputs[0], add.inputs[0])
    else:
        g = t.nodes.new("ShaderNodeBsdfTransparent")
        t.links.new(g.outputs[0], add.inputs[0])
    e = t.nodes.new("ShaderNodeEmission")
    t.links.new(attr_node(t).outputs["Fac"], e.inputs["Strength"])
    t.links.new(e.outputs[0], add.inputs[1])
    t.links.new(add.outputs[0], out.inputs["Surface"])

    seam = bpy.data.materials.new("seam")
    seam.use_nodes = True
    t = seam.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputMaterial")
    add = t.nodes.new("ShaderNodeAddShader")
    tr = t.nodes.new("ShaderNodeBsdfTransparent")
    e = t.nodes.new("ShaderNodeEmission")
    mul = t.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 4.0
    t.links.new(attr_node(t).outputs["Fac"], mul.inputs[0])
    t.links.new(mul.outputs[0], e.inputs["Strength"])
    t.links.new(tr.outputs[0], add.inputs[0])
    t.links.new(e.outputs[0], add.inputs[1])
    t.links.new(add.outputs[0], out.inputs["Surface"])
    dome.mesh.materials.append(face)
    dome.mesh.materials.append(seam)


class Env:
    """Lights only rays that leave the glass see. The view axis behind the dome stays black, so
    the middle stays clear; n softboxes circle the view axis (seamless over 2 pi / n), and a
    fixed key sits top-left like D3's light."""

    def __init__(self, scene, gain=1.0, fold=5):
        self.fold = fold
        world = bpy.data.worlds.new("env")
        scene.world = world
        world.use_nodes = True
        t = world.node_tree
        t.nodes.clear()
        out = t.nodes.new("ShaderNodeOutputWorld")
        bg = t.nodes.new("ShaderNodeBackground")
        geo = t.nodes.new("ShaderNodeNewGeometry")
        sep = t.nodes.new("ShaderNodeSeparateXYZ")
        t.links.new(geo.outputs["Incoming"], sep.inputs[0])
        # Incoming points from the surface back along the ray: flip it for the ray's direction.
        def m(op, a, b=None, clamp=False):
            n = t.nodes.new("ShaderNodeMath")
            n.operation = op
            n.use_clamp = clamp
            for i, v in enumerate((a, b)):
                if v is None:
                    continue
                if isinstance(v, (int, float)):
                    n.inputs[i].default_value = v
                else:
                    t.links.new(v, n.inputs[i])
            return n.outputs[0]

        x = m("MULTIPLY", sep.outputs[0], -1)
        y = m("MULTIPLY", sep.outputs[1], -1)
        z = m("MULTIPLY", sep.outputs[2], -1)
        theta = m("ARCTAN2", z, x)
        rot = t.nodes.new("ShaderNodeValue")
        self.rot = rot.outputs[0]
        lobes = m("COSINE", m("MULTIPLY", m("ADD", theta, self.rot), fold))
        boxes = m("POWER", m("MULTIPLY", m("ADD", lobes, 1), 0.5, clamp=True), 14)
        # Bands of elevation from the view axis: front (reflections) and rear (rim refraction).
        def band(lo, hi, soft):
            up = m("SUBTRACT", y, lo)
            dn = m("SUBTRACT", hi, y)
            return m("MULTIPLY", m("DIVIDE", up, soft, clamp=True), m("DIVIDE", dn, soft, clamp=True), clamp=True)

        front = m("MULTIPLY", boxes, band(0.1, 0.72, 0.12))
        rear = m("MULTIPLY", boxes, band(-0.72, 0.1, 0.1))
        key = t.nodes.new("ShaderNodeVectorMath")
        key.operation = "DOT_PRODUCT"
        comb = t.nodes.new("ShaderNodeCombineXYZ")
        t.links.new(x, comb.inputs[0])
        t.links.new(y, comb.inputs[1])
        t.links.new(z, comb.inputs[2])
        t.links.new(comb.outputs[0], key.inputs[0])
        d = np.array([-0.55, 0.55, 0.63])
        d = d / np.linalg.norm(d)
        key.inputs[1].default_value = tuple(d)
        keyl = m("POWER", m("MAXIMUM", key.outputs["Value"], 0), 40)
        fill = m("MULTIPLY", band(0.0, 1.01, 0.5), 0.05)
        total = m("ADD", m("ADD", m("MULTIPLY", front, 3.2 * gain), m("MULTIPLY", rear, 1.3 * gain)), m("ADD", m("MULTIPLY", keyl, 7 * gain), fill))
        # Rays straight from the camera see black, whatever the lights do.
        path = t.nodes.new("ShaderNodeLightPath")
        cam = m("SUBTRACT", 1, path.outputs["Is Camera Ray"])
        t.links.new(m("MULTIPLY", total, cam), bg.inputs["Strength"])
        t.links.new(bg.outputs[0], out.inputs["Surface"])

    def turn(self, frac):
        self.rot.node.outputs[0].default_value = frac * 2 * math.pi / self.fold


def render_loop(scene, frames, out, only, draw, subs=1):
    os.makedirs(out, exist_ok=True)
    picked = [int(x) for x in only.split(",")] if only else range(frames)
    if subs == 1:
        for i in picked:
            draw(i, 0.0)
            scene.render.filepath = os.path.join(out, f"f{i:03d}.png")
            bpy.ops.render.render(write_still=True)
        return
    for i in picked:
        for k in range(subs):
            draw(i, k / subs)
            scene.render.filepath = os.path.join(out, f"f{i:03d}_{k}.png")
            bpy.ops.render.render(write_still=True)


def blow_angles(dome, blow):
    b = np.array(blow)
    b = b / np.linalg.norm(b)
    c = dome.centroid / np.linalg.norm(dome.centroid, axis=1, keepdims=True)
    return np.arccos(np.clip(c.dot(b), -1, 1))


def rotate(points, axes, angles):
    """Rodrigues, per point, axes and angles already per point."""
    c = np.cos(angles)[:, None]
    s = np.sin(angles)[:, None]
    d = (axes * points).sum(1, keepdims=True)
    return points * c + np.cross(axes, points) * s + axes * d * (1 - c)


def do_shell(a):
    frames = a.frames or 32
    scene = setup_scene(a.size, a.samples)
    camera(scene, 1.06)
    dome = Dome()
    materials(dome, glass=True)
    env = Env(scene)
    # Idle: the seams only a hint; the facets carry it.
    dome.set_fx(np.where(dome.kind == 1, 0.018, 0.0))

    def draw(i, _sub):
        env.turn(i / frames)

    render_loop(scene, frames, a.out, a.only, draw)


def do_shatter(a):
    frames = a.frames or 25
    secs = a.seconds or SHATTER_SECONDS
    scene = setup_scene(a.size, a.samples)
    camera(scene, 2.1)
    dome = Dome()
    materials(dome, glass=True)
    env = Env(scene)
    env.turn(0.3)
    n = len(dome.centroid)
    rng = np.random.default_rng(77)
    d = blow_angles(dome, BLOW_SHATTER)
    # Broken from the blow outward; the crack front outruns the pieces.
    t0 = 0.05 + 0.14 * d / math.pi + rng.uniform(0, 0.015, n)
    out_dir = dome.centroid / np.linalg.norm(dome.centroid, axis=1, keepdims=True)
    vel = out_dir * rng.uniform(1.9, 4.0, (n, 1)) + rng.normal(0, 0.6, (n, 3))
    vel[:, 2] += 0.6  # thrown upward, then falls
    axes = rng.normal(0, 1, (n, 3))
    axes /= np.linalg.norm(axes, axis=1, keepdims=True)
    omega = rng.uniform(9, 22, n) * rng.choice([-1, 1], n)
    shard = dome.shard_of
    local = dome.rest - dome.centroid[shard]

    def draw(i, sub):
        t = (i + sub) / (frames - 1) * secs
        tau = np.maximum(t - t0, 0)
        drag = (1 - np.exp(-2.0 * tau)) / 2.0
        disp = vel * drag[:, None]
        disp[:, 2] -= 2.4 * tau * tau  # falls
        ang = omega * (1 - np.exp(-1.6 * tau)) / 1.6
        scale = 1 - 0.3 * np.clip(tau / 0.75, 0, 1)
        pts = rotate(local, axes[shard], ang[shard]) * scale[shard, None]
        dome.set_co(dome.centroid[shard] + disp[shard] + pts)
        # Seams: lit by the crack front as it passes, then cooling. Faces: a flash at the blow.
        front = 0.02 + 0.13 * d / math.pi
        since = np.maximum(t - front, 0)
        lit = (t >= front) * (0.15 + 0.85 * np.exp(-since / 0.14))
        seam = 0.018 + lit * 1.0
        face = 3.5 * np.exp(-d * 2.2) * math.exp(-t / 0.05)
        dome.set_fx(np.where(dome.kind == 1, seam[shard], face[shard]))

    render_loop(scene, frames, a.out, a.only, draw, subs=3)


def do_hit(a):
    frames = a.frames or 16
    secs = a.seconds or HIT_SECONDS
    scene = setup_scene(a.size, a.samples)
    camera(scene, 1.06)
    dome = Dome()
    materials(dome, glass=False)
    scene.world = bpy.data.worlds.new("black")
    scene.world.use_nodes = False
    scene.world.color = (0, 0, 0)
    d = blow_angles(dome, BLOW_HIT)
    shard = dome.shard_of
    # The far side of the dome is seen through it: dim it.
    facing = 0.25 + 0.75 * np.clip(dome.centroid[:, 1] + 0.1, 0, 1)

    def draw(i, _sub):
        t = i / (frames - 1) * secs
        front = 0.015 + 0.34 * d / math.pi
        since = np.maximum(t - front, 0)
        lit = (t >= front) * np.exp(-since / 0.11) * np.exp(-d * 1.5) * facing
        face = 1.6 * np.exp(-d * 5.0) * math.exp(-t / 0.05) * facing
        dome.set_fx(np.where(dome.kind == 1, lit[shard] * 0.55, face[shard]))

    render_loop(scene, frames, a.out, a.only, draw)


def do_swirl(a):
    frames = a.frames or 32
    scene = setup_scene(a.size, a.samples)
    camera(scene, 2.0)
    scene.world = bpy.data.worlds.new("black")
    scene.world.use_nodes = False
    scene.world.color = (0, 0, 0)
    scene.cycles.volume_step_rate = 1.0
    scene.cycles.volume_max_steps = 256
    bpy.ops.mesh.primitive_cube_add(size=1)
    box = bpy.context.active_object
    box.scale = (4.1, 3.2, 4.1)
    mat = bpy.data.materials.new("vortex")
    mat.use_nodes = True
    box.data.materials.append(mat)
    t = mat.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputMaterial")
    tc = t.nodes.new("ShaderNodeTexCoord")
    sep = t.nodes.new("ShaderNodeSeparateXYZ")
    t.links.new(tc.outputs["Object"], sep.inputs[0])

    def m(op, a_, b_=None, clamp=False):
        n = t.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a_, b_)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                t.links.new(v, n.inputs[i])
        return n.outputs[0]

    # Object space is -0.5..0.5 of the box; back to world units.
    x = m("MULTIPLY", sep.outputs[0], 4.1)
    y = m("MULTIPLY", sep.outputs[1], 3.2)
    z = m("MULTIPLY", sep.outputs[2], 4.1)
    rho = m("SQRT", m("ADD", m("ADD", m("MULTIPLY", x, x), m("MULTIPLY", z, z)), 0.0004))
    theta = m("ARCTAN2", z, x)
    lnr = m("LOGARITHM", rho, math.e)
    # Funnel: the far end of the vortex goes away from the viewer toward the centre.
    yc = m("MULTIPLY", -1.1, m("SUBTRACT", 1, m("MINIMUM", m("DIVIDE", rho, 2.0), 1)))
    # Depth shears the arms, so sheets at different depths slide past each other.
    arm = m("ADD", m("ADD", m("MULTIPLY", theta, 5), m("MULTIPLY", lnr, 7.5)), m("MULTIPLY", m("SUBTRACT", y, yc), 0.4))
    time_v = t.nodes.new("ShaderNodeValue")
    inflow = m("ADD", m("MULTIPLY", lnr, 1.0), time_v.outputs[0])

    def tor(ca, r_arm, r_flow):
        c = t.nodes.new("ShaderNodeCombineXYZ")
        t.links.new(m("MULTIPLY", m("COSINE", arm), r_arm), c.inputs[0])
        t.links.new(m("MULTIPLY", m("SINE", arm), r_arm), c.inputs[1])
        t.links.new(m("MULTIPLY", m("COSINE", inflow), r_flow), c.inputs[2])
        n = t.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = "4D"
        n.inputs["Scale"].default_value = ca[0]
        n.inputs["Detail"].default_value = ca[1]
        n.inputs["Roughness"].default_value = 0.58
        n.inputs["Distortion"].default_value = ca[2]
        t.links.new(c.outputs[0], n.inputs["Vector"])
        t.links.new(m("MULTIPLY", m("SINE", inflow), r_flow), n.inputs["W"])
        return n.outputs[0]

    streak = tor((2.0, 9.0, 0.45), 2.2, 0.32)
    sheets = tor((0.9, 3.0, 0.1), 1.1, 0.35)
    env_r = m("MULTIPLY", m("SUBTRACT", rho, 0.04), 2.5, clamp=True)
    env_o = m("SUBTRACT", 1, m("DIVIDE", m("SUBTRACT", rho, 1.25), 0.72, clamp=True))
    env_o = m("POWER", m("MAXIMUM", env_o, 0), 1.6)
    half = m("ADD", 0.28, m("MULTIPLY", rho, 0.1))
    env_y = m("SUBTRACT", 1, m("DIVIDE", m("ABSOLUTE", m("SUBTRACT", y, yc)), half, clamp=True))
    env = m("MULTIPLY", m("MULTIPLY", env_r, env_o), env_y)
    thresh = t.nodes.new("ShaderNodeMapRange")
    thresh.inputs["From Min"].default_value = 0.585
    thresh.inputs["From Max"].default_value = 0.70
    t.links.new(streak, thresh.inputs["Value"])
    wide = t.nodes.new("ShaderNodeMapRange")
    wide.inputs["From Min"].default_value = 0.44
    wide.inputs["From Max"].default_value = 0.68
    t.links.new(sheets, wide.inputs["Value"])
    glow = m("ADD", m("MULTIPLY", m("POWER", thresh.outputs[0], 2.2), 1.0), m("MULTIPLY", wide.outputs[0], 0.07))
    # Brighter toward the rim of the globe, where the light is pouring in.
    pour = m("ADD", 0.45, m("MULTIPLY", 1.6, m("POWER", m("MAXIMUM", m("SUBTRACT", 1, m("ABSOLUTE", m("SUBTRACT", rho, 1.0))), 0), 2.0)))
    em = t.nodes.new("ShaderNodeEmission")
    t.links.new(m("MULTIPLY", m("MULTIPLY", m("MULTIPLY", glow, env), pour), 5.0), em.inputs["Strength"])
    ab = t.nodes.new("ShaderNodeVolumeAbsorption")
    t.links.new(m("MULTIPLY", m("MULTIPLY", thresh.outputs[0], env), 6.0), ab.inputs["Density"])
    add = t.nodes.new("ShaderNodeAddShader")
    t.links.new(em.outputs[0], add.inputs[0])
    t.links.new(ab.outputs[0], add.inputs[1])
    t.links.new(add.outputs[0], out.inputs["Volume"])

    def draw(i, _sub):
        time_v.outputs[0].default_value = i / frames * 2 * math.pi

    render_loop(scene, frames, a.out, a.only, draw)


def main():
    a = args()
    {"shell": do_shell, "shatter": do_shatter, "hit": do_hit, "swirl": do_swirl}[a.mode](a)


main()
