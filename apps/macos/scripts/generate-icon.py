#!/usr/bin/env python3
from pathlib import Path
from subprocess import run

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
SOURCE_PNG = RESOURCES / "CopyPasteIcon.png"
ICONSET = RESOURCES / "CopyPaste.iconset"
ICNS = RESOURCES / "CopyPaste.icns"


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
        for x in range(size):
            pixels[x, y] = color
    return image


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon() -> Image.Image:
    size = 1024
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((84, 92, 940, 948), radius=224, fill=(0, 0, 0, 118))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    canvas.alpha_composite(shadow)

    bg = vertical_gradient(size, (31, 43, 68), (10, 145, 141))
    bg.putalpha(rounded_mask(size, 220))
    canvas.alpha_composite(bg)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rounded_rectangle((156, 164, 868, 876), radius=168, outline=(255, 255, 255, 36), width=4)

    shelf_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shelf_draw = ImageDraw.Draw(shelf_shadow, "RGBA")
    shelf_draw.rounded_rectangle((226, 276, 798, 782), radius=94, fill=(0, 0, 0, 70))
    shelf_shadow = shelf_shadow.filter(ImageFilter.GaussianBlur(20))
    canvas.alpha_composite(shelf_shadow)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rounded_rectangle((220, 258, 804, 760), radius=94, fill=(255, 255, 255, 36))
    draw.rounded_rectangle((258, 220, 766, 322), radius=50, fill=(255, 255, 255, 52))
    draw.rounded_rectangle((346, 190, 678, 282), radius=46, fill=(255, 255, 255, 86))
    draw.rounded_rectangle((388, 216, 636, 246), radius=15, fill=(22, 44, 62, 95))

    draw.line((284, 446, 740, 446), fill=(255, 255, 255, 38), width=12)
    draw.line((284, 570, 740, 570), fill=(255, 255, 255, 30), width=10)

    text = "C-V"
    text_font = font(int(245 * scale))
    bbox = draw.textbbox((0, 0), text, font=text_font, stroke_width=2)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (size - text_width) / 2 - bbox[0]
    y = 492 - text_height / 2 - bbox[1]
    draw.text((x + 0, y + 8), text, font=text_font, fill=(0, 0, 0, 46))
    draw.text((x, y), text, font=text_font, fill=(18, 43, 60, 252))

    return canvas


def write_iconset(source: Image.Image) -> None:
    if ICONSET.exists():
        for child in ICONSET.iterdir():
            child.unlink()
    else:
        ICONSET.mkdir(parents=True)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, px in sizes:
        source.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / name)


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    source = draw_icon()
    source.save(SOURCE_PNG)
    write_iconset(source)
    run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"Created {SOURCE_PNG}")
    print(f"Created {ICNS}")


if __name__ == "__main__":
    main()
