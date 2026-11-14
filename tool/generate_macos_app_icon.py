#!/usr/bin/env python3
"""Generate Voryxel Code macOS AppIcon with true alpha outside Apple squircle.

Apple Dock icons are full-bleed: mid-edges stay opaque; only the region
outside the continuous corner is alpha=0. A large transparent margin on
all four edges makes macOS show a black square behind the smaller glyph.

Constants:
  CORNER_RADIUS_RATIO  Apple continuous-corner ≈ 22.37% of icon side
  CONTENT_SAFE_RATIO   ~9.5% inset used only to place the neon V artwork
  EDGE_MARGIN_RATIO    tiny AA inset for the mask (0 = full-bleed)
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "branding" / "voryxel_app_icon.png"
FALLBACK_SOURCE = Path(
    "/Users/cubcolexpress/.cursor/projects/"
    "Users-cubcolexpress-Desktop-Proyectos-constructor/assets/voryxel_app_icon.jpg"
)
APPICONSET = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
BRANDING = ROOT / "assets" / "branding"

CORNER_RADIUS_RATIO = 0.2237
CONTENT_SAFE_RATIO = 0.095
EDGE_MARGIN_RATIO = 0.0  # full-bleed; do NOT use 9.5% here (causes black box)
DARK_BG = (12, 16, 22, 255)
SIZES = (16, 32, 64, 128, 256, 512, 1024)


def apple_squircle_mask(size: int) -> Image.Image:
    """L-mode mask: 255 inside rounded rect, 0 outside (true transparency)."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    m = size * EDGE_MARGIN_RATIO
    # Radius is of the full icon side (Apple HIG continuous corner).
    r = max(1.0, size * CORNER_RADIUS_RATIO - m)
    # Keep radius inside the drawable rect.
    inner = size - 2 * m
    r = min(r, inner / 2.0)
    box = (m, m, size - 1 - m, size - 1 - m)
    draw.rounded_rectangle(box, radius=r, fill=255)
    return mask


def extract_neon_mark(src: Image.Image) -> Image.Image:
    """Crop the neon V/> mark from a dark-background source."""
    rgba = src.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    minx, miny, maxx, maxy = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            # Neon green/cyan on dark plate.
            if g > 90 and g > r + 20 and (g + b) > r + 40:
                found = True
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    if not found:
        # Fallback: use non-near-black opaque pixels.
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a > 200 and (r + g + b) > 80:
                    found = True
                    minx = min(minx, x)
                    miny = min(miny, y)
                    maxx = max(maxx, x)
                    maxy = max(maxy, y)
    if not found:
        raise SystemExit("Could not locate neon mark in source image")

    pad = 4
    minx = max(0, minx - pad)
    miny = max(0, miny - pad)
    maxx = min(w - 1, maxx + pad)
    maxy = min(h - 1, maxy + pad)
    crop = rgba.crop((minx, miny, maxx + 1, maxy + 1))
    cp = crop.load()
    cw, ch = crop.size
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    op = out.load()
    for y in range(ch):
        for x in range(cw):
            r, g, b, a = cp[x, y]
            if a < 8:
                continue
            if g > 55 and g >= r - 5 and (g + b) > r + 20:
                op[x, y] = (r, g, b, 255)
            elif g > 40 and g >= r:
                op[x, y] = (r, g, b, min(255, int((g - 30) * 5)))
    bbox = out.getbbox()
    return out.crop(bbox) if bbox else out


def make_icon(size: int, mark: Image.Image) -> Image.Image:
    """Dark plate + centered mark + Apple squircle alpha mask."""
    plate = Image.new("RGBA", (size, size), DARK_BG)

    safe = size * CONTENT_SAFE_RATIO
    target = size - 2 * safe
    # Mark occupies ~52% of the safe content box.
    mark_box = target * 0.72
    mw, mh = mark.size
    scale = min(mark_box / mw, mark_box / mh)
    nw = max(1, int(round(mw * scale)))
    nh = max(1, int(round(mh * scale)))
    logo = mark.resize((nw, nh), Image.Resampling.LANCZOS)
    plate.paste(logo, ((size - nw) // 2, (size - nh) // 2), logo)

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(plate, (0, 0), apple_squircle_mask(size))
    return out


def verify_alpha(path: Path) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    corner = im.getpixel((0, 0))
    mid_top = im.getpixel((w // 2, 0))
    center = im.getpixel((w // 2, h // 2))
    if corner[3] != 0:
        raise SystemExit(f"FAIL {path}: corner alpha={corner[3]} (want 0)")
    # Tiny sizes: rounded corners + AA can soften the mid-edge; require
    # opaque mid-edge from 32px up (that's what kills the Dock black box).
    if w >= 32 and mid_top[3] < 200:
        raise SystemExit(
            f"FAIL {path}: mid-edge alpha={mid_top[3]} "
            "(want opaque — transparent mid-edge causes black Dock box)"
        )
    if center[3] == 0:
        raise SystemExit(f"FAIL {path}: center fully transparent {center}")
    print(f"OK {path.name}: corner={corner} mid-edge={mid_top} center={center}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="Source logo (V neon on dark). Defaults to branding PNG or JPG fallback.",
    )
    args = parser.parse_args()

    source = args.source
    if source is None:
        source = DEFAULT_SOURCE if DEFAULT_SOURCE.exists() else FALLBACK_SOURCE
    if not source.exists():
        raise SystemExit(f"Source not found: {source}")

    print(f"Source: {source}")
    mark = extract_neon_mark(Image.open(source))
    print(f"Mark size: {mark.size}")

    APPICONSET.mkdir(parents=True, exist_ok=True)
    BRANDING.mkdir(parents=True, exist_ok=True)

    master = make_icon(1024, mark)
    master_path = BRANDING / "voryxel_app_icon.png"
    master.save(master_path, "PNG")
    (ROOT / "logo.png").write_bytes(master_path.read_bytes())
    make_icon(512, mark).save(BRANDING / "voryxel_logo_tile.png", "PNG")

    for size in SIZES:
        icon = master if size == 1024 else make_icon(size, mark)
        out = APPICONSET / f"app_icon_{size}.png"
        icon.save(out, "PNG")
        verify_alpha(out)

    verify_alpha(master_path)
    print("Done. Regenerated AppIcon.appiconset + branding PNGs.")


if __name__ == "__main__":
    main()
