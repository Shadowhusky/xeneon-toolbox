"""
Procedurally model the Corsair Xeneon Edge and render a product mockup with a
chosen UI screenshot mapped onto the screen.

Run headless:
  Blender --background --python xeneon_mockup.py -- <ui_png> <out_png> [angle] [res]

angle: hero | front | left
Modeled from Corsair product photography: 372x120x22mm matte-black slab, glossy
32:9 screen offset left with thin bezels, a vertical oval cutout through the
right end section, and a low magnetic wedge stand at a slight backward tilt.
Convention: camera sits on -Y and looks toward +Y, so the screen faces -Y.
"""
import bpy, sys, math, bmesh, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
UI = argv[0] if len(argv) > 0 else "blender/textures/hd-dashboard.png"
OUT = argv[1] if len(argv) > 1 else "blender/render.png"
ANGLE = argv[2] if len(argv) > 2 else "hero"
RES = int(argv[3]) if len(argv) > 3 else 1400

W, H, D = 0.372, 0.120, 0.022
SCREEN_W, SCREEN_H = 0.330, 0.0928
SCREEN_CX = -0.020
CUTOUT_CX = 0.156
TILT = math.radians(12)
FRONT = -D / 2            # screen side (toward camera)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def set_mat(obj, mat):
    obj.data.materials.clear()       # primitives ship with a default slot 0
    obj.data.materials.append(mat)


def pbr(name, base, rough, metal=0.0, coat=0.0, ior=1.45):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "IOR" in b.inputs: b.inputs["IOR"].default_value = ior
    if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = coat
    if "Specular IOR Level" in b.inputs: b.inputs["Specular IOR Level"].default_value = 0.4
    return m


def screen_mat(img_path):
    m = bpy.data.materials.new("screen_ui"); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emis = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(img_path)
    tex.interpolation = "Cubic"
    emis.inputs["Strength"].default_value = 1.5
    nt.links.new(tex.outputs["Color"], emis.inputs["Color"])
    nt.links.new(emis.outputs["Emission"], out.inputs["Surface"])
    return m


# ---------- body ----------
bpy.ops.mesh.primitive_cube_add(size=1)
body = bpy.context.object; body.name = "body"
body.dimensions = (W, D, H)
bpy.ops.object.transform_apply(scale=True)
bev = body.modifiers.new("bevel", "BEVEL"); bev.width = 0.0075; bev.segments = 6; bev.harden_normals = True

bpy.ops.mesh.primitive_cylinder_add(vertices=80, radius=0.02, depth=0.08)
cut = bpy.context.object; cut.name = "cutter"
cut.scale = (0.6, 1.0, 1.0)
cut.rotation_euler = (math.radians(90), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
cut.scale = (1.0, 1.0, 1.3)
bpy.ops.object.transform_apply(scale=True)
cut.location = (CUTOUT_CX, 0, 0)
boo = body.modifiers.new("cutout", "BOOLEAN"); boo.operation = "DIFFERENCE"; boo.object = cut
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier="bevel")
bpy.ops.object.modifier_apply(modifier="cutout")
bpy.data.objects.remove(cut, do_unlink=True)
set_mat(body, pbr("matte_black", (0.010, 0.010, 0.012), 0.62, coat=0.0))
if hasattr(bpy.ops.object, "shade_auto_smooth"):
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))

# ---------- glossy glass over the screen region ----------
bpy.ops.mesh.primitive_cube_add(size=1)
glass = bpy.context.object; glass.name = "glass"
glass.dimensions = (SCREEN_W + 0.015, 0.002, SCREEN_H + 0.015)
bpy.ops.object.transform_apply(scale=True)
glass.location = (SCREEN_CX, FRONT - 0.0003, 0)
gb = glass.modifiers.new("b", "BEVEL"); gb.width = 0.0015; gb.segments = 3
set_mat(glass, pbr("glass", (0.004, 0.004, 0.006), 0.08, coat=0.7, ior=1.5))

