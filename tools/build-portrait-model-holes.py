"""Build the inverted shape masks that cut the solid ring of a 3D portrait.

The solid ring of a shaped portrait is a filled shape drawn under the image.
Opaque 2D art hides its middle; a 3D model has a transparent background, so
the ring texture carries a second mask: the shipped portrait mask, inverted.
Each output keeps a white margin of PAD texels (RING_HOLE_PAD = 0.5 of the
shape) on every side, so CLAMP wrapping repeats white past the edges and a
ring wider than the margin keeps its outer band. Inputs are MSUF's own masks.
Run from any directory.
"""
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
MASKS = ROOT / 'MidnightSimpleUnitFrames/Media/Masks'
SHAPES = ('circle', 'rounded', 'diamond')
PAD_FRACTION = 0.5


def read_tga(path):
    data = path.read_bytes()
    id_length, color_map, image_type = data[0], data[1], data[2]
    width, height, depth, descriptor = struct.unpack('<HHBB', data[12:18])
    if color_map != 0 or image_type != 2 or depth != 32:
        raise SystemExit(f'{path.name}: expected an uncompressed 32-bit TGA')
    pixels = data[18 + id_length:18 + id_length + width * height * 4]
    top_origin = descriptor & 0x20 != 0
    rows = [pixels[r * width * 4:(r + 1) * width * 4] for r in range(height)]
    if not top_origin:
        rows.reverse()
    return width, height, rows


def write_tga(path, size, pixels):
    # Uncompressed BGRA, top-left origin, eight alpha bits.
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    path.write_bytes(header + pixels)


def build_hole(shape):
    width, height, rows = read_tga(MASKS / f'{shape}_mask.tga')
    if width != height:
        raise SystemExit(f'{shape}_mask.tga: expected a square mask')
    pad = round(width * PAD_FRACTION)
    size = width + 2 * pad
    out = bytearray()
    for row in range(size):
        for col in range(size):
            x, y = col - pad, row - pad
            alpha = 255
            if 0 <= x < width and 0 <= y < height:
                alpha = 255 - rows[y][x * 4 + 3]
            out.extend((255, 255, 255, alpha))
    write_tga(MASKS / f'portrait_model_hole_{shape}.tga', size, out)


if __name__ == '__main__':
    for name in SHAPES:
        build_hole(name)
