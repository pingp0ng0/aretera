"""Apply the arched scene window and new background colours to both badge SVGs.

Run once: python -I design/update_badges.py   (stdlib only)
The SVG files stay the editable source of truth; this script just records the edit.
"""
import pathlib

HERE = pathlib.Path(__file__).parent
# Arched "window" for the scene: 20px inside the inner ring, below the BIVI title.
WINDOW = "M84 472 L84 380 A216 170 0 0 1 516 380 L516 472 Z"

STRUCTURE = [
    ('<clipPath id="scene"><rect x="64" y="210" width="472" height="262"/></clipPath>',
     f'<clipPath id="scene"><path d="{WINDOW}"/></clipPath>'),
]

COLOURS = {
    "bivi_badge_sky.svg": {
        "ink": "#16596B", "sky": "#CDEFF7",
        "replace": [
            ('fill="#FFFCF4" stroke="#16596B" stroke-width="14"', 'fill="#FFF0C2" stroke="#16596B" stroke-width="14"'),
            ('<use href="#inner" fill="none" stroke="#FFC23C" stroke-width="4"/>',
             '<use href="#inner" fill="none" stroke="#FFFFFF" stroke-width="5"/>'),
            # Pole grips and side dashes would vanish on the butter background → coral.
            ('rx="3" fill="#FFC23C" stroke="none"', 'rx="3" fill="#FF6B57" stroke="none"'),
            ('<g stroke="#FFC23C" stroke-width="3" stroke-linecap="round"><line x1="232"',
             '<g stroke="#FF6B57" stroke-width="3" stroke-linecap="round"><line x1="232"'),
            ('option 1 "sky & mint".', 'option 1 "sky & mint", butter background, arched scene window.'),
        ],
    },
    "bivi_badge_dawn.svg": {
        "ink": "#3A4A9F", "sky": "#FFE3D3",
        "replace": [
            ('fill="#FFF9F5" stroke="#3A4A9F" stroke-width="14"', 'fill="#E9ECFF" stroke="#3A4A9F" stroke-width="14"'),
            ('<use href="#inner" fill="none" stroke="#FF8A65" stroke-width="4"/>',
             '<use href="#inner" fill="none" stroke="#FFFFFF" stroke-width="5"/>'),
            ('option 2 "dawn & coral".', 'option 2 "dawn & coral", lavender background, arched scene window.'),
        ],
    },
}

for name, spec in COLOURS.items():
    path = HERE / name
    svg = path.read_text(encoding="utf-8")
    ink, sky = spec["ink"], spec["sky"]
    edits = STRUCTURE + spec["replace"] + [
        # Sky fills the window shape instead of a rectangle.
        (f'<rect x="64" y="210" width="472" height="262" fill="{sky}"/>', f'<path d="{WINDOW}" fill="{sky}"/>'),
        # Frame the window instead of a full-width ground line that touched the ring.
        (f'<line x1="64" y1="472" x2="536" y2="472" stroke="{ink}" stroke-width="4"/>',
         f'<path d="{WINDOW}" fill="none" stroke="{ink}" stroke-width="4" stroke-linejoin="round"/>'),
    ]
    for old, new in edits:
        if old not in svg:
            raise SystemExit(f"{name}: pattern not found: {old[:60]}")
        svg = svg.replace(old, new)
    path.write_text(svg, encoding="utf-8", newline="\n")
    print(f"updated {name}")