# ---------- emissive UI ----------
bpy.ops.mesh.primitive_plane_add(size=1)
ui = bpy.context.object; ui.name = "ui"
ui.scale = (SCREEN_W, SCREEN_H, 1)
bpy.ops.object.transform_apply(scale=True)
ui.rotation_euler = (math.radians(90), 0, 0)   # XY -> XZ, normal faces -Y
bpy.ops.object.transform_apply(rotation=True)
ui.location = (SCREEN_CX, FRONT - 0.0016, 0)
set_mat(ui, screen_mat(UI))

# ---------- raise device so it rests bottom-on-desk, then tilt ----------
parts = [body, glass, ui]
for o in parts:
    o.location.z += H / 2          # bottom now at z = 0
bpy.ops.object.empty_add(location=(0, 0, 0.004))
pivot = bpy.context.object; pivot.name = "pivot"
for o in parts:
    o.parent = pivot
    o.matrix_parent_inverse = pivot.matrix_world.inverted()
pivot.rotation_euler = (-TILT, 0, 0)   # top leans back (+Y, away from camera)

# ---------- magnetic wedge stand (behind, +Y) ----------
mesh = bpy.data.meshes.new("stand"); stand = bpy.data.objects.new("stand", mesh)
bpy.context.collection.objects.link(stand)
bm = bmesh.new()
prof = [(0.0, 0.0), (0.085, 0.0), (0.012, 0.052)]   # (Y,Z) doorstop wedge
half = 0.125
r1 = [bm.verts.new((-half, y, z)) for (y, z) in prof]
r2 = [bm.verts.new((half, y, z)) for (y, z) in prof]
bm.faces.new(r1); bm.faces.new(list(reversed(r2)))
for i in range(3):
    bm.faces.new([r1[i], r1[(i + 1) % 3], r2[(i + 1) % 3], r2[i]])
bm.to_mesh(mesh); bm.free()
sbev = stand.modifiers.new("b", "BEVEL"); sbev.width = 0.004; sbev.segments = 2
set_mat(stand, pbr("stand", (0.016, 0.016, 0.018), 0.55))
stand.location = (0, 0.006, 0)

# ---------- studio floor (light, seamless) ----------
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
set_mat(bpy.context.object, pbr("floor", (0.42, 0.42, 0.45), 0.45))

# ---------- world: bright soft lightbox so the matte-black device reads ----------
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
bgn = world.node_tree.nodes["Background"]
bgn.inputs["Color"].default_value = (0.62, 0.63, 0.66, 1)
bgn.inputs["Strength"].default_value = 1.0

# ---------- lights (soft key + rim for edge definition) ----------
def area(name, loc, energy, size, rot):
    ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.size = size
    lo = bpy.data.objects.new(name, ld); lo.location = loc; lo.rotation_euler = rot
    bpy.context.collection.objects.link(lo)

area("key", (-0.45, -0.6, 0.65), 14, 0.9, (math.radians(42), 0, math.radians(-36)))
area("rim", (0.35, 0.65, 0.6), 22, 0.5, (math.radians(125), 0, math.radians(14)))

# ---------- camera ----------
cd = bpy.data.cameras.new("cam"); cd.lens = 58
cam = bpy.data.objects.new("cam", cd); bpy.context.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 0, 0.052))
positions = {
    "hero":  Vector((0.30, -0.82, 0.17)),
    "front": Vector((0.00, -0.88, 0.11)),
    "left":  Vector((-0.34, -0.78, 0.17)),
}
cam.location = positions.get(ANGLE, positions["hero"])
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

# ---------- render ----------
engines = [e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
try:
    scene.eevee.taa_render_samples = 128
    scene.eevee.use_shadow_jitter_viewport = True
except Exception:
    pass
scene.render.resolution_x = int(RES * 1.5)
scene.render.resolution_y = RES
vt = [v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items]
scene.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
try: scene.eevee.use_raytracing = True
except Exception: pass
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = OUT

# Optionally save a self-contained .blend (textures packed) for reuse / web export.
if os.environ.get("XENEON_SAVE_BLEND"):
    try: bpy.ops.file.pack_all()
    except Exception: pass
    bpy.ops.wm.save_as_mainfile(filepath=os.environ["XENEON_SAVE_BLEND"])
    print("SAVED BLEND ->", os.environ["XENEON_SAVE_BLEND"])

bpy.ops.render.render(write_still=True)
print("RENDERED", scene.render.resolution_x, scene.render.resolution_y, "->", OUT)
