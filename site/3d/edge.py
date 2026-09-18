"""Parametric Corsair Xeneon Edge hero asset, built headless in Blender 5.x.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python site/3d/edge.py -- \
        --screen docs/img/dashboard.png --out site/assets/3d

Writes edge.glb (mesh "Screen" / material "ScreenEmissive" carry the swappable
screenshot), hero.png, hero-alpha.png, front.png and detail.png.

Options: --samples N, --scale PCT (resolution %), --only glb,hero,front,detail
"""

import argparse
import json
import math
import os
import struct
import sys
import time

import bpy
import bmesh
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MM = 0.001

# Panel (mm)
ACTIVE_W, ACTIVE_H = 373.0, 105.0
BEZEL = 6.0
W, H = ACTIVE_W + 2 * BEZEL, ACTIVE_H + 2 * BEZEL
T = 12.0
R_CORNER = 4.0
LIP = 1.2            # flat rim between chamfer and glass
CHAMFER = 0.7
RECESS = 0.95        # glass pocket depth
R_BACK = 2.0         # rear edge rounding
GLASS_FRONT = -0.35  # glass sits slightly proud of the lip
GLASS_BACK = 0.65
GLASS_GAP = 0.06     # clearance to the pocket wall
GLASS_EDGE = 0.3
SCREEN_Y = 0.75
TILT = math.radians(12.0)

# Stand (mm)
FOOT_W, FOOT_D, FOOT_H = 150.0, 80.0, 7.0
FOOT_FRONT_Y = -10.0
FOOT_R = 9.0
ARM_W, ARM_T = 70.0, 6.0
ARM_TOP = 66.0
ARM_BOTTOM = -4.4
PIVOT_Z = FOOT_H + 5.0

CARBON = "#0A0B0D"


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.clip(c, 0, None), 1 / 2.4) - 0.055)


def hex_linear(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def rounded_rect(w, h, r, segs=10, guard=0.25):
    """CCW outline of a w x h rounded rectangle centred on the origin.

    Every corner arc is bracketed by a short guard segment so the long flat
    sides keep exact vertex normals under smooth shading."""
    r = max(r, 0.02)
    guard = min(guard, r * 0.5)
    cx, cy = w / 2 - r, h / 2 - r
    corners = [((cx, -cy), -90.0), ((cx, cy), 0.0), ((-cx, cy), 90.0), ((-cx, -cy), 180.0)]
    pts = []
    for (ox, oy), a0 in corners:
        arc = []
        for k in range(segs + 1):
            a = math.radians(a0 + 90.0 * k / segs)
            arc.append((ox + r * math.cos(a), oy + r * math.sin(a)))
        t0 = math.radians(a0)
        t1 = math.radians(a0 + 90.0)
        before = (arc[0][0] + guard * math.sin(t0), arc[0][1] - guard * math.cos(t0))
        after = (arc[-1][0] - guard * math.sin(t1), arc[-1][1] + guard * math.cos(t1))
        pts += [before] + arc + [after]
    return pts


def offset_rect(w, h, r, off, segs=10):
    return rounded_rect(w + 2 * off, h + 2 * off, r + off, segs)


def loft_solid(name, loops, sharp_rings, materials, cap_material=(0, 0), uv_scale=0.06):
    """Closed solid through equal-count loops. loops[0] is wound so its cap normal
    points against the extrusion direction; side quads follow from that."""
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector(p) * MM) for p in loop] for loop in loops]
    n = len(rings[0])
    faces = []
    front = bm.faces.new(rings[0])
    front.material_index = cap_material[0]
    back = bm.faces.new(list(reversed(rings[-1])))
    back.material_index = cap_material[1]
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    for f in bm.faces:
        f.smooth = True
    for idx in sharp_rings:
        ring = rings[idx]
        for i in range(n):
            e = bm.edges.get((ring[i], ring[(i + 1) % n]))
            if e:
                e.smooth = False
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        nx, ny, nz = (abs(c) for c in f.normal)
        for lp in f.loops:
            co = lp.vert.co
            if nx >= ny and nx >= nz:
                lp[uv].uv = (co.y / uv_scale, co.z / uv_scale)
            elif ny >= nz:
                lp[uv].uv = (co.x / uv_scale, co.z / uv_scale)
            else:
                lp[uv].uv = (co.x / uv_scale, co.y / uv_scale)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def xz(loop2d, y):
    return [(u, y, v) for u, v in loop2d]


