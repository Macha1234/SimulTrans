#!/usr/bin/env python3
"""Generate the app icon from the checked-in logo source image."""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

SIZE = 1024
ROOT_DIR = Path(__file__).resolve().parent
SOURCE_ICON = ROOT_DIR / "assets" / "logo" / "app-logo-source.png"
DIST_DIR = ROOT_DIR / "dist"
RESOURCES_DIR = ROOT_DIR / "AppTemplate" / "Contents" / "Resources"


def load_icon(source_path: Path = SOURCE_ICON, size: int = SIZE) -> Image.Image:
    if not source_path.exists():
        raise FileNotFoundError(f"Logo source image not found: {source_path}")

    image = Image.open(source_path).convert("RGBA")
    if image.size != (size, size):
        image = image.resize((size, size), Image.LANCZOS)
    return image


def create_icns(image: Image.Image, output_path: Path) -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        iconset_dir = Path(tmpdir) / "AppIcon.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)

        sizes = [16, 32, 64, 128, 256, 512, 1024]
        for size in sizes:
            resized = image.resize((size, size), Image.LANCZOS)
            resized.save(iconset_dir / f"icon_{size}x{size}.png")
            if size <= 512:
                resized_2x = image.resize((size * 2, size * 2), Image.LANCZOS)
                resized_2x.save(iconset_dir / f"icon_{size}x{size}@2x.png")

        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(output_path)],
            check=True,
        )


def main() -> None:
    image = load_icon()

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    preview_path = DIST_DIR / "icon_preview.png"
    image.save(preview_path)
    print(f"Saved preview: {preview_path}")

    icns_path = RESOURCES_DIR / "AppIcon.icns"
    create_icns(image, icns_path)
    print(f"Generated icon: {icns_path}")


if __name__ == "__main__":
    main()
