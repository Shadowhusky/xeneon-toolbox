#!/usr/bin/env python3
"""Generate Xeneon Edge concept/mockup images with gpt-image-2.

  python3 gen-concept.py <out.png> "<prompt>" [input1.png input2.png ...]

With input images -> /v1/images/edits (multipart), so output is grounded in the
real product photo. Without -> /v1/images/generations. Key from OPENAI_API_KEY
or /tmp/oai-key (kept outside the repo; never committed).
"""
import os, sys, json, base64, uuid, urllib.request, urllib.error

key = os.environ.get("OPENAI_API_KEY")
if not key and os.path.exists("/tmp/oai-key"):
    key = open("/tmp/oai-key").read().strip()
if not key:
    print("no key", file=sys.stderr); sys.exit(2)

out, prompt = sys.argv[1], sys.argv[2]
imgs = sys.argv[3:]
MODEL, SIZE = "gpt-image-2", "1536x1024"

if imgs:
    boundary = "----b" + uuid.uuid4().hex
    buf = bytearray()
    def field(name, val):
        buf.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{val}\r\n').encode())
    field("model", MODEL); field("prompt", prompt); field("size", SIZE)
    field("quality", "high"); field("n", "1")
    for p in imgs:
        buf.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="image[]"; '
                    f'filename="{os.path.basename(p)}"\r\nContent-Type: image/png\r\n\r\n').encode())
        buf.extend(open(p, "rb").read()); buf.extend(b"\r\n")
    buf.extend((f'--{boundary}--\r\n').encode())
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/edits", data=bytes(buf),
        headers={"Authorization": f"Bearer {key}", "Content-Type": f"multipart/form-data; boundary={boundary}"})
else:
    data = json.dumps({"model": MODEL, "prompt": prompt, "size": SIZE, "quality": "high", "n": 1}).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=data,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})

try:
    resp = urllib.request.urlopen(req, timeout=420)
    d = json.load(resp)
    open(out, "wb").write(base64.b64decode(d["data"][0]["b64_json"]))
    print("OK", out)
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read().decode()[:800], file=sys.stderr); sys.exit(1)
