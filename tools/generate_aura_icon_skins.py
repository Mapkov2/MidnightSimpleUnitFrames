"""Generate the aura icon skin textures in MidnightSimpleUnitFrames/Media/Skins.

Every texture is computed from closed-form profiles, so the art is original and
byte-reproducible: no pixel of any other addon's art is used. The shape lives in
alpha; RGB carries grey shading (bevels, metal) or plain white. The runtime
tints each layer once with SetVertexColor, so one grey frame serves every metal
colour and every user colour.

Two kinds of texture:
  * Edge files (bands) use Blizzard's backdrop edgeFile layout (256x32, eight
    32x32 tiles: left, right, top, bottom, TL, TR, BL, BR), drawn by
    MSUF.BorderStyles as eight pieces so a band keeps its width on any icon
    size or aspect. The visible part of each tile is its inner 28x28 window
    (the backdrop UVs inset 1/16); the margins repeat the window's border. Left
    and top tiles have the band's outer side at tile x=0, right and bottom
    tiles at x=31 (BorderStyles maps top/bottom strips through a rotated tile).
    Top and left tiles are lit, bottom and right shaded, for bevels.
  * Quads (rings, gloss) are single textures laid over the icon plus `extent`
    u on every side, for shapes that cannot be sliced (circles, rounded rings).

Distances are in "u", 1/32 of the icon side. `d` is the signed distance from
the icon outline in u, positive outward.

Usage:
  python tools/generate_aura_icon_skins.py            # write the media
  python tools/generate_aura_icon_skins.py --check    # exit 1 when the files differ
  python tools/generate_aura_icon_skins.py --preview out.png   # needs Pillow

Generation itself is plain Python (no Pillow), so the gate smoke can rebuild
the textures on any machine and compare them byte for byte.
"""

import argparse
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "MidnightSimpleUnitFrames" / "Media" / "Skins"
# Spans and extents per texture, for the Lua smoke that checks the catalog.
MANIFEST = ROOT / "tools" / "aura_icon_skins_manifest.tsv"
TILE = 32
WINDOW_LO, WINDOW_HI = 2, 30  # visible texels of a tile, [lo, hi)
SUB = 4  # supersamples per axis
ROUNDED_RADIUS = 5.1  # u; MSUF's Media/Masks/rounded_mask.tga corner (16% of the side)


def clamp01(value):
    return max(0.0, min(1.0, value))


def ramp(value, power):
    return clamp01(value) ** power


def step(edge, d, soft=0.5):
    """1 below `edge`, 0 above, with a `soft` u antialiased transition."""
    return clamp01((edge - d) / soft + 0.5)


def window(d, lo, hi, soft=0.5):
    """1 while lo <= d <= hi (antialiased)."""
    return min(step(hi, d, soft), step(-lo, -d, soft))


def rounded_distance(dx, dy, radius):
    """Signed distance to the outline of a square whose straight edges are at
    dx = 0 and dy = 0 (positive outward) and whose corner has `radius`."""
    if radius <= 0:
        if dx > 0 and dy > 0:
            return math.hypot(dx, dy)
        return max(dx, dy)
    qx, qy = dx + radius, dy + radius
    if qx > 0 and qy > 0:
        return math.hypot(qx, qy) - radius
    return max(qx, qy) - radius


# ---------------------------------------------------------------- bands
class Band:
    """A band from `outer` u outside to `inner` u inside the icon edge.

    shade: "vignette" combines the two edge profiles inside the icon (corners
    read darker) and uses the Euclidean distance outside; "frame" uses the
    signed distance to the (optionally rounded) outline.
    alpha(d) and lum(d) take the signed distance; light is the bevel strength.
    """

    def __init__(self, outer, inner, alpha, lum=None, shade="frame", radius=0.0, light=0.0):
        self.outer, self.inner = outer, inner
        self.alpha, self.lum = alpha, lum or (lambda d: 1.0)
        self.shade, self.radius, self.light = shade, radius, light

    def sample(self, tx, ty, lit):
        span = self.outer + self.inner
        dx = self.outer - tx * span
        dy = self.outer - ty * span
        if self.shade == "vignette":
            if dx > 0 and dy > 0:
                return self.alpha(math.hypot(dx, dy)), 1.0
            if dx > 0 or dy > 0:
                return self.alpha(max(dx, dy)), 1.0
            ax, ay = self.alpha(dx), self.alpha(dy)
            return 1 - (1 - ax) * (1 - ay), 1.0
        d = rounded_distance(dx, dy, self.radius)
        return self.alpha(d), clamp01(self.lum(d) + self.light * lit)


