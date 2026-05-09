#!/usr/bin/env python3
"""Crop the LuCI screenshots and compose into a 3x3 grid + a 1x3 hero strip.

Source images: docs/screenshots/01..09.png (1440x900)
Crop region: drop the left LuCI sidebar, top breadcrumb area, footer.
Output:
  docs/screenshots/grid-3x3.png  (3 kernels x 3 modes)
  docs/screenshots/hero-1x3.png  (one mode per kernel, for README header)
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots"

# Crop the Clashoo content region. Original 1440x900 ArgonTheme has:
#   left sidebar ~200px, top header ~60px, content tabs at ~70px,
#   footer with branding ~870px+. Tighten to the cards.
CROP = (210, 65, 1430, 720)  # left, top, right, bottom -> 1220x655

LABEL_BAR = 56
GAP = 16
PAD = 24
BG = (24, 24, 27)        # gray-900-ish, matches dark theme
LABEL_BG = (39, 39, 42)
LABEL_FG = (244, 244, 245)
TITLE_FG = (255, 255, 255)


def load_font(size):
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except Exception:
            continue
    return ImageFont.load_default()


def labelled_tile(path, label, font):
    base = Image.open(path).convert("RGB").crop(CROP)
    w, h = base.size
    tile = Image.new("RGB", (w, h + LABEL_BAR), LABEL_BG)
    tile.paste(base, (0, LABEL_BAR))
    draw = ImageDraw.Draw(tile)
    bbox = draw.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text(((w - tw) / 2, (LABEL_BAR - th) / 2 - 2), label, fill=LABEL_FG, font=font)
    return tile


# (filename, label) — order: rows = kernels, cols = modes
LAYOUT = [
    [("01-mihomo-fakeip.png", "Mihomo · Fake-IP"),
     ("02-mihomo-tun.png",     "Mihomo · TUN"),
     ("03-mihomo-mixed.png",   "Mihomo · Mixed")],
    [("04-smart-fakeip.png",   "Smart · Fake-IP"),
     ("05-smart-tun.png",      "Smart · TUN"),
     ("06-smart-mixed.png",    "Smart · Mixed")],
    [("07-singbox-fakeip.png", "Sing-box · Fake-IP"),
     ("08-singbox-tun.png",    "Sing-box · TUN"),
     ("09-singbox-mixed.png",  "Sing-box · Mixed")],
]


def grid_3x3():
    font = load_font(28)
    tiles = [[labelled_tile(SHOTS / f, lab, font) for f, lab in row]
             for row in LAYOUT]
    tw, th = tiles[0][0].size
    cols, rows = 3, 3
    canvas_w = PAD * 2 + cols * tw + (cols - 1) * GAP
    canvas_h = PAD * 2 + rows * th + (rows - 1) * GAP
    canvas = Image.new("RGB", (canvas_w, canvas_h), BG)
    for r, row in enumerate(tiles):
        for c, tile in enumerate(row):
            x = PAD + c * (tw + GAP)
            y = PAD + r * (th + GAP)
            canvas.paste(tile, (x, y))
    out = SHOTS / "grid-3x3.png"
    # Cap at 3600px wide so README displays crisp; browsers downscale.
    canvas.thumbnail((3600, 3600), Image.LANCZOS)
    canvas.save(out, optimize=True)
    print(f"wrote {out} {canvas.size}")


def hero_1x3():
    """One representative mode per kernel."""
    font = load_font(30)
    picks = [
        ("01-mihomo-fakeip.png",   "Mihomo"),
        ("04-smart-fakeip.png",    "Smart"),
        ("07-singbox-fakeip.png",  "Sing-box"),
    ]
    tiles = [labelled_tile(SHOTS / f, lab, font) for f, lab in picks]
    tw, th = tiles[0].size
    canvas_w = PAD * 2 + 3 * tw + 2 * GAP
    canvas_h = PAD * 2 + th
    canvas = Image.new("RGB", (canvas_w, canvas_h), BG)
    for i, tile in enumerate(tiles):
        canvas.paste(tile, (PAD + i * (tw + GAP), PAD))
    out = SHOTS / "hero-1x3.png"
    canvas.thumbnail((2400, 1200), Image.LANCZOS)
    canvas.save(out, optimize=True)
    print(f"wrote {out} {canvas.size}")


if __name__ == "__main__":
    grid_3x3()
    hero_1x3()
