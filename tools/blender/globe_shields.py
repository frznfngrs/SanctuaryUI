"""Prototype shield looks and breaks that want real 3D: rendered white on black for ADD.

Run headless:
  blender -b --factory-startup -P tools/blender/globe_shields.py -- --mode aegis --out DIR \
      [--frames N] [--size 512] [--samples 24] [--only 0,8]

Modes:
  aegis        loop: 12 runed gold plates and a tick ring round the rim, rotating one 6-fold step
  bulwark      loop: overlapping iron plates round the rim, still; a soft light circles them
  bulwark_hit  one-shot: the plate under the blow rings and jolts, the shock runs round the rim
  crumble      one-shot: the plates come loose from the top down and fall, tumbling

World units: the globe's radius is 1. The camera looks along -Y from +Y, ortho; the screen's right
is -X and up is +Z. Angles below are screen angles, counter-clockwise from the right.
A fixed render seed keeps the sampling noise from flashing between frames.
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--frames", type=int, default=0)
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--samples", type=int, default=24)
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
    scene.cycles.seed = 7
    scene.cycles.use_animated_seed = False
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "16"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("black")
    world.use_nodes = False
    world.color = (0.0, 0.0, 0.0)
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


def screen(ang, r, y=0.0):
    """Screen angle (radians), radius and height toward the camera -> world."""
    return np.array([-r * math.cos(ang), y, r * math.sin(ang)])


def material(name, roughness, emit=4.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    out = t.nodes.new("ShaderNodeOutputMaterial")
    pbr = t.nodes.new("ShaderNodeBsdfPrincipled")
    pbr.inputs["Base Color"].default_value = (1, 1, 1, 1)
    pbr.inputs["Metallic"].default_value = 1.0
    pbr.inputs["Roughness"].default_value = roughness
    attr = t.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "fx"
    em = t.nodes.new("ShaderNodeEmission")
    mul = t.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = emit
    t.links.new(attr.outputs["Fac"], mul.inputs[0])
    t.links.new(mul.outputs[0], em.inputs["Strength"])
    add = t.nodes.new("ShaderNodeAddShader")
    t.links.new(pbr.outputs[0], add.inputs[0])
    t.links.new(em.outputs[0], add.inputs[1])
    t.links.new(add.outputs[0], out.inputs["Surface"])
    return m


class Mesh:
    def __init__(self, name, verts, faces, plate, mat):
        self.rest = np.array(verts, np.float64)
        self.plate = np.array(plate)
        self.mesh = bpy.data.meshes.new(name)
        self.mesh.from_pydata([tuple(v) for v in verts], [], faces)
        self.mesh.validate(clean_customdata=False)
        self.mesh.polygons.foreach_set("use_smooth", [True] * len(self.mesh.polygons))
        self.fx = self.mesh.attributes.new("fx", "FLOAT", "POINT")
        self.mesh.materials.append(mat)
        self.obj = bpy.data.objects.new(name, self.mesh)
        bpy.context.collection.objects.link(self.obj)

    def set_fx(self, v):
        self.fx.data.foreach_set("value", np.asarray(v, np.float32))
        self.mesh.update()

    def set_co(self, co):
        self.mesh.vertices.foreach_set("co", np.asarray(co, np.float32).ravel())
        self.mesh.update()


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fbm(u, v, seed, scale):
    """A small sum of sines: hammered metal, no texture needed."""
    out = 0 * u
    amp = 1.0
    f = scale
    for i in range(4):
        a = seed * 1.7 + i * 2.1
        d = (math.cos(a), math.sin(a))
        out = out + amp * np.sin((u * d[0] + v * d[1]) * f + seed * 3.1 + i)
        amp *= 0.55
        f *= 1.9
    return out


def segment_field(us, vs, segs):
    """Distance from each point to the nearest of a list of segments."""
    best = np.full(us.shape, 9.0)
    for (a, b, c, d) in segs:
        ux, uy = c - a, d - b
        l2 = ux * ux + uy * uy + 1e-9
        t = np.clip(((us - a) * ux + (vs - b) * uy) / l2, 0, 1)
        dist = np.hypot(us - (a + t * ux), vs - (b + t * uy))
        best = np.minimum(best, dist)
    return best


RUNES = [
    # Angular strokes in a -1..1 box; two of them alternate round the band.
    [(0, -0.9, 0, 0.9), (0, 0.9, -0.62, 0.3), (0, 0.9, 0.62, 0.3), (-0.62, -0.25, 0.62, -0.25)],
    [(-0.55, -0.9, -0.55, 0.9), (0.55, -0.9, 0.55, 0.9), (-0.55, 0.15, 0.55, -0.45), (-0.55, 0.9, 0.55, 0.3)],
]


def plate_ring(n, r_in, r_out, slope, arc_frac, nu, nv, relief, thick, tilt_jit=0.0, seed=3):
    """n plates round the view axis. Each is a fine grid, conical, so it faces up and out toward
    the lights. relief(i, u, v) -> (height, fx) for u, v in -1..1. A skirt and a back face make it
    a solid that can tumble. Returns verts, faces, plate index, centroids, angles."""
    verts, faces, plate = [], [], []
    rng = np.random.default_rng(seed)
    step = 2 * math.pi / n
    half_arc = step * arc_frac / 2
    fx_all = []
    centroids, angles = [], []
    for i in range(n):
        ang = i * step + rng.uniform(-0.02, 0.02) * tilt_jit
        angles.append(ang)
        us, vs = np.meshgrid(np.linspace(-1, 1, nu), np.linspace(-1, 1, nv), indexing="ij")
        height, fx = relief(i, us, vs)
        base = len(verts)
        fx_grid = fx.ravel()
        # Per-plate lean: its own small tilt, so each catches the light differently.
        ta, tb = rng.uniform(-0.03, 0.03, 2) * tilt_jit
        pts = []
        for a, (u_row, v_row, h_row) in enumerate(zip(us, vs, height)):
            for u, v, h in zip(u_row, v_row, h_row):
                r = r_in + (v + 1) / 2 * (r_out - r_in)
                th = ang + u * half_arc
                y = (r_out - r) * slope + h + ta * u + tb * v
                pts.append((-r * math.cos(th), y, r * math.sin(th)))
        pts = np.array(pts)
        c = pts.mean(0)
        centroids.append(c)
        k = len(pts)
        verts.extend(pts)
        plate.extend([i] * k)
        back = pts + np.array([0, -thick, 0])
        verts.extend(back)
        plate.extend([i] * k)
        fx_all.append(fx_grid)
        fx_all.append(np.zeros(k))
        for a in range(nu - 1):
            for b in range(nv - 1):
                q = base + a * nv + b
                faces.append((q, q + nv, q + nv + 1, q + 1))
                faces.append((q + k, q + k + 1, q + k + nv + 1, q + k + nv))
        # Skirt round the outline.
        outline = [base + a * nv for a in range(nu)] + [base + (nu - 1) * nv + b for b in range(1, nv)] + \
                  [base + a * nv + nv - 1 for a in range(nu - 2, -1, -1)] + [base + b for b in range(nv - 2, 0, -1)]
        for a in range(len(outline)):
            p, q = outline[a], outline[(a + 1) % len(outline)]
            faces.append((p, p + k, q + k, q))
    return verts, faces, plate, np.array(centroids), np.array(angles), np.concatenate(fx_all)


def aegis_scene(a):
    frames = a.frames or 64
    scene = setup(a.size, a.samples, 1.08)
    relief_seed = np.random.default_rng(11).uniform(0, 100, 12)

    def relief(i, us, vs):
        ed = np.minimum(1 - np.abs(us), 1 - np.abs(vs))
        bevel = smooth(0.0, 0.09, ed) * 0.022 + smooth(0.06, 0.22, ed) * 0.010
        # Inset panel for the rune.
        inner = smooth(0.1, 0.16, ed) * (1 - smooth(0.82, 0.9, np.maximum(np.abs(us) * 0.55, np.abs(vs))))
        hammer = fbm(us * 2.8, vs, relief_seed[i], 3.0) * 0.0009
        # The rune, in its own square, centred on the plate.
        ru, rv = us * 3.0, vs * 1.22
        d = segment_field(ru, rv, RUNES[i % 2])
        rune = 1 - smooth(0.05, 0.13, d)
        rune = rune * (np.abs(ru) < 1.25) * (np.abs(rv) < 1.25)
        height = bevel + inner * 0.004 - rune * 0.012 + hammer
        fx = rune * 0.9 + smooth(0.0, 0.03, ed) * (1 - smooth(0.03, 0.09, ed)) * 0.05
        return height, fx

    verts, faces, plate, _, _, fx = plate_ring(12, 0.845, 1.0, 0.72, 0.9, 90, 30, relief, 0.05)
    gold = material("gold", 0.3, emit=5.5)
    ring = Mesh("band", verts, faces, plate, gold)
    ring.set_fx(fx)

    def tick_relief(i, us, vs):
        ed = np.minimum(1 - np.abs(us), 1 - np.abs(vs))
        tick = 1 - smooth(0.3, 0.42, np.abs(us))
        return smooth(0.0, 0.12, ed) * 0.012 + tick * 0.016 * (vs > 0.0), tick * 0.55 * (vs > 0.0)

    verts, faces, plate, _, _, tfx = plate_ring(24, 0.792, 0.826, 0.8, 0.96, 14, 8, tick_relief, 0.03)
    thin = Mesh("ticks", verts, faces, plate, material("thin", 0.3, emit=4.0))
    thin.set_fx(tfx)

    def light(name, power, loc, size):
        l = bpy.data.lights.new(name, "AREA")
        l.shape = "DISK"
        l.size = size
        l.energy = power
        o = bpy.data.objects.new(name, l)
        bpy.context.collection.objects.link(o)
        o.location = loc
        o.rotation_mode = "QUATERNION"
        v = -np.array(loc, np.float64)
        v /= np.linalg.norm(v)
        o.rotation_quaternion = _look(v)
        return o

    # The band's faces lean out at about 35 degrees, so its mirror direction is nearly in the
    # picture plane: the key sits up and to the left, a little toward the camera.
    d = screen(math.radians(128), 7.0, 2.5)
    light("key", 240, d, 7.0)
    light("low", 60, screen(math.radians(-55), 7.0, 2.0), 6.0)
    light("front", 35, (0, 9, 0.6), 4.0)
    step = math.radians(60)

    def draw(i):
        f = i / frames
        ring.obj.rotation_euler = (0, f * step, 0)
        thin.obj.rotation_euler = (0, -f * step, 0)

    return scene, frames, draw


def _look(v):
    """Quaternion turning an area light's -Z onto v."""
    from mathutils import Vector
    return Vector((float(v[0]), float(v[1]), float(v[2]))).to_track_quat("-Z", "Y")


