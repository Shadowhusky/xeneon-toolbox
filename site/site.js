import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";
import { initLanguage, setVersion } from "./i18n.js";

initLanguage();

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const damp = (cur, target, lambda, dt) => reduce ? target : cur + (target - cur) * (1 - Math.exp(-lambda * dt));
const AMBER = new THREE.Color(0xf5b544);

// ---------- Boot ring (48 ticks, the app's gauge)
const bootTicks = [];
{
  const g = document.getElementById("boot-ticks");
  for (let i = 0; i < 48; i++) {
    const a = (-225 + (270 * i) / 47) * Math.PI / 180;
    const l = document.createElementNS("http://www.w3.org/2000/svg", "line");
    l.setAttribute("x1", 100 + 74 * Math.cos(a)); l.setAttribute("y1", 100 + 74 * Math.sin(a));
    l.setAttribute("x2", 100 + 92 * Math.cos(a)); l.setAttribute("y2", 100 + 92 * Math.sin(a));
    l.setAttribute("class", "tick"); g.appendChild(l); bootTicks.push(l);
  }
}
const bootProgress = (p) => bootTicks.forEach((t, i) => t.classList.toggle("lit", i < Math.round(p * 48)));

// ---------- The panel's geometry, in the model's own metres (see site/3d/edge.py)
const S = 3.2 / 0.385;                 // world units per metre: the panel is 3.2 wide
const SCREEN = { w: 0.373, h: 0.105, y: 0.0585 };
const IMG = { w: 2560, h: 720 };
// Dashboard tiles as pixel rects in the 2560 × 720 capture: [x0, y0, x1, y1]
const TILE_RECTS = {
  clock: [132, 19, 418, 700], cpu: [435, 19, 721, 351], gpu: [738, 19, 1024, 351], memory: [1041, 19, 1327, 351],
  network: [1344, 19, 1933, 351], storage: [1949, 19, 2236, 351], power: [2253, 19, 2540, 351],
  upNext: [435, 369, 1024, 700], tasks: [1041, 369, 1327, 700], thermals: [1344, 369, 1631, 700],
  running: [1647, 369, 2236, 700], nowPlaying: [2253, 369, 2540, 700],
};
const FOCUS = ["cpu", "upNext", "running", "nowPlaying", "clock"];
const STRIP = ["dashboard", "deck", "clock", "assistant", "control-center", "boost"];
const HERO = ["dashboard", "deck", "clock", "assistant", "control-center"];
const SCREENS = ["dashboard", "deck", "clock", "assistant", "control-center", "boost", "minimal"];

const screenShader = {
  vertex: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragment: `
    uniform sampler2D texA, texB; uniform float mixT, power, time, dim, gain; uniform vec3 ripples[4];
    varying vec2 vUv;
    const vec3 WARM = vec3(1.0, 0.92, 0.80);
    float ease(float x){ x = clamp(x, 0.0, 1.0); return x * x * x * (x * (6.0 * x - 15.0) + 10.0); }
    // One soft front travels across the glass; every point has its own moment inside it.
    float wave(vec2 uv, float t){ return ease(t * 1.62 - (uv.x * 0.86 + uv.y * 0.14) * 0.62); }
    // A page seen at a given depth: scaled about the centre, and out of focus by mip bias.
    vec3 page(sampler2D tex, vec2 uv, float scale, float blur){
      vec2 p = 0.5 + (uv - 0.5) / scale;
      vec2 edge = smoothstep(vec2(0.0), vec2(0.004, 0.012), p) * smoothstep(vec2(0.0), vec2(0.004, 0.012), 1.0 - p);
      return texture2D(tex, p, blur).rgb * edge.x * edge.y;
    }
    void main(){
      vec2 uv = vUv; float glow = 0.0;
      // A touch bends the picture like a drop on water, then settles.
      for (int i = 0; i < 4; i++) {
        float t = time - ripples[i].z;
        if (t > 0.0 && t < 1.8) {
          vec2 d = (uv - ripples[i].xy) * vec2(3.552, 1.0);
          float r = length(d) + 1e-4, front = t * 0.5, life = 1.0 - t / 1.8;
          float w = sin((r - front) * 40.0) * exp(-abs(r - front) * 11.0) * life * life;
          uv += (d / r) * w * 0.005 / vec2(3.552, 1.0);
          glow += exp(-r * r * 30.0) * (1.0 - smoothstep(0.0, 0.8, t)) * 0.16 + max(w, 0.0) * 0.07;
        }
      }
      vec3 col;
      if (power < 0.999) {
        float pw = wave(uv, power);
        col = page(texA, uv, mix(1.12, 1.0, pw), (1.0 - pw) * 5.0) * pw;
        col += vec3(0.5, 0.58, 0.7) * 0.03 * smoothstep(0.0, 0.35, power) * (1.0 - pw);      // the backlight swells first
        col += WARM * sin(pw * 3.14159) * 0.06;
      } else {
        float p = wave(uv, mixT), turning = sin(p * 3.14159) * step(0.001, mixT) * step(mixT, 0.999);
        vec3 leaving = page(texA, uv, mix(1.0, 0.92, p), p * 4.5) * (1.0 - smoothstep(0.0, 0.6, p));
        vec3 arriving = page(texB, uv, mix(1.1, 1.0, p), (1.0 - p) * 4.5) * smoothstep(0.3, 1.0, p);
        col = leaving + arriving + WARM * turning * 0.045;
      }
      col += WARM * glow;
      gl_FragColor = vec4(col * gain * (1.0 - dim * 0.88), 1.0);
    }`,
};