def xy(loop2d, z):
    return [(u, v, z) for u, v in reversed(loop2d)]


def principled(name, **kw):
    mat = bpy.data.materials.new(name)
    nodes = mat.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        out = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
        mat.node_tree.links.new(bsdf.outputs[0], out.inputs[0])
    for k, v in kw.items():
        bsdf.inputs[k].default_value = v
    return mat, bsdf


def value_noise(size, seed=7):
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size), dtype=np.float32)
    for cells, amp in ((6, 1.0), (12, 0.6), (24, 0.35), (48, 0.2), (128, 0.12), (256, 0.08)):
        g = rng.random((cells, cells)).astype(np.float32)
        x = np.arange(size, dtype=np.float32) * cells / size
        ix = np.floor(x).astype(int)
        fx = (x - ix)
        fx = fx * fx * (3 - 2 * fx)
        ix0, ix1 = ix % cells, (ix + 1) % cells
        gx = g[:, ix0] * (1 - fx) + g[:, ix1] * fx        # (cells, size)
        gxy = gx[ix0, :] * (1 - fx)[:, None] + gx[ix1, :] * fx[:, None]
        out += amp * gxy
    out -= out.min()
    out /= out.max()
    return out


def roughness_image(name, size=512, centre=0.52, spread=0.14):
    n = value_noise(size)
    r = centre + (n - 0.5) * spread
    rgba = np.empty((size * size, 4), dtype=np.float32)
    rgba[:, 0] = rgba[:, 1] = rgba[:, 2] = r.reshape(-1)
    rgba[:, 3] = 1.0
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(rgba.reshape(-1))
    img.pack()
    return img


def build_materials(screen_path):
    mats = {}
    housing, b = principled("HousingMatte", **{
        "Base Color": (0.012, 0.012, 0.0135, 1), "Metallic": 0.0, "Roughness": 0.5,
        "Specular IOR Level": 0.4})
    tex = housing.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = roughness_image("HousingRoughness")
    tex.location = (-400, 0)
    housing.node_tree.links.new(tex.outputs["Color"], b.inputs["Roughness"])
    mats["housing"] = housing

    mats["bezel"], _ = principled("BezelInk", **{
        "Base Color": (0.002, 0.002, 0.0025, 1), "Roughness": 0.32, "Specular IOR Level": 0.4})

    glass, gb = principled("Glass", **{
        "Base Color": (0.004, 0.004, 0.005, 1), "Metallic": 0.0, "Roughness": 0.09,
        "IOR": 1.52, "Alpha": 0.26, "Specular IOR Level": 0.55})
    glass.surface_render_method = "BLENDED"
    glass.use_backface_culling = False
    mats["glass"] = glass

    screen, sb = principled("ScreenEmissive", **{
        "Base Color": (0, 0, 0, 1), "Roughness": 1.0, "Specular IOR Level": 0.0,
        "Emission Strength": 1.7})
    img = bpy.data.images.load(screen_path, check_existing=True)
    img.colorspace_settings.name = "sRGB"
    tex = screen.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Cubic"
    tex.extension = "CLIP"
    tex.location = (-400, 0)
    screen.node_tree.links.new(tex.outputs["Color"], sb.inputs["Emission Color"])
    mats["screen"] = screen

    mats["alu"], _ = principled("Aluminium", **{
        "Base Color": (0.62, 0.63, 0.65, 1), "Metallic": 1.0, "Roughness": 0.36})
    return mats


