# Xeneon Edge — 3D mockup pipeline

A Blender model of the Corsair Xeneon Edge with the app's UI mapped onto the
screen, for product mockups and dynamic web demos. The device is modeled from
Corsair product photography: a 372×120×22 mm matte-black slab, glossy 32:9
screen offset toward the left with thin bezels, the signature vertical oval
cutout through the right-end section, and a low magnetic wedge stand at a slight
backward tilt.

## 1. Export a high-res UI texture (vector-crisp, 3×)

The Edge panel is only 2560×720, so instead of screen-capturing it, the app
renders any screen off-screen via `ImageRenderer` at 3× (→ 7680×2160):

```bash
# XENEON_RENDER="route@scale@warmupSeconds@/abs/out.png"
env XENEON_RENDER="dashboard@3@8@$PWD/blender/textures/hd-dashboard.png" .build/release/XeneonToolbox
env XENEON_RENDER="assistant@3@2@$PWD/blender/textures/hd-assistant.png" .build/release/XeneonToolbox
env XENEON_RENDER="minimal@3@5@$PWD/blender/textures/hd-minimal.png"   .build/release/XeneonToolbox
```

Routes: `dashboard`, `assistant`, `minimal`, `sleep`, `clock`.

## 2. Render a mockup

```bash
BL=/Applications/Blender.app/Contents/MacOS/Blender
# args: <ui_png> <out_png> [angle: hero|front|left] [vertical_res]
"$BL" --background --python blender/xeneon_mockup.py -- \
    "$PWD/blender/textures/hd-dashboard.png" "$PWD/docs/mockup-dashboard-hero.png" hero 1600
```

Swap the UI texture to demo any screen — that's the "dynamic" part: one model,
any UI. Set `XENEON_SAVE_BLEND=/abs/xeneon-edge.blend` to also write a
self-contained `.blend` (textures packed) you can open, tweak, or export to
glTF for a web (Three.js / `<model-viewer>`) demo.

Working textures (`blender/textures/`) and reference photos (`blender/ref/`) are
git-ignored — regenerate them with step 1.