def bulwark_mesh(a, half):
    scene = setup(a.size, a.samples, half)
    n = 10
    seeds = np.random.default_rng(23).uniform(0, 100, n)

    def relief(i, us, vs):
        ed = np.minimum(1 - np.abs(us), 1 - np.abs(vs))
        bevel = smooth(0.0, 0.07, ed) * 0.030
        # A pressed ridge along the plate, the shield-boss feel.
        ridge = np.exp(-((vs + 0.05) * 3.2) ** 2) * (1 - smooth(0.72, 1.0, np.abs(us))) * 0.022
        # Dished: the middle of the plate falls away from its edges.
        dish = -0.018 * smooth(0.1, 0.5, ed)
        hammer = fbm(us * 3.0, vs, seeds[i], 3.5) * 0.0007 * smooth(0.04, 0.2, ed)
        # Dents, one or two, unique to each plate.
        dent = -0.007 * np.exp(-(((us - math.sin(seeds[i]) * 0.6) * 2.4) ** 2 + ((vs - math.cos(seeds[i] * 1.3) * 0.55) * 3.0) ** 2))
        # Rivets at the corners and along the outer edge.
        rivet = 0 * us
        for u0, v0 in ((-0.82, -0.68), (0.82, -0.68), (-0.82, 0.68), (0.82, 0.68), (0.0, -0.72), (0.0, 0.76)):
            rivet = rivet + 0.026 * np.exp(-(((us - u0) * 8) ** 2 + ((vs - v0) * 7) ** 2))
        height = bevel + ridge + dish + hammer + dent + rivet
        # The edge carries a thread of light on a hit; idle it's dark.
        fx = smooth(0.0, 0.02, ed) * (1 - smooth(0.02, 0.07, ed))
        return height, fx

    verts, faces, plate, cent, angles, fx = plate_ring(n, 0.79, 1.015, 0.62, 1.04, 90, 40, relief, 0.05, tilt_jit=3.2)
    # Overlap: alternate plates sit a little proud, so each lies on the next like a scale.
    verts = np.array(verts)
    plate_a = np.array(plate)
    verts[:, 1] += (plate_a % 2) * 0.03
    iron = material("iron", 0.48, emit=6.0)
    mesh = Mesh("plates", [tuple(v) for v in verts], faces, plate, iron)
    return scene, mesh, cent, angles, fx


