#!/usr/bin/env python3
"""Generates the Transclase app icon.

Follows Apple's macOS icon grid: a 1024×1024 canvas where the artwork occupies a
824×824 rounded square (radius 185) centred, leaving room for the drop shadow
the system expects. Flat white fill, black waveform glyph.
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CONTENT = 824           # macOS icon grid: content square inside the canvas
RADIUS = 185            # Big Sur squircle radius for that square
BARS = [0.40, 0.62, 0.86, 0.58, 0.36]
BAR_WIDTH = 62
BAR_GAP = 52
BAR_FILL = 0.46         # tallest bar as a fraction of the content square


def squircle_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def build(with_shadow: bool = True) -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    offset = (SIZE - CONTENT) // 2

    if with_shadow:
        # Soft shadow so the white tile keeps an edge on a white desktop, which
        # is what macOS icons are expected to do.
        shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_draw.rounded_rectangle(
            [offset, offset + 12, offset + CONTENT, offset + CONTENT + 12],
            radius=RADIUS,
            fill=(0, 0, 0, 46),
        )
        canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))

    tile = Image.new("RGBA", (CONTENT, CONTENT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    draw.rounded_rectangle([0, 0, CONTENT - 1, CONTENT - 1], radius=RADIUS, fill=(255, 255, 255, 255))

    total = len(BARS) * BAR_WIDTH + (len(BARS) - 1) * BAR_GAP
    x = (CONTENT - total) / 2
    for ratio in BARS:
        height = CONTENT * BAR_FILL * ratio
        y = (CONTENT - height) / 2
        draw.rounded_rectangle([x, y, x + BAR_WIDTH, y + height], radius=BAR_WIDTH / 2, fill=(0, 0, 0, 255))
        x += BAR_WIDTH + BAR_GAP

    canvas.alpha_composite(tile, (offset, offset))
    return canvas


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    assetset = root / "Transclase/Assets.xcassets/AppIcon.appiconset"
    docs_icon = root / "docs/img/icon.png"

    if len(sys.argv) > 1 and sys.argv[1] == "--flat":
        master = build(with_shadow=False)
    else:
        master = build(with_shadow=True)

    assetset.mkdir(parents=True, exist_ok=True)
    master.resize((SIZE, SIZE), Image.LANCZOS).save(assetset / "icon-1024@2x.png")

    for pixels, scale in [(16, "1x"), (32, "2x"), (32, "1x"), (64, "2x"),
                          (128, "1x"), (256, "2x"), (256, "1x"), (512, "2x"),
                          (512, "1x")]:
        master.resize((pixels, pixels), Image.LANCZOS).save(assetset / f"icon-{pixels}@{scale}.png")

    master.resize((256, 256), Image.LANCZOS).save(docs_icon)
    master.save("/tmp/icon-master.png")
    print(f"wrote {SIZE}px master + 9 sizes, docs icon")


if __name__ == "__main__":
    main()
