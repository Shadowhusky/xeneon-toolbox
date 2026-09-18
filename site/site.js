import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

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
    const vec3 amber = vec3(0.92, 0.47, 0.06);
    void main(){
      vec3 a = texture2D(texA, vUv).rgb, b = texture2D(texB, vUv).rgb;
      float w = mixT * 1.16;
      float m = smoothstep(w - 0.1, w, vUv.x);                      // 1 where the old page still shows
      vec3 col = mix(b, a, m);
      float edge = (1.0 - abs(m - 0.5) * 2.0) * step(0.001, mixT) * step(mixT, 0.999);
      col += amber * edge * 1.4;
      for (int i = 0; i < 4; i++) {
        float t = time - ripples[i].z;
        if (t > 0.0 && t < 1.3) {
          float r = length((vUv - ripples[i].xy) * vec2(3.552, 1.0));
          float ring = smoothstep(0.035, 0.0, abs(r - t * 0.6)) * (1.0 - t / 1.3);
          float dot = smoothstep(0.07, 0.0, r) * (1.0 - smoothstep(0.0, 0.3, t));
          col += amber * ring * 1.5 + vec3(1.0, 0.9, 0.75) * dot * 0.35;
        }
      }
      float open = power * power * (3.0 - 2.0 * power);
      float band = step(abs(vUv.y - 0.5), open * 0.5 + 0.0008);
      float line = smoothstep(0.014, 0.0, abs(abs(vUv.y - 0.5) - open * 0.5)) * (1.0 - open) * step(0.001, power);
      col = col * band * smoothstep(0.1, 1.0, power) + amber * line * 3.0;
      gl_FragColor = vec4(col * gain * (1.0 - dim * 0.88), 1.0);
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
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0a0b0d);
  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.45;
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);

  const target = new THREE.WebGLRenderTarget(2, 2, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, target);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(2, 2), 0.45, 0.75, 0.9);
  composer.addPass(bloom);
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
    if (o.material.name === "Glass") { o.material.envMapIntensity = 0.22; o.material.roughness = 0.12; }
    if (o.material.name === "Aluminium") { o.material.color.setHex(0x80848a); o.material.envMapIntensity = 0.6; }
  });

  // A mirrored twin under a translucent floor gives the reflection (made before the tiles exist).
  const mirror = rig.clone(true); mirror.scale.y *= -1; scene.add(mirror);
  const fade = document.createElement("canvas"); fade.width = fade.height = 256;
  { const c = fade.getContext("2d"), g = c.createRadialGradient(128, 128, 10, 128, 128, 128);
    g.addColorStop(0, "#fff"); g.addColorStop(0.35, "#d0d0d0"); g.addColorStop(0.7, "#3a3a3a"); g.addColorStop(1, "#000"); c.fillStyle = g; c.fillRect(0, 0, 256, 256); }
  const floor = new THREE.Mesh(new THREE.CircleGeometry(9, 64), new THREE.MeshStandardMaterial({
    color: 0x050608, roughness: 0.42, metalness: 0.55, envMapIntensity: 0.15, transparent: true, opacity: 0.9, alphaMap: new THREE.CanvasTexture(fade), depthWrite: false }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = 0.001; floor.renderOrder = 1; scene.add(floor);

  // Amber outlines that appear with the exploded view, one per layer.
  const outline = (of, w, h, dz) => {
    const pts = [[-w, -h], [w, -h], [w, h], [-w, h]].map(([x, y]) => new THREE.Vector3(x, SCREEN.y + y, 0));
    const line = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color: AMBER.clone().multiplyScalar(1.8), transparent: true, opacity: 0, toneMapped: false }));
    line.visible = false; panel.add(line); return { of, line, dz };
  };
  const outlines = [outline(glass, 0.1912, 0.0572, 0.0006), outline(screenMesh, 0.1865, 0.0525, -0.0006), outline(housing, 0.1925, 0.0585, -0.0121)];

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
      pos: new THREE.Vector3(cx, SCREEN.y + cy, 0.0014), rot: new THREE.Vector3(), scale: 1, opacity: 1,
    };
  });

  // ----- The dial: 48 ticks in space behind the panel, lit by how far you've scrolled
  const dial = new THREE.InstancedMesh(new THREE.BoxGeometry(0.035, 0.27, 0.035), new THREE.MeshBasicMaterial({ toneMapped: false }), 48);
  { const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
    for (let i = 0; i < 48; i++) {
      const th = (-45 + (270 * i) / 47) * Math.PI / 180;   // lit from the lower right, away from the copy
      p.set(Math.cos(th) * 2.55, Math.sin(th) * 2.55, 0); q.setFromAxisAngle(new THREE.Vector3(0, 0, 1), th - Math.PI / 2);
      dial.setMatrixAt(i, m.compose(p, q, one)); dial.setColorAt(i, new THREE.Color(0x15161a));
    } }
  dial.position.copy(C).add(new THREE.Vector3(0, 0.2, -2.0)); scene.add(dial);
  let dialLit = -1;
  const litColor = AMBER.clone().multiplyScalar(2.4), dimColor = new THREE.Color(0x0f1013), tmpColor = new THREE.Color();
  const setDial = (count, brightness) => {
    const key = count * 100 + Math.round(brightness * 20);
    if (key === dialLit) return; dialLit = key;
    for (let i = 0; i < 48; i++) dial.setColorAt(i, i < count ? tmpColor.copy(litColor).multiplyScalar(brightness) : dimColor);
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
  const cursorLight = new THREE.PointLight(0xd4ecff, 0, 5.5, 2); scene.add(cursorLight);

  // ----- Camera poses, one per chapter
  const dir = (x, y, z) => new THREE.Vector3(x, y, z).normalize();
  let poses = [];
  const buildPoses = () => {
    const wide = camera.aspect > 1.05;
    const hFov = 2 * Math.atan(Math.tan(camera.fov * Math.PI / 360) * camera.aspect);
    const fit = (frac) => 1.6 / (frac * Math.tan(hFov / 2));
    poses = [
      { v: dir(-0.46, 0.2, 1), d: fit(wide ? 0.5 : 0.92), t: new THREE.Vector3(), shift: wide ? [0.2, 0.02] : [0, -0.3] },
      { v: N.clone(), d: fit(0.95), t: new THREE.Vector3(), shift: wide ? [0, -0.06] : [0, -0.24] },
      { v: dir(0.74, 0.36, 1), d: fit(wide ? 0.46 : 0.84), t: new THREE.Vector3(), shift: wide ? [0.1, 0] : [0, -0.22] },
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
  const where = () => {
    const y = scrollY; let idx = 0;
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
  const labels = [...document.querySelectorAll(".label")];

  // ----- Pointer: parallax, a light that follows the cursor, and touches on the glass
  let clock = 0;
  const pointer = { x: 0, y: 0, sx: 0, sy: 0, lastMove: -10 };
  addEventListener("pointermove", (e) => {
    pointer.x = (e.clientX / innerWidth) * 2 - 1; pointer.y = -((e.clientY / innerHeight) * 2 - 1); pointer.lastMove = clock;
  }, { passive: true });
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  let rippleAt = 0, heroIdx = 0;
  canvas.addEventListener("click", (e) => {
    ndc.set((e.clientX / innerWidth) * 2 - 1, -((e.clientY / innerHeight) * 2 - 1));
    ray.setFromCamera(ndc, camera);
    const hit = ray.intersectObject(screenMesh, false)[0];
    if (!hit || !hit.uv) return;
    screenMat.uniforms.ripples.value[rippleAt++ % 4].set(hit.uv.x, hit.uv.y, clock);
    if (where().idx === 0) heroIdx = (heroIdx + 1) % HERO.length;
  });

  // ----- Screen pages wipe from one to the next
  let pageNow = "dashboard", pageNext = null, wipe = 0;
  const showPage = (name, dt) => {
    if (pageNext) {
      wipe += dt / 0.55; screenMat.uniforms.mixT.value = smooth(0, 1, wipe);
      if (wipe >= 1) { pageNow = pageNext; pageNext = null; screenMat.uniforms.texA.value = textures[pageNow]; screenMat.uniforms.mixT.value = 0; }
    } else if (name !== pageNow) {
      pageNext = name; wipe = 0; screenMat.uniforms.texB.value = textures[name];
    }
  };

  // ----- Frame
  const resize = () => {
    const w = innerWidth, h = innerHeight;
    renderer.setSize(w, h, false); composer.setSize(w, h); bloom.resolution.set(w / 2, h / 2);
    camera.aspect = w / h; camera.updateProjectionMatrix(); buildPoses(); measure();
  };
  addEventListener("resize", resize); resize();

  const cam = { v: poses[0].v.clone(), d: poses[0].d * 1.35, t: new THREE.Vector3(), sx: poses[0].shift[0], sy: poses[0].shift[1] };
  const state = { explode: 0, lift: 0, night: 0, floor: 1, dial: 1, power: 0, booted: false, bootAt: 0 };
  const tmpV = new THREE.Vector3(), tmpT = new THREE.Vector3(), tmpP = new THREE.Vector3(), lookAt = new THREE.Vector3();

  let last = performance.now();
  function frame(now) {
    requestAnimationFrame(frame);
    if (document.hidden) { last = now; return; }
    update(now);
  }
  function update(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now; clock += dt;
    const { idx, local } = where();
    const isLast = idx === poses.length - 1;
    const hold = isLast ? 0 : smooth(0.62, 1.0, local);
    const s = clamp(local / 0.62);
    const chapter = names[idx];

    // Camera: blend this chapter's pose toward the next one at the end of the chapter.
    const a = poses[idx], b = poses[Math.min(idx + 1, poses.length - 1)];
    tmpV.copy(a.v).lerp(b.v, hold).normalize();
    tmpT.copy(a.t).lerp(b.t, hold);
    const d = a.d + (b.d - a.d) * hold, sx = a.shift[0] + (b.shift[0] - a.shift[0]) * hold, sy = a.shift[1] + (b.shift[1] - a.shift[1]) * hold;
    cam.v.x = damp(cam.v.x, tmpV.x, 4.5, dt); cam.v.y = damp(cam.v.y, tmpV.y, 4.5, dt); cam.v.z = damp(cam.v.z, tmpV.z, 4.5, dt);
    cam.d = damp(cam.d, d, 4.5, dt); cam.sx = damp(cam.sx, sx, 4.5, dt); cam.sy = damp(cam.sy, sy, 4.5, dt);
    cam.t.x = damp(cam.t.x, tmpT.x, 4.5, dt); cam.t.y = damp(cam.t.y, tmpT.y, 4.5, dt); cam.t.z = damp(cam.t.z, tmpT.z, 4.5, dt);
    pointer.sx = damp(pointer.sx, reduce ? 0 : pointer.x, 3, dt); pointer.sy = damp(pointer.sy, reduce ? 0 : pointer.y, 3, dt);
    lookAt.copy(C).add(cam.t);
    tmpP.copy(cam.v).normalize().multiplyScalar(cam.d).add(lookAt);
    tmpP.x += pointer.sx * 0.32; tmpP.y += pointer.sy * 0.18;
    camera.position.copy(tmpP); camera.lookAt(lookAt);
    camera.setViewOffset(innerWidth, innerHeight, -cam.sx * innerWidth, -cam.sy * innerHeight, innerWidth, innerHeight);

    // Chapter choreography
    const wantExplode = chapter === "apart" ? smooth(0.04, 0.5, s) * (1 - hold) : 0;
    const wantLift = chapter === "tiles" ? smooth(0, 0.2, s) * (1 - smooth(0, 0.7, hold)) : 0;
    const wantNight = chapter === "night" ? smooth(0, 0.3, s) * (1 - hold) : 0;
    const floorOf = { hero: 1, strip: 0.45, apart: 0, tiles: 0, night: 1, land: 1 };
    const dialOf = { hero: 1, strip: 0.5, apart: 0.3, tiles: 0.28, night: 0.3, land: 0.85 };
    state.dial = damp(state.dial, dialOf[chapter] + ((dialOf[names[idx + 1]] ?? dialOf[chapter]) - dialOf[chapter]) * hold, 4, dt);
    const wantFloor = floorOf[chapter] + ((floorOf[names[idx + 1]] ?? floorOf[chapter]) - floorOf[chapter]) * hold;
    state.explode = damp(state.explode, wantExplode, 5, dt);
    state.lift = damp(state.lift, wantLift, 5, dt);
    state.night = damp(state.night, wantNight, 3.5, dt);
    state.floor = damp(state.floor, wantFloor, 4, dt);

    // Power on, once the boot screen is gone
    if (state.booted) state.power = reduce ? 1 : clamp((clock - state.bootAt - 0.35) / 1.7);
    const lit = smooth(0, 1, state.power);
    screenMat.uniforms.power.value = state.power; screenMat.uniforms.time.value = clock;
    key.intensity = (0.3 + lit * 1.5) * (1 - state.night * 0.93);
    hemi.intensity = lit * 0.4 * (1 - state.night * 0.85);
    rim.intensity = 5 + lit * 6 + state.night * 12;
    bloom.strength = 0.42 + state.night * 0.4;
    scene.environmentIntensity = 0.12 + lit * 0.36 - state.night * 0.3;

    // Exploded panel
    const e = state.explode;
    glass.position.z = rest.glass + e * 0.11; screenMesh.position.z = rest.screen + e * 0.045;
    housing.position.z = rest.housing - e * 0.04; stand.position.z = rest.stand - e * 0.085;
    for (const o of outlines) { o.line.position.z = o.of.position.z + o.dz; o.line.material.opacity = smooth(0.15, 0.8, e) * 0.9; o.line.visible = e > 0.02; }
    const showLabels = e > 0.72;
    labels.forEach((el) => {
      const part = el.dataset.part;
      const z = part === "glass" ? glass.position.z : part === "screen" ? screenMesh.position.z - 0.0008 : housing.position.z - 0.006;
      const x = part === "screen" ? 0.1865 : part === "glass" ? 0.1912 : 0.1925;
      tmpP.set(x, SCREEN.y + (part === "glass" ? -0.036 : part === "screen" ? 0 : 0.036), z); panel.localToWorld(tmpP); tmpP.project(camera);
      el.style.transform = `translate3d(${((tmpP.x + 1) / 2 * innerWidth).toFixed(1)}px, ${((1 - tmpP.y) / 2 * innerHeight - 11).toFixed(1)}px, 0)`;
      el.classList.toggle("on", showLabels);
    });

    // Tiles
    const L = state.lift, focus = chapter === "tiles" && s >= 0.2 && hold < 0.5 ? Math.min(4, Math.floor((s - 0.2) / 0.8 * 5)) : -1;
    screenMat.uniforms.dim.value = L;
    for (const t of tiles) {
      const focused = focus >= 0 && t.name === FOCUS[focus];
      t.mesh.visible = L > 0.004;
      if (!t.mesh.visible) { t.pos.copy(t.home); t.rot.set(0, 0, 0); t.scale = 1; t.opacity = 1; continue; }
      const tp = focused ? tmpP.set(0.02, SCREEN.y + 0.004, 0.2) : tmpP.copy(t.home).lerp(t.away, L);
      t.pos.x = damp(t.pos.x, tp.x, 6, dt); t.pos.y = damp(t.pos.y, tp.y, 6, dt); t.pos.z = damp(t.pos.z, tp.z, 6, dt);
      t.rot.x = damp(t.rot.x, focused ? 0 : t.awayRot.x * L, 6, dt); t.rot.y = damp(t.rot.y, focused ? 0 : t.awayRot.y * L, 6, dt);
      t.scale = damp(t.scale, focused ? t.focusScale : 1, 6, dt);
      t.opacity = damp(t.opacity, focus >= 0 && !focused ? 0.32 : 1, 6, dt);
      const bob = reduce ? 0 : Math.sin(clock * 0.7 + t.home.x * 40) * 0.0012 * L;
      t.mesh.position.set(t.pos.x, t.pos.y + bob, t.pos.z); t.mesh.rotation.set(t.rot.x, t.rot.y, 0); t.mesh.scale.setScalar(t.scale);
      t.mat.uniforms.opacity.value = t.opacity; t.mesh.renderOrder = focused ? 5 : 3;
    }

    // Floor and reflection
    mirror.visible = state.floor > 0.5;
    floor.visible = state.floor > 0.01;
    floor.material.opacity = state.floor > 0.5 ? 1 - (state.floor - 0.5) * 2 * 0.12 : state.floor * 2;

    // Dial, dust, cursor light
    const overall = (idx + local) / names.length;
    setDial(Math.round(lit * (5 + overall * 43)), state.dial);
    dial.rotation.z = pointer.sx * -0.03; dial.position.x = C.x + pointer.sx * -0.25;
    if (!reduce) dust.rotation.y += dt * 0.012;
    const active = !reduce && clock - pointer.lastMove < 3 ? 1 : 0;
    cursorLight.intensity = damp(cursorLight.intensity, active * (1.4 + state.night * 2) * lit, 4, dt);
    cursorLight.position.copy(C).addScaledVector(N, 1.5).addScaledVector(RIGHT, pointer.sx * 2.0).addScaledVector(UP, pointer.sy * 0.75);

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
  .then((j) => { if (j?.tag_name) document.getElementById("ver").textContent = j.tag_name; })
  .catch(() => {});