def add_area(name, power, size):
    l = bpy.data.lights.new(name, "AREA")
    l.shape = "DISK"
    l.size = size
    l.energy = power
    o = bpy.data.objects.new(name, l)
    bpy.context.collection.objects.link(o)
    o.rotation_mode = "QUATERNION"
    return o


def place(o, loc):
    o.location = loc
    v = -np.array(loc, np.float64)
    v /= np.linalg.norm(v)
    o.rotation_quaternion = _look(v)


def bulwark_scene(a):
    frames = a.frames or 32
    scene, mesh, _, _, _ = bulwark_mesh(a, 1.08)
    mesh.set_fx(np.zeros(len(mesh.rest)))
    key = add_area("key", 300, 7.0)
    place(key, screen(math.radians(128), 7.0, 2.2))
    fill = add_area("fill", 45, 7.0)
    place(fill, (0, 9, 0.8))
    orbit = add_area("orbit", 90, 4.0)

    def draw(i):
        f = i / frames
        # Slow orbiting softbox: the sheen crawls round the plates.
        place(orbit, screen(f * 2 * math.pi + math.radians(40), 7.0, 3.0))

    return scene, frames, draw


def bulwark_hit_scene(a):
    frames = a.frames or 16
    secs = 0.45
    scene, mesh, cent, angles, fx = bulwark_mesh(a, 1.08)
    blow = math.radians(38)  # upper right; the game mirrors it toward the blow
    key = add_area("key", 300, 7.0)
    place(key, screen(math.radians(128), 7.0, 2.2))
    fill = add_area("fill", 45, 7.0)
    place(fill, (0, 9, 0.8))
    mesh.set_fx(np.zeros(len(mesh.rest)))
    plate = mesh.plate
    # Angular distance of each plate from the blow, around the ring.
    da = np.abs((angles - blow + math.pi) % (2 * math.pi) - math.pi)

    def draw(i):
        t = i / (frames - 1) * secs
        # The shock runs round both ways, ringing each plate as it passes.
        front = da / math.pi * 0.20
        since = np.maximum(t - front, 0)
        ring_it = (t >= front) * np.exp(-since / 0.09) * (0.35 + 0.65 * np.exp(-da * 1.4))
        vel = (t >= front) * np.exp(-since / 0.07) * np.sin(since * 34) * 0.016 * np.exp(-da * 0.9)
        push = -vel[plate][:, None] * np.array([0, 1, 0])
        flash = 1.6 * np.exp(-da * 2.2) * math.exp(-t / 0.05)
        mesh.set_co(mesh.rest + push)
        mesh.set_fx(fx * ring_it[plate] * 1.2 + flash[plate] * (plate == int(np.argmin(da))) * 0.8 * (0.06 + fx * 0.6))

    return scene, frames, draw


