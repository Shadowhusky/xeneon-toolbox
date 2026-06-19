#!/usr/bin/env python3
"""Meshy image-to-3D: turn a product photo into a .glb mesh.

  python3 meshy_gen.py <input_image> <out.glb> [polycount]

Mirrors makewise-3dgen's Meshy client (api.meshy.ai/openapi/v1, ai_model
meshy-6). Key from MESHY_API_KEY env or /tmp/meshy-key (outside the repo).
"""
import os, sys, json, base64, time, urllib.request, urllib.error

key = os.environ.get("MESHY_API_KEY")
if not key and os.path.exists("/tmp/meshy-key"):
    key = open("/tmp/meshy-key").read().strip()
if not key:
    print("no MESHY_API_KEY", file=sys.stderr); sys.exit(2)

img, out = sys.argv[1], sys.argv[2]
poly = int(sys.argv[3]) if len(sys.argv) > 3 else 30000
BASE = "https://api.meshy.ai/openapi/v1"

raw = open(img, "rb").read()
ext = img.lower().rsplit(".", 1)[-1]
mime = "image/jpeg" if ext in ("jpg", "jpeg") else "image/png"
data_url = f"data:{mime};base64," + base64.b64encode(raw).decode()

body = json.dumps({
    "image_url": data_url, "ai_model": "meshy-6",
    "should_texture": True, "enable_pbr": True,
    "target_formats": ["glb"], "target_polycount": poly,
}).encode()
req = urllib.request.Request(f"{BASE}/image-to-3d", data=body,
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
try:
    r = json.load(urllib.request.urlopen(req, timeout=60))
except urllib.error.HTTPError as e:
    print("CREATE HTTP", e.code, e.read().decode()[:400], file=sys.stderr); sys.exit(1)
tid = r.get("result") or r.get("id")
print("TASK", tid, flush=True)

start = time.time()
while time.time() - start < 600:
    time.sleep(6)
    pr = urllib.request.Request(f"{BASE}/image-to-3d/{tid}", headers={"Authorization": f"Bearer {key}"})
    try:
        t = json.load(urllib.request.urlopen(pr, timeout=60))
    except urllib.error.HTTPError as e:
        print("POLL HTTP", e.code, e.read().decode()[:300], file=sys.stderr); continue
    st = t.get("status")
    print("STATUS", st, t.get("progress"), flush=True)
    if st == "SUCCEEDED":
        glb = (t.get("model_urls") or {}).get("glb")
        if not glb:
            print("no glb url", file=sys.stderr); sys.exit(1)
        d = urllib.request.urlopen(glb, timeout=180).read()
        open(out, "wb").write(d)
        print("OK", out, len(d), "bytes")
        sys.exit(0)
    if st in ("FAILED", "CANCELED"):
        print("FAIL", t.get("task_error"), file=sys.stderr); sys.exit(1)
print("TIMEOUT", file=sys.stderr); sys.exit(1)
