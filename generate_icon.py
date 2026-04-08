#!/usr/bin/env python3
"""SimulTrans 用のアプリアイコンを生成する。"""
from PIL import Image, ImageDraw, ImageFont
import os, subprocess, tempfile

SIZE = 1024


def draw_icon(size=SIZE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size / 2, size / 2

    # === Rounded square background with gradient ===
    margin = size * 0.06
    rr = size * 0.22
    x0, y0, x1, y1 = margin, margin, size - margin, size - margin

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=rr, fill=255)

    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i in range(size):
        t = i / size
        r = int(18 + t * 25)
        g = int(55 + t * 55)
        b = int(145 + t * 55)
        ImageDraw.Draw(grad).line([(0, i), (size, i)], fill=(r, g, b, 255))

    img = Image.composite(grad, img, mask)
    draw = ImageDraw.Draw(img)

    # === Load fonts ===
    # English font (bold)
    en_font = None
    en_size = int(size * 0.38)
    for fp in [
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Geneva.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]:
        if os.path.exists(fp):
            try:
                en_font = ImageFont.truetype(fp, en_size)
                break
            except Exception:
                continue

    # Chinese font
    zh_font = None
    zh_size = int(size * 0.34)
    for fp in [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
    ]:
        if os.path.exists(fp):
            try:
                zh_font = ImageFont.truetype(fp, zh_size)
                break
            except Exception:
                continue

    if en_font is None:
        en_font = ImageFont.load_default()
    if zh_font is None:
        zh_font = ImageFont.load_default()

    # === Draw "A" on the left side ===
    a_x = cx * 0.58
    a_y = cy * 0.85
    draw.text((a_x, a_y), "A", fill=(255, 255, 255, 255), font=en_font, anchor="mm")

    # === Draw "文" on the right side ===
    w_x = cx * 1.42
    w_y = cy * 1.15
    draw.text((w_x, w_y), "\u6587", fill=(255, 255, 255, 255), font=zh_font, anchor="mm")

    # === Arrow from A to 文 ===
    arrow_y = cy
    ax1 = a_x + size * 0.12
    ax2 = w_x - size * 0.12
    aw = max(4, size // 140)
    ah = size * 0.025

    # Slight diagonal arrow
    ay1 = cy * 0.9
    ay2 = cy * 1.1
    draw.line([(ax1, ay1), (ax2 - ah * 2, ay2)],
              fill=(255, 255, 255, 200), width=aw)
    # Arrowhead
    import math
    angle = math.atan2(ay2 - ay1, ax2 - ax1)
    draw.polygon([
        (ax2, ay2),
        (ax2 - ah * 3 * math.cos(angle - 0.4), ay2 - ah * 3 * math.sin(angle - 0.4)),
        (ax2 - ah * 3 * math.cos(angle + 0.4), ay2 - ah * 3 * math.sin(angle + 0.4)),
    ], fill=(255, 255, 255, 200))

    return img


def create_icns(img, output_path):
    with tempfile.TemporaryDirectory() as tmpdir:
        iconset_dir = os.path.join(tmpdir, "AppIcon.iconset")
        os.makedirs(iconset_dir)
        sizes = [16, 32, 64, 128, 256, 512, 1024]
        for s in sizes:
            resized = img.resize((s, s), Image.LANCZOS)
            resized.save(os.path.join(iconset_dir, f"icon_{s}x{s}.png"))
            if s <= 512:
                resized2x = img.resize((s * 2, s * 2), Image.LANCZOS)
                resized2x.save(os.path.join(iconset_dir, f"icon_{s}x{s}@2x.png"))
        subprocess.run(
            ["iconutil", "-c", "icns", iconset_dir, "-o", output_path],
            check=True
        )


if __name__ == "__main__":
    img = draw_icon()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dist_dir = os.path.join(script_dir, "dist")
    os.makedirs(dist_dir, exist_ok=True)
    resources_dir = os.path.join(script_dir, "AppTemplate", "Contents", "Resources")
    os.makedirs(resources_dir, exist_ok=True)

    preview_path = os.path.join(dist_dir, "icon_preview.png")
    img.save(preview_path)
    print(f"プレビューを保存しました: {preview_path}")

    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    create_icns(img, icns_path)
    print(f"アイコンを生成しました: {icns_path}")
