import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---------- The dial behind the hero: 48 ticks over 270°, lit from −225°.
{
  const g = document.getElementById("ticks");
  const cx = 500, cy = 500, r1 = 456, r2 = 486;
  for (let i = 0; i < 48; i++) {
    const a = (-225 + (270 * i) / 47) * Math.PI / 180;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", cx + r1 * Math.cos(a)); line.setAttribute("y1", cy + r1 * Math.sin(a));
    line.setAttribute("x2", cx + r2 * Math.cos(a)); line.setAttribute("y2", cy + r2 * Math.sin(a));
    line.setAttribute("class", "tick" + (i < 30 ? " lit" : ""));
    g.appendChild(line);
  }
}

// ---------- Hero: the panel in 3D, its screen swappable by a tap.
const screens = [
  ["Dashboard", "assets/screens/dashboard.png"],
  ["Deck", "assets/screens/deck.png"],
  ["Ambient", "assets/screens/minimal.png"],
  ["Clock", "assets/screens/clock.png"],
  ["Assistant", "assets/screens/assistant.png"],
  ["Control centre", "assets/screens/control-center.png"],
];

async function hero() {
  const wrap = document.getElementById("stage-wrap");
  const canvas = document.getElementById("stage");
  const fallback = document.getElementById("stage-fallback");
  const caption = document.getElementById("stage-caption");
  const showFallback = () => { canvas.hidden = true; fallback.hidden = false; };

  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
  } catch { showFallback(); return; }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

  const camera = new THREE.PerspectiveCamera(28, 1, 0.1, 100);
  const key = new THREE.DirectionalLight(0xfff4e6, 2.2); key.position.set(-4, 6, 5); scene.add(key);
  const rim = new THREE.PointLight(0xf5b544, 18, 20, 2); rim.position.set(5, 1.5, -3); scene.add(rim);
  const fill = new THREE.HemisphereLight(0x8fd3f4, 0x0a0b0d, 0.35); scene.add(fill);

  let model, screenMesh, screenMat;
  try {
    const gltf = await new GLTFLoader().loadAsync("assets/3d/edge.glb");
    model = gltf.scene;
  } catch { showFallback(); return; }

  // Frame the model: centre it, normalise its width, then keep the camera at a
  // distance where the panel fills most of the stage at any aspect ratio.
  // Anything that isn't the panel or its stand (a floor, a backdrop) is hidden
  // and left out of the framing, so the strip itself sets the scale.
  const scenery = /floor|ground|plane|backdrop|wall|light|camera/i;
  model.traverse((o) => { if (o.isMesh && scenery.test(o.name)) o.visible = false; });
  const box = new THREE.Box3();
  model.traverse((o) => { if (o.isMesh && o.visible) box.expandByObject(o); });
  const size = box.getSize(new THREE.Vector3());
  const centre = box.getCenter(new THREE.Vector3());
  model.position.sub(centre);
  model.scale.setScalar(3.2 / Math.max(size.x, 0.001));
  const pivot = new THREE.Group(); pivot.add(model); scene.add(pivot);
  pivot.rotation.set(0.12, -0.42, 0.02);
  pivot.position.y = -0.22;   // sit the panel a little below centre so its glow has room
  const frameCamera = () => {
    const vFov = camera.fov * Math.PI / 180;
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * camera.aspect);
    // The panel is 3.2 units wide; let it take about 85% of the stage's width.
    const dist = Math.max(1.6 / (0.85 * Math.tan(hFov / 2)), 0.75 / Math.tan(vFov / 2));
    camera.position.set(0, dist * 0.08, dist); camera.lookAt(0, -0.05, 0);
  };

  model.traverse((o) => {
    if (o.isMesh && (o.name === "Screen" || o.material?.name === "ScreenEmissive")) { screenMesh = o; screenMat = o.material; }
  });

  const loader = new THREE.TextureLoader();
  const textures = new Map();
  const texture = async (src) => {
    if (!textures.has(src)) {
      const t = await loader.loadAsync(src);
      t.colorSpace = THREE.SRGBColorSpace; t.flipY = false; t.anisotropy = renderer.capabilities.getMaxAnisotropy();
      textures.set(src, t);
    }
    return textures.get(src);
  };
  let index = 0;
  const show = async (i) => {
    index = (i + screens.length) % screens.length;
    const [name, src] = screens[index];
    caption.textContent = name;
    if (!screenMat) return;
    const t = await texture(src);
    if (screenMat.emissiveMap !== undefined) {
      screenMat.emissiveMap = t; screenMat.emissive = new THREE.Color(0xffffff);
      screenMat.emissiveIntensity = 2.3;   // ACES tone mapping dims the panel; this matches the Cycles renders
    }
    if (screenMat.map !== undefined) screenMat.map = t;
    screenMat.needsUpdate = true;
    pulse = 1;
  };
  screens.slice(1, 3).forEach(([, s]) => texture(s));   // warm the next two

  // Pointer: parallax look-around; a tap on the screen changes the page.
  const target = { x: 0.12, y: -0.42 };
  const current = { x: 0.12, y: -0.42 };
  let pulse = 0;
  const raycaster = new THREE.Raycaster(); const ndc = new THREE.Vector2();
  const pointerNDC = (e) => {
    const r = canvas.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    return r;
  };
  if (!reduceMotion) {
    addEventListener("pointermove", (e) => {
      const r = wrap.getBoundingClientRect();
      const nx = ((e.clientX - r.left) / r.width - 0.5) * 2, ny = ((e.clientY - r.top) / r.height - 0.5) * 2;
      target.y = -0.42 + Math.max(-1, Math.min(1, nx)) * 0.22;
      target.x = 0.12 + Math.max(-1, Math.min(1, ny)) * 0.12;
    }, { passive: true });
  }
  canvas.addEventListener("pointerdown", (e) => {
    const r = pointerNDC(e);
    raycaster.setFromCamera(ndc, camera);
    const hit = screenMesh ? raycaster.intersectObject(screenMesh, true)[0] : null;
    const ripple = document.createElement("span");
    ripple.className = "ripple";
    ripple.style.left = `${e.clientX - r.left}px`; ripple.style.top = `${e.clientY - r.top}px`;
    wrap.appendChild(ripple); setTimeout(() => ripple.remove(), 600);
    show(index + 1);
    if (!hit) pivot.rotation.y += 0.0001;   // a tap off the screen still counts
  });
  addEventListener("keydown", (e) => { if (e.target === canvas && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); show(index + 1); } });
  canvas.tabIndex = 0;

  const resize = () => {
    const w = wrap.clientWidth, h = wrap.clientHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.updateProjectionMatrix();
    frameCamera();
  };
  new ResizeObserver(resize).observe(wrap); resize();

  let visible = true;
  new IntersectionObserver(([en]) => { visible = en.isIntersecting; if (visible) frame(); }, { threshold: 0.05 }).observe(wrap);

  const base = rim.intensity;
  let last = performance.now();
  function frame(now = performance.now()) {
    if (!visible) return;
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    current.x += (target.x - current.x) * Math.min(1, dt * 6);
    current.y += (target.y - current.y) * Math.min(1, dt * 6);
    pivot.rotation.x = current.x; pivot.rotation.y = current.y;
    if (pulse > 0) { pulse = Math.max(0, pulse - dt * 2.5); rim.intensity = base * (1 + pulse * 0.6); }
    renderer.render(scene, camera);
    const settled = Math.abs(target.x - current.x) < 1e-4 && Math.abs(target.y - current.y) < 1e-4 && pulse === 0;
    if (!settled || !reduceMotion) requestAnimationFrame(frame);
  }
  await show(0);
  frame();
}
hero().catch(() => { document.getElementById("stage").hidden = true; document.getElementById("stage-fallback").hidden = false; });

