from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[3]
BASE = Path(__file__).resolve().parent
SOURCES = BASE / "sources"
EXPORTS = BASE / "exports"


def font(size: int, bold: bool = False):
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size=size, index=0)
    return ImageFont.load_default()


def contain(image: Image.Image, target: tuple[int, int], background=(245, 247, 250)):
    image = image.convert("RGB")
    image.thumbnail(target, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", target, background)
    canvas.paste(image, ((target[0] - image.width) // 2, (target[1] - image.height) // 2))
    return canvas


def phone_source(path: Path):
    image = Image.open(path).convert("RGB")
    # The recording has a black strip on the right. Remove only that capture margin.
    crop_width = min(image.width, int(image.height * 0.69))
    return image.crop((0, 0, crop_width, image.height))


def shadow_layer(size, box, radius=55, blur=34, alpha=105):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y, w, h = box
    draw.rounded_rectangle((x + 12, y + 18, x + w + 12, y + h + 18), radius=radius, fill=(0, 0, 0, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_iphone(canvas: Image.Image, source: Image.Image, box):
    x, y, w, h = box
    canvas.alpha_composite(shadow_layer(canvas.size, box, radius=92, blur=40, alpha=120))
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, w - 1, h - 1), radius=92, fill=(22, 24, 29, 255), outline=(104, 110, 120, 255), width=3)
    inset = 18
    screen = contain(source, (w - inset * 2, h - inset * 2), (245, 247, 250))
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen.width - 1, screen.height - 1), radius=76, fill=255)
    frame.paste(screen, (inset, inset), mask)
    fd = ImageDraw.Draw(frame)
    island_w = min(190, w // 3)
    fd.rounded_rectangle(((w - island_w) // 2, 26, (w + island_w) // 2, 56), radius=18, fill=(8, 9, 12, 255))
    canvas.alpha_composite(frame, (x, y))


def draw_duo(canvas: Image.Image, source: Image.Image, box):
    x, y, w, h = box
    canvas.alpha_composite(shadow_layer(canvas.size, box, radius=72, blur=42, alpha=125))
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, w - 1, h - 1), radius=72, fill=(20, 22, 27, 255), outline=(108, 115, 125, 255), width=3)
    inset = 18
    screen = contain(source, (w - inset * 2, h - inset * 2), (246, 248, 250))
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen.width - 1, screen.height - 1), radius=56, fill=255)
    frame.paste(screen, (inset, inset), mask)
    # A quiet central hinge identifies Duo without covering either pane.
    fd = ImageDraw.Draw(frame)
    hinge_x = w // 2
    fd.rounded_rectangle((hinge_x - 5, 80, hinge_x + 5, h - 80), radius=5, fill=(22, 24, 29, 170))
    canvas.alpha_composite(frame, (x, y))


def text(draw, xy, value, size, fill, spacing=10):
    draw.multiline_text(xy, value, font=font(size, True), fill=fill, spacing=spacing)


def make_header(duo, iphone):
    width, height = 3840, 1646
    canvas = Image.new("RGBA", (width, height), (12, 15, 21, 255))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((2480, -900, 4300, 900), fill=(23, 48, 83, 180))
    draw.ellipse((-500, 950, 1500, 2450), fill=(20, 34, 52, 210))
    text(draw, (210, 220), "把 V2EX\n装进你的工作流", 150, (247, 249, 252, 255), spacing=12)
    text(draw, (225, 720), "左边看主题，右边读讨论\n在 iPhone Duo 上同时打开。", 54, (177, 188, 204, 255), spacing=16)
    text(draw, (225, 1030), "iPhone · iPhone Duo 原生适配", 38, (90, 145, 255, 255))
    draw_duo(canvas, duo, (1700, 150, 1770, 1340))
    draw_iphone(canvas, iphone, (3120, 450, 500, 1020))
    return canvas.convert("RGB")


def make_search(duo, iphone):
    width, height = 2880, 1920
    canvas = Image.new("RGBA", (width, height), (244, 246, 249, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((130, 150, 970, 1660), radius=40, fill=(231, 236, 246, 255))
    text(draw, (230, 330), "看主题，\n读完整讨论", 126, (17, 23, 32, 255), spacing=12)
    text(draw, (240, 720), "MV2 把 V2EX 的主题、回复和节点\n放在一个清晰的阅读空间里。", 46, (75, 87, 105, 255), spacing=18)
    text(draw, (240, 1030), "iPhone Duo：列表与正文同时打开", 34, (40, 102, 232, 255))
    draw_duo(canvas, duo, (1110, 210, 1460, 1010))
    draw_iphone(canvas, iphone, (2040, 1080, 500, 700))
    return canvas.convert("RGB")


def main():
    EXPORTS.mkdir(parents=True, exist_ok=True)
    duo = Image.open(SOURCES / "iphone-duo" / "duo-topic-reading-primary.png").convert("RGB")
    iphone = phone_source(SOURCES / "iphone" / "iphone-feed-light.png")
    header = make_header(duo, iphone)
    search = make_search(duo, iphone)
    header.save(EXPORTS / "mv2-header-real-ui-3840x1646.png", optimize=True)
    search.save(EXPORTS / "mv2-search-results-real-ui-2880x1920.png", optimize=True)
    print("wrote real UI assets")


if __name__ == "__main__":
    main()
