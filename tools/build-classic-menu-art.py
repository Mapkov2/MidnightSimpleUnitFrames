"""Rebuild MSUF's original atlas UI textures (Pillow; no external artwork).

Power-of-two RGBA TGA assets use the existing panel nine-slice and control
three-slice contracts. All decoration is baked; no runtime drawing/tickers.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "MidnightSimpleUnitFrames/Media/Menu2/Classic"
SCALE = 4


def canvas(w, h):
    return Image.new("RGBA", (w * SCALE, h * SCALE))


def poly(im, points, fill, line=None, width=1):
    draw = ImageDraw.Draw(im)
    pts = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
    if fill:
        draw.polygon(pts, fill=fill)
    if line:
        draw.line(pts + [pts[0]], fill=line, width=round(width * SCALE), joint="curve")


def bevel(im, box, cut, fill, line=None, width=1):
    x, y, r, b = box
    poly(im, [(x + cut, y), (r - cut, y), (r, y + cut),
              (r, b - cut), (r - cut, b), (x + cut, b),
              (x, b - cut), (x, y + cut)], fill, line, width)


def save(im, name):
    im = im.resize((im.width // SCALE, im.height // SCALE), Image.Resampling.LANCZOS)
    im.save(OUT / (name + ".tga"))


def panel(name, fill, border, strong=False):
    im = canvas(128, 128)
    # One fine rim, no nested bevels or black grooves around every panel.
    bevel(im, (2, 2, 125, 125), 4, fill, border if strong else None, 0.6)
    # Horizontal engraved lines live inside nine-slice edges. The flat center
    # stays flat so enlarging a panel cannot stretch grain beneath labels.
    d = ImageDraw.Draw(im)
    d.line((12*SCALE, 3*SCALE, 115*SCALE, 3*SCALE), fill=(213, 182, 129, 35 if strong else 12), width=2)
    if strong:
        for cx, cy in ((7, 7), (120, 7), (7, 120), (120, 120)):
            poly(im, [(cx, cy-2), (cx+2, cy), (cx, cy+2), (cx-2, cy)],
                 (169, 130, 82, 200))
    save(im, name)


def compass(im, cx, cy, radius, alpha=255):
    d = ImageDraw.Draw(im)
    ink = (169, 130, 82, alpha)
    for r in (radius*.72, radius*.80):
        d.ellipse(tuple(round(v*SCALE) for v in (cx-r, cy-r, cx+r, cy+r)), outline=ink, width=2)
    for i in range(16):
        a = i * math.pi / 8
        r = radius if i % 4 == 0 else radius*.67 if i % 2 == 0 else radius*.43
        tip = (cx + math.sin(a)*r, cy - math.cos(a)*r)
        left = (cx + math.sin(a-.65)*radius*.14, cy - math.cos(a-.65)*radius*.14)
        right = (cx + math.sin(a+.65)*radius*.14, cy - math.cos(a+.65)*radius*.14)
        poly(im, [(cx, cy), left, tip], (212, 180, 124, alpha))
        poly(im, [(cx, cy), right, tip], (101, 126, 136, alpha))
    d.ellipse(tuple(round(v*SCALE) for v in (cx-2, cy-2, cx+2, cy+2)), fill=(238, 229, 212, alpha))


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    # Keep the glass, but shield navigation and reading surfaces from scenery.
    # shell + host + card transmit ~5% of the game scene at their centers.
    panel("shell", (9, 18, 30, 230), (142, 133, 111, 75), True)
    panel("rail", (14, 27, 43, 87), (0, 0, 0, 0))
    panel("host", (18, 34, 53, 41), (0, 0, 0, 0))
    panel("status", (14, 27, 43, 77), (0, 0, 0, 0))
    panel("card", (22, 35, 46, 92), (0, 0, 0, 0))
    panel("popup", (11, 23, 37, 245), (142, 133, 111, 110), True)
    for state, fill, edge in (
        ("idle", (14, 27, 43, 65), (97, 106, 110, 50)),
        ("hover", (53, 67, 77, 117), (164, 150, 116, 85)),
        ("active", (38, 51, 62, 122), (216, 182, 106, 105)),
    ):
        im = canvas(256, 32)
        bevel(im, (1, 1, 254, 30), 4, fill, edge)
        if state == "active":
            poly(im, [(6, 11), (10, 15.5), (6, 20), (3, 15.5)], (238, 229, 212, 255))
        save(im, "nav_" + state)
    # The existing three-slice renderer samples quarters. A short horizontal
    # bevel remains crisp when the new 4px cap is stretched vertically.
    im = canvas(64, 64)
    bevel(im, (0, 0, 63, 63), 10, (255, 255, 255, 255))
    save(im, "bevel")
    for name, w, h, cut, edge in (
        ("check_fill", 32, 32, 3, False), ("check_edge", 32, 32, 3, True),
        ("switch_track", 64, 32, 4, False), ("switch_knob", 32, 32, 4, False),
    ):
        im = canvas(w, h)
        bevel(im, (2, 2, w-3, h-3), cut, (255, 255, 255, 255))
        if edge:
            bevel(im, (4, 4, w-5, h-5), 2, (0, 0, 0, 0))
        save(im, name)
    im = canvas(32, 32)
    # Neutral luminance: StyleSlider supplies the bronze (or saved accent).
    bevel(im, (7, 3, 24, 28), 3, (230, 230, 230, 255), (255, 255, 255, 255))
    bevel(im, (9, 5, 22, 26), 2, (205, 205, 205, 255), (95, 95, 95, 255))
    d = ImageDraw.Draw(im)
    for x in (14, 17):
        d.line((x*SCALE, 11*SCALE, x*SCALE, 20*SCALE), fill=(255, 255, 255, 230), width=SCALE)
    save(im, "slider_thumb")
    im = canvas(128, 128)
    for row in range(4):
        y = row * 32
        bevel(im, (1, y+3, 95, y+28), 3, (18, 51, 79, 255), (70, 116, 141, 120))
        d = ImageDraw.Draw(im)
        for x in (32, 64):
            d.line((x*SCALE, (y+4)*SCALE, x*SCALE, (y+27)*SCALE), fill=(70, 116, 141, 120), width=SCALE)
        if row:
            x = (row-1)*32
            bevel(im, (x+2, y+4, x+30, y+27), 2,
                  (92, 40, 37, 255) if row == 3 else (32, 95, 131, 255),
                  (209, 106, 91, 255) if row == 3 else (92, 191, 231, 180))
    save(im, "window_controls")
    im = canvas(128, 128)
    compass(im, 64, 64, 58)
    save(im, "compass")
    im = canvas(512, 128)
    d = ImageDraw.Draw(im)
    for x in range(24, 512, 40):
        d.line((x*SCALE, 0, (x-40)*SCALE, 128*SCALE), fill=(110, 154, 169, 85), width=2)
    for y in (24, 64, 104):
        d.line((0, y*SCALE, 512*SCALE, y*SCALE), fill=(110, 154, 169, 85), width=2)
    # Original abstract coastlines, not a reproduction of Blizzard's map.
    for offset in (0, 8, 16):
        pts = [(x, 57 + offset + 15*math.sin(x/31) + 7*math.sin(x/11)) for x in range(8, 325, 3)]
        d.line([(x*SCALE, round(y*SCALE)) for x, y in pts], fill=(151, 177, 177, 150-offset*5), width=2)
    compass(im, 415, 64, 56)
    save(im, "chart")
    print(f"Built {len(list(OUT.glob('*.tga')))} atlas textures in {OUT}")


if __name__ == "__main__":
    build()
