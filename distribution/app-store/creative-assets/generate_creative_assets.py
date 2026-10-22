#!/usr/bin/env python3
"""Build Apple App Store creative assets from the verified MV2 UI captures.

The output is intentionally a deterministic composition. The product UI stays
pixel-faithful; the surrounding artwork supplies the brand and short message.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SOURCE_FEED = ROOT / "docs/images/1.png"
SOURCE_TOPIC = ROOT / "docs/images/2.png"
LOGO = ROOT / "app/branding/mv2_logo.svg"

FONT_REGULAR = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_BOLD = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def rounded_card(image: Image.Image, size: tuple[int, int], radius: int = 58) -> Image.Image:
    image = image.convert("RGB")
    image.thumbnail(size, Image.Resampling.LANCZOS)
    card = Image.new("RGB", size, (255, 255, 255))
    x = (size[0] - image.width) // 2
    y = (size[1] - image.height) // 2
    card.paste(image, (x, y))
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    card.putalpha(mask)
    return card


def add_shadow(canvas: Image.Image, card: Image.Image, xy: tuple[int, int], blur: int = 42) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_card = Image.new("RGBA", card.size, (0, 0, 0, 130))
    shadow_card.putalpha(card.getchannel("A").filter(ImageFilter.GaussianBlur(blur // 2)))
    shadow.alpha_composite(shadow_card, (xy[0] + 22, xy[1] + 30))
    canvas.alpha_composite(shadow)


def gradient(size: tuple[int, int]) -> Image.Image:
    width, height = size
    result = Image.new("RGB", size)
    px = result.load()
    for y in range(height):
        for x in range(width):
            red = math.exp(-(((x / width - 0.12) / 0.45) ** 2 + ((y / height - 0.55) / 0.95) ** 2))
            blue = math.exp(-(((x / width - 0.90) / 0.48) ** 2 + ((y / height - 0.42) / 0.95) ** 2))
            px[x, y] = (
                int(8 + 18 * red),
                int(13 + 21 * blue),
                int(25 + 36 * blue + 14 * red),
            )
    return result.convert("RGBA")


def logo_mark(size: int) -> Image.Image:
    svg = cairosvg.svg2png(url=str(LOGO), output_width=size, output_height=size)
    image = Image.open(__import__("io").BytesIO(svg)).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            if r > 248 and g > 248 and b > 248:
                pixels[x, y] = (r, g, b, 0)
    return image


def draw_copy(draw: ImageDraw.ImageDraw, x: int, y: int, title: str, subtitle: str, header: bool) -> None:
    white = (248, 250, 255, 255)
    muted = (180, 192, 214, 255)
    accent = (72, 144, 255, 255)
    draw.text((x, y), "MV2", font=font(104 if header else 92, True), fill=white)
    draw.text((x, y + (132 if header else 118)), title, font=font(64 if header else 58, True), fill=white)
    draw.text((x, y + (230 if header else 216)), subtitle, font=font(34 if header else 32), fill=muted)
    line_y = y + (326 if header else 312)
    draw.rounded_rectangle((x, line_y, x + 128, line_y + 8), radius=4, fill=accent)
    pills = ("阅读主题", "搜索节点", "参与讨论")
    px = x
    for label in pills:
        bbox = draw.textbbox((0, 0), label, font=font(25, True))
        w = bbox[2] - bbox[0] + 42
        draw.rounded_rectangle((px, line_y + 55, px + w, line_y + 102), radius=24, fill=(31, 49, 78, 230))
        draw.text((px + 21, line_y + 65), label, font=font(25, True), fill=(218, 228, 246, 255))
        px += w + 16


def save_rgb(image: Image.Image, filename: str) -> None:
    image.convert("RGB").save(OUT / filename, quality=96, optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    feed = Image.open(SOURCE_FEED).convert("RGB")
    topic = Image.open(SOURCE_TOPIC).convert("RGB")

    # Product page header: Apple 21:9, 3840 x 1646.
    header = gradient((3840, 1646))
    hd = ImageDraw.Draw(header)
    mark = logo_mark(190)
    header.alpha_composite(mark, (250, 184))
    draw_copy(hd, 510, 205, "看见正在发生的讨论", "一个更接近社区本身的 V2EX 客户端", True)
    phone = rounded_card(feed, (760, 1450), 58)
    add_shadow(header, phone, (2800, 112))
    header.alpha_composite(phone, (2800, 112))
    topic_card = rounded_card(topic, (570, 1080), 48)
    add_shadow(header, topic_card, (2220, 470), 28)
    header.alpha_composite(topic_card, (2220, 470))
    save_rgb(header, "mv2-product-page-header-21x9-3840x1646.png")

    # Search result: Apple 3:2, 2880 x 1920. The message is deliberately explicit.
    search = gradient((2880, 1920))
    sd = ImageDraw.Draw(search)
    mark = logo_mark(176)
    search.alpha_composite(mark, (205, 215))
    draw_copy(sd, 435, 232, "搜索主题，找到答案", "阅读、搜索、参与 V2EX 社区", False)
    phone = rounded_card(feed, (770, 1675), 58)
    add_shadow(search, phone, (1870, 122))
    search.alpha_composite(phone, (1870, 122))
    topic_card = rounded_card(topic, (485, 930), 42)
    add_shadow(search, topic_card, (1310, 790), 24)
    search.alpha_composite(topic_card, (1310, 790))
    save_rgb(search, "mv2-search-results-3x2-2880x1920.png")

    manifest = {
        "product": "MV2",
        "source_ui": [str(SOURCE_FEED.relative_to(ROOT)), str(SOURCE_TOPIC.relative_to(ROOT))],
        "assets": [
            {"file": "mv2-product-page-header-21x9-3840x1646.png", "placement": "Product page header", "width": 3840, "height": 1646, "ratio": "21:9", "alpha": False},
            {"file": "mv2-search-results-3x2-2880x1920.png", "placement": "Search results", "width": 2880, "height": 1920, "ratio": "3:2", "alpha": False},
        ],
        "copy": {
            "header": "看见正在发生的讨论",
            "search_results": "搜索主题，找到答案",
        },
        "review_status": "draft; preview in App Store Connect before submission",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
