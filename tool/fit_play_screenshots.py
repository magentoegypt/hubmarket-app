"""Fit raw phone screenshots to Google Play's listing rules.

Play takes 24-bit PNG or JPEG without an alpha channel, each side 320-3840 px, and a long side
that is at most twice the short side. A tall phone (1080x2400 is 2.22:1) is over that, so each
capture is scaled to fit inside a 1080x2160 (2:1) canvas and centred on the brand navy: nothing
is cropped and the UI is not stretched. A capture that already fits keeps its size and only
loses its alpha channel.

    python tool/fit_play_screenshots.py RAW_DIR OUT_DIR

Needs Pillow. Used by tool/android_screenshots.sh.
"""
import sys
from pathlib import Path

from PIL import Image

NAVY = (0x0F, 0x21, 0x44)  # lib/app/theme/app_colors.dart, the primary navy
CANVAS = (1080, 2160)  # 2:1, the tallest Play accepts
MIN_SIDE, MAX_SIDE = 320, 3840


def fit(src: Path, dst: Path) -> tuple[int, int]:
    image = Image.open(src)
    if image.mode == 'RGBA':
        # Flutter's surface capture is opaque; composite anyway so no alpha survives.
        flat = Image.new('RGB', image.size, NAVY)
        flat.paste(image, mask=image.getchannel('A'))
        image = flat
    else:
        image = image.convert('RGB')
    width, height = image.size
    long_side, short_side = max(width, height), min(width, height)
    if long_side <= 2 * short_side:
        out = image
    else:
        canvas_w, canvas_h = CANVAS if height >= width else CANVAS[::-1]
        scale = min(canvas_w / width, canvas_h / height)
        resized = image.resize((round(width * scale), round(height * scale)), Image.LANCZOS)
        out = Image.new('RGB', (canvas_w, canvas_h), NAVY)
        out.paste(resized, ((canvas_w - resized.width) // 2, (canvas_h - resized.height) // 2))
    assert MIN_SIDE <= min(out.size) and max(out.size) <= MAX_SIDE, out.size
    assert max(out.size) <= 2 * min(out.size), out.size
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, 'PNG', optimize=True)
    return out.size


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    raw, out = Path(argv[1]), Path(argv[2])
    files = sorted(raw.glob('*.png'))
    if not files:
        print(f'No PNG files in {raw}', file=sys.stderr)
        return 1
    for src in files:
        size = fit(src, out / src.name)
        print(f'{src.name}: {Image.open(src).size[0]}x{Image.open(src).size[1]} -> {size[0]}x{size[1]}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