class RoundedFrame(Band):
    """An opaque frame between a rounded outer outline `outer` u outside the
    icon edge (corner `radius_out`) and a rounded inner outline `inner` u
    inside it (corner `radius_in`). The outer corner must stay close enough to
    cover the icon's square corner: 0.414 * (radius_out - outer) <= 0 is not
    required, only that the icon corner lies inside the outer outline.
    lum(depth, gap) gets the depth below the outer outline and the gap to the
    inner one, both in u."""

    def __init__(self, outer, inner, radius_out, radius_in, lum, light=0.0):
        super().__init__(outer, inner, None, None, "rounded", 0.0, light)
        self.radius_out, self.radius_in, self.shade_fn = radius_out, radius_in, lum

    def sample(self, tx, ty, lit):
        span = self.outer + self.inner
        dx = self.outer - tx * span
        dy = self.outer - ty * span
        d_out = rounded_distance(dx - self.outer, dy - self.outer, self.radius_out)
        d_in = rounded_distance(dx + self.inner, dy + self.inner, self.radius_in)
        alpha = step(0.0, d_out) * step(0.0, -d_in)
        return alpha, clamp01(self.shade_fn(-d_out, d_in) + self.light * lit)


def vignette(outer_fn, inner_fn):
    return lambda d: outer_fn(d) if d > 0 else inner_fn(-d)


BANDS = {
    # Shadow family. Soft drop shadow plus inner vignette.
    "msuf_skin_shadow_soft": Band(4.0, 10.0, vignette(
        lambda d: 0.85 * ramp(1 - d / 4.0, 1.6), lambda d: 0.85 * ramp(1 - d / 10.0, 1.8)), shade="vignette"),
    "msuf_skin_shadow_outer": Band(4.0, 0.0, vignette(
        lambda d: 0.85 * ramp(1 - d / 4.0, 1.6), lambda d: 0.0), shade="vignette"),
    "msuf_skin_shadow_hard": Band(0.0, 13.0, vignette(
        lambda d: 0.0, lambda d: 0.75 * ramp(1 - d / 13.0, 2.6)), shade="vignette"),
    "msuf_skin_shadow_ring": Band(3.75, 5.0, vignette(
        lambda d: ramp(1 - d / 3.75, 1.5), lambda d: ramp(1 - d / 5.0, 1.5)), shade="vignette"),
    # Dark family: inner vignettes.
    "msuf_skin_vignette_crisp": Band(0.0, 9.0, vignette(
        lambda d: 0.0, lambda d: ramp(1 - d / 9.0, 3.0)), shade="vignette"),
    "msuf_skin_vignette_soft": Band(0.0, 14.0, vignette(
        lambda d: 0.0, lambda d: 0.67 * ramp(1 - d / 14.0, 1.8)), shade="vignette"),
    "msuf_skin_vignette_heavy": Band(0.0, 11.0, vignette(
        lambda d: 0.0, lambda d: ramp(1 - d / 11.0, 1.8)), shade="vignette"),
    # Frame family: opaque frames that cover the icon's outer edge.
    "msuf_skin_frame_slim": Band(0.5, 2.5, lambda d: window(d, -2.5, 0.5),
                                 lambda d: 0.45 if d < -1.9 else 0.12, light=0.06),
    "msuf_skin_frame_bold": Band(1.0, 4.0, lambda d: window(d, -4.0, 1.0),
                                 lambda d: 0.5 if d < -3.3 else (0.3 if d > 0.3 else 0.1), light=0.08),
    "msuf_skin_frame_double": Band(0.7, 2.9, lambda d: max(window(d, -0.5, 0.7, 0.4), window(d, -2.9, -2.0, 0.4)),
                                   lambda d: 1.0),
    "msuf_skin_frame_bevel": Band(0.5, 3.0, lambda d: window(d, -3.0, 0.5),
                                  lambda d: 0.06 + 0.44 * clamp01((d + 3.0) / 3.5), light=0.12),
    "msuf_skin_frame_dark": Band(1.0, 7.0, lambda d: window(d, -3.5, 1.0) if d > -3.5 else 0.6 * ramp(1 - (-d - 3.5) / 3.5, 1.4),
                                 lambda d: 0.08 if d > -3.5 else 0.0, light=0.04),
    "msuf_skin_frame_clean": Band(0.8, 5.0, lambda d: window(d, -2.0, 0.8) if d > -2.0 else 0.4 * ramp(1 - (-d - 2.0) / 3.0, 1.4),
                                  lambda d: 0.1 if d > -2.0 else 0.0, light=0.03),
    # Rounded frames: the outer corner stays close enough to cover the icon's
    # square corner (0.414 * radius <= outer), the inner corner is rounder.
    "msuf_skin_frame_rounded": RoundedFrame(2.0, 3.5, 4.0, 2.0,
                                            lambda depth, gap: 0.4 if gap < 0.7 else 0.14, light=0.06),
    "msuf_skin_frame_steel": RoundedFrame(2.0, 3.5, 4.0, 2.0,
                                          lambda depth, gap: 0.92 if depth < 0.8 else (0.85 if gap < 0.9 else 0.45),
                                          light=0.15),
    # Metal frame, grey bevel tinted per metal by the skin colour.
    "msuf_skin_metal_frame": Band(1.0, 4.0, lambda d: window(d, -4.0, 1.0),
                                  lambda d: (0.95 if d > 0.3 else (0.85 if d < -3.4 else (0.25 if -3.0 < d < -2.4 else 0.6))),
                                  radius=0.5, light=0.18),
}


