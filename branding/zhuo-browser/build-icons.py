#!/usr/bin/env python3
"""Build the Zhuo 浏览器 macOS icon set from the master SVGs.

Usage:
    python3 build-icons.py

Requires cairosvg and Pillow. On macOS with a keg-only Homebrew cairo:
    DYLD_LIBRARY_PATH=/opt/homebrew/opt/cairo/lib python3 build-icons.py

Outputs:
    dist/Zhuo.iconset/*.png   iconutil input
    dist/Zhuo.icns            drag-and-drop macOS icon
    dist/png/*.png            flat exports for docs and the web
"""

from __future__ import annotations

import io
import shutil
import subprocess
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
ICONSET = DIST / "Zhuo.iconset"
PNG = DIST / "png"

FULL = ROOT / "zhuo-app-icon.svg"
SMALL = ROOT / "zhuo-app-icon-small.svg"
MICRO = ROOT / "zhuo-app-icon-micro.svg"
MARK = ROOT / "zhuo-mark.svg"

# (pixel size, source art). The 128 px slot drops the horizon; 32 px and below
# switch to the flat, heavier micro cut.
SLOTS = [
    (16, MICRO),
    (32, MICRO),
    (32, MICRO),
    (64, SMALL),
    (128, SMALL),
    (256, FULL),
    (256, FULL),
    (512, FULL),
    (512, FULL),
    (1024, FULL),
]

ICONSET_FILES = [
    "icon_16x16.png",
    "icon_16x16@2x.png",
    "icon_32x32.png",
    "icon_32x32@2x.png",
    "icon_128x128.png",
    "icon_128x128@2x.png",
    "icon_256x256.png",
    "icon_256x256@2x.png",
    "icon_512x512.png",
    "icon_512x512@2x.png",
]


def render(svg: Path, size: int) -> Image.Image:
    data = cairosvg.svg2png(
        url=str(svg),
        output_width=size,
        output_height=size,
        background_color=None,
    )
    return Image.open(io.BytesIO(data)).convert("RGBA")


APP_ASSETS = ROOT.parents[1] / "macos" / "ZhuoBrowserMac" / "Assets.xcassets"


def sync_app() -> None:
    """Keep the Xcode asset catalog byte-identical to the generated icons."""
    icon_dir = APP_ASSETS / "AppIcon.appiconset"
    mark_dir = APP_ASSETS / "ZhuoMark.imageset"
    if not icon_dir.is_dir() or not mark_dir.is_dir():
        return
    for name, _ in zip(ICONSET_FILES, SLOTS):
        shutil.copy2(ICONSET / name, icon_dir / name)
    for scale in ("1x", "2x", "3x"):
        shutil.copy2(PNG / f"zhuo-mark-{scale}.png", mark_dir / f"zhuo-mark-{scale}.png")
    print(f"synced {APP_ASSETS}")


def main() -> None:
    for d in (ICONSET, PNG):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)

    for name, (size, art) in zip(ICONSET_FILES, SLOTS):
        render(art, size).save(ICONSET / name)

    for size, art, label in [
        (16, MICRO, "16"),
        (32, MICRO, "32"),
        (64, SMALL, "64"),
        (128, SMALL, "128"),
        (256, FULL, "256"),
        (512, FULL, "512"),
        (1024, FULL, "1024"),
    ]:
        render(art, size).save(PNG / f"zhuo-icon-{label}.png")

    for scale, pixels in (("1x", 58), ("2x", 116), ("3x", 174)):
        render(MARK, pixels).save(PNG / f"zhuo-mark-{scale}.png")

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(DIST / "Zhuo.icns")], check=True)
    print(f"wrote {DIST/'Zhuo.icns'}")
    sync_app()


if __name__ == "__main__":
    main()
