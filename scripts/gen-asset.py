#!/usr/bin/env python3
"""Generate a transparent PNG sprite via OpenAI images (gpt-image-2).

Usage: OPENAI_API_KEY=... python3 scripts/gen-asset.py "<prompt>" out.png [size]
Mirrors the shanhai asset pipeline: gpt-image-2, high quality, transparent bg.
"""
import os, sys, json, base64, urllib.request, urllib.error

key = os.environ.get("OPENAI_API_KEY")
if not key:
    print("OPENAI_API_KEY not set", file=sys.stderr); sys.exit(2)

prompt, out = sys.argv[1], sys.argv[2]
size = sys.argv[3] if len(sys.argv) > 3 else "1024x1024"
body = json.dumps({
    "model": "gpt-image-2", "prompt": prompt, "size": size,
    "quality": "high", "n": 1,
}).encode()
req = urllib.request.Request(
    "https://api.openai.com/v1/images/generations", data=body,
    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
try:
    resp = urllib.request.urlopen(req, timeout=240)
    data = json.load(resp)
    b64 = data["data"][0]["b64_json"]
    with open(out, "wb") as f:
        f.write(base64.b64decode(b64))
    print("OK", out)
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read().decode()[:600], file=sys.stderr); sys.exit(1)
