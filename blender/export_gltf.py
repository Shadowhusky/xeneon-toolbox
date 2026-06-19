"""
Build the Xeneon Edge model, export a self-contained .glb (for web /
model-viewer / three.js), then RE-IMPORT the exported .glb and render it — so
the preview proves the glТF round-trips correctly (materials, emissive screen,
geometry, scale all intact).

  Blender --background --python export_gltf.py -- <ui_png> <glb_out> <preview_png>
"""
import bpy, sys, math, bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
UI = argv[0] if len(argv) > 0 else "blender/textures/hd-dashboard.png"
GLB = argv[1] if len(argv) > 1 else "blender/xeneon-edge.glb"
PREVIEW = argv[2] if len(argv) > 2 else "blender/gltf-preview.png"

W, H, D = 0.372, 0.120, 0.022
SCREEN_W, SCREEN_H = 0.330, 0.0928
SCREEN_CX, CUTOUT_CX = -0.020, 0.156
TILT, FRONT = math.radians(12), -0.011

bpy.ops.wm.read_factory_settings(use_empty=True)


def set_mat(o, m):
    o.data.materials.clear(); o.data.materials.append(m)


def pbr(name, base, rough, metal=0.0, coat=0.0, ior=1.45):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "IOR" in b.inputs: b.inputs["IOR"].default_value = ior
    if "Coat Weight" in b.inputs: b.inputs["Coat Weight"].default_value = coat
    return m


def screen_mat(img):
    # Principled emission (exports cleanly to glTF via KHR_materials_emissive_strength)
    m = bpy.data.materials.new("screen_ui"); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(img); tex.interpolation = "Cubic"
    m.node_tree.links.new(tex.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 1.3
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Roughness"].default_value = 1.0
    return m


# ---- body ----
bpy.ops.mesh.primitive_cube_add(size=1)
body = bpy.context.object; body.name = "Body"
body.dimensions = (W, D, H); bpy.ops.object.transform_apply(scale=True)
bev = body.modifiers.new("bevel", "BEVEL"); bev.width = 0.0075; bev.segments = 6; bev.harden_normals = True
bpy.ops.mesh.primitive_cylinder_add(vertices=80, radius=0.02, depth=0.08)
cut = bpy.context.object
cut.scale = (0.6, 1, 1); cut.rotation_euler = (math.radians(90), 0, 0)
bpy.ops.object.transform_apply(scale=True, rotation=True)
cut.scale = (1, 1, 1.3); bpy.ops.object.transform_apply(scale=True); cut.location = (CUTOUT_CX, 0, 0)
bo = body.modifiers.new("cut", "BOOLEAN"); bo.operation = "DIFFERENCE"; bo.object = cut
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier="bevel"); bpy.ops.object.modifier_apply(modifier="cut")
bpy.data.objects.remove(cut, do_unlink=True)
set_mat(body, pbr("matte_black", (0.010, 0.010, 0.012), 0.62))
if hasattr(bpy.ops.object, "shade_auto_smooth"):
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))

# ---- glass ----
bpy.ops.mesh.primitive_cube_add(size=1)
glass = bpy.context.object; glass.name = "Glass"
glass.dimensions = (SCREEN_W + 0.015, 0.002, SCREEN_H + 0.015); bpy.ops.object.transform_apply(scale=True)
glass.location = (SCREEN_CX, FRONT - 0.0003, 0)
glass.modifiers.new("b", "BEVEL").width = 0.0015
set_mat(glass, pbr("glass", (0.004, 0.004, 0.006), 0.08, coat=0.7, ior=1.5))

# ---- ui ----
bpy.ops.mesh.primitive_plane_add(size=1)
ui = bpy.context.object; ui.name = "Screen"
ui.scale = (SCREEN_W, SCREEN_H, 1); bpy.ops.object.transform_apply(scale=True)
ui.rotation_euler = (math.radians(90), 0, 0); bpy.ops.object.transform_apply(rotation=True)
ui.location = (SCREEN_CX, FRONT - 0.0016, 0)
set_mat(ui, screen_mat(UI))

# ---- raise + tilt, then bake the tilt into the meshes (no empty in the glTF) ----
parts = [body, glass, ui]
for o in parts:
    o.location.z += H / 2
bpy.ops.object.empty_add(location=(0, 0, 0.004)); pivot = bpy.context.object
for o in parts:
    o.parent = pivot; o.matrix_parent_inverse = pivot.matrix_world.inverted()
pivot.rotation_euler = (-TILT, 0, 0)
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.data.objects.remove(pivot, do_unlink=True)

# ---- stand ----
mesh = bpy.data.meshes.new("Stand"); stand = bpy.data.objects.new("Stand", mesh)
bpy.context.collection.objects.link(stand)
bm = bmesh.new(); prof = [(0, 0), (0.085, 0), (0.012, 0.052)]; half = 0.125
r1 = [bm.verts.new((-half, y, z)) for (y, z) in prof]
r2 = [bm.verts.new((half, y, z)) for (y, z) in prof]
bm.faces.new(r1); bm.faces.new(list(reversed(r2)))
for i in range(3):
    bm.faces.new([r1[i], r1[(i + 1) % 3], r2[(i + 1) % 3], r2[i]])
bm.to_mesh(mesh); bm.free()
stand.modifiers.new("b", "BEVEL").width = 0.004
set_mat(stand, pbr("stand", (0.016, 0.016, 0.018), 0.55))
stand.location = (0, 0.006, 0)

# ---- export selected (device + stand) ----
bpy.ops.object.select_all(action="DESELECT")
for o in [body, glass, ui, stand]:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
                          export_apply=True, export_yup=True)
print("EXPORTED GLB ->", GLB)

# ================= verify: re-import the exported glb and render it =================
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in scene.objects if o.type == "MESH"]

mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector((min(mn[i], w[i]) for i in range(3)))
        mx = Vector((max(mx[i], w[i]) for i in range(3)))
center = (mn + mx) / 2
diag = (mx - mn).length

# floor under the model
bpy.ops.mesh.primitive_plane_add(size=8, location=(center.x, center.y, mn.z))
set_mat(bpy.context.object, pbr("floor", (0.42, 0.42, 0.45), 0.45))

world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
bgn = world.node_tree.nodes["Background"]
bgn.inputs["Color"].default_value = (0.62, 0.63, 0.66, 1); bgn.inputs["Strength"].default_value = 1.0

def area(loc, energy, size, rot):
    ld = bpy.data.lights.new("a", "AREA"); ld.energy = energy; ld.size = size
    lo = bpy.data.objects.new("a", ld); lo.location = loc; lo.rotation_euler = rot
    scene.collection.objects.link(lo)

area((center.x - 0.45, center.y - 0.6, center.z + 0.6), 14, 0.9, (math.radians(42), 0, math.radians(-36)))
area((center.x + 0.35, center.y + 0.65, center.z + 0.6), 22, 0.5, (math.radians(125), 0, math.radians(14)))

cd = bpy.data.cameras.new("c"); cd.lens = 58
cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = center + Vector((0.30, -0.82, 0.12)) * (diag / 0.40)
cam.rotation_euler = (center + Vector((0, 0, 0.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()

engines = [e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
try: scene.eevee.taa_render_samples = 128
except Exception: pass
scene.render.resolution_x = 2400; scene.render.resolution_y = 1600
vt = [v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items]
scene.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
scene.render.filepath = PREVIEW
bpy.ops.render.render(write_still=True)
print("RENDERED GLB PREVIEW ->", PREVIEW)