def crumble_scene(a):
    frames = a.frames or 25
    secs = 1.2
    scene, mesh, cent, angles, fx = bulwark_mesh(a, 2.1)
    n = len(cent)
    key = add_area("key", 300, 7.0)
    place(key, screen(math.radians(128), 7.0, 2.2))
    fill = add_area("fill", 50, 7.0)
    place(fill, (0, 9, 0.8))
    rng = np.random.default_rng(5)
    # Topmost plates go first, so the ring peels down both sides.
    height = np.sin(angles)
    t0 = 0.03 + (1 - height) / 2 * 0.28 + rng.uniform(0, 0.03, n)
    outward = np.stack([cent[:, 0], np.zeros(n), cent[:, 2]], 1)
    outward /= np.maximum(np.linalg.norm(outward, axis=1, keepdims=True), 1e-6)
    vel = outward * rng.uniform(0.15, 0.6, (n, 1)) + np.array([0, 0, 0.1])
    vel[:, 1] = rng.uniform(0.3, 0.9, n)  # toward the camera, so they swing past
    axes = rng.normal(0, 1, (n, 3))
    axes /= np.linalg.norm(axes, axis=1, keepdims=True)
    spin = rng.uniform(2.0, 5.5, n) * rng.choice([-1, 1], n)
    plate = mesh.plate
    local = mesh.rest - cent[plate]
    rest_fx = fx.copy()

    def draw(i, sub):
        t = (i + sub * 0.45) / (frames - 1) * secs
        tau = np.maximum(t - t0, 0)
        g = 5.2
        disp = vel * tau[:, None]
        disp[:, 2] -= 0.5 * g * tau * tau
        # Tumble starts slow, so it reads as coming loose.
        ang = spin * tau * tau / (tau + 0.25)
        c = np.cos(ang)[:, None]
        s = np.sin(ang)[:, None]
        ax = axes[plate]
        cp = c[plate]
        sp = s[plate]
        dot = (ax * local).sum(1, keepdims=True)
        rot = local * cp + np.cross(ax, local) * sp + ax * dot * (1 - cp)
        mesh.set_co(cent[plate] + disp[plate] + rot)
        # Brief thread of light along the edges as each comes free.
        crack = np.exp(-np.maximum(t - t0, 0) / 0.07) * (t >= t0 - 0.02)
        mesh.set_fx(rest_fx * crack[plate] * 1.5)

    return scene, frames, draw


def run(a):
    os.makedirs(a.out, exist_ok=True)
    if a.mode == "aegis":
        scene, frames, draw = aegis_scene(a)
        subs = 1
    elif a.mode == "bulwark":
        scene, frames, draw = bulwark_scene(a)
        subs = 1
    elif a.mode == "bulwark_hit":
        scene, frames, draw = bulwark_hit_scene(a)
        subs = 1
    elif a.mode == "crumble":
        scene, frames, draw = crumble_scene(a)
        subs = 3
    else:
        raise SystemExit("unknown mode " + a.mode)
    picked = [int(x) for x in a.only.split(",")] if a.only else range(frames)
    for i in picked:
        if subs == 1:
            draw(i)
            scene.render.filepath = os.path.join(a.out, f"f{i:03d}.png")
            bpy.ops.render.render(write_still=True)
        else:
            for k in range(subs):
                draw(i, k / subs)
                scene.render.filepath = os.path.join(a.out, f"f{i:03d}_{k}.png")
                bpy.ops.render.render(write_still=True)


run(args())
