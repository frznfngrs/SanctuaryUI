"""Lights the console angel's relief with gold: the passes angel_radiance_art.py builds from.

  blender -b --factory-startup -P angel_radiance.py -- WORK

WORK holds height.npy and albedo.png from `angel_radiance_art.py prep`. One unit is one
frame.png px, x right, y up (so y = -sheet y), the relief rising toward the camera.

Passes, each a 16-bit RGBA PNG of the same view:
  key    gold sun raking down the statue from above, with a low sun behind it for the rims
  roots  light held just off the stone at each wing's root, falling away down the feathers
  face   white light straight on: the relief's own shading, no cast shadows to speak of
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

REGION = (1376, 36, 1600, 204)
NEAR_ROOT = (1493, 64)
FAR_ROOT = (1445, 62)


def setup(samples):
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
    except Exception:
        sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    world = bpy.data.worlds.new("black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    sc.world = world
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    return sc


def relief(height, albedo_path):
    """The statue as a height field, one vertex per sample."""
    h, w = height.shape
    x0, y0, x1, y1 = REGION
    xs = x0 + (np.arange(w, dtype=np.float32) + 0.5) * (x1 - x0) / w
    ys = -(y0 + (np.arange(h, dtype=np.float32) + 0.5) * (y1 - y0) / h)
    gx, gy = np.meshgrid(xs, ys)
    co = np.dstack([gx, gy, height]).reshape(-1, 3)

    idx = np.arange(h * w, dtype=np.int32).reshape(h, w)
    quads = np.dstack([idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:], idx[:-1, :-1]]).reshape(-1, 4)
    me = bpy.data.meshes.new("relief")
    me.vertices.add(len(co))
    me.vertices.foreach_set("co", co.ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", np.arange(0, quads.size, 4, dtype=np.int32))
    me.polygons.foreach_set("loop_total", np.full(len(quads), 4, dtype=np.int32))
    me.polygons.foreach_set("use_smooth", np.ones(len(quads), dtype=bool))
    uv = me.uv_layers.new(name="uv")
    u = (np.arange(w, dtype=np.float32) + 0.5) / w
    v = 1 - (np.arange(h, dtype=np.float32) + 0.5) / h
    gu, gv = np.meshgrid(u, v)
    uvs = np.dstack([gu, gv]).reshape(-1, 2)[quads.ravel()]
    uv.data.foreach_set("uv", uvs.ravel())
    me.update()
    me.validate()

    mat = bpy.data.materials.new("stone")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(albedo_path))
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    # Worn, polished stone: enough sheen that the gold glints off the ridges.
    bsdf.inputs["Roughness"].default_value = 0.38
    bsdf.inputs["Metallic"].default_value = 0.35
    me.materials.append(mat)

    ob = bpy.data.objects.new("relief", me)
    bpy.context.collection.objects.link(ob)
    return ob


def camera(sc, scale):
    x0, y0, x1, y1 = REGION
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = x1 - x0
    cam.clip_end = 1000
    ob = bpy.data.objects.new("cam", cam)
    ob.location = ((x0 + x1) / 2, -(y0 + y1) / 2, 200)
    bpy.context.collection.objects.link(ob)
    sc.camera = ob
    sc.render.resolution_x = (x1 - x0) * scale
    sc.render.resolution_y = (y1 - y0) * scale
    sc.render.resolution_percentage = 100


def sun(name, travels, energy, angle, color):
    """A sun whose light travels along `travels`."""
    li = bpy.data.lights.new(name, "SUN")
    li.energy, li.angle, li.color = energy, math.radians(angle), color
    ob = bpy.data.objects.new(name, li)
    ob.rotation_euler = Vector(travels).normalized().to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(ob)
    return ob


def point(name, sheet_xy, z, energy, radius, color):
    li = bpy.data.lights.new(name, "POINT")
    li.energy, li.shadow_soft_size, li.color = energy, radius, color
    ob = bpy.data.objects.new(name, li)
    ob.location = (sheet_xy[0], -sheet_xy[1], z)
    bpy.context.collection.objects.link(ob)
    return ob


def render(sc, path, lights, on):
    for group, obs in lights.items():
        for ob in obs:
            ob.hide_render = group != on
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    work = Path(sys.argv[sys.argv.index("--") + 1])
    height = np.load(work / "height.npy")
    scale = height.shape[1] // (REGION[2] - REGION[0])
    sc = setup(samples=256)
    relief(height, work / "albedo.png")
    camera(sc, scale)

    gold = (1.0, 0.66, 0.22)
    pale = (1.0, 0.86, 0.55)
    lights = {
        "key": [
            # Down the statue and into it, low enough that every feather throws a shadow.
            sun("key", (0.10, -1.0, -0.55), 5.0, 6, gold),
            # From behind the top edge: a thin line of light along what faces up.
            sun("rim", (-0.15, -1.0, -0.12), 3.0, 3, pale),
        ],
        "roots": [
            point("near", NEAR_ROOT, 16, 9.0e4, 5, pale),
            point("far", FAR_ROOT, 13, 4.0e4, 4, pale),
        ],
        "face": [sun("face", (0, -0.25, -1.0), 2.5, 20, (1, 1, 1))],
    }
    for name in lights:
        render(sc, work / f"{name}.png", lights, name)


main()
