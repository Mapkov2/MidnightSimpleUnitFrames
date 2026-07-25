#!/usr/bin/env python3
"""Generate MSUF's beveled portrait ring art.

One 128x128 32-bit TGA per portrait shape: a THIN beveled ring (a lit
half-torus cross-section) in a warm metal base tone, sized so it hugs the
portrait rim like the flat ring does rather than framing it like a picture
frame. The portrait border colour still tints it at runtime via SetVertexColor:
the default white keeps the gold, a coloured border re-hues the metal, and
Class/Reaction colour keep working exactly as with the flat border.

The light sits straight above the ring, so rotating the texture in 90 degree
steps moves the highlight to top / right / bottom / left - which is what the
portrait border direction control does, at zero runtime cost (the rotation is
baked into tex coords).

TGA layout matches the assets already in Media: uncompressed 32-bit BGRA,
bottom-up row order, descriptor 0x08.

Usage:  python tools/generate_portrait_ring_art.py [repoRoot]
"""
from __future__ import annotations

import math
import pathlib
import sys

SIZE = 128
SUPERSAMPLE = 4
INNER = 0.84          # nominal opening: the geometry contract in the element
# The band extends slightly INSIDE the nominal opening so the ring's dark inner
# contact line is drawn over the portrait edge. Both the ring and the portrait
# edge are antialiased; without this overlap a 1px background seam can show
# between them at some sizes. The element still aims INNER at the portrait rim.
OVERLAP = 0.05        # band actually spans (INNER - OVERLAP)..1.0
# Measured from the shipped rounded_mask.tga silhouette (boundary reach at 45
# degrees vs the axes): the mask is a superellipse of exponent ~7.6, not 4.
ROUNDED_EXPONENT = 7.6
AMBIENT = 0.46
SPECULAR_GAMMA = 1.6
SPECULAR_TIGHT = 14.0   # exponent of the narrow highlight streak
SPECULAR_GAIN = 0.40
# Light straight above the ring. Kept well off the viewer axis on purpose: a
# head-on light would leave the crest evenly lit and the 90 degree rotations
# would be almost invisible.
LIGHT = (0.0, 0.78, 0.63)
# Warm metal base. The texture is still tinted by the portrait border colour,
# so this is what the default white colour resolves to: gold rather than the
# flat silver a pure greyscale ring produced. A coloured border tints from here,
# which keeps the metal reading as metal instead of as a flat colour ring.
METAL = (1.00, 0.84, 0.55)
# Ambient occlusion at both rims, as a fraction of the band width.
RIM_FRACTION = 0.16
RIM_DARKEN = 0.48
# Gentle overall gradient along the light axis so the ring reads as "lit from
# above" even at a glance, at portrait sizes where the bevel is only a few px.
GRADIENT = 0.16


def _normalize(vec):
    length = math.sqrt(sum(component * component for component in vec))
    return tuple(component / length for component in vec)


LIGHT = _normalize(LIGHT)


def shape_distance(kind: str, nx: float, ny: float) -> float:
    ax, ay = abs(nx), abs(ny)
    if kind == "circle":
        return math.sqrt(nx * nx + ny * ny)
    if kind == "square":
        return max(ax, ay)
    if kind == "diamond":
        return ax + ay
    if kind == "rounded":
        n = ROUNDED_EXPONENT
        return (ax ** n + ay ** n) ** (1.0 / n)
    raise ValueError(kind)


def radial_direction(kind: str, nx: float, ny: float):
    """In-plane outward direction of the ring surface at this point."""
    if kind == "diamond":
        # The diamond's outward normal is constant per quadrant.
        return _normalize((math.copysign(1.0, nx or 1.0), math.copysign(1.0, ny or 1.0)))[:2]
    if kind == "square":
        # Whichever axis is on the boundary owns the normal.
        if abs(nx) >= abs(ny):
            return (math.copysign(1.0, nx or 1.0), 0.0)
        return (0.0, math.copysign(1.0, ny or 1.0))
    length = math.sqrt(nx * nx + ny * ny)
    if length < 1e-6:
        return (0.0, 1.0)
    return (nx / length, ny / length)