// A glowing frame that draws itself around a layer of the exploded panel.
const frameShader = {
  fragment: `
    uniform vec2 size; uniform float radius, progress, strength, time; varying vec2 vUv;
    void main(){
      vec2 p = (vUv - 0.5) * (size + 0.016), q = abs(p) - size * 0.5 + radius;
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
      float stroke = 1.0 - smoothstep(0.0, 0.00028, abs(d));
      float halo = exp(-abs(d) * 1400.0) * 0.12;
      float ang = atan(p.y, -p.x) / 6.28318 + 0.5;
      float drawn = 1.0 - smoothstep(progress * 1.3 - 0.3, progress * 1.3, ang);
      float g = fract(ang - time * 0.05);
      float glint = exp(-g * g * 260.0) + exp(-(1.0 - g) * (1.0 - g) * 260.0);
      vec3 col = vec3(0.93, 0.91, 0.88) * (stroke * 0.42 + halo) + vec3(0.96, 0.62, 0.16) * glint * (stroke * 1.5 + halo * 2.0);
      gl_FragColor = vec4(col * drawn * strength, 1.0);
    }`,
};

const tileShader = {
  vertex: screenShader.vertex,
  fragment: `
    uniform sampler2D map; uniform vec4 rect; uniform vec2 size; uniform float radius, opacity, gain;
    varying vec2 vUv;
    void main(){
      vec2 p = (vUv - 0.5) * size, q = abs(p) - size * 0.5 + radius;
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
      float alpha = 1.0 - smoothstep(-0.0005, 0.0005, d);
      if (alpha * opacity < 0.01) discard;
      vec2 uv = vec2(mix(rect.x, rect.z, vUv.x), mix(rect.w, rect.y, vUv.y));
      vec3 col = texture2D(map, uv).rgb * gain;
      col += vec3(1.0) * 0.06 * smoothstep(-0.0016, -0.0002, d);     // a lit edge, like the app's bezel
      gl_FragColor = vec4(col, alpha * opacity);
    }`,
};

