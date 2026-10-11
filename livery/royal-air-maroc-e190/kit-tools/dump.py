"""Save selected PSD layers as 8-bit PNGs (full res) plus 1024 previews."""
import sys, re
import numpy as np
from PIL import Image
from psd_tools import PSDImage

src, tag = sys.argv[1], sys.argv[2]
wanted = sys.argv[3:]
psd = PSDImage.open(src)

def path(l):
    names = []
    while l is not None and l.parent is not None and hasattr(l, 'name'):
        names.append(l.name)
        l = l.parent
    return '/'.join(reversed(names))

for l in psd.descendants():
    p = path(l)
    if p in wanted:
        img = l.composite(force=True) if l.is_group() else l.topil()
        if img is None:
            print('empty', p); continue
        # place on the full canvas
        canvas = Image.new('RGBA', psd.size, (0, 0, 0, 0))
        im = img.convert('RGBA')
        x0, y0 = (l.bbox[0], l.bbox[1]) if not l.is_group() else (l.bbox[0], l.bbox[1])
        canvas.paste(im, (x0, y0))
        safe = re.sub(r'[^A-Za-z0-9]+', '_', p).strip('_')
        canvas.save(f'layers/{tag}__{safe}.png')
        prev = Image.new('RGBA', psd.size, (255, 0, 255, 255))
        prev.alpha_composite(canvas)
        prev.convert('RGB').resize((1024, 1024), Image.LANCZOS).save(f'prev/{tag}__{safe}.png')
        print('saved', p, l.bbox, im.mode)
