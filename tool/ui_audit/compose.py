"""Put a Figma frame and the app's render of it side by side for review.

    python tool/ui_audit/compose.py FIGMA.png APP.png OUT.png [--chunk 844]

Left is the Figma frame, right is the app, both scaled to the same width (390 px) and cut into
chunks of --chunk px (default 844, one phone screen) so a long scroll page becomes a few images
that are easy to read: OUT.png when there is one chunk, otherwise OUT_1.png, OUT_2.png, ...
Prints the two sizes so a height difference (extra or missing content) is visible at once.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

W = 390
GAP = 12
BG = (214, 217, 224)


def load(path: str) -> Image.Image:
    im = Image.open(path).convert('RGB')
    if im.width != W:
        im = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
    return im


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith('--')]
    chunk = 844
    if '--chunk' in argv:
        chunk = int(argv[argv.index('--chunk') + 1])
        args = [a for a in args if a != str(chunk)]
    if len(args) != 3:
        print(__doc__)
        return 2
    figma, app, out = load(args[0]), load(args[1]), Path(args[2])
    print('figma %dx%d | app %dx%d' % (figma.width, figma.height, app.width, app.height))
    height = max(figma.height, app.height)
    parts = max(1, -(-height // chunk))
    out.parent.mkdir(parents=True, exist_ok=True)
    for i in range(parts):
        top, bottom = i * chunk, min((i + 1) * chunk, height)
        canvas = Image.new('RGB', (W * 2 + GAP, bottom - top), BG)
        canvas.paste(figma.crop((0, top, W, min(bottom, figma.height))) if top < figma.height else Image.new('RGB', (W, 1), BG), (0, 0))
        canvas.paste(app.crop((0, top, W, min(bottom, app.height))) if top < app.height else Image.new('RGB', (W, 1), BG), (W + GAP, 0))
        target = out if parts == 1 else out.with_name('%s_%d%s' % (out.stem, i + 1, out.suffix))
        canvas.save(target)
        print('wrote', target)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
