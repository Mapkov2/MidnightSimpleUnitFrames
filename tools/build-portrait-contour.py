"""Build the standalone gold portrait rim and its matching coverage mask.

The contour is analytic: three circular quadrants and a gently rounded lower
right corner. Both files share one distance field and one pixel grid. No client
atlas crops or third-party artwork are inputs. Run from any directory.
"""
from math import hypot
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
SIZE = 256
RADIUS = 124.0
CORNER = 8.0
STROKE = 8.0


def distance(x, y):
    if x <= 0 or y <= 0:
        return hypot(x, y) - RADIUS
    qx, qy = x - (RADIUS - CORNER), y - (RADIUS - CORNER)
    return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - CORNER


def coverage(distance):
    return max(0.0, min(1.0, 0.5 - distance))


def write_tga(path, pixels):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Uncompressed BGRA, top-left origin, eight alpha bits.
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    path.write_bytes(header + pixels)


def build():
    mask, rim = bytearray(), bytearray()
    for row in range(SIZE):
        for col in range(SIZE):
            x, y = col + 0.5 - SIZE / 2, row + 0.5 - SIZE / 2
            d = distance(x, y)
            outer = coverage(d)
            inner = coverage(d + STROKE)
            alpha = round(255 * (outer - inner))
            # The portrait ends inside the opaque middle of the rim, so neither
            # its antialiasing nor transparent texels can leak beyond the gold.
            mask_alpha = round(255 * coverage(d + STROKE / 2))
            mask.extend((255, 255, 255, mask_alpha))
            t = max(0.0, min(1.0, -d / STROKE))
            bevel = max(0.0, 1.0 - abs(t - 0.4) / 0.6)
            light = 0.76 + 0.19 * bevel - 0.08 * y / RADIUS
            red, green, blue = [round(min(255, v * light)) for v in (255, 207, 94)]
            rim.extend((blue, green, red, alpha))
    media = ROOT / 'MidnightSimpleUnitFrames/Media'
    write_tga(media / 'Masks/portrait_blizzard_mask.tga', mask)
    write_tga(media / 'Borders/msuf_portrait_ring_blizzard.tga', rim)


if __name__ == '__main__':
    build()
