"""Swap the vector hiker silhouette in both badges for the Bivi mascot (side view, with backpack).

Run: python -I design/put_mascot_in_badge.py   (stdlib only, re-runnable)
The PNG is embedded as a data URI so each SVG stays a single self-contained file.
"""
import base64
import pathlib
import re

HERE = pathlib.Path(__file__).parent
MASCOT = HERE.parent / "assets" / "character" / "side.png"  # 165x247 cutout

# Feet on the window floor (y=472) at the start of the dotted trail, so the mascot walks up it.
# 118px read as too small at badge scale; 150px makes the mascot the clear focal point.
HEIGHT = 150
WIDTH = round(HEIGHT * 165 / 246)
X, Y = 214, 472 - HEIGHT + 4  # +4: the cutout keeps a soft ground shadow under the boots

data = base64.b64encode(MASCOT.read_bytes()).decode("ascii")
# The side cutout faces left; mirror it so it heads right, toward the tent.
image = (f'<image id="mascot" x="{X}" y="{Y}" width="{WIDTH}" height="{HEIGHT}" '
         f'transform="matrix(-1 0 0 1 {2 * X + WIDTH} 0)" '
         f'preserveAspectRatio="xMidYMax meet" href="data:image/png;base64,{data}"/>')

# Old vector hiker group, or a mascot image from a previous run.
hiker = re.compile(r'<g transform="translate\(232 386\)"[^>]*>.*?</g>|<image id="mascot"[^>]*/>', re.S)

for name in ("bivi_badge_sky.svg", "bivi_badge_dawn.svg"):
    path = HERE / name
    svg = path.read_text(encoding="utf-8")
    svg, n = hiker.subn(lambda _: image, svg, count=1)
    if n != 1:
        raise SystemExit(f"{name}: hiker element not found")
    path.write_text(svg, encoding="utf-8", newline="\n")
    print(f"{name}: mascot {WIDTH}x{HEIGHT} at ({X},{Y}), {path.stat().st_size // 1024} KB")
