#!/usr/bin/env python3
"""Preview sheet for the new MV2 mark: sizes, launcher-mask mock, splash.

    python3 app/branding/build_preview.py
"""

from pathlib import Path

import cairosvg
import numpy as np
from PIL import Image, ImageDraw

BRANDING = Path(__file__).resolve().parent
APP = BRANDING.parent
SOURCE = BRANDING / "source" / "symmetric_red_blue_v_exact.svg"

MARK = BRANDING / "mv2_logo.svg"
FOREGROUND = APP / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png"


def render_mark(size: int, *, background="#ffffff") -> Image.Image:
    png = cairosvg.svg2png(
        bytestring=MARK.read_text(encoding="utf-8"),
        output_width=size,
        output_height=size,
    )
    import io

    return Image.open(io.BytesIO(png)).convert("RGBA")


def circle_mask(image: Image.Image) -> Image.Image:
    """Keeps the central circle (the smallest Android launcher mask)."""
    w, h = image.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, w - 1, h - 1], fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(image, (0, 0), mask)
    return out


def main() -> None:
    sheet = Image.new("RGB", (1240, 620), (244, 245, 247))
    draw = ImageDraw.Draw(sheet)

    def paste(target: Image.Image, x: int, y: int, w: int) -> None:
        sheet.paste(target, (x, y), target)
        draw.rectangle([x - 1, y - 1, x + w, y + w], outline=(206, 211, 219))

    # 1 · the mark itself, large
    big = render_mark(360)
    paste(big, 30, 40, 360)

    # 2 · launcher mask mock: adaptive foreground on an Android-green circle
    fg = Image.open(FOREGROUND).convert("RGBA")
    tile = 360
    green = Image.new("RGBA", (tile, tile), (61, 220, 132, 255))
    scaled = fg.resize((tile, tile), Image.LANCZOS)
    green.alpha_composite(scaled)
    paste(circle_mask(green).convert("RGB").convert("RGBA"), 430, 40, 360)

    # 3 · small sizes on white (Home Screen / Spotlight / Settings)
    x, y = 830, 40
    for size in (128, 96, 64, 48):
        paste(render_mark(size), x, y, size)
        draw.text((x, y + size + 6), f"{size}px", fill=(90, 98, 112))
        y += size + 26

    # 4 · splash mock (white background, mark centred)
    splash = Image.new("RGBA", (360, 360), (255, 255, 255, 255))
    mark = render_mark(220)
    splash.alpha_composite(mark, ((360 - 220) // 2, (360 - 220) // 2))
    paste(splash, 30, 470, 360)

    out = BRANDING / "preview_new_logo.png"
    sheet.save(out)
    print(f"wrote {out} {sheet.size}")


if __name__ == "__main__":
    main()
