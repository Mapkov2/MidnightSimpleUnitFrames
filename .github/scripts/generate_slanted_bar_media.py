"""Generate directional bar masks and tintable contours for frame bars."""

from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2] / "MidnightSimpleUnitFrames" / "Media" / "Masks"
WIDTH, HEIGHT, SCALE = 256, 64, 4
SLOPE = 10


VARIANTS = {
    "": (False, False, False, True),  # Original right-down shape and filename.
    "right_up": (False, True, False, False),
    "left_down": (False, False, True, False),
    "left_up": (True, False, False, False),
    "both_down": (False, False, True, True),
    "both_up": (True, True, False, False),
}


def polygon(inset, corners):
    width, height = WIDTH * SCALE, HEIGHT * SCALE
    cut = SLOPE * SCALE
    top_left, top_right, bottom_left, bottom_right = corners
    return [
        (inset + (cut if top_left else 0), inset),
        (width - 1 - inset - (cut if top_right else 0), inset),
        (width - 1 - inset - (cut if bottom_right else 0), height - 1 - inset),
        (inset + (cut if bottom_left else 0), height - 1 - inset),
    ]


def save(name, outline, corners):
    size = WIDTH * SCALE, HEIGHT * SCALE
    image = Image.new("RGBA", size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(image)
    draw.polygon(polygon(0, corners), fill=(255, 255, 255, 255))
    if outline:
        draw.polygon(polygon(3 * SCALE, corners), fill=(255, 255, 255, 0))
    image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(ROOT / name)


if __name__ == "__main__":
    for suffix, corners in VARIANTS.items():
        name_suffix = "_" + suffix if suffix else ""
        save("slanted_bar_mask" + name_suffix + ".png", False, corners)
        save("slanted_bar_edge" + name_suffix + ".png", True, corners)