def build_product(mats):
    root = bpy.data.objects.new("XeneonEdge", None)
    panel = bpy.data.objects.new("Panel", None)
    stand = bpy.data.objects.new("Stand", None)
    for e in (root, panel, stand):
        bpy.context.scene.collection.objects.link(e)
    panel.parent = root
    stand.parent = root
    panel.location = (0, 0, PIVOT_Z * MM)
    panel.rotation_euler = (-TILT, 0, 0)

    # Housing: pocket floor -> pocket wall -> lip -> chamfer -> side -> rounded back
    loops = [
        xz(offset_rect(W, H, R_CORNER, -LIP), RECESS),
        xz(offset_rect(W, H, R_CORNER, -LIP), 0.0),
        xz(offset_rect(W, H, R_CORNER, -CHAMFER), 0.0),
        xz(offset_rect(W, H, R_CORNER, 0.0), CHAMFER),
        xz(offset_rect(W, H, R_CORNER, 0.0), T - R_BACK - 0.3),
    ]
    sharp = [0, 1, 2, 3]
    for k in range(7):
        a = math.radians(90.0 * k / 6)
        loops.append(xz(offset_rect(W, H, R_CORNER, -R_BACK * (1 - math.cos(a))), T - R_BACK + R_BACK * math.sin(a)))
    housing = loft_solid("Housing", loops, sharp, [mats["housing"], mats["bezel"]], cap_material=(1, 0))

    g_off = -LIP - GLASS_GAP
    loops = [xz(offset_rect(W, H, R_CORNER, g_off - GLASS_EDGE), GLASS_FRONT)]
    for k in range(1, 4):
        a = math.radians(90.0 * k / 3)
        loops.append(xz(offset_rect(W, H, R_CORNER, g_off - GLASS_EDGE + GLASS_EDGE * math.sin(a)),
                        GLASS_FRONT + GLASS_EDGE - GLASS_EDGE * math.cos(a)))
    loops.append(xz(offset_rect(W, H, R_CORNER, g_off), GLASS_BACK))
    glass = loft_solid("Glass", loops, [len(loops) - 1], [mats["glass"]])

    bm = bmesh.new()
    hw, hh = ACTIVE_W / 2 * MM, ACTIVE_H / 2 * MM
    y = SCREEN_Y * MM
    vs = [bm.verts.new(v) for v in ((-hw, y, -hh), (hw, y, -hh), (hw, y, hh), (-hw, y, hh))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UVMap")
    for lp, st in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp[uv].uv = st
    me = bpy.data.meshes.new("Screen")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mats["screen"])
    screen = bpy.data.objects.new("Screen", me)
    bpy.context.scene.collection.objects.link(screen)

    for ob in (housing, glass, screen):
        ob.parent = panel
        ob.location = (0, 0, H / 2 * MM)

    # Foot: flat aluminium slab, small chamfer below, soft rounding on top
    fr = 2.5
    loops = [xy(offset_rect(FOOT_W, FOOT_D, FOOT_R, -0.4), 0.0),
             xy(offset_rect(FOOT_W, FOOT_D, FOOT_R, 0.0), 0.4),
             xy(offset_rect(FOOT_W, FOOT_D, FOOT_R, 0.0), FOOT_H - fr - 0.3)]
    for k in range(5):
        a = math.radians(90.0 * k / 4)
        loops.append(xy(offset_rect(FOOT_W, FOOT_D, FOOT_R, -fr * (1 - math.cos(a))), FOOT_H - fr + fr * math.sin(a)))
    foot = loft_solid("StandFoot", loops, [0, 1], [mats["alu"]])
    foot.parent = stand
    foot.location = (0, (FOOT_FRONT_Y + FOOT_D / 2) * MM, 0)

    # Arm: plate parallel to the panel back, sunk into the housing and the foot
    ah = ARM_TOP - ARM_BOTTOM
    ar = 1.0
    y0, y1 = T - 0.5, T - 0.5 + ARM_T
    loops = [xz(offset_rect(ARM_W, ah, 8.0, 0.0), y0),
             xz(offset_rect(ARM_W, ah, 8.0, 0.0), y1 - ar - 0.2)]
    for k in range(5):
        a = math.radians(90.0 * k / 4)
        loops.append(xz(offset_rect(ARM_W, ah, 8.0, -ar * (1 - math.cos(a))), y1 - ar + ar * math.sin(a)))
    arm = loft_solid("StandArm", loops, [0], [mats["alu"]])
    arm.parent = stand
    arm.location = (0, 0, PIVOT_Z * MM)
    arm.rotation_euler = (-TILT, 0, 0)
    arm.delta_location = (0, 0, (ARM_BOTTOM + ah / 2) * MM)

    return root, [housing, glass, screen, foot, arm]


