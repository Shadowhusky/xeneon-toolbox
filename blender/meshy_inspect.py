"""Import a Meshy .glb, report stats, and render a studio preview from a given
azimuth/elevation so we can see what the AI reconstructed.

  Blender --background --python meshy_inspect.py -- <glb> <out_png> [azimuth_deg] [elev_deg]
"""
import bpy, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB = argv[0]
OUT = argv[1]
AZ = float(argv[2]) if len(argv) > 2 else 35.0
EL = float(argv[3]) if len(argv) > 3 else 14.0

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)

meshes = [o for o in scene.objects if o.type == "MESH"]
tot = sum(len(o.data.polygons) for o in meshes)
print("OBJECTS", len(meshes), "POLYS", tot)

mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector((min(mn[i], w[i]) for i in range(3)))
        mx = Vector((max(mx[i], w[i]) for i in range(3)))
center = (mn + mx) / 2
diag = (mx - mn).length
print("DIMS", [round((mx - mn)[i], 3) for i in range(3)], "diag", round(diag, 3))

# floor
bpy.ops.mesh.primitive_plane_add(size=diag * 10, location=(center.x, center.y, mn.z))
fm = bpy.data.materials.new("f"); fm.use_nodes = True
bf = fm.node_tree.nodes["Principled BSDF"]
bf.inputs["Base Color"].default_value = (0.42, 0.42, 0.45, 1); bf.inputs["Roughness"].default_value = 0.5
bpy.context.object.data.materials.append(fm)

# world + scale-independent sun lighting
w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.6, 0.6, 0.63, 1); bg.inputs["Strength"].default_value = 0.8

def sun(rot, e):
    ld = bpy.data.lights.new("s", "SUN"); ld.energy = e
    o = bpy.data.objects.new("s", ld); o.rotation_euler = rot
    scene.collection.objects.link(o)

sun((math.radians(52), 0, math.radians(-35)), 3.2)
sun((math.radians(120), 0, math.radians(20)), 2.2)

# camera orbit
azr, elr = math.radians(AZ), math.radians(EL)
R = diag * 2.2
pos = Vector((center.x + R * math.sin(azr) * math.cos(elr),
              center.y - R * math.cos(azr) * math.cos(elr),
              center.z + R * math.sin(elr)))
cd = bpy.data.cameras.new("c"); cd.lens = 50
cam = bpy.data.objects.new("c", cd); scene.collection.objects.link(cam); scene.camera = cam
cam.location = pos
cam.rotation_euler = (center - pos).to_track_quat("-Z", "Y").to_euler()

engines = [e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
scene.render.resolution_x = 1500; scene.render.resolution_y = 1050
vt = [v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items]
scene.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
