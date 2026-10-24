"""Aura icon skin media: reproducible textures and their manifest.

1. Rebuilds every texture with tools/generate_aura_icon_skins.py (plain
   Python) and compares it byte for byte with MidnightSimpleUnitFrames/Media/Skins:
   the shipped art is exactly what the documented profiles produce, and no
   other file lives in that folder.
2. The manifest the catalog smoke reads (tools/aura_icon_skins_manifest.tsv:
   band spans and quad extents) matches the generator.
3. Headers: 32-bit uncompressed truecolor; 256x32 edge files; square quads.

The Lua side (every catalog layer names a manifest texture with the same span
or extent, and every texture is used) is in aura_icon_skin_paint_smoke.lua.
Argument: the repository root.
"""

import importlib.util
import struct
import sys
from pathlib import Path


def fail(message):
    print("aura_icon_skin_media_smoke: FAIL " + message)
    sys.exit(1)


def main():
    root = Path(sys.argv[1]).resolve()
    spec = importlib.util.spec_from_file_location("skin_generator", root / "tools" / "generate_aura_icon_skins.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)

    media = root / "MidnightSimpleUnitFrames" / "Media" / "Skins"
    built = generator.build_all()
    for name, image in built.items():
        target = media / name
        if not target.is_file():
            fail("missing texture " + name)
        data = target.read_bytes()
        if data != generator.tga_bytes(image):
            fail(name + " differs from its generator profile; rerun tools/generate_aura_icon_skins.py")
        id_len, cmap, kind = data[0], data[1], data[2]
        width, height, bpp, descriptor = struct.unpack("<HHBB", data[12:18])
        if (id_len, cmap, kind, bpp, descriptor & 0x0F) != (0, 0, 2, 32, 8):
            fail(name + " is not an uncompressed 32-bit truecolor TGA")
        stem = name[:-4]
        if stem in generator.BANDS:
            expected = (256, 32)
        else:
            expected = (generator.QUADS[stem].size, generator.QUADS[stem].size)
        if (width, height) != expected:
            fail("%s is %dx%d, want %dx%d" % (name, width, height, expected[0], expected[1]))
    shipped = {path.name for path in media.iterdir() if path.is_file()}
    if shipped != set(built):
        fail("unexpected files in Media/Skins: " + ", ".join(sorted(shipped ^ set(built))))

    manifest = generator.MANIFEST
    if not manifest.is_file():
        fail("missing " + manifest.name)
    if manifest.read_bytes().replace(b"\r\n", b"\n") != generator.manifest_text().encode("utf-8"):
        fail(manifest.name + " is stale; rerun tools/generate_aura_icon_skins.py")
    print("aura_icon_skin_media_smoke: OK (%d textures: %d bands, %d quads)"
          % (len(built), len(generator.BANDS), len(generator.QUADS)))


if __name__ == "__main__":
    main()
