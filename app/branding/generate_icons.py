#!/usr/bin/env python3
"""Rasterise the MV2 logo into every platform's app-icon and splash sizes.

Usage (from the repository root or anywhere):

    python3 app/branding/generate_icons.py

Requirements: ``cairosvg``, ``Pillow`` and ``numpy``
(``pip3 install cairosvg pillow numpy``).

Single source of truth: ``source/symmetric_red_blue_v_exact.svg`` — the mark the
product owner drew (two capsules, red #C90522 and blue #0953A3, symmetric about
the vertical axis, transparent background). Everything else this script writes
is *derived* from it, so the mark only ever exists in one place.

The canvas is 1254×1254 with the mark already centred on x = 627.
"""

from __future__ import annotations

import io
import re
from pathlib import Path

import cairosvg
import numpy as np
from PIL import Image

BRANDING = Path(__file__).resolve().parent
APP = BRANDING.parent
SOURCE = BRANDING / "source" / "symmetric_red_blue_v_exact.svg"

CANVAS = 1254  # the source viewBox side
CENTRE = CANVAS / 2

# Android adaptive icons: the launcher mask can be as small as a circle covering
# the middle 2/3 of the canvas, so the mark is shrunk to fit that circle.
ADAPTIVE_SAFE_FRACTION = 1 / 3

_ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

_written: list[str] = []


# --------------------------------------------------------------------- compose
def _source_text() -> str:
    return SOURCE.read_text(encoding="utf-8")


def mark_svg(*, background: str | None = None, scale: float = 1.0) -> str:
    """The mark, optionally on a background and/or scaled about the centre.

    ``background`` is required (white) wherever the result must be opaque —
    iOS/macOS app icons may not carry an alpha channel. ``scale`` is used by the
    Android adaptive foreground so the mark stays inside the launcher's safe
    circle.
    """
    inner = re.sub(r"^<svg[^>]*>", "", _source_text(), count=1)
    inner = inner.rsplit("</svg>", 1)[0]

    body = ""
    if background:
        body += (
            f'<rect x="0" y="0" width="{CANVAS}" height="{CANVAS}" '
            f'fill="{background}"/>'
        )
    if scale != 1.0:
        body += (
            f'<g transform="translate({CENTRE} {CENTRE}) scale({scale}) '
            f'translate({-CENTRE} {-CENTRE})">' + inner + "</g>"
        )
    else:
        body += inner

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">'
        + body
        + "</svg>"
    )


# --------------------------------------------------------------------- rasterise
def render(svg: str, size: int, out: Path, *, opaque: bool) -> None:
    """Render an SVG string to a ``size``×``size`` PNG at ``out``."""
    out.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(
        bytestring=svg.encode("utf-8"),
        write_to=str(out),
        output_width=size,
        output_height=size,
    )
    if opaque:
        # iOS/macOS app icons must ship without an alpha channel; the mark sits
        # on an opaque white field, so flattening is lossless.
        with Image.open(out) as image:
            image.convert("RGB").save(out, format="PNG")
    _written.append(f"{out.relative_to(APP)}  ({size}x{size})")


def adaptive_scale() -> float:
    """Scale that keeps the mark inside the adaptive-icon safe circle.

    Measured rather than hard-coded, so redrawing the mark never silently
    pushes its capsule ends under the launcher mask.
    """
    png = cairosvg.svg2png(
        bytestring=mark_svg().encode("utf-8"),
        output_width=512,
        output_height=512,
    )
    alpha = np.array(Image.open(io.BytesIO(png)).convert("RGBA"))[:, :, 3]
    half = 512 / 2  # centre of the *rendered* bitmap, not of the SVG viewBox
    ys, xs = np.nonzero(alpha > 8)
    if xs.size == 0:
        return 1.0
    radius = float(np.max(np.hypot(xs - half, ys - half))) / half
    if radius <= ADAPTIVE_SAFE_FRACTION:
        return 1.0
    return round(ADAPTIVE_SAFE_FRACTION / radius, 3)


# --------------------------------------------------------------------- targets
def generate_ios(appiconset: Path) -> None:
    """Every filename listed in the asset catalog's Contents.json."""
    pattern = re.compile(r"^Icon-App-(\d+(?:\.\d+)?)x\1@(\d)x\.png$")
    for png in sorted(appiconset.glob("*.png")):
        match = pattern.match(png.name)
        if match is None:
            print(f"  ! skipping unrecognised iOS icon: {png.name}")
            continue
        render(
            mark_svg(background="#ffffff"),
            round(float(match.group(1)) * int(match.group(2))),
            png,
            opaque=True,
        )


def generate_macos() -> None:
    directory = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for png in sorted(directory.glob("app_icon_*.png")):
        digits = re.search(r"(\d+)", png.stem)
        if digits is None:
            print(f"  ! skipping unrecognised macOS icon: {png.name}")
            continue
        render(mark_svg(background="#ffffff"), int(digits.group(1)), png, opaque=True)


def generate_android(foreground_scale: float) -> None:
    """Legacy square icons plus the adaptive-icon foreground layer."""
    res = APP / "android/app/src/main/res"
    for density, factor in _ANDROID_DENSITIES.items():
        render(
            mark_svg(background="#ffffff"),
            round(48 * factor),
            res / f"mipmap-{density}/ic_launcher.png",
            opaque=True,
        )
        render(
            mark_svg(scale=foreground_scale),
            round(108 * factor),
            res / f"mipmap-{density}/ic_launcher_foreground.png",
            opaque=False,
        )


def generate_web() -> None:
    web = APP / "web"
    render(mark_svg(background="#ffffff"), 16, web / "favicon.png", opaque=True)
    render(mark_svg(background="#ffffff"), 192, web / "icons/Icon-192.png", opaque=True)
    render(mark_svg(background="#ffffff"), 512, web / "icons/Icon-512.png", opaque=True)
    render(
        mark_svg(background="#ffffff"),
        192,
        web / "icons/Icon-maskable-192.png",
        opaque=True,
    )
    render(
        mark_svg(background="#ffffff"),
        512,
        web / "icons/Icon-maskable-512.png",
        opaque=True,
    )


def generate_splash() -> None:
    """Launch images: the transparent mark centred on each platform's backdrop."""
    launch = APP / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for scale, name in (
        (1, "LaunchImage.png"),
        (2, "LaunchImage@2x.png"),
        (3, "LaunchImage@3x.png"),
    ):
        render(mark_svg(), 168 * scale, launch / name, opaque=False)

    res = APP / "android/app/src/main/res"
    for density, factor in _ANDROID_DENSITIES.items():
        render(
            mark_svg(),
            round(96 * factor),
            res / f"mipmap-{density}/launch_image.png",
            opaque=False,
        )


def write_composed_logo() -> None:
    """The white-field logo, as a standalone SVG people can open."""
    out = BRANDING / "mv2_logo.svg"
    out.write_text(mark_svg(background="#ffffff"), encoding="utf-8")
    _written.append(f"{out.relative_to(APP)}  (source of truth: source/)")


def main() -> None:
    if not SOURCE.exists():
        sys.exit(f"missing source: {SOURCE}")

    scale = adaptive_scale()
    print(f"adaptive foreground scale: {scale}")

    write_composed_logo()
    generate_ios(APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    generate_macos()
    generate_android(scale)
    generate_web()
    generate_splash()

    print(f"MV2 icons written ({len(_written)} files):")
    for line in _written:
        print(f"  {line}")


if __name__ == "__main__":
    main()