// ---------- Screens reel
{
  const reel = document.getElementById("reel");
  const frames = [...reel.querySelectorAll(".frame")];
  const dots = document.getElementById("dots");
  frames.forEach((f, i) => {
    const b = document.createElement("button");
    b.setAttribute("aria-label", `Screen ${i + 1}`);
    b.addEventListener("click", () => f.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", inline: "center", block: "nearest" }));
    dots.appendChild(b);
  });
  const mark = () => {
    const mid = reel.scrollLeft + reel.clientWidth / 2;
    let best = 0, dist = Infinity;
    frames.forEach((f, i) => { const d = Math.abs(f.offsetLeft + f.offsetWidth / 2 - mid); if (d < dist) { dist = d; best = i; } });
    [...dots.children].forEach((d, i) => d.toggleAttribute("aria-current", i === best) || d.setAttribute("aria-current", i === best));
    return best;
  };
  const go = (delta) => { const i = Math.max(0, Math.min(frames.length - 1, mark() + delta)); frames[i].scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", inline: "center", block: "nearest" }); };
  document.getElementById("prev").addEventListener("click", () => go(-1));
  document.getElementById("next").addEventListener("click", () => go(1));
  reel.addEventListener("keydown", (e) => { if (e.key === "ArrowRight") go(1); if (e.key === "ArrowLeft") go(-1); });
  reel.addEventListener("scroll", () => requestAnimationFrame(mark), { passive: true });
  mark();
}

// ---------- Film: sound toggle
{
  const v = document.getElementById("promo"), b = document.getElementById("sound");
  b.setAttribute("aria-pressed", "false");
  b.addEventListener("click", () => {
    v.muted = !v.muted;
    b.setAttribute("aria-pressed", String(!v.muted));
    b.setAttribute("aria-label", v.muted ? "Turn sound on" : "Turn sound off");
    if (!v.muted) v.play().catch(() => {});
  });
}

// ---------- Version from GitHub, when reachable
fetch("https://api.github.com/repos/Shadowhusky/xeneon-toolbox/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
  .then((r) => r.ok ? r.json() : null)
  .then((j) => { if (j?.tag_name) document.getElementById("ver").textContent = j.tag_name; })
  .catch(() => {});
