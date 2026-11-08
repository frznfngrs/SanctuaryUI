"""Pre-rendered globe liquid (prototype): a seamless volumetric loop inside a sphere.

Run headless:
  blender -b --factory-startup -P tools/blender/globe_liquid.py -- --out DIR --variant calm \
      [--frames 48] [--seconds 5] [--size 512] [--samples 64] [--only 0,12,24]

One render carries three separate images, one per colour channel, because the volume's
extinction is the same in every channel:
  R  emission only: the hot filaments and the core (becomes the ADD "light" sheet)
  G  scattered light from the point lamp inside (becomes the tintable "body" sheet)
  B  the background seen through the volume, e^-tau (thickness, for shading the body)

The loop is seamless by construction. Two copies of the field run with time t and t-T and
are mixed by t/T, so frame T is exactly frame 0, drift and turning included. The mix's lost
contrast is put back by dividing by sqrt(s^2 + (1-s)^2).
"""
import argparse
import math
import os
import sys

import bpy

VARIANTS = {
    # span of noise, motion per second, thresholds. Motion is per second, loop length is free.
    "calm": dict(
        scale=2.0, warp=0.62, warp_scale=1.1, evolve=0.1, rise=0.075, spin=0.11, twist=0.45,
        density=(2.0, 26.0), density_edges=(0.44, 0.60), detail=8.0, rough=0.62,
        fil_scale=3.1, fil_evolve=0.12, fil_edges=(0.90, 0.992), fil_gain=26.0,
        core=(0.0, -0.05, -0.2), core_gain=0.65, core_power=1.0, lamp=(0.0, -0.45, -0.1), lamp_w=9.0,
    ),
    "agitated": dict(
        scale=2.8, warp=0.95, warp_scale=1.7, evolve=0.36, rise=0.42, spin=0.34, twist=0.9,
        density=(3.0, 34.0), density_edges=(0.42, 0.56), detail=8.0, rough=0.66,
        fil_scale=4.2, fil_evolve=0.44, fil_edges=(0.86, 0.985), fil_gain=30.0,
        core=(0.0, -0.05, -0.55), core_gain=0.4, core_power=1.6, lamp=(0.0, -0.5, -0.5), lamp_w=4.5,
    ),
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--variant", default="calm", choices=sorted(VARIANTS))
    p.add_argument("--frames", type=int, default=48)
    p.add_argument("--seconds", type=float, default=5.0)
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--samples", type=int, default=64)
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
    """Thin node-graph helper."""
    def __init__(self, tree):
        self.t = tree

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

    def smooth(self, x, lo, hi):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        self.link(x, n.inputs["Value"])
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = 0
        n.inputs["To Max"].default_value = 1
        return n.outputs[0]

    def noise(self, vec, w, scale, detail, rough, dist=0.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        self.link(vec, n.inputs["Vector"])
        if isinstance(w, (int, float)):
            n.inputs["W"].default_value = w
        else:
            self.link(w, n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        return n


def field_group(cfg):
    """One copy of the moving field. Input: Tau. Output: Body and Filament noise, both 0..1."""
    tree = bpy.data.node_groups.new("LiquidField", "ShaderNodeTree")
    tree.interface.new_socket("Tau", in_out="INPUT", socket_type="NodeSocketFloat")
    tree.interface.new_socket("Body", in_out="OUTPUT", socket_type="NodeSocketFloat")
    tree.interface.new_socket("Fil", in_out="OUTPUT", socket_type="NodeSocketFloat")
    g = G(tree)
    inp = g.node("NodeGroupInput")
    out = g.node("NodeGroupOutput")
    tau = inp.outputs["Tau"]
    obj = g.node("ShaderNodeTexCoord").outputs["Object"]

    # Rise: the field climbs, so plumes rise through the sphere.
    rise = g.node("ShaderNodeVectorMath", operation="SUBTRACT")
    g.link(obj, rise.inputs[0])
    lift = g.node("ShaderNodeCombineXYZ")
    g.link(g.math("MULTIPLY", tau, cfg["rise"]), lift.inputs["Z"])
    g.link(lift.outputs[0], rise.inputs[1])

    # Turn about the vertical, more at the top than the bottom: near and far sides pass each
    # other, which is what reads as a sphere of liquid rather than a sliding picture.
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(obj, sep.inputs[0])
    angle = g.math("ADD", g.math("MULTIPLY", tau, cfg["spin"]), g.math("MULTIPLY", sep.outputs["Z"], cfg["twist"]))
    rot = g.node("ShaderNodeVectorRotate", rotation_type="Z_AXIS")
    g.link(rise.outputs[0], rot.inputs["Vector"])
    g.link(angle, rot.inputs["Angle"])
    p = rot.outputs[0]

    # Domain warp: plumes curl around the large flow instead of being blobs.
    w1 = g.math("MULTIPLY", tau, cfg["evolve"])
    n1 = g.noise(p, w1, cfg["warp_scale"], 2.0, 0.5)
    centre = g.node("ShaderNodeVectorMath", operation="SUBTRACT")
    g.link(n1.outputs["Color"], centre.inputs[0])
    centre.inputs[1].default_value = (0.5, 0.5, 0.5)
    amt = g.node("ShaderNodeVectorMath", operation="SCALE")
    g.link(centre.outputs[0], amt.inputs[0])
    amt.inputs["Scale"].default_value = cfg["warp"] * 2
    warped = g.node("ShaderNodeVectorMath", operation="ADD")
    g.link(p, warped.inputs[0])
    g.link(amt.outputs[0], warped.inputs[1])
    q = warped.outputs[0]

    body = g.noise(q, g.math("ADD", w1, 17.0), cfg["scale"], cfg.get("detail", 5.0), cfg.get("rough", 0.55))
    fil = g.noise(q, g.math("ADD", g.math("MULTIPLY", tau, cfg["fil_evolve"]), 41.0), cfg["fil_scale"], 4.0, 0.55)
    g.link(body.outputs["Fac"], out.inputs["Body"])
    g.link(fil.outputs["Fac"], out.inputs["Fil"])
    return tree


def material(cfg):
    mat = bpy.data.materials.new("Liquid")
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    g = G(tree)
    group = field_group(cfg)
    a = g.node("ShaderNodeGroup")
    b = g.node("ShaderNodeGroup")
    a.node_tree = group
    b.node_tree = group
    mix = g.node("ShaderNodeValue")
    comp = g.node("ShaderNodeValue")
    tau_a = g.node("ShaderNodeValue")
    tau_b = g.node("ShaderNodeValue")
    g.link(tau_a.outputs[0], a.inputs["Tau"])
    g.link(tau_b.outputs[0], b.inputs["Tau"])

    def blended(name):
        la = g.math("MULTIPLY", a.outputs[name], g.math("SUBTRACT", 1.0, mix.outputs[0]))
        lb = g.math("MULTIPLY", b.outputs[name], mix.outputs[0])
        centred = g.math("SUBTRACT", g.math("ADD", la, lb), 0.5)
        return g.math("ADD", g.math("DIVIDE", centred, comp.outputs[0]), 0.5, clamp=True)

    body = blended("Body")
    fil = blended("Fil")

    base, gain = cfg["density"]
    lo, hi = cfg["density_edges"]
    density = g.math("ADD", base, g.math("MULTIPLY", g.smooth(body, lo, hi), gain))

    # Filaments: a thin ridge where the noise crosses its middle, so they are lines, not blobs.
    ridge = g.math("SUBTRACT", 1.0, g.math("ABSOLUTE", g.math("MULTIPLY", g.math("SUBTRACT", fil, 0.5), 2.0)))
    fl, fh = cfg["fil_edges"]
    lines = g.smooth(ridge, fl, fh)
    lines = g.math("MULTIPLY", lines, g.math("MULTIPLY", g.smooth(body, 0.35, 0.65), cfg["fil_gain"]))

    # The core: a soft light low in the sphere, feeding the filaments near it.
    tc = g.node("ShaderNodeTexCoord").outputs["Object"]
    off = g.node("ShaderNodeVectorMath", operation="DISTANCE")
    g.link(tc, off.inputs[0])
    off.inputs[1].default_value = cfg["core"]
    near = g.math("SUBTRACT", 1.0, g.math("DIVIDE", off.outputs["Value"], 1.2), clamp=True)
    glow = g.math("POWER", near, cfg["core_power"])
    emit_amount = g.math("ADD", g.math("MULTIPLY", lines, glow), g.math("MULTIPLY", glow, cfg["core_gain"]))

    emission = g.node("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 0, 0, 1)
    g.link(emit_amount, emission.inputs["Strength"])
    scatter = g.node("ShaderNodeVolumeScatter")
    scatter.inputs["Color"].default_value = (0, 1, 0, 1)
    scatter.inputs["Anisotropy"].default_value = 0.2
    g.link(density, scatter.inputs["Density"])
    # Cycles' scatter colour is a per-channel coefficient, so a green scatter leaves R and B
    # unattenuated; an absorption of the same density in R and B makes extinction equal.
    absorb = g.node("ShaderNodeVolumeAbsorption")
    absorb.inputs["Color"].default_value = (0, 1, 0, 1)
    g.link(density, absorb.inputs["Density"])
    add = g.node("ShaderNodeAddShader")
    g.link(emission.outputs[0], add.inputs[0])
    g.link(scatter.outputs[0], add.inputs[1])
    add2 = g.node("ShaderNodeAddShader")
    g.link(add.outputs[0], add2.inputs[0])
    g.link(absorb.outputs[0], add2.inputs[1])
    output = g.node("ShaderNodeOutputMaterial")
    g.link(add2.outputs[0], output.inputs["Volume"])
    return mat, mix, comp, tau_a, tau_b


def scene(cfg, opt):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    gpu()
    s.cycles.samples = opt.samples
    s.cycles.use_adaptive_sampling = False
    s.cycles.use_denoising = True
    s.cycles.denoiser = "OPENIMAGEDENOISE"
    s.cycles.max_bounces = 6
    s.cycles.volume_bounces = 3
    s.cycles.diffuse_bounces = 0
    s.cycles.glossy_bounces = 0
    s.cycles.transmission_bounces = 0
    s.cycles.volume_step_rate = 1.0
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
    mat, *controls = material(cfg)
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
    lamp.energy = cfg["lamp_w"]
    lamp.color = (1, 1, 1)
    lamp.shadow_soft_size = 0.15
    lob = bpy.data.objects.new("L", lamp)
    lob.location = cfg["lamp"]
    s.collection.objects.link(lob)
    return s, controls


def main():
    opt = args()
    cfg = VARIANTS[opt.variant]
    s, (mix, comp, tau_a, tau_b) = scene(cfg, opt)
    os.makedirs(opt.out, exist_ok=True)
    wanted = [int(x) for x in opt.only.split(",") if x] or range(opt.frames)
    for f in wanted:
        u = f / opt.frames
        t = u * opt.seconds
        mix.outputs[0].default_value = u
        comp.outputs[0].default_value = math.sqrt(u * u + (1 - u) * (1 - u))
        tau_a.outputs[0].default_value = t
        tau_b.outputs[0].default_value = t - opt.seconds
        s.render.filepath = os.path.join(opt.out, f"f{f:03d}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", f, flush=True)


main()