def band_tile_sample(band, tile, u, v):
    far = 1e3  # along an edge strip the other axis lies far inside the icon
    lit = {0: 1.0, 2: 1.0, 1: -1.0, 3: -1.0, 4: 1.0, 5: 0.0, 6: 0.0, 7: -1.0}[tile]
    if tile in (0, 2):
        return band.sample(u, far, lit)
    if tile in (1, 3):
        return band.sample(1 - u, far, lit)
    if tile == 4:
        return band.sample(u, v, lit)
    if tile == 5:
        return band.sample(1 - u, v, lit)
    if tile == 6:
        return band.sample(u, 1 - v, lit)
    return band.sample(1 - u, 1 - v, lit)


class Canvas:
    """Texels with alpha and grey level, row 0 at the top."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.alpha = [[0] * width for _ in range(height)]
        self.lum = [[255] * width for _ in range(height)]


def supersample(fn, px, py, width):
    alpha_sum, lum_sum = 0.0, 0.0
    for sy in range(SUB):
        for sx in range(SUB):
            alpha, lum = fn((px + (sx + 0.5) / SUB) / width, (py + (sy + 0.5) / SUB) / width)
            alpha_sum += alpha
            lum_sum += lum * alpha
    alpha = alpha_sum / (SUB * SUB)
    lum = lum_sum / alpha_sum if alpha_sum > 0 else 1.0
    return alpha, lum


def window_coord(texel):
    clamped = min(max(texel, WINDOW_LO), WINDOW_HI - 1)
    return clamped - WINDOW_LO


def render_band(band):
    width = WINDOW_HI - WINDOW_LO
    image = Canvas(TILE * 8, TILE)
    for tile in range(8):
        cache = {}
        for y in range(TILE):
            for x in range(TILE):
                key = (window_coord(x), window_coord(y))
                if key not in cache:
                    cache[key] = supersample(lambda u, v, t=tile: band_tile_sample(band, t, u, v), key[0], key[1], width)
                alpha, lum = cache[key]
                image.alpha[y][tile * TILE + x] = round(255 * clamp01(alpha))
                image.lum[y][tile * TILE + x] = round(255 * clamp01(lum))
    return image


# ---------------------------------------------------------------- quads
class Quad:
    """A single texture over the icon plus `extent` u on every side.
    fn(x, y) gets icon-centred coordinates in u (the icon spans -16..16) and
    returns (alpha, lum)."""

    def __init__(self, extent, fn, size=128):
        self.extent, self.fn, self.size = extent, fn, size

    def sample(self, u, v):
        span = 32 + 2 * self.extent
        return self.fn(u * span - span / 2, v * span - span / 2)


def circle_d(x, y):
    return math.hypot(x, y) - 16.0


def rounded_d(x, y):
    return rounded_distance(abs(x) - 16.0, abs(y) - 16.0, ROUNDED_RADIUS)


def top_light(y, strength):
    return strength * clamp01(-y / 16.0)  # brighter toward the top (y < 0)


def gloss_crescent(x, y):
    u, v = (x + 16) / 32, (y + 16) / 32
    e = ((u - 0.5) / 0.62) ** 2 + ((v + 0.18) / 0.62) ** 2
    if e >= 1:
        return 0.0, 1.0
    return 0.9 * ramp(1 - e, 0.55) * ramp(1 - v / 0.46, 1.2), 1.0


def gloss_sheen(x, y):
    u, v = (x + 16) / 32, (y + 16) / 32
    distance = abs((u + v) - 0.62) / 0.16
    return 0.7 * ramp(1 - distance, 1.4) * ramp(1 - (u + v) / 1.4, 0.8), 1.0


def gloss_top(x, y):
    """Glassy band over the upper part of a square icon."""
    v = (y + 16) / 32
    edge = clamp01((15.5 - abs(x)) / 1.0) * clamp01((y + 15.5) / 1.0)
    return edge * 0.75 * ramp(1 - v / 0.42, 1.3), 1.0


def gloss_dome(x, y):
    """Dome highlight inside a circle."""
    r = math.hypot(x, y + 5.5) / 10.5
    inside = clamp01((15.0 - math.hypot(x, y)) / 1.0)
    return inside * 0.8 * ramp(1 - r, 1.2) * clamp01(-(y - 2.0) / 4.0), 1.0


def glass_gloss(x, y):
    inside = clamp01(-rounded_d(x, y) - 1.0)
    return inside * 0.65 * ramp(1 - (y + 16) / 14.0, 1.4), 1.0


def ring_segmented(x, y):
    d = circle_d(x, y)
    angle = (math.degrees(math.atan2(y, x)) + 360) % 45.0
    gap = clamp01((min(angle, 45.0 - angle) - 2.5) / 1.0)
    outer = window(d, 0.6, 3.6, 0.4) * gap
    inner = window(d, -1.3, -0.3, 0.4)
    return max(outer, inner), clamp01(0.72 + top_light(y, 0.25) - (0.15 if outer else 0.0))


def ring_simple(x, y):
    d = circle_d(x, y)
    return max(window(d, 0.3, 1.3, 0.4), window(d, 2.3, 3.0, 0.4)), clamp01(0.8 + top_light(y, 0.2))


def shadow_round(x, y):
    d = circle_d(x, y)
    if d < 0:
        return 0.0, 0.0
    return 0.85 * ramp(1 - d / 5.0, 1.6), 0.0


def gear_ring(x, y):
    d = circle_d(x, y)
    angle = (math.degrees(math.atan2(y, x)) + 360) % 22.5
    tooth = clamp01((5.0 - min(angle, 22.5 - angle)) / 1.2)
    body = window(d, -0.8, 3.0, 0.4)
    teeth = window(d, 2.5, 5.2, 0.4) * tooth
    groove = window(d, -0.8, 0.0, 0.3)
    lum = 0.62 + top_light(y, 0.28) - 0.35 * groove - (0.1 if teeth > body else 0.0)
    return max(body, teeth), clamp01(lum)


def orb_ring(x, y):
    d = circle_d(x, y)
    light = window(d, -0.6, 1.4, 0.4)
    dark = window(d, 1.4, 4.0, 0.4)
    return max(light, dark), clamp01((0.92 if light >= dark else 0.08) + top_light(y, 0.08))


def orb_thin(x, y):
    d = circle_d(x, y)
    light = window(d, -0.4, 0.8, 0.4)
    dark = window(d, 0.8, 2.2, 0.4)
    return max(light, dark), clamp01((0.95 if light >= dark else 0.1) + top_light(y, 0.05))


def glass_ring(x, y):
    d = rounded_d(x, y)
    light = window(d, -1.0, 0.8, 0.4)
    dark = window(d, 0.8, 1.8, 0.4)
    return max(light, dark), clamp01((1.0 if light >= dark else 0.1))


def glass_thick(x, y):
    d = rounded_d(x, y)
    light = window(d, -1.0, 1.0, 0.4)
    dark = window(d, 1.0, 3.5, 0.4)
    return max(light, dark), clamp01((0.85 if light >= dark else 0.1) + top_light(y, 0.1))


QUADS = {
    "msuf_skin_gloss_crescent": Quad(0.0, gloss_crescent, 64),
    "msuf_skin_gloss_sheen": Quad(0.0, gloss_sheen, 64),
    "msuf_skin_gloss_top": Quad(0.0, gloss_top, 64),
    "msuf_skin_gloss_dome": Quad(0.0, gloss_dome, 64),
    "msuf_skin_glass_gloss": Quad(0.0, glass_gloss, 64),
    "msuf_skin_ring_segmented": Quad(4.0, ring_segmented),
    "msuf_skin_ring_simple": Quad(4.0, ring_simple),
    "msuf_skin_shadow_round": Quad(5.0, shadow_round),
    "msuf_skin_gear_ring": Quad(6.0, gear_ring),
    "msuf_skin_orb_ring": Quad(4.0, orb_ring),
    "msuf_skin_orb_thin": Quad(4.0, orb_thin),
    "msuf_skin_glass_ring": Quad(2.0, glass_ring),
    "msuf_skin_glass_thick": Quad(4.0, glass_thick),
}


def render_quad(quad):
    image = Canvas(quad.size, quad.size)
    for y in range(quad.size):
        for x in range(quad.size):
            alpha, lum = supersample(quad.sample, x, y, quad.size)
            image.alpha[y][x] = round(255 * clamp01(alpha))
            image.lum[y][x] = round(255 * clamp01(lum))
    return image


TGA_FOOTER = b"\0" * 8 + b"TRUEVISION-XFILE.\0"


def tga_bytes(image):
    """Uncompressed 32-bit truecolor TGA, bottom-left origin, 8 alpha bits."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, image.width, image.height, 32, 0x08)
    body = bytearray()
    for y in range(image.height - 1, -1, -1):
        alphas, lums = image.alpha[y], image.lum[y]
        for x in range(image.width):
            grey = lums[x]
            body += bytes((grey, grey, grey, alphas[x]))
    return header + bytes(body) + TGA_FOOTER


