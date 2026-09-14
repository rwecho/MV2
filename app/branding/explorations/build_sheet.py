#!/usr/bin/env python3
"""Render the logo exploration candidates and side-by-side contact sheets.

    python3 app/branding/explorations/build_sheet.py

Each sheet shows one column per candidate: a large preview plus a small 88px
preview (launcher legibility) and the candidate id.
"""

from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

# Round 1 — first pass, kept for comparison.
ROUND_1 = [
    ("a_capsule_v_person.svg", "A  capsules = V + person"),
    ("b_capsule_v_person_seam.svg", "B  A + pill seams"),
    ("c_curved_v_person.svg", "C  original curves + person"),
    ("d_person_two_pills.svg", "D  no V, person between pills"),
]

# Round 2 — pill proportions fixed, person separated from the pills.
ROUND_2 = [
    ("e_pills_v_person.svg", "E  true pills = V + person"),
    ("f_pills_v_person_seam.svg", "F  E + pill seams"),
    ("c_curved_v_person.svg", "C  (round 1, for comparison)"),
    ("g_person_flanked_pills.svg", "G  no V, pills flank the person"),
]

BIG = 360
SMALL = 88
PAD = 24
LABEL_H = 36

FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 17)


def build(candidates: list[tuple[str, str]], out_name: str) -> None:
    sheet = Image.new(
        "RGB",
        (len(candidates) * (BIG + PAD) + PAD, PAD + BIG + PAD + SMALL + LABEL_H + PAD),
        (244, 245, 247),
    )
    draw = ImageDraw.Draw(sheet)

    for index, (svg_name, label) in enumerate(candidates):
        svg = HERE / svg_name
        png = svg.with_suffix(".png")
        cairosvg.svg2png(
            url=str(svg), write_to=str(png), output_width=456, output_height=456
        )
        with Image.open(png) as source:
            image = source.convert("RGB")
            big = image.resize((BIG, BIG), Image.LANCZOS)
            small = image.resize((SMALL, SMALL), Image.LANCZOS)

        x = PAD + index * (BIG + PAD)
        sheet.paste(big, (x, PAD))
        draw.rectangle([x, PAD, x + BIG - 1, PAD + BIG - 1], outline=(206, 211, 219))

        small_x = x + (BIG - SMALL) // 2
        small_y = PAD + BIG + PAD
        sheet.paste(small, (small_x, small_y))
        draw.rectangle(
            [small_x, small_y, small_x + SMALL - 1, small_y + SMALL - 1],
            outline=(206, 211, 219),
        )
        draw.text((x, small_y + SMALL + 8), label, fill=(17, 24, 39), font=FONT)

    out = HERE / out_name
    sheet.save(out)
    print(f"wrote {out} {sheet.size}")


if __name__ == "__main__":
    build(ROUND_1, "contact_sheet.png")
    build(ROUND_2, "contact_sheet_v2.png")
