#!/usr/bin/env python3
"""Rasterise the MV2 logo into every platform's app-icon and splash sizes.

Usage (from the repository root or anywhere):

    python3 app/branding/generate_icons.py

Requirements: ``cairosvg`` and ``Pillow`` (``pip3 install cairosvg pillow``).

The logo is the published MV2 brand mark, merged from the .NET MAUI client's
``AppIcon/appicon.svg`` + ``appiconfg.svg`` (see ``mv2_logo.svg``). Re-run this
script whenever those sources change; it overwrites the generated PNGs in place.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import cairosvg
    from PIL import Image
except ImportError as exc:  # pragma: no cover - developer tooling
    sys.exit(f"missing dependency: {exc}\nInstall with: pip3 install cairosvg pillow")

BRANDING = Path(__file__).resolve().parent
APP = BRANDING.parent
FULL = BRANDING / "mv2_logo.svg"  # white field + mark
MARK = BRANDING / "mv2_logo_mark.svg"  # transparent mark only

# Android adaptive icons reserve the middle 66 % of a 108dp canvas, so the mark
# is rendered through a tighter viewBox to fill that safe zone.
ADAPTIVE_VIEW_BOX = "38 38 380 380"

ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

_written: list[str] = []


def render(
    svg: Path,
    size: int,
    out: Path,
    *,
    opaque: bool,
    view_box: str | None = None,
) -> None:
    """Render ``svg`` to a ``size``×``size`` PNG at ``out``."""
    out.parent.mkdir(parents=True, exist_ok=True)
    if view_box is None:
        cairosvg.svg2png(
            url=str(svg),
            write_to=str(out),
            output_width=size,
            output_height=size,
        )
    else:
        source = re.sub(
            r'viewBox="[^"]*"',
            f'viewBox="{view_box}"',
            svg.read_text(encoding="utf-8"),
            count=1,
        )
        cairosvg.svg2png(
            bytestring=source.encode("utf-8"),
            write_to=str(out),
            output_width=size,
            output_height=size,
        )
    if opaque:
        # iOS/macOS app icons must ship without an alpha channel; the mark's own
        # background is opaque white, so flattening is lossless.
        with Image.open(out) as image:
            image.convert("RGB").save(out, format="PNG")
    _written.append(f"{out.relative_to(APP)}  ({size}x{size})")


def generate_ios() -> None:
    """Every filename listed in the asset catalog's Contents.json."""
    directory = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    pattern = re.compile(r"^Icon-App-(\d+(?:\.\d+)?)x\1@(\d)x\.png$")
    for png in sorted(directory.glob("*.png")):
        match = pattern.match(png.name)
        if match is None:
            print(f"  ! skipping unrecognised iOS icon: {png.name}")
            continue
        render(FULL, round(float(match.group(1)) * int(match.group(2))), png, opaque=True)


def generate_macos() -> None:
    directory = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for png in sorted(directory.glob("app_icon_*.png")):
        digits = re.search(r"(\d+)", png.stem)
        if digits is None:
            print(f"  ! skipping unrecognised macOS icon: {png.name}")
            continue
        render(FULL, int(digits.group(1)), png, opaque=True)


def generate_android() -> None:
    """Legacy square icons plus the adaptive-icon foreground layer."""
    res = APP / "android/app/src/main/res"
    for density, factor in ANDROID_DENSITIES.items():
        render(
            FULL,
            round(48 * factor),
            res / f"mipmap-{density}/ic_launcher.png",
            opaque=True,
        )
        render(
            MARK,
            round(108 * factor),
            res / f"mipmap-{density}/ic_launcher_foreground.png",
            opaque=False,
            view_box=ADAPTIVE_VIEW_BOX,
        )


def generate_web() -> None:
    web = APP / "web"
    render(FULL, 16, web / "favicon.png", opaque=True)
    render(FULL, 192, web / "icons/Icon-192.png", opaque=True)
    render(FULL, 512, web / "icons/Icon-512.png", opaque=True)
    render(FULL, 192, web / "icons/Icon-maskable-192.png", opaque=True)
    render(FULL, 512, web / "icons/Icon-maskable-512.png", opaque=True)


def generate_splash() -> None:
    """Launch images: the transparent mark centred on each platform's backdrop."""
    # iOS LaunchScreen.storyboard centres `LaunchImage` on a white view.
    launch = APP / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for scale, name in (
        (1, "LaunchImage.png"),
        (2, "LaunchImage@2x.png"),
        (3, "LaunchImage@3x.png"),
    ):
        render(MARK, 168 * scale, launch / name, opaque=False)

    # Android pre-12 launch background (`drawable*/launch_background.xml`), which
    # keeps its own (possibly dark) backdrop colour.
    res = APP / "android/app/src/main/res"
    for density, factor in ANDROID_DENSITIES.items():
        render(
            MARK,
            round(96 * factor),
            res / f"mipmap-{density}/launch_image.png",
            opaque=False,
        )


def main() -> None:
    for svg in (FULL, MARK):
        if not svg.exists():
            sys.exit(f"missing source: {svg}")

    generate_ios()
    generate_macos()
    generate_android()
    generate_web()
    generate_splash()

    print(f"MV2 icons written ({len(_written)} files):")
    for line in _written:
        print(f"  {line}")


if __name__ == "__main__":
    main()