def manifest_text():
    """name, kind, outer, inner, extent per texture (tab-separated, LF)."""
    rows = ["name\tkind\touter\tinner\textent"]
    for name, band in BANDS.items():
        rows.append("%s\tband\t%g\t%g\t" % (name, band.outer, band.inner))
    for name, quad in QUADS.items():
        rows.append("%s\tquad\t\t\t%g" % (name, quad.extent))
    return "\n".join(rows) + "\n"


def build_all():
    files = {}
    for name, band in BANDS.items():
        files[name + ".tga"] = render_band(band)
    for name, quad in QUADS.items():
        files[name + ".tga"] = render_quad(quad)
    return files


# ---------------------------------------------------------------- preview
def sample_icon(size):
    """A synthetic spell icon: a warm radial gradient with a light rune."""
    from PIL import Image
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5
            r = math.hypot(u, v)
            rune = 1.0 if abs(abs(u) - abs(v)) < 0.05 and r < 0.33 else 0.0
            base = (int(210 - 160 * r), int(90 - 60 * r), int(40 + 40 * r))
            pixels[x, y] = tuple(min(255, int(c + rune * 140)) for c in base) + (255,)
    return image


def to_pil(canvas):
    from PIL import Image
    image = Image.new("RGBA", (canvas.width, canvas.height))
    image.putdata([(canvas.lum[y][x],) * 3 + (canvas.alpha[y][x],)
                   for y in range(canvas.height) for x in range(canvas.width)])
    return image


