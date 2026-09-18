#!/usr/bin/env python3
"""Generates the VeraFlow app icon (1024×1024) and the alpha variant.

Reproducible: run `python3 scripts/icon/make_icon.py` (needs Pillow) and the PNGs in
VeraFlow/Resources/Assets.xcassets are rewritten. iOS masks the corners itself, so the
image is a full-bleed square. The mark: waveform bars whose tops trace a "V" that flows
into a check mark — audio in, to-do list out.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
ROOT = Path(__file__).resolve().parents[2] / "VeraFlow/Resources/Assets.xcassets"

TOP = (18, 104, 128)      # deep teal
BOTTOM = (36, 42, 110)    # indigo
WHITE = (255, 255, 255, 255)


def gradient(size):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
        g = round(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
        b = round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b, 255)
    return img


def draw_mark(img):
    """Nine rounded bars. Heights dip to a V in the middle; the last two rise into a check."""
    d = ImageDraw.Draw(img)
    s = SIZE
    n = 9
    bar_w = s * 0.056
    gap = s * 0.026
    total = n * bar_w + (n - 1) * gap
    x0 = (s - total) / 2
    center_y = s * 0.54
    # Relative half-heights: a V whose right arm keeps rising into the check's upstroke.
    # Everything stays inside the central 76% of the canvas (iOS masks the corners).
    halves = [0.22, 0.17, 0.12, 0.08, 0.05, 0.09, 0.15, 0.22, 0.29]
    for i, h in enumerate(halves):
        x = x0 + i * (bar_w + gap)
        top = center_y - s * h
        bottom = center_y + s * min(h, 0.22)
        # The check's tail leans right: shift the last two bars up so the tops draw the upstroke.
        lift = s * 0.045 * max(0, i - 6)
        d.rounded_rectangle(
            [x, top - lift, x + bar_w, bottom - lift],
            radius=bar_w / 2,
            fill=WHITE,
        )
    return img


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
    base = draw_mark(gradient(SIZE))
    out = ROOT / "AppIcon.appiconset" / "AppIcon.png"
    base.convert("RGB").save(out, "PNG", optimize=True)
    alpha_dir = ROOT / "AppIcon-Alpha.appiconset"
    alpha_dir.mkdir(exist_ok=True)
    alpha_band(base.copy()).convert("RGB").save(alpha_dir / "AppIcon-Alpha.png", "PNG", optimize=True)
    print(f"wrote {out} and {alpha_dir / 'AppIcon-Alpha.png'}")


if __name__ == "__main__":
    main()
