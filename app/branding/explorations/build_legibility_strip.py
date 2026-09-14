#!/usr/bin/env python3
"""Small-size legibility strip for the shortlisted candidates.

    python3 app/branding/explorations/build_legibility_strip.py

Renders each candidate at the sizes an app icon actually appears at, so a mark
that only reads at 1024px is caught before it ships.
"""

from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

CANDIDATES = [
    ("e_pills_v_person.svg", "E"),
    ("f_pills_v_person_seam.svg", "F"),
    ("h_pills_v_person_large.svg", "H"),
    ("g_person_flanked_pills.svg", "G"),
]
SIZES = [40, 64, 88, 128]

LABEL_W = 40
PAD = 22
ROW_GAP = 14

FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 16)
CELL = max(SIZES) + 16
width = LABEL_W + PAD + len(SIZES) * (CELL + PAD) + PAD
height = PAD + len(CANDIDATES) * (CELL + ROW_GAP) + PAD
sheet = Image.new("RGB", (width, height), (244, 245, 247))
draw = ImageDraw.Draw(sheet)

for row, (svg_name, label) in enumerate(CANDIDATES):
    png = HERE / svg_name.replace(".svg", "_master.png")
    cairosvg.svg2png(
        url=str(HERE / svg_name), write_to=str(png), output_width=456, output_height=456
    )
    y = PAD + row * (CELL + ROW_GAP)
    draw.text((PAD, y + CELL // 2 - 10), label, fill=(17, 24, 39), font=FONT)

    for col, size in enumerate(SIZES):
        with Image.open(png) as source:
            icon = source.convert("RGB").resize((size, size), Image.LANCZOS)
        x = LABEL_W + PAD + col * (CELL + PAD) + (CELL - size) // 2
        sheet.paste(icon, (x, y + (CELL - size) // 2))
        draw.rectangle(
            [x, y + (CELL - size) // 2, x + size - 1, y + (CELL - size) // 2 + size - 1],
            outline=(214, 219, 226),
        )

for col, size in enumerate(SIZES):
    x = LABEL_W + PAD + col * (CELL + PAD)
    draw.text((x + CELL // 2 - 12, height - PAD + 2), f"{size}px", fill=(90, 98, 112), font=FONT)

out = HERE / "legibility_strip.png"
sheet.save(out)
print(f"wrote {out} {sheet.size}")
