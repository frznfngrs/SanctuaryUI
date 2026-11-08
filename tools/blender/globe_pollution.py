"""Debuff "pollution" inside the health globe (prototype): one seamless volumetric loop per
dispel type, built to play as a stepped flipbook.

Run headless:
  blender -b --factory-startup -P tools/blender/globe_pollution.py -- --out DIR --kind poison \
      [--frames 36] [--size 340] [--samples 48] [--only 0,9,18]

One render carries three images, one per colour channel (as tools/blender/globe_liquid.py):
  R  emission only: the lit veins, threads and hearts (becomes the ADD glow sheet)
  G  scattered light from the lamp in front (the shape of the mix)
  B  the background seen through the volume, e^-tau (becomes the mix sheet's alpha)

The loop has no cross-mix, because blending two fields ghosts thin lines and cells. Every noise
is sampled on a circle in its own x-W plane instead, so frame N is frame 0 exactly.

The lamp sits on the view axis, so a slow client-side Rotation of the sheet can't swing the light.
"""
import argparse
import math
import os
import sys

import bpy

KINDS = ("poison", "disease", "curse", "magic")


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--kind", required=True, choices=KINDS)
    p.add_argument("--frames", type=int, default=36)
    p.add_argument("--size", type=int, default=340)
    p.add_argument("--samples", type=int, default=48)
    p.add_argument("--only", default="")
    return p.parse_args(argv)


def gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    bpy.context.scene.cycles.device = "GPU"