def write_preview(path, files):
    from PIL import Image
    names = list(files)
    cell, size = 120, 64
    canvas = Image.new("RGBA", (cell * 6, cell * ((len(names) + 5) // 6)), (40, 44, 52, 255))
    for index, name in enumerate(names):
        x, y = (index % 6) * cell, (index // 6) * cell
        thumb = to_pil(files[name]).resize((size if files[name].width != 256 else 2 * size, size))
        canvas.alpha_composite(thumb, (x + 4, y + 4))
    canvas.save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview")
    parser.add_argument("--out", default=str(OUT))
    args = parser.parse_args()
    files = build_all()
    out = Path(args.out)
    if args.preview:
        write_preview(args.preview, files)
    stale = []
    for name, image in files.items():
        data = tga_bytes(image)
        target = out / name
        if args.check:
            if not target.is_file() or target.read_bytes() != data:
                stale.append(name)
            continue
        out.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    manifest = manifest_text().encode("utf-8")
    if args.check:
        if not MANIFEST.is_file() or MANIFEST.read_bytes().replace(b"\r\n", b"\n") != manifest:
            stale.append(MANIFEST.name)
    else:
        MANIFEST.write_bytes(manifest)
    if args.check and stale:
        print("stale skin textures: " + ", ".join(sorted(stale)))
        return 1
    print(("checked " if args.check else "wrote ") + str(len(files)) + " skin textures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
