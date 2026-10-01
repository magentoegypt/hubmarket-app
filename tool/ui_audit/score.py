"""Rank the Figma-vs-app pairs by how far apart they are, to decide where to look first.

    python tool/ui_audit/score.py [LOCALE]

For every pair in pairs.PAIRS that has both images, the two are scaled to 390 px wide, blurred and
compared on a coarse grid: `diff` is the mean absolute luminance difference over the common height
(photos and Latin/Arabic glyph shapes put a floor under it, so compare screens with each other, not
with zero) and `dh` is the height difference in px (extra or missing content). Prints the worst
first. It judges nothing by itself: read the composite of anything near the top.
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
import pairs  # noqa: E402

W = 390


def load(path: Path) -> Image.Image:
    im = Image.open(path).convert('L')
    if im.width != W:
        im = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
    return im


def coarse(im: Image.Image, height: int) -> list[int]:
    crop = im.crop((0, 0, W, height)).filter(ImageFilter.GaussianBlur(5))
    small = crop.resize((W // 6, max(1, height // 6)), Image.BILINEAR)
    return list(small.getdata())


def main(argv: list[str]) -> int:
    locale = argv[1] if len(argv) > 1 else 'en'
    figma_dir = pairs.FIGMA_DIRS.get(locale, pairs.FIGMA_DIRS['en'])
    rows = []
    for name, captures in pairs.PAIRS.items():
        figma = figma_dir / f'{name}.png'
        if not figma.exists():
            continue
        for capture in captures:
            shot = pairs.SHOTS / f'{capture}_{locale}.png'
            if not shot.exists():
                continue
            a, b = load(figma), load(shot)
            height = min(a.height, b.height)
            pa, pb = coarse(a, height), coarse(b, height)
            diff = sum(abs(x - y) for x, y in zip(pa, pb)) / max(1, len(pa))
            rows.append((diff, b.height - a.height, name, capture))
    for diff, dh, name, capture in sorted(rows, reverse=True):
        print(f'{diff:6.1f}  dh={dh:+5d}  {name:24s} {capture}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
