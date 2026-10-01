"""Put each Figma frame beside what the phone drew for it (the device audit, docs/device-audit.md).

    python tool/ui_audit/device_pairs.py [LOCALE] [FILTER] [--dir DIR]

The phone captures are DIR/<locale>-<frame>__<state>[__s<n>].png (DIR is build/device_audit by default;
build/device_audit_host is the host sweep's), 720 x 1640 px at 2x, so 360 x 820 dp. The frames are
build/ui_audit/figma/<frame>.png (English) and figma_ar/ (Arabic), 390 wide, with a 47 px status bar on top and a
34 px home indicator at the bottom; `<frame>` is the PAIRS key of tool/ui_audit/pairs.py.

Unlike compose.py nothing is scaled to match: the frame stays 390 wide and the capture is halved to 1 dp = 1 px
(360 wide), so a row that no longer fits at 360 dp, or text that wraps differently, shows as it does on the phone.
Each row is one phone screen high (the capture, or one of its scrolled-down captures `__s<n>`) beside the same
stretch of the frame. Writes DIR/cmp/<locale>-<frame>__<state>[_<k>].png (at most two rows per image) and
DIR/cmp/index_<locale>_<k>.png (thumbnails of every capture, eight to a sheet, for a first look), and lists the
frames that have no capture.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FIGMA_DIRS = {'en': ROOT / 'build' / 'ui_audit' / 'figma', 'ar': ROOT / 'build' / 'ui_audit' / 'figma_ar'}
FRAME_W = 390
ROW_H = 844          # one phone screen of the frame (390 x 844)
DEV_W, DEV_H = 360, 820
GAP = 12
BG = (214, 217, 224)
NAME = re.compile(r'^(?P<locale>[a-z]{2})-(?P<frame>[A-Za-z0-9_]+?)__(?P<state>[A-Za-z0-9_]+?)(?:__s(?P<scroll>\d+))?$')


def font(size: int):
    for candidate in ('C:/Windows/Fonts/arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def device_image(path: Path) -> Image.Image:
    im = Image.open(path).convert('RGB')
    return im.resize((DEV_W, round(im.height * DEV_W / im.width)), Image.LANCZOS)


def collect(directory: Path, locale: str, only: str):
    """frame -> state -> [(scroll index, path)] sorted by scroll index."""
    found = defaultdict(lambda: defaultdict(list))
    for path in sorted(directory.glob(f'{locale}-*.png')):
        m = NAME.match(path.stem)
        if not m:
            continue
        key = f"{m['frame']}__{m['state']}"
        if only and only not in key:
            continue
        found[m['frame']][m['state']].append((int(m['scroll'] or 0), path))
    for states in found.values():
        for shots in states.values():
            shots.sort()
    return found


def compose(frame_png: Path, shots, label: str, out_base: Path) -> int:
    frame = Image.open(frame_png).convert('RGB')
    if frame.width != FRAME_W:
        frame = frame.resize((FRAME_W, round(frame.height * FRAME_W / frame.width)), Image.LANCZOS)
    devs = [device_image(p) for _, p in shots]
    rows = max(len(devs), -(-frame.height // ROW_H))
    head = 22
    made = 0
    for first in range(0, rows, 2):
        chunk = range(first, min(first + 2, rows))
        height = head + ROW_H * len(chunk) + GAP * (len(chunk) - 1)
        canvas = Image.new('RGB', (FRAME_W + GAP + DEV_W, height), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((4, 4), f'{label}   Figma {frame.width}x{frame.height} | phone {len(devs)} shot(s)', fill=(20, 20, 20), font=font(13))
        y = head
        for i in chunk:
            top = i * ROW_H
            if top < frame.height:
                canvas.paste(frame.crop((0, top, FRAME_W, min(top + ROW_H, frame.height))), (0, y))
            if i < len(devs):
                canvas.paste(devs[i].crop((0, 0, DEV_W, min(devs[i].height, ROW_H))), (FRAME_W + GAP, y))
            y += ROW_H + GAP
        out = out_base if rows <= 2 else out_base.with_name(f'{out_base.stem}_{first // 2 + 1}{out_base.suffix}')
        out.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(out)
        made += 1
    return made


def index_sheets(directory: Path, locale: str, out_dir: Path) -> int:
    files = [p for p in sorted(directory.glob(f'{locale}-*.png')) if NAME.match(p.stem)]
    w = 270
    thumbs = []
    f = font(12)
    for path in files:
        im = Image.open(path).convert('RGB')
        t = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
        c = Image.new('RGB', (w, t.height + 18), (255, 255, 255))
        c.paste(t, (0, 18))
        ImageDraw.Draw(c).text((3, 3), path.stem.split('-', 1)[1][:44], fill=(0, 0, 0), font=f)
        thumbs.append(c)
    sheets = 0
    for first in range(0, len(thumbs), 8):
        group = thumbs[first:first + 8]
        h = max(t.height for t in group)
        sheet = Image.new('RGB', (4 * (w + 6), 2 * (h + 6)), (150, 150, 150))
        for i, t in enumerate(group):
            sheet.paste(t, ((i % 4) * (w + 6), (i // 4) * (h + 6)))
        out_dir.mkdir(parents=True, exist_ok=True)
        sheet.save(out_dir / f'index_{locale}_{first // 8 + 1}.png')
        sheets += 1
    return sheets


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith('--')]
    directory = ROOT / 'build' / 'device_audit'
    if '--dir' in argv:
        directory = Path(argv[argv.index('--dir') + 1])
        args = [a for a in args if a != str(directory) and a != argv[argv.index('--dir') + 1]]
    locale = args[0] if args else 'en'
    only = args[1] if len(args) > 1 else ''
    figma_dir = FIGMA_DIRS.get(locale, FIGMA_DIRS['en'])
    cmp_dir = directory / 'cmp'
    found = collect(directory, locale, only)
    images = 0
    no_frame = []
    for frame, states in sorted(found.items()):
        frame_png = figma_dir / f'{frame}.png'
        if not frame_png.exists():
            no_frame.append(frame)
            continue
        for state, shots in sorted(states.items()):
            images += compose(frame_png, shots, f'{locale}-{frame}__{state}', cmp_dir / f'{locale}-{frame}__{state}.png')
    sheets = 0 if only else index_sheets(directory, locale, cmp_dir)
    print(f'{images} comparison image(s) for {len(found)} frame(s), {sheets} index sheet(s) in {cmp_dir}')
    if no_frame:
        print('no Figma image for: ' + ', '.join(no_frame))
    # frames of the audit that the phone run has not captured
    sys.path.insert(0, str(Path(__file__).parent))
    try:
        from pairs import PAIRS
        missing = [name for name in PAIRS if name not in found]
        if missing and not only:
            print(f'frames without a phone capture ({len(missing)}): ' + ', '.join(missing))
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