class G:
    """Node helpers. cos and sin are the loop clock; everything periodic hangs off them.
    speed scales how far the noise moves in a loop: motion per flipbook frame."""
    def __init__(self, tree):
        self.t = tree
        self.speed = 1.0
        c = self.node("ShaderNodeValue")
        s = self.node("ShaderNodeValue")
        self.cos_v, self.sin_v = c, s
        self.cos, self.sin = c.outputs[0], s.outputs[0]
        self.p = self.node("ShaderNodeTexCoord").outputs["Object"]

    def node(self, kind, **props):
        n = self.t.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.t.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for sock, v in zip(n.inputs, (a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                sock.default_value = v
            else:
                self.link(v, sock)
        return n.outputs[0]

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def add(self, a, b):
        return self.math("ADD", a, b)

    def smooth(self, x, lo, hi):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        self.link(x, n.inputs["Value"])
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = 0
        n.inputs["To Max"].default_value = 1
        return n.outputs[0]

    def orbit(self, vec, radius):
        """vec moved round its circle, and the W that goes with it."""
        radius = radius * self.speed
        xyz = self.node("ShaderNodeCombineXYZ")
        self.link(self.mul(self.cos, radius), xyz.inputs["X"])
        v = self.node("ShaderNodeVectorMath", operation="ADD")
        self.link(vec, v.inputs[0])
        self.link(xyz.outputs[0], v.inputs[1])
        return v.outputs[0], self.mul(self.sin, radius)

    def noise(self, vec, scale, detail, rough, radius, w0):
        q, w = self.orbit(vec, radius)
        n = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        self.link(q, n.inputs["Vector"])
        self.link(self.add(w, w0), n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n

    def warp(self, vec, scale, amount, radius, w0):
        n = self.noise(vec, scale, 2.0, 0.5, radius, w0)
        centre = self.node("ShaderNodeVectorMath", operation="SUBTRACT")
        self.link(n.outputs["Color"], centre.inputs[0])
        centre.inputs[1].default_value = (0.5, 0.5, 0.5)
        amt = self.node("ShaderNodeVectorMath", operation="SCALE")
        self.link(centre.outputs[0], amt.inputs[0])
        amt.inputs["Scale"].default_value = amount * 2
        out = self.node("ShaderNodeVectorMath", operation="ADD")
        self.link(vec, out.inputs[0])
        self.link(amt.outputs[0], out.inputs[1])
        return out.outputs[0]

    def ridge(self, fac):
        """1 on the noise's mid-line, falling off either side: lines, not blobs."""
        return self.math("SUBTRACT", 1.0, self.math("ABSOLUTE", self.mul(self.math("SUBTRACT", fac, 0.5), 2.0)))

    def voronoi(self, vec, scale, radius, w0, smooth=0.35):
        q, w = self.orbit(vec, radius)
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature="SMOOTH_F1")
        self.link(q, n.inputs["Vector"])
        self.link(self.add(w, w0), n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Smoothness"].default_value = smooth
        n.inputs["Randomness"].default_value = 1.0
        return n.outputs["Distance"]

    def cracks(self, vec, scale, radius, w0):
        """Distance to the nearest cell wall: 0 on the walls, so clots can part along them."""
        q, w = self.orbit(vec, radius)
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature="DISTANCE_TO_EDGE")
        self.link(q, n.inputs["Vector"])
        self.link(self.add(w, w0), n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = 1.0
        return n.outputs["Distance"]

    def radius(self):
        n = self.node("ShaderNodeVectorMath", operation="LENGTH")
        self.link(self.p, n.inputs[0])
        return n.outputs["Value"]


def strands(g, q, sa, sb, r, w0, edges_a, edges_b):
    """Two sheets of ridge crossed: where they meet is a line, so veins read as veins."""
    a = g.smooth(g.ridge(g.noise(q, sa, 2.0, 0.42, r, w0).outputs["Fac"]), *edges_a)
    b = g.smooth(g.ridge(g.noise(q, sb, 2.0, 0.42, r, w0 + 5.0).outputs["Fac"]), *edges_b)
    return g.mul(a, b)


def poison(g):
    q = g.warp(g.p, 1.3, 0.62, 0.13, 3.0)
    q2 = g.warp(q, 2.6, 0.2, 0.09, 7.0)
    cloud = g.noise(q, 1.6, 5.0, 0.6, 0.1, 11.0).outputs["Fac"]
    v1 = strands(g, q2, 1.8, 1.25, 0.08, 13.0, (0.92, 0.99), (0.78, 0.95))
    v2 = strands(g, q2, 3.6, 2.4, 0.08, 23.0, (0.93, 0.992), (0.8, 0.96))
    veins = g.math("MAXIMUM", v1, g.mul(v2, 0.75))
    density = g.add(g.mul(g.smooth(cloud, 0.52, 0.72), 0.3), g.mul(veins, 6.0))
    emit = g.mul(veins, 1.6)
    return density, emit, 1.6


def disease(g):
    """Clots packed on the near face of the volume, parted by cracks the red shows through, with
    pustules on them. Only a shell near the viewer: through the whole depth cells average out
    to a soft cloud. R carries the pustule heads, which the grade paints pale, not a glow."""
    q = g.warp(g.p, 1.2, 0.34, 0.3, 5.0)
    walls = g.cracks(q, 4.4, 0.1, 17.0)
    lump = g.smooth(walls, 0.02, 0.09)
    dome = g.math("SUBTRACT", 1.0, g.smooth(g.voronoi(q, 4.4, 0.1, 17.0, 0.15), 0.05, 0.44))
    small = g.voronoi(q, 6.6, 0.12, 23.0, 0.1)
    pox = g.math("SUBTRACT", 1.0, g.smooth(small, 0.06, 0.16))
    # Where the clots gather at all: a slow cloud, so the red shows between the patches.
    mass = g.smooth(g.noise(q, 1.25, 4.0, 0.55, 0.18, 29.0).outputs["Fac"], 0.41, 0.51)
    y = g.node("ShaderNodeSeparateXYZ")
    g.link(g.p, y.inputs[0])
    near = g.mul(g.smooth(g.mul(y.outputs["Y"], -1.0), 0.05, 0.3), g.smooth(g.radius(), 0.52, 0.78))
    density = g.mul(g.mul(g.add(g.mul(lump, g.add(g.mul(dome, 55.0), 11.0)), g.mul(pox, 20.0)), mass), near)
    return density, g.mul(g.mul(pox, lump), g.mul(mass, near)), 1.1


def curse(g):
    q = g.warp(g.p, 0.9, 0.95, 0.34, 2.0)
    q2 = g.warp(q, 2.1, 0.42, 0.26, 31.0)
    a = g.ridge(g.noise(q2, 1.5, 4.0, 0.5, 0.2, 37.0).outputs["Fac"])
    b = g.ridge(g.noise(q2, 3.3, 3.0, 0.5, 0.2, 41.0).outputs["Fac"])
    fat = g.smooth(g.ridge(g.noise(q2, 1.05, 2.0, 0.45, 0.2, 43.0).outputs["Fac"]), 0.72, 0.92)
    ink = g.mul(g.math("MAXIMUM", g.smooth(a, 0.88, 0.975), g.mul(g.smooth(b, 0.91, 0.985), 0.8)), fat)
    # Ink creeps in from the rim, so the heart of the globe is the last to go.
    creep = g.smooth(g.radius(), 0.22, 0.86)
    density = g.mul(g.add(g.mul(ink, 26.0), 0.12), g.add(0.14, g.mul(creep, 0.86)))
    edge = g.mul(g.smooth(a, 0.8, 0.87), g.math("SUBTRACT", 1.0, g.smooth(a, 0.89, 0.96)))
    emit = g.mul(g.mul(g.mul(edge, fat), creep), 1.0)
    return density, emit, 1.0


def magic(g):
    g.speed = 0.38  # thin threads: any faster and they change too much per flipbook frame
    q = g.warp(g.p, 1.1, 0.5, 0.18, 43.0)
    wash = g.smooth(g.noise(q, 1.4, 4.0, 0.55, 0.12, 47.0).outputs["Fac"], 0.5, 0.72)
    t1 = strands(g, q, 1.9, 1.3, 0.16, 53.0, (0.965, 0.998), (0.8, 0.96))
    t2 = strands(g, q, 4.0, 2.6, 0.22, 61.0, (0.97, 0.998), (0.82, 0.97))
    threads = g.math("MAXIMUM", t1, g.mul(t2, 0.75))
    density = g.add(g.mul(wash, 0.55), g.mul(threads, 3.0))
    emit = g.mul(threads, 7.0)
    return density, emit, 1.4


def material(kind):
    mat = bpy.data.materials.new("Pollution")
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    g = G(tree)
    density, emit, lamp = {"poison": poison, "disease": disease, "curse": curse, "magic": magic}[kind](g)
    emission = g.node("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 0, 0, 1)
    g.link(emit, emission.inputs["Strength"])
    scatter = g.node("ShaderNodeVolumeScatter")
    scatter.inputs["Color"].default_value = (0, 1, 0, 1)
    scatter.inputs["Anisotropy"].default_value = 0.1
    g.link(density, scatter.inputs["Density"])
    absorb = g.node("ShaderNodeVolumeAbsorption")
    absorb.inputs["Color"].default_value = (0, 1, 0, 1)
    g.link(density, absorb.inputs["Density"])
    add = g.node("ShaderNodeAddShader")
    g.link(emission.outputs[0], add.inputs[0])
    g.link(scatter.outputs[0], add.inputs[1])
    add2 = g.node("ShaderNodeAddShader")
    g.link(add.outputs[0], add2.inputs[0])
    g.link(absorb.outputs[0], add2.inputs[1])
    g.link(add2.outputs[0], g.node("ShaderNodeOutputMaterial").inputs["Volume"])
    return mat, g, lamp


def scene(kind, opt):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    gpu()
    s.cycles.samples = opt.samples
    s.cycles.use_adaptive_sampling = False
    s.cycles.use_denoising = True
    s.cycles.denoiser = "OPENIMAGEDENOISE"
    s.cycles.max_bounces = 4
    s.cycles.volume_bounces = 2
    s.cycles.diffuse_bounces = 0
    s.cycles.glossy_bounces = 0
    s.cycles.transmission_bounces = 0
    s.cycles.volume_step_rate = 0.5
    s.render.resolution_x = s.render.resolution_y = opt.size
    s.render.film_transparent = False
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGB"
    s.render.image_settings.color_depth = "16"
    s.view_settings.view_transform = "Raw"
    s.view_settings.look = "None"

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0, 0, 1, 1)
    bg.inputs["Strength"].default_value = 1.0
    s.world = world

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5, radius=1.0)
    ball = bpy.context.object
    bpy.ops.object.shade_smooth()
    mat, g, lamp_w = material(kind)
    ball.data.materials.append(mat)

    cam = bpy.data.cameras.new("C")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.0
    ob = bpy.data.objects.new("C", cam)
    ob.location = (0, -5, 0)
    ob.rotation_euler = (math.pi / 2, 0, 0)
    s.collection.objects.link(ob)
    s.camera = ob

    lamp = bpy.data.lights.new("L", "POINT")
    lamp.energy = 40.0 * lamp_w
    lamp.color = (1, 1, 1)
    lamp.shadow_soft_size = 0.5
    lob = bpy.data.objects.new("L", lamp)
    lob.location = (0, -2.2, 0)
    s.collection.objects.link(lob)
    return s, g


def main():
    opt = args()
    s, g = scene(opt.kind, opt)
    os.makedirs(opt.out, exist_ok=True)
    wanted = [int(x) for x in opt.only.split(",") if x] or range(opt.frames)
    for f in wanted:
        th = 2 * math.pi * f / opt.frames
        g.cos_v.outputs[0].default_value = math.cos(th)
        g.sin_v.outputs[0].default_value = math.sin(th)
        s.render.filepath = os.path.join(opt.out, f"f{f:03d}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", f, flush=True)


main()
