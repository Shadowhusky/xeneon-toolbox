"""Refine a raw Meshy mesh: decimate (simplify the dense AI mesh), override to a
clean matte-black material, overlay the app UI as an emissive screen, and render
a studio hero.

  Blender --background --python meshy_refine.py -- <glb> <ui_png> <out_png> \
      [az] [el] [screenW] [screenH] [sx] [sz] [pushY]

screenW/H = UI plane size; sx/sz = screen-centre offset (X,Z); pushY = how far in
front of the body front the UI sits.
"""
import bpy, sys, math, os
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB, UI, OUT = a[0], a[1], a[2]
AZ = float(a[3]) if len(a) > 3 else 28.0
EL = float(a[4]) if len(a) > 4 else 14.0
SW = float(a[5]) if len(a) > 5 else 1.50
SH = float(a[6]) if len(a) > 6 else 0.42
SX = float(a[7]) if len(a) > 7 else -0.10
SZ = float(a[8]) if len(a) > 8 else 0.0
PUSH = float(a[9]) if len(a) > 9 else 0.02
DSY = float(a[10]) if len(a) > 10 else 0.12   # depth scale (thin the inflated AI mesh)
DSZ = float(a[11]) if len(a) > 11 else 0.66   # height scale

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in scene.objects if o.type == "MESH"]
obj = meshes[0]
for m in meshes[1:]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = obj

before = sum(len(o.data.polygons) for o in meshes)
dec = obj.modifiers.new("dec", "DECIMATE")
dec.ratio = max(0.01, min(1.0, 30000.0 / max(1, before)))   # simplify but keep enough to stay smooth
bpy.ops.object.modifier_apply(modifier="dec")
after = len(obj.data.polygons)
print("DECIMATE", before, "->", after)

# Correct the AI mesh's inflated depth/height back to the real slab proportions,
# then smooth-shade to kill the decimation faceting.
obj.scale = (1.0, DSY, DSZ)
bpy.ops.object.transform_apply(scale=True)
bpy.ops.object.shade_smooth()

# clean matte-black override (hide Meshy's baked screen/texture artifacts)
mb = bpy.data.materials.new("matte_black"); mb.use_nodes = True
b = mb.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.012, 0.012, 0.014, 1)
b.inputs["Roughness"].default_value = 0.6
obj.data.materials.clear(); obj.data.materials.append(mb)

# bbox (post-decimate)
mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for c in obj.bound_box:
    w = obj.matrix_world @ Vector(c)
    mn = Vector((min(mn[i], w[i]) for i in range(3)))
    mx = Vector((max(mx[i], w[i]) for i in range(3)))
center = (mn + mx) / 2
diag = (mx - mn).length
frontY = mn.y  # screen faces -Y (toward camera)

# emissive UI plane on the front
def screen_mat(img):
    m = bpy.data.materials.new("ui"); m.use_nodes = True
    bb = m.node_tree.nodes["Principled BSDF"]
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(img); tex.interpolation = "Cubic"
    m.node_tree.links.new(tex.outputs["Color"], bb.inputs["Emission Color"])
    bb.inputs["Emission Strength"].default_value = 1.7
    bb.inputs["Base Color"].default_value = (0, 0, 0, 1); bb.inputs["Roughness"].default_value = 1.0
    return m

bpy.ops.mesh.primitive_plane_add(size=1)
ui = bpy.context.object
ui.scale = (SW, SH, 1); bpy.ops.object.transform_apply(scale=True)
ui.rotation_euler = (math.radians(90), 0, 0); bpy.ops.object.transform_apply(rotation=True)
ui.location = (center.x + SX, frontY - PUSH, center.z + SZ)
ui.data.materials.clear(); ui.data.materials.append(screen_mat(UI))

# cinematic studio: dark reflective floor, near-black world, soft key + rim
bpy.ops.mesh.primitive_plane_add(size=diag * 14, location=(center.x, center.y, mn.z))
fm = bpy.data.materials.new("f"); fm.use_nodes = True
fb = fm.node_tree.nodes["Principled BSDF"]
fb.inputs["Base Color"].default_value = (0.018, 0.018, 0.022, 1); fb.inputs["Roughness"].default_value = 0.22
bpy.context.object.data.materials.append(fm)

w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
wbg = w.node_tree.nodes["Background"]
wbg.inputs["Color"].default_value = (0.02, 0.02, 0.028, 1); wbg.inputs["Strength"].default_value = 1.0

def sun(rot, e):
    ld = bpy.data.lights.new("s", "SUN"); ld.energy = e; ld.angle = math.radians(3)
    o = bpy.data.objects.new("s", ld); o.rotation_euler = rot; scene.collection.objects.link(o)

sun((math.radians(58), 0, math.radians(-42)), 1.4)    # soft key
sun((math.radians(118), 0, math.radians(28)), 3.0)    # rim / edge light

azr, elr = math.radians(AZ), math.radians(EL)
R = diag * 1.7
pos = Vector((center.x + R * math.sin(azr) * math.cos(elr),
              center.y - R * math.cos(azr) * math.cos(elr),
              center.z + R * math.sin(elr)))
cd = bpy.data.cameras.new("c"); cd.lens = 70
cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = pos
cam.rotation_euler = (center - pos).to_track_quat("-Z", "Y").to_euler()

engines = [e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
try: scene.eevee.taa_render_samples = 96
except Exception: pass
scene.render.resolution_x = 2000; scene.render.resolution_y = 1400
vt = [v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items]
scene.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
scene.render.filepath = OUT

if os.environ.get("XENEON_SAVE_GLB"):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True); ui.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.environ["XENEON_SAVE_GLB"], export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    print("SAVED GLB ->", os.environ["XENEON_SAVE_GLB"])

bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
