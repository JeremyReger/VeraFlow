#!/usr/bin/env python3
"""Generates the VeraFlow app icon (1024×1024) and the alpha variant.

Reproducible: run `python3 scripts/icon/make_icon.py` (needs Pillow) and the PNGs in
VeraFlow/Resources/Assets.xcassets are rewritten. iOS masks the corners itself, so the
image is a full-bleed square with no rounding. The mark is "Ember" from the design spec §7:
five bars, one lit.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
ROOT = Path(__file__).resolve().parents[2] / "VeraFlow/Resources/Assets.xcassets"

# "Ember" (design spec §7): five bars on a dark tile, centre bar in clay. Same tile in both
# appearances; it is the one warm note now that the interface is cool.
TILE = (0x1B, 0x1D, 0x22)
OUTER = (0x4A, 0x50, 0x5A)
INNER = (0xB4, 0xBA, 0xC4)
CENTRE = (0xE0, 0x7A, 0x4F)
BAR_FRACTION = 0.0536          # bar width and gap, as a fraction of the tile
HEIGHTS = [0.238, 0.440, 0.619, 0.440, 0.238]   # outward from the centre: 61.9 / 44.0 / 23.8 %
COLOURS = [OUTER, INNER, CENTRE, INNER, OUTER]


def draw_mark(img):
    d = ImageDraw.Draw(img)
    s = SIZE
    bar_w = s * BAR_FRACTION
    gap = s * BAR_FRACTION
    total = 5 * bar_w + 4 * gap
    x0 = (s - total) / 2
    for i, (h, colour) in enumerate(zip(HEIGHTS, COLOURS)):
        x = x0 + i * (bar_w + gap)
        bar_h = s * h
        top = (s - bar_h) / 2
        d.rounded_rectangle([x, top, x + bar_w, top + bar_h], radius=bar_w / 2, fill=colour + (255,))
    return img


def tile():
    return Image.new("RGBA", (SIZE, SIZE), TILE + (255,))


def alpha_band(img):
    """A band across the bottom reading RIFFLE, so testers can tell alpha builds apart."""
    d = ImageDraw.Draw(img, "RGBA")
    band_h = int(SIZE * 0.17)
    d.rectangle([0, SIZE - band_h, SIZE, SIZE], fill=(255, 176, 0, 235))
    text = "RIFFLE"
    font = None
    for candidate in [
        "/System/Library/Fonts/SFCompact.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]:
        if Path(candidate).exists():
            font = ImageFont.truetype(candidate, int(band_h * 0.62))
            break
    if font is None:
        font = ImageFont.load_default()
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(
        ((SIZE - tw) / 2 - bbox[0], SIZE - band_h + (band_h - th) / 2 - bbox[1]),
        text,
        font=font,
        fill=(40, 30, 0, 255),
    )
    return img


def main():
    base = draw_mark(tile())
    out = ROOT / "AppIcon.appiconset" / "AppIcon.png"
    base.convert("RGB").save(out, "PNG", optimize=True)
    alpha_dir = ROOT / "AppIcon-Alpha.appiconset"
    alpha_dir.mkdir(exist_ok=True)
    alpha_band(base.copy()).convert("RGB").save(alpha_dir / "AppIcon-Alpha.png", "PNG", optimize=True)
    print(f"wrote {out} and {alpha_dir / 'AppIcon-Alpha.png'}")


if __name__ == "__main__":
    main()
