"""Renders the promo film's caption plates (transparent 1920x1080 PNGs) so ffmpeg
can overlay them without a freetype build. Usage: captions.py <out dir> <n> <text>..."""
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
FONTS = [
    "/System/Library/Fonts/SFCompact.ttf",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
]

def font(size, bold=False):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, size, index=1 if bold and path.endswith(".ttc") else 0)
        except Exception:
            continue
    return ImageFont.load_default()

def plate(path, text, sub=None, centre=False):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(88 if centre else 54, bold=True)
    if centre:
        tw = d.textlength(text, font=f)
        d.text(((W - tw) / 2, H / 2 - 90), text, font=f, fill=(236, 233, 225, 255))
        if sub:
            fs = font(38)
            sw = d.textlength(sub, font=fs)
            d.text(((W - sw) / 2, H / 2 + 26), sub, font=fs, fill=(245, 181, 68, 255))
    else:
        # A soft plate behind the caption so it reads over any screenshot.
        d.rounded_rectangle((72, H - 190, 72 + d.textlength(text, font=f) + 64, H - 92), radius=18, fill=(10, 11, 13, 170))
        d.rounded_rectangle((72, H - 190, 76, H - 92), radius=2, fill=(245, 181, 68, 255))
        d.text((104, H - 172), text, font=f, fill=(236, 233, 225, 255))
    img.save(path)

if __name__ == "__main__":
    out = sys.argv[1]
    mode = sys.argv[2]
    if mode == "end":
        plate(f"{out}/end.png", sys.argv[3], sys.argv[4], centre=True)
    else:
        for i, text in enumerate(sys.argv[3:]):
            plate(f"{out}/cap{i}.png", text)