def build_studio(product):
    sc = bpy.context.scene
    world = sc.world or bpy.data.worlds.new("World")
    sc.world = world
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.004, 0.004, 0.004, 1)
    bg.inputs["Strength"].default_value = 1.0

    floor_mat, fb = principled("StudioFloor", **{
        "Base Color": (0.005, 0.005, 0.005, 1), "Roughness": 0.12, "Specular IOR Level": 0.5})
    nt = floor_mat.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeVectorMath")
    sep.operation = "LENGTH"
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = 0.3
    rng.inputs["From Max"].default_value = 0.68
    rng.interpolation_type = "SMOOTHSTEP"
    mix = nt.nodes.new("ShaderNodeMixShader")
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Value"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(fb.outputs[0], mix.inputs[1])
    nt.links.new(transp.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])

    bm = bmesh.new()
    s = 3.0
    f = bm.faces.new([bm.verts.new(v) for v in ((-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0))])
    me = bpy.data.meshes.new("StudioFloor")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(floor_mat)
    floor = bpy.data.objects.new("StudioFloor", me)
    sc.collection.objects.link(floor)

    def area(name, loc, target, size, energy, color, spread=180.0):
        ld = bpy.data.lights.new(name, "AREA")
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = size
        ld.energy = energy
        ld.color = color
        ld.spread = math.radians(spread)
        ob = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        aim(ob, target)
        return ob

    centre = (0, 0.01, 0.07)
    key = area("KeyLight", (-0.55, -0.62, 0.78), centre, (1.1, 0.7), 85.0, (1.0, 0.975, 0.94), 120)
    rim = area("RimLight", (0.55, 0.5, 0.45), (0.12, 0.02, 0.09), (0.2, 0.5), 13.0, hex_linear("#F5B544"), 70)
    fill = area("FillLight", (0.9, -0.7, 0.6), centre, (2.0, 2.0), 3.0, (1.0, 0.98, 0.96), 180)
    # The rim only touches the product, so the floor stays carbon black
    receivers = bpy.data.collections.new("RimReceivers")
    for ob in product:
        receivers.objects.link(ob)
    rim.light_linking.receiver_collection = receivers
    return floor, [key, rim, fill]


def aim(ob, target):
    d = Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def bbox_points(objects):
    bpy.context.view_layer.update()
    pts = []
    for ob in objects:
        pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    return pts


def fit_camera(cam, centre, direction, lens, points, margin=(0.08, 0.08)):
    sc = bpy.context.scene
    cam.data.lens = lens
    direction = Vector(direction).normalized()
    centre = Vector(centre)
    lo, hi = 0.05, 8.0
    for _ in range(36):
        d = (lo + hi) / 2
        cam.location = centre + direction * d
        aim(cam, centre)
        bpy.context.view_layer.update()
        ok = True
        for p in points:
            x, y, z = world_to_camera_view(sc, cam, p)
            if z <= 0 or x < margin[0] or x > 1 - margin[0] or y < margin[1] or y > 1 - margin[1]:
                ok = False
                break
        if ok:
            hi = d
        else:
            lo = d
    cam.location = centre + direction * hi
    aim(cam, centre)
    bpy.context.view_layer.update()
    return hi