def sample(kind: str, nx: float, ny: float):
    """Return (covered, (r, g, b)) for one subsample."""
    s = shape_distance(kind, nx, ny)
    band_start = INNER - OVERLAP
    if s < band_start or s > 1.0:
        return False, None
    u = (s - band_start) / (1.0 - band_start)
    # Half-torus cross-section: inner wall faces inward, crest faces the viewer,
    # outer wall faces outward.
    angle = math.pi * (u - 0.5)
    rx, ry = radial_direction(kind, nx, ny)
    nz = math.cos(angle)
    scale = math.sin(angle)
    normal = (rx * scale, ry * scale, nz)
    diffuse = max(0.0, sum(a * b for a, b in zip(normal, LIGHT)))
    lum = AMBIENT + (1.0 - AMBIENT) * (diffuse ** SPECULAR_GAMMA)
    # Narrow specular streak: this is what sells "polished metal" rather than
    # "grey band" once the ring is only a handful of pixels wide on screen.
    lum += SPECULAR_GAIN * (diffuse ** SPECULAR_TIGHT)
    # Ambient occlusion at both rims so the ring reads as a distinct object
    # against both the portrait and whatever sits behind the frame.
    rim = min(u, 1.0 - u) / RIM_FRACTION
    if rim < 1.0:
        lum *= RIM_DARKEN + (1.0 - RIM_DARKEN) * rim
    # Overall gradient along the light axis.
    axis = sum(a * b for a, b in zip((nx, ny), LIGHT[:2]))
    lum *= (1.0 - GRADIENT) + GRADIENT * (axis * 0.5 + 0.5)
    lum = min(1.0, max(0.0, lum))
    return True, (lum * METAL[0], lum * METAL[1], lum * METAL[2])


def build(kind: str) -> bytes:
    step = 2.0 / (SIZE * SUPERSAMPLE)
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            covered = 0
            acc = [0.0, 0.0, 0.0]
            for sy in range(SUPERSAMPLE):
                ny = -1.0 + ((py * SUPERSAMPLE + sy) + 0.5) * step
                for sx in range(SUPERSAMPLE):
                    nx = -1.0 + ((px * SUPERSAMPLE + sx) + 0.5) * step
                    hit, rgb = sample(kind, nx, ny)
                    if hit:
                        covered += 1
                        acc[0] += rgb[0]
                        acc[1] += rgb[1]
                        acc[2] += rgb[2]
            total = SUPERSAMPLE * SUPERSAMPLE
            alpha = covered / total
            if covered:
                r = int(round(acc[0] / covered * 255))
                g = int(round(acc[1] / covered * 255))
                b = int(round(acc[2] / covered * 255))
            else:
                r = g = b = 0
            row += bytes((b, g, r, int(round(alpha * 255))))  # BGRA
        rows.append(bytes(row))
    header = bytes((
        0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        SIZE & 0xFF, SIZE >> 8, SIZE & 0xFF, SIZE >> 8, 32, 0x08,
    ))
    # Descriptor 0x08 means bottom-up: the first stored row is the image's
    # bottom edge, which is exactly the ny = -1 row this loop produced first.
    return header + b"".join(rows)


def main() -> None:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    out = root / "MidnightSimpleUnitFrames" / "Media" / "Borders"
    out.mkdir(parents=True, exist_ok=True)
    for kind in ("circle", "rounded", "diamond", "square"):
        path = out / ("msuf_portrait_ring_%s.tga" % kind)
        path.write_bytes(build(kind))
        print("wrote %s (%d bytes)" % (path.name, path.stat().st_size))


if __name__ == "__main__":
    main()