async function world() {
  const canvas = document.getElementById("world");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: "high-performance" });
  // Retina canvases are where the time goes: render to a pixel budget, and shrink it if frames run long.
  const small = () => innerWidth < 900 || innerHeight < 620;
  let quality = 1;
  const pixelRatio = () => clamp(Math.sqrt((small() ? 1.5e6 : 2.5e6) * quality / (innerWidth * innerHeight)), 0.7, Math.min(devicePixelRatio, 2));
  renderer.setPixelRatio(pixelRatio());
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0a0b0d);
  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.45;
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);

  const target = new THREE.WebGLRenderTarget(2, 2, { type: THREE.HalfFloatType, samples: small() ? 2 : 4 });
  const composer = new EffectComposer(renderer, target);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(2, 2), 0.45, 0.75, 0.9);
  composer.addPass(bloom);
  const film = new ShaderPass({
    uniforms: { tDiffuse: { value: null }, time: { value: 0 } },
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform sampler2D tDiffuse; uniform float time; varying vec2 vUv;
      void main(){ vec4 c = texture2D(tDiffuse, vUv); vec2 q = (vUv - 0.5) * vec2(1.0, 0.86);
        c.rgb *= mix(0.55, 1.0, smoothstep(0.9, 0.28, length(q)));
        c.rgb += (fract(sin(dot(vUv * (time + 1.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.014;
        gl_FragColor = c; }`,
  });
  composer.addPass(film);
  composer.addPass(new OutputPass());

  // ----- Assets
  let loaded = 0; const total = SCREENS.length + 1;
  const tick = () => bootProgress(++loaded / total);
  const texLoader = new THREE.TextureLoader();
  const textures = {};
  const jobs = SCREENS.map(async (name) => {
    const t = await texLoader.loadAsync(`assets/screens/${name}.webp`);
    t.colorSpace = THREE.SRGBColorSpace; t.flipY = false; t.anisotropy = renderer.capabilities.getMaxAnisotropy();
    t.generateMipmaps = true; t.minFilter = THREE.LinearMipmapLinearFilter;
    textures[name] = t; tick();
  });
  const gltfJob = new GLTFLoader().loadAsync("assets/3d/edge.glb").then((g) => { tick(); return g; });
  const [gltf] = await Promise.all([gltfJob, ...jobs]);

  // ----- The panel
  const rig = new THREE.Group(); rig.scale.setScalar(S); rig.add(gltf.scene); scene.add(rig);
  const node = (n) => gltf.scene.getObjectByName(n);
  const panel = node("Panel"), glass = node("Glass"), housing = node("Housing"), screenMesh = node("Screen"), stand = node("Stand");
  const rest = { glass: glass.position.z, housing: housing.position.z, screen: screenMesh.position.z, stand: stand.position.z };

  const screenMat = new THREE.ShaderMaterial({
    vertexShader: screenShader.vertex, fragmentShader: screenShader.fragment,
    uniforms: {
      texA: { value: textures.dashboard }, texB: { value: textures.dashboard }, mixT: { value: 0 }, power: { value: 0 },
      time: { value: 0 }, dim: { value: 0 }, gain: { value: 1.35 },
      ripples: { value: [0, 1, 2, 3].map(() => new THREE.Vector3(0, 0, -10)) },
    },
  });
  screenMesh.material = screenMat;
  gltf.scene.traverse((o) => {
    if (!o.isMesh) return;
    if (o.material.name === "Glass") { o.material.envMapIntensity = 0.16; o.material.roughness = 0.3; o.material.specularIntensity = 0.25; }
    if (o.material.name === "BezelInk") { o.material.roughness = 0.75; o.material.envMapIntensity = 0.1; }
    if (o.material.name === "Aluminium") { o.material.color.setHex(0x80848a); o.material.envMapIntensity = 0.6; }
  });

  // A mirrored twin under a translucent floor gives the reflection (made before the tiles exist).
  const mirror = small() ? null : rig.clone(true);
  if (mirror) { mirror.scale.y *= -1; scene.add(mirror); }
  const fade = document.createElement("canvas"); fade.width = fade.height = 256;
  { const c = fade.getContext("2d"), g = c.createRadialGradient(128, 128, 10, 128, 128, 128);
    g.addColorStop(0, "#fff"); g.addColorStop(0.35, "#d0d0d0"); g.addColorStop(0.7, "#3a3a3a"); g.addColorStop(1, "#000"); c.fillStyle = g; c.fillRect(0, 0, 256, 256); }
  const floor = new THREE.Mesh(new THREE.CircleGeometry(9, 64), new THREE.MeshStandardMaterial({
    color: 0x050608, roughness: 0.42, metalness: 0.55, envMapIntensity: 0.15, transparent: true, opacity: 0.9, alphaMap: new THREE.CanvasTexture(fade), depthWrite: false }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = 0.001; floor.renderOrder = 1; scene.add(floor);

  // Frames that draw themselves around each layer of the exploded panel.
  const frameFor = (of, w, h, z) => {
    const mat = new THREE.ShaderMaterial({
      vertexShader: screenShader.vertex, fragmentShader: frameShader.fragment, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      uniforms: { size: { value: new THREE.Vector2(w * 2, h * 2) }, radius: { value: 0.004 }, progress: { value: 0 }, strength: { value: 0 }, time: { value: 0 } },
    });
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w * 2 + 0.016, h * 2 + 0.016), mat);
    mesh.position.z = z; mesh.visible = false; mesh.renderOrder = 4; of.add(mesh);
    return { mesh, mat };
  };
  const frames = [frameFor(glass, 0.1912, 0.0572, 0.0012), frameFor(screenMesh, 0.1865, 0.0525, 0.0002), frameFor(housing, 0.1925, 0.0585, -0.0122)];

  scene.updateMatrixWorld(true);
  const C = new THREE.Vector3(0, SCREEN.y, 0); panel.localToWorld(C);
  const N = new THREE.Vector3(0, 0, 1).transformDirection(panel.matrixWorld);
  const UP = new THREE.Vector3(0, 1, 0).transformDirection(panel.matrixWorld);
  const RIGHT = new THREE.Vector3(1, 0, 0);

  // ----- Dashboard tiles that lift off the glass
  const tiles = Object.entries(TILE_RECTS).map(([name, [x0, y0, x1, y1]], i) => {
    const w = (x1 - x0) / IMG.w * SCREEN.w, h = (y1 - y0) / IMG.h * SCREEN.h;
    const cx = ((x0 + x1) / 2 / IMG.w - 0.5) * SCREEN.w, cy = (0.5 - (y0 + y1) / 2 / IMG.h) * SCREEN.h;
    const mat = new THREE.ShaderMaterial({
      vertexShader: tileShader.vertex, fragmentShader: tileShader.fragment, transparent: true,
      uniforms: { map: { value: textures.dashboard }, rect: { value: new THREE.Vector4(x0 / IMG.w, y0 / IMG.h, x1 / IMG.w, y1 / IMG.h) },
        size: { value: new THREE.Vector2(w, h) }, radius: { value: 0.0032 }, opacity: { value: 1 }, gain: { value: 1.35 } },
    });
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
    mesh.visible = false; mesh.renderOrder = 3; panel.add(mesh);
    const jitter = ((i * 7919) % 13) / 13;
    return {
      name, mesh, mat, w, h,
      home: new THREE.Vector3(cx, SCREEN.y + cy, 0.0014),
      away: new THREE.Vector3(cx * 1.34, SCREEN.y + cy * 1.95 + 0.004, 0.045 + jitter * 0.06),
      awayRot: new THREE.Euler(cy * 3.2, -cx * 2.1, 0),
      focusScale: Math.min(0.118 / h, 0.21 / w),
      order: (cx / SCREEN.w + 0.5) * 0.85 + (cy > 0 ? 0 : 0.15),
      pos: new THREE.Vector3(cx, SCREEN.y + cy, 0.0014), rot: new THREE.Vector3(), scale: 1, opacity: 1,
    };
  });

  // ----- The dial: a fine ring of 96 ticks behind the panel; scroll fills it, the leading ticks glow amber
  const TICKS = 96;
  const dial = new THREE.InstancedMesh(new THREE.BoxGeometry(0.011, 1, 0.011), new THREE.MeshBasicMaterial({ toneMapped: false, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }), TICKS);
  { const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), sc = new THREE.Vector3();
    for (let i = 0; i < TICKS; i++) {
      const th = (-45 + (270 * i) / (TICKS - 1)) * Math.PI / 180, len = i % 4 === 0 ? 0.2 : 0.1;
      p.set(Math.cos(th) * (2.55 - len / 2), Math.sin(th) * (2.55 - len / 2), 0); q.setFromAxisAngle(new THREE.Vector3(0, 0, 1), th - Math.PI / 2);
      dial.setMatrixAt(i, m.compose(p, q, sc.set(1, len, 1))); dial.setColorAt(i, new THREE.Color(0x0f1013));
    } }
  dial.position.copy(C).add(new THREE.Vector3(0, 0.2, -2.0)); scene.add(dial);
  const boneColor = new THREE.Color(0.62, 0.6, 0.56), leadColor = AMBER.clone().multiplyScalar(2.6), dimColor = new THREE.Color(0x060606), tmpColor = new THREE.Color();
  // A fractional fill: ticks fade up rather than pop, and the newest few carry the amber.
  const setDial = (fill, brightness) => {
    for (let i = 0; i < TICKS; i++) {
      const on = clamp(fill - i), lead = clamp(1 - (fill - i) / 7);
      dial.setColorAt(i, tmpColor.copy(boneColor).lerp(leadColor, lead * lead).multiplyScalar(on * brightness).add(dimColor));
    }
    dial.instanceColor.needsUpdate = true;
  };

  // ----- Dust in the light
  const dustGeo = new THREE.BufferGeometry(); const dustPos = new Float32Array(110 * 3);
  for (let i = 0; i < 110; i++) { dustPos[i * 3] = (Math.random() - 0.5) * 11; dustPos[i * 3 + 1] = Math.random() * 3.6; dustPos[i * 3 + 2] = (Math.random() - 0.5) * 7; }
  dustGeo.setAttribute("position", new THREE.BufferAttribute(dustPos, 3));
  const dust = new THREE.Points(dustGeo, new THREE.PointsMaterial({ size: 0.013, color: 0xece9e1, transparent: true, opacity: 0.16, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(dust);

  // ----- Lights
  const key = new THREE.DirectionalLight(0xfff1df, 0); key.position.set(-4, 6, 5); scene.add(key);
  const rim = new THREE.PointLight(0xf5b544, 16, 14, 2); rim.position.copy(C).add(new THREE.Vector3(3.2, 1.6, -2.4)); scene.add(rim);
  const hemi = new THREE.HemisphereLight(0x8fd3f4, 0x0a0b0d, 0); scene.add(hemi);

  // ----- Camera poses, one per chapter
  const dir = (x, y, z) => new THREE.Vector3(x, y, z).normalize();
  let poses = [], wide = true;
  const buildPoses = () => {
    wide = camera.aspect > 1.05;
    const hFov = 2 * Math.atan(Math.tan(camera.fov * Math.PI / 360) * camera.aspect);
    const fit = (frac) => 1.6 / (frac * Math.tan(hFov / 2));
    poses = [
      { v: dir(-0.46, 0.2, 1), d: fit(wide ? 0.5 : 0.92), t: new THREE.Vector3(), shift: wide ? [0.2, 0.02] : [0, -0.3] },
      { v: N.clone(), d: fit(wide ? 0.95 : 1.4), t: new THREE.Vector3(), shift: wide ? [0, -0.06] : [0, -0.15] },
      { v: dir(0.74, 0.36, 1), d: fit(wide ? 0.44 : 0.84), t: new THREE.Vector3(), shift: wide ? [0.06, 0] : [0, -0.22] },
      { v: dir(-0.08, 0.36, 1), d: fit(wide ? 0.62 : 1.0), t: N.clone().multiplyScalar(0.7), shift: wide ? [0.05, -0.09] : [0, -0.2] },
      { v: dir(0.58, -0.05, 1), d: fit(wide ? 0.54 : 0.9), t: new THREE.Vector3(), shift: wide ? [0.18, 0] : [0, -0.22] },
      { v: dir(-0.34, 0.2, 1), d: fit(wide ? 0.42 : 0.86), t: new THREE.Vector3(0, -0.12, 0), shift: wide ? [0, -0.24] : [0, -0.28] },
    ];
  };

  // ----- Scroll → chapter, progress inside it
  const chapters = [...document.querySelectorAll(".chapter")];
  const names = chapters.map((c) => c.dataset.chapter);
  let metrics = [];
  const measure = () => { metrics = chapters.map((c) => ({ top: c.offsetTop, h: c.offsetHeight })); };
  let softY = scrollY;          // the scroll position with inertia; everything reads this
  const where = () => {
    const y = softY; let idx = 0;
    for (let i = 0; i < metrics.length; i++) if (y >= metrics[i].top - 1) idx = i;
    const m = metrics[idx], last = idx === metrics.length - 1;
    const local = clamp((y - m.top) / Math.max(1, last ? m.h - innerHeight * 0.75 : m.h));
    return { idx, local };
  };

  const caps = [...document.querySelectorAll(".cap")];
  const setOn = (el, on) => { if (el.hasAttribute("data-on") !== on) el.toggleAttribute("data-on", on); };
  const railButtons = [...document.querySelectorAll(".rail button")];
  railButtons.forEach((b) => b.addEventListener("click", () => {
    const i = names.indexOf(b.dataset.go), m = metrics[i];
    scrollTo({ top: m.top + (i === 0 ? 0 : m.h * 0.12), behavior: reduce ? "auto" : "smooth" });
  }));
  const labels = [...document.querySelectorAll(".label")]; let labelW = labels.map(() => 200);

  // ----- Pointer: parallax, a light that follows the cursor, and touches on the glass
  let clock = 0;
  const pointer = { x: 0, y: 0, sx: 0, sy: 0, lastMove: -10 };
  addEventListener("pointermove", (e) => {
    pointer.x = (e.clientX / innerWidth) * 2 - 1; pointer.y = -((e.clientY / innerHeight) * 2 - 1); pointer.lastMove = clock;
  }, { passive: true });
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  let rippleAt = 0, heroIdx = 0, lastTouch = -10;
  canvas.addEventListener("click", (e) => {
    ndc.set((e.clientX / innerWidth) * 2 - 1, -((e.clientY / innerHeight) * 2 - 1));
    ray.setFromCamera(ndc, camera);
    const hit = ray.intersectObject(screenMesh, false)[0];
    if (!hit || !hit.uv) return;
    screenMat.uniforms.ripples.value[rippleAt++ % 4].set(hit.uv.x, hit.uv.y, clock); lastTouch = clock;
    if (where().idx === 0) heroIdx = (heroIdx + 1) % HERO.length;
  });

  // ----- Screen pages wipe from one to the next
  let pageNow = "dashboard", pageNext = null, wipe = 0;
  const showPage = (name, dt) => {
    if (pageNext) {
      wipe += dt / 1.25; screenMat.uniforms.mixT.value = clamp(wipe);
      if (wipe >= 1) { pageNow = pageNext; pageNext = null; screenMat.uniforms.texA.value = textures[pageNow]; screenMat.uniforms.mixT.value = 0; }
    } else if (name !== pageNow) {
      pageNext = name; wipe = 0; screenMat.uniforms.texB.value = textures[name];
    }
  };

  // ----- Frame
  const resize = () => {
    const w = innerWidth, h = innerHeight;
    const pr = pixelRatio();
    renderer.setPixelRatio(pr); composer.setPixelRatio(pr);
    renderer.setSize(w, h, false); composer.setSize(w, h);
    camera.aspect = w / h; camera.updateProjectionMatrix(); buildPoses(); measure();
    labelW = labels.map((el) => el.offsetWidth);
  };
  addEventListener("resize", resize); resize();

  const cam = { v: poses[0].v.clone(), d: poses[0].d * 1.35, t: new THREE.Vector3(), sx: poses[0].shift[0], sy: poses[0].shift[1] };
  let labelsShown = false;
  const state = { explode: 0, explodeV: 0, lift: 0, liftV: 0, night: 0, floor: 1, dial: 1, fill: 0, fov: 30, roll: 0, power: 0, booted: false, bootAt: 0 };
  // A lightly under-damped spring: arrives with a breath of overshoot instead of a dead stop.
  const spring = (key, to, dt, k = 64, c = 12.5) => {
    if (reduce) { state[key] = to; return; }
    const v = key + "V"; state[v] += ((to - state[key]) * k - state[v] * c) * dt; state[key] += state[v] * dt;
  };
  const ease5 = (x) => { x = clamp(x); return x * x * x * (x * (6 * x - 15) + 10); };
  const tmpV = new THREE.Vector3(), tmpT = new THREE.Vector3(), tmpP = new THREE.Vector3(), lookAt = new THREE.Vector3();

  let last = performance.now();
  let lastRaf = performance.now(), slow = 0, fast = 0, frameNo = 0, lastActive = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    if (document.hidden) { last = now; lastRaf = now; return; }
    const raw = (now - lastRaf) / 1000; lastRaf = now;
    if (raw < 0.2 && clock - lastActive < 0.5) {            // only judge frames while something is moving
      if (raw > 1 / 45) slow++; else fast++;
      if (slow + fast >= 50) {
        if (slow > 20 && quality > 0.4) { quality *= 0.78; resize(); }
        slow = fast = 0;
      }
    }
    if (clock - lastActive > 1.2 && ++frameNo % 3) return;  // settled: ambient motion only, a third of the frames
    update(now);
  }
  function update(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now; clock += dt;
    softY = damp(softY, scrollY, 7.5, dt);
    if (Math.abs(scrollY - softY) > 0.5 || clock - pointer.lastMove < 1 || pageNext || state.power < 1 || clock - lastTouch < 2) lastActive = clock;
    const { idx, local } = where();
    const isLast = idx === poses.length - 1;
    const hold = isLast ? 0 : ease5((local - 0.56) / 0.44);
    const s = clamp(local / 0.58);
    const chapter = names[idx];

    // Camera: blend this chapter's pose toward the next one at the end of the chapter.
    const a = poses[idx], b = poses[Math.min(idx + 1, poses.length - 1)];
    tmpV.copy(a.v).lerp(b.v, hold).normalize();
    tmpT.copy(a.t).lerp(b.t, hold);
    if (!wide && chapter === "strip") tmpT.addScaledVector(RIGHT, (s * 2 - 1) * 0.45 * (1 - hold));   // pan along the strip
    const d = a.d + (b.d - a.d) * hold, sx = a.shift[0] + (b.shift[0] - a.shift[0]) * hold, sy = a.shift[1] + (b.shift[1] - a.shift[1]) * hold;
    const CL = 3.6, intro = 1 + 0.26 * (1 - ease5(state.power));      // a slow push-in while the panel wakes
    cam.v.x = damp(cam.v.x, tmpV.x, CL, dt); cam.v.y = damp(cam.v.y, tmpV.y, CL, dt); cam.v.z = damp(cam.v.z, tmpV.z, CL, dt);
    cam.d = damp(cam.d, d * intro, CL, dt); cam.sx = damp(cam.sx, sx, CL, dt); cam.sy = damp(cam.sy, sy, CL, dt);
    cam.t.x = damp(cam.t.x, tmpT.x, CL, dt); cam.t.y = damp(cam.t.y, tmpT.y, CL, dt); cam.t.z = damp(cam.t.z, tmpT.z, CL, dt);
    // Between chapters the lens opens a touch and the camera banks into the move.
    const travel = Math.sin(Math.PI * hold);
    state.fov = damp(state.fov, 30 + travel * 4, 4, dt); state.roll = damp(state.roll, travel * 0.035 * (idx % 2 ? 1 : -1), 4, dt);
    camera.fov = state.fov;
    pointer.sx = damp(pointer.sx, reduce ? 0 : pointer.x, 3, dt); pointer.sy = damp(pointer.sy, reduce ? 0 : pointer.y, 3, dt);
    lookAt.copy(C).add(cam.t);
    tmpP.copy(cam.v).normalize().multiplyScalar(cam.d).add(lookAt);
    tmpP.x += pointer.sx * 0.32; tmpP.y += pointer.sy * 0.18;
    camera.position.copy(tmpP); camera.lookAt(lookAt); camera.rotateZ(reduce ? 0 : state.roll);
    camera.setViewOffset(innerWidth, innerHeight, -cam.sx * innerWidth, -cam.sy * innerHeight, innerWidth, innerHeight);

    // Chapter choreography
    const wantExplode = chapter === "apart" ? smooth(0.04, 0.5, s) * (1 - hold) : 0;
    const wantLift = chapter === "tiles" ? smooth(0, 0.2, s) * (1 - smooth(0, 0.7, hold)) : 0;
    const wantNight = chapter === "night" ? smooth(0, 0.3, s) * (1 - hold) : 0;
    const floorOf = { hero: 1, strip: 0.45, apart: 0, tiles: 0, night: 1, land: 1 };
    const dialOf = { hero: 1, strip: 0.5, apart: 0.3, tiles: 0.28, night: 0.3, land: 0.85 };
    state.dial = damp(state.dial, dialOf[chapter] + ((dialOf[names[idx + 1]] ?? dialOf[chapter]) - dialOf[chapter]) * hold, 4, dt);
    const wantFloor = floorOf[chapter] + ((floorOf[names[idx + 1]] ?? floorOf[chapter]) - floorOf[chapter]) * hold;
    spring("explode", wantExplode, dt);
    spring("lift", wantLift, dt);
    state.night = damp(state.night, wantNight, 3.5, dt);
    state.floor = damp(state.floor, wantFloor, 4, dt);

    // Power on, once the boot screen is gone
    if (state.booted) state.power = reduce ? 1 : clamp((clock - state.bootAt - 0.3) / 2.6);
    const lit = smooth(0, 1, state.power);
    screenMat.uniforms.power.value = state.power; screenMat.uniforms.time.value = clock; film.uniforms.time.value = reduce ? 0 : clock;
    key.intensity = (0.3 + lit * 1.5) * (1 - state.night * 0.93);
    hemi.intensity = lit * 0.4 * (1 - state.night * 0.85);
    rim.intensity = 5 + lit * 6 + state.night * 12;
    bloom.strength = 0.42 + state.night * 0.4;
    scene.environmentIntensity = 0.12 + lit * 0.36 - state.night * 0.3;

    // Exploded panel: the layers leave in turn and fan a few degrees, frames drawing themselves as they go
    const e = clamp(state.explode, -0.05, 1.08), e1 = smooth(0, 0.7, e) + (e - clamp(e)) , e2 = smooth(0.12, 0.85, e), e3 = smooth(0.25, 1, e);
    glass.position.z = rest.glass + e1 * 0.11; glass.rotation.y = -0.07 * e1;
    screenMesh.position.z = rest.screen + e2 * 0.045;
    housing.position.z = rest.housing - e3 * 0.04; housing.rotation.y = 0.07 * e3;
    stand.position.z = rest.stand - e3 * 0.085;
    [e1, e2, e3].forEach((v, i) => {
      const f = frames[i]; f.mesh.visible = v > 0.01;
      f.mat.uniforms.progress.value = smooth(0.05, 0.9, v); f.mat.uniforms.strength.value = smooth(0, 0.6, v) * 0.9; f.mat.uniforms.time.value = reduce ? 0 : clock;
    });
    const showLabels = e > 0.78;
    if (e > 0.01 || showLabels !== labelsShown) labels.forEach((el) => {
      const part = el.dataset.part, of = part === "glass" ? glass : part === "screen" ? screenMesh : housing;
      tmpP.set(part === "screen" ? 0.1865 : part === "glass" ? 0.1912 : 0.1925, part === "glass" ? -0.036 : part === "screen" ? 0 : 0.036,
               part === "glass" ? 0 : part === "screen" ? -0.0008 : -0.006);
      of.localToWorld(tmpP); tmpP.project(camera);
      const lx = Math.min((tmpP.x + 1) / 2 * innerWidth, innerWidth - labelW[labels.indexOf(el)] - 20);
      el.style.transform = `translate3d(${lx.toFixed(1)}px, ${((1 - tmpP.y) / 2 * innerHeight - 11).toFixed(1)}px, 0)`;
      el.classList.toggle("on", showLabels);
    });
    labelsShown = showLabels;

    // Tiles
    const L = clamp(state.lift, 0, 1.06), focus = chapter === "tiles" && s >= 0.2 && hold < 0.5 ? Math.min(4, Math.floor((s - 0.2) / 0.8 * 5)) : -1;
    screenMat.uniforms.dim.value = clamp(L);
    for (const t of tiles) {
      const focused = focus >= 0 && t.name === FOCUS[focus];
      t.mesh.visible = L > 0.004;
      if (!t.mesh.visible) { t.pos.copy(t.home); t.rot.set(0, 0, 0); t.scale = 1; t.opacity = 1; continue; }
      const Li = ease5(L * 1.55 - t.order * 0.55) + Math.max(0, L - 1);      // each column leaves a beat after the last
      const tp = focused ? tmpP.set(0.02, SCREEN.y + 0.004, 0.2) : tmpP.copy(t.home).lerp(t.away, Li);
      t.pos.x = damp(t.pos.x, tp.x, 5, dt); t.pos.y = damp(t.pos.y, tp.y, 5, dt); t.pos.z = damp(t.pos.z, tp.z, 5, dt);
      t.rot.x = damp(t.rot.x, focused ? 0 : t.awayRot.x * Li, 5, dt); t.rot.y = damp(t.rot.y, focused ? 0 : t.awayRot.y * Li, 5, dt);
      t.scale = damp(t.scale, focused ? t.focusScale : 1, 5, dt);
      t.opacity = damp(t.opacity, focus >= 0 && !focused ? 0.3 : 1, 4, dt);
      const bob = reduce ? 0 : Math.sin(clock * 0.7 + t.home.x * 40) * 0.0012 * L;
      t.mesh.position.set(t.pos.x, t.pos.y + bob, t.pos.z); t.mesh.rotation.set(t.rot.x, t.rot.y, 0); t.mesh.scale.setScalar(t.scale);
      t.mat.uniforms.opacity.value = t.opacity; t.mesh.renderOrder = focused ? 5 : 3;
    }

    // Floor and reflection
    if (mirror) mirror.visible = state.floor > 0.5;
    floor.visible = state.floor > 0.01;
    floor.material.opacity = state.floor > 0.5 ? 1 - (state.floor - 0.5) * 2 * 0.12 : state.floor * 2;

    // Dial, dust, cursor light
    const overall = (idx + local) / names.length;
    state.fill = damp(state.fill, lit * (8 + overall * (TICKS - 8)), 4, dt); setDial(state.fill, state.dial);
    dial.rotation.z = pointer.sx * -0.03 - overall * 0.5; dial.position.x = C.x + pointer.sx * -0.25;
    if (!reduce) dust.rotation.y += dt * 0.012;

    // Screen content
    const page = chapter === "hero" ? HERO[heroIdx] : chapter === "strip" ? STRIP[Math.min(5, Math.floor(s * 6))]
      : chapter === "night" ? (wantNight > 0.25 ? "minimal" : "dashboard") : "dashboard";
    showPage(page, dt);

    // Captions and the rail
    const stripK = Math.min(5, Math.floor(s * 6));
    for (const el of caps) {
      const c = el.dataset.cap, k = el.dataset.k === undefined ? -1 : +el.dataset.k;
      let on = state.booted && c === chapter;
      if (c === "hero") on = on && local < 0.55;
      else if (c === "strip") on = on && hold < 0.35 && k === stripK;
      else if (c === "tiles") on = on && hold < 0.35 && k === focus;
      else if (c === "land") on = on && local > 0.2;
      else on = on && s > 0.1 && hold < 0.45;
      setOn(el, on);
    }
    railButtons.forEach((bn, i) => { if ((bn.getAttribute("aria-current") === "true") !== (i === idx)) bn.setAttribute("aria-current", String(i === idx)); });

    composer.render(dt);
  }

  // Lets a hidden tab (tests, screenshots) advance the scene by hand: __xt.step(seconds).
  window.__xt = { step(seconds = 1) { for (let t = 0; t < seconds; t += 1 / 60) update(last + 1000 / 60); } };

  // First frames behind the boot screen, then power on.
  requestAnimationFrame((t0) => { last = t0; frame(t0); });
  await new Promise((r) => setTimeout(r, reduce ? 0 : 450));
  document.body.classList.remove("booting"); state.booted = true; state.bootAt = clock;
}

world().catch((err) => {
  console.error(err);
  document.body.classList.remove("booting"); document.body.classList.add("no-gl");
});

// ---------- Sound (off until asked)
{
  const b = document.getElementById("sound"), audio = document.getElementById("theme");
  b.addEventListener("click", () => {
    const on = b.getAttribute("aria-pressed") !== "true";
    b.setAttribute("aria-pressed", String(on));
    if (on) { audio.volume = 0.5; audio.play().catch(() => b.setAttribute("aria-pressed", "false")); } else audio.pause();
  });
}

// ---------- Version from GitHub, when reachable
fetch("https://api.github.com/repos/Shadowhusky/xeneon-toolbox/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
  .then((r) => r.ok ? r.json() : null)
  .then((j) => { if (j?.tag_name) setVersion(j.tag_name); })
  .catch(() => {});