def setup_render(samples, scale):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        gpu = False
        for d in prefs.devices:
            d.use = d.type == "METAL"
            gpu |= d.use
        sc.cycles.device = "GPU" if gpu else "CPU"
    except Exception:
        sc.cycles.device = "CPU"
    cy = sc.cycles
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.008
    cy.use_denoising = True
    cy.denoiser = "OPENIMAGEDENOISE"
    cy.denoising_use_gpu = True
    cy.max_bounces = 10
    cy.glossy_bounces = 6
    cy.transparent_max_bounces = 12
    cy.sample_clamp_indirect = 8.0
    cy.blur_glossy = 0.5
    sc.render.use_persistent_data = True
    sc.render.resolution_x, sc.render.resolution_y = 2400, 1350
    sc.render.resolution_percentage = scale
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.image_settings.compression = 40
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    print(f"[edge] cycles on {sc.cycles.device}, {samples} samples, {scale}%")


def render_to(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"[edge] rendered {os.path.basename(path)} in {time.time() - t:.1f}s")


def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    px = px.reshape(h, w, 4)
    rgb = np.where(px[..., :3] <= 0.04045, px[..., :3] / 12.92, np.power((px[..., :3] + 0.055) / 1.055, 2.4))
    return rgb, px[..., 3:4]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def composite(product_png, floor_png, dst, bg_hex):
    """bg <- floor (alpha faded at the left/right/bottom frame edges) <- product."""
    prgb, pa = load_rgba(product_png)
    frgb, fa = load_rgba(floor_png)
    h, w = pa.shape[:2]
    x = (np.arange(w, dtype=np.float32) + 0.5) / w
    y = (np.arange(h, dtype=np.float32) + 0.5) / h
    fade = (smoothstep(0.0, 0.12, x) * smoothstep(0.0, 0.12, 1 - x))[None, :, None] * smoothstep(0.0, 0.18, y)[:, None, None]
    fa = fa * fade
    lin = np.array(hex_linear(bg_hex), dtype=np.float32)[None, None, :]
    lin = frgb * fa + lin * (1 - fa)
    lin = prgb * pa + lin * (1 - pa)
    out = np.empty((h, w, 4), dtype=np.float32)
    out[..., :3] = linear_to_srgb(lin)
    out[..., 3] = 1.0
    res = bpy.data.images.new("composite", w, h, alpha=False)
    res.pixels.foreach_set(out.reshape(-1))
    res.filepath_raw = dst
    res.file_format = "PNG"
    res.save()
    bpy.data.images.remove(res)


