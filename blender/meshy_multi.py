#!/usr/bin/env python3
"""Meshy MULTI-image-to-3D: reconstruct a mesh from several views.

  python3 meshy_multi.py <out.glb> <img1> <img2> [img3 ...]

Uses api.meshy.ai/openapi/v1/multi-image-to-3d (ai_model meshy-6). Multiple
views (esp. side/back) let Meshy recover the true thin proportions that a single
3/4 image can't. Key from MESHY_API_KEY or /tmp/meshy-key.
"""
import os, sys, json, base64, time, urllib.request, urllib.error

key = os.environ.get("MESHY_API_KEY")
if not key and os.path.exists("/tmp/meshy-key"):
    key = open("/tmp/meshy-key").read().strip()
if not key:
    print("no MESHY_API_KEY", file=sys.stderr); sys.exit(2)

out = sys.argv[1]
imgs = sys.argv[2:]
BASE = "https://api.meshy.ai/openapi/v1"


def data_url(p):
    raw = open(p, "rb").read()
    ext = p.lower().rsplit(".", 1)[-1]
    mime = "image/jpeg" if ext in ("jpg", "jpeg") else "image/png"
    return f"data:{mime};base64," + base64.b64encode(raw).decode()


body = json.dumps({
    "image_urls": [data_url(p) for p in imgs],
    "ai_model": "meshy-6",
    "should_texture": True, "enable_pbr": True,
    "target_formats": ["glb"], "target_polycount": 30000,
}).encode()
req = urllib.request.Request(f"{BASE}/multi-image-to-3d", data=body,
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
try:
    r = json.load(urllib.request.urlopen(req, timeout=60))
except urllib.error.HTTPError as e:
    print("CREATE HTTP", e.code, e.read().decode()[:500], file=sys.stderr); sys.exit(1)
tid = r.get("result") or r.get("id")
print("TASK", tid, flush=True)

start = time.time()
while time.time() - start < 600:
    time.sleep(6)
    pr = urllib.request.Request(f"{BASE}/multi-image-to-3d/{tid}", headers={"Authorization": f"Bearer {key}"})
    try:
        t = json.load(urllib.request.urlopen(pr, timeout=60))
    except urllib.error.HTTPError as e:
        print("POLL HTTP", e.code, e.read().decode()[:300], file=sys.stderr); continue
    st = t.get("status")
    print("STATUS", st, t.get("progress"), flush=True)
    if st == "SUCCEEDED":
        glb = (t.get("model_urls") or {}).get("glb")
        if not glb:
            print("no glb", file=sys.stderr); sys.exit(1)
        open(out, "wb").write(urllib.request.urlopen(glb, timeout=180).read())
        print("OK", out); sys.exit(0)
    if st in ("FAILED", "CANCELED"):
        print("FAIL", t.get("task_error"), file=sys.stderr); sys.exit(1)
print("TIMEOUT", file=sys.stderr); sys.exit(1)
