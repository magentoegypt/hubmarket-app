"""Fit raw phone screenshots to a store's listing rules.

Google Play takes 24-bit PNG or JPEG without an alpha channel, each side 320-3840 px, and a long
side that is at most twice the short side. A tall phone (1080x2400 is 2.22:1) is over that, so each
capture is scaled to fit inside a 1080x2160 (2:1) canvas and centred on the brand navy: nothing is
cropped and the UI is not stretched. A capture that already fits keeps its size and only loses its
alpha channel.

The App Store also wants no alpha channel, and its captures (tool/ios_screenshots.sh) are already
the right size, so --flatten-only drops the alpha and leaves the size alone.

    python tool/fit_play_screenshots.py RAW_DIR OUT_DIR                  # Google Play
    python tool/fit_play_screenshots.py --flatten-only RAW_DIR OUT_DIR   # App Store

Needs Pillow. The Play form is run by tool/android_screenshots.sh.
"""
import sys
from pathlib import Path

from PIL import Image

NAVY = (0x0F, 0x21, 0x44)  # lib/app/theme/app_colors.dart, the primary navy
CANVAS = (1080, 2160)  # 2:1, the tallest Play accepts
MIN_SIDE, MAX_SIDE = 320, 3840


def flatten(image: Image.Image) -> Image.Image:
    """The image without an alpha channel. Flutter's surface capture is opaque; composite anyway."""
    if image.mode == 'RGBA':
        flat = Image.new('RGB', image.size, NAVY)
        flat.paste(image, mask=image.getchannel('A'))
        return flat
    return image.convert('RGB')


def fit(src: Path, dst: Path, flatten_only: bool = False) -> tuple[int, int]:
    image = flatten(Image.open(src))
    width, height = image.size
    long_side, short_side = max(width, height), min(width, height)
    if flatten_only or long_side <= 2 * short_side:
        out = image
    else:
        canvas_w, canvas_h = CANVAS if height >= width else CANVAS[::-1]
        scale = min(canvas_w / width, canvas_h / height)
        resized = image.resize((round(width * scale), round(height * scale)), Image.LANCZOS)
        out = Image.new('RGB', (canvas_w, canvas_h), NAVY)
        out.paste(resized, ((canvas_w - resized.width) // 2, (canvas_h - resized.height) // 2))
    if not flatten_only:
        assert MIN_SIDE <= min(out.size) and max(out.size) <= MAX_SIDE, out.size
        assert max(out.size) <= 2 * min(out.size), out.size
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, 'PNG', optimize=True)
    return out.size


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if a != '--flatten-only']
    flatten_only = len(args) != len(argv) - 1
    if len(args) != 2:
        print(__doc__)
        return 2
    raw, out = Path(args[0]), Path(args[1])
    files = sorted(raw.glob('*.png'))
    if not files:
        print(f'No PNG files in {raw}', file=sys.stderr)
        return 1
    for src in files:
        before = Image.open(src).size
        size = fit(src, out / src.name, flatten_only)
        print(f'{src.name}: {before[0]}x{before[1]} -> {size[0]}x{size[1]}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