def export_glb(path, objects):
    for ob in bpy.context.scene.objects:
        ob.select_set(False)
    for ob in objects:
        ob.select_set(True)
        p = ob.parent
        while p:
            p.select_set(True)
            p = p.parent
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_materials="EXPORT", export_image_format="AUTO", export_yup=True,
        export_lights=False, export_cameras=False, export_animations=False,
        export_texcoords=True, export_normals=True, export_extras=False)
    with open(path, "rb") as fh:
        magic, _, _ = struct.unpack("<III", fh.read(12))
        length, ctype = struct.unpack("<II", fh.read(8))
        doc = json.loads(fh.read(length))
    print(f"[edge] glb {os.path.getsize(path) / 1e6:.2f} MB; nodes={[n.get('name') for n in doc['nodes']]}")
    print(f"[edge] glb meshes={[m.get('name') for m in doc['meshes']]} materials={[m.get('name') for m in doc['materials']]}")
    print(f"[edge] glb images={len(doc.get('images', []))} extensions={doc.get('extensionsUsed', [])}")
    for m in doc["materials"]:
        if m.get("name") == "Glass":
            print(f"[edge] glass alphaMode={m.get('alphaMode')}")
        if m.get("name") == "ScreenEmissive":
            print(f"[edge] screen emissive={m.get('emissiveFactor')} tex={'emissiveTexture' in m} strength={m.get('extensions', {}).get('KHR_materials_emissive_strength')}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", default=os.path.join(ROOT, "docs", "img", "dashboard.png"))
    ap.add_argument("--out", default=os.path.join(ROOT, "site", "assets", "3d"))
    ap.add_argument("--samples", type=int, default=128)
    ap.add_argument("--scale", type=int, default=100)
    ap.add_argument("--only", default="glb,hero,front,detail")
    args = ap.parse_args(argv)
    only = set(args.only.split(","))

    screen = args.screen if os.path.isabs(args.screen) else (
        args.screen if os.path.exists(args.screen) else os.path.join(ROOT, args.screen))
    screen = os.path.abspath(screen)
    if not os.path.exists(screen):
        sys.exit(f"screen image not found: {screen}")
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    print(f"[edge] blender {bpy.app.version_string}; screen={screen}; out={out}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0

    mats = build_materials(screen)
    root, product = build_product(mats)
    floor, lights = build_studio(product)
    setup_render(args.samples, args.scale)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.sensor_width = 36.0
    cam_data.clip_start = 0.01
    cam_data.clip_end = 20.0
    cam = bpy.data.objects.new("Camera", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam

    housing, glass, screen_ob, foot, arm = product
    bpy.context.view_layer.update()
    panel_pts = bbox_points([housing])
    stand_pts = bbox_points([foot])
    panel_mat = housing.matrix_world

    if "glb" in only:
        export_glb(os.path.join(out, "edge.glb"), product)

    tmp_product = os.path.join(out, ".tmp-product.png")
    tmp_floor = os.path.join(out, ".tmp-floor.png")

    def shoot(name, product_png):
        """Two passes: the product alone, then the floor with the product held out."""
        floor.hide_render = True
        render_to(product_png)
        floor.hide_render = False
        for ob in product:
            ob.is_holdout = True
        render_to(tmp_floor)
        for ob in product:
            ob.is_holdout = False
        composite(product_png, tmp_floor, os.path.join(out, name + ".png"), CARBON)

    if "hero" in only:
        az, el = math.radians(-34.0), math.radians(13.0)
        direction = (math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))
        centre = panel_mat @ Vector((0, T / 2 * MM, 0))
        cam_data.shift_x = 0.0
        cam_data.shift_y = -0.055
        cam_data.dof.use_dof = False
        d = fit_camera(cam, centre, direction, 50.0, panel_pts + stand_pts, (0.06, 0.12))
        cam_data.dof.use_dof = True
        cam_data.dof.focus_distance = d
        cam_data.dof.aperture_fstop = 8.0
        shoot("hero", os.path.join(out, "hero-alpha.png"))
    if "front" in only:
        normal = (panel_mat.to_3x3() @ Vector((0, -1, 0))).normalized()
        centre = panel_mat @ Vector((0, 0, 0))
        cam_data.shift_x = 0.0
        cam_data.shift_y = -0.02
        cam_data.dof.use_dof = False
        fit_camera(cam, centre, normal, 85.0, panel_pts, (0.045, 0.1))
        shoot("front", tmp_product)
    if "detail" in only:
        corner = panel_mat @ Vector(((-W / 2 + 12.0) * MM, 0.0, (H / 2 - 9.0) * MM))
        az, el = math.radians(-45.0), math.radians(22.0)
        direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
        cam_data.lens = 100.0
        cam_data.shift_x = 0.0
        cam_data.shift_y = 0.0
        dist = 0.24
        cam.location = corner + direction * dist
        aim(cam, corner)
        cam_data.dof.use_dof = True
        cam_data.dof.focus_distance = dist
        cam_data.dof.aperture_fstop = 5.6
        shoot("detail", tmp_product)
    for p in (tmp_product, tmp_floor):
        if os.path.exists(p):
            os.remove(p)

    for name in ("edge.glb", "hero.png", "hero-alpha.png", "front.png", "detail.png"):
        p = os.path.join(out, name)
        if os.path.exists(p):
            print(f"[edge] {name}: {os.path.getsize(p) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
