"""Pull the paint kit's own Embraer title and oneworld logo out of the
fuselage PSD, for paint_fus.py.

usage: kitart.py <fuselage psd> <out dir>
  embraer_190.png  the left-side "EMBRAER 190" title as an alpha mask
                   (X-Crafts' artwork of Embraer's italic lettering)
  oneworld.png     the oneworld emblem, 1024 px
"""
import os, sys
import numpy as np
from PIL import Image
from psd_tools import PSDImage

psd = PSDImage.open(sys.argv[1])
out = sys.argv[2]
os.makedirs(out, exist_ok=True)


def find(g, name, parent):
    for l in g:
        if l.is_group():
            r = find(l, name, parent)
            if r is not None:
                return r
        elif l.name == name and l.parent.name == parent:
            return l


def show(l):
    p = l
    while p is not None and not isinstance(p, PSDImage):
        p.visible = True
        p = p.parent


# The title sits in the kit's (hidden) white airplane-names group, once per
# side; the left one is the upper instance.
emb = find(psd, 'EMBRAER', 'WHITE (AIRPLANE NAMES)')
num = find(psd, '190', 'WHITE (AIRPLANE NAMES)')
show(emb); show(num)
x0, y0 = emb.bbox[0], emb.bbox[1]
canvas = np.zeros((emb.bbox[3] - y0, max(emb.bbox[2], num.bbox[2]) - x0), np.float32)
a = np.asarray(emb.topil().convert('RGBA'))[..., 3] / 255.0
canvas[:a.shape[0], :a.shape[1]] = np.maximum(canvas[:a.shape[0], :a.shape[1]], a)
b = np.asarray(num.composite(force=True).convert('RGBA'))[..., 3] / 255.0
oy, ox = num.bbox[1] - y0, num.bbox[0] - x0
canvas[oy:oy + b.shape[0], ox:ox + b.shape[1]] = np.maximum(canvas[oy:oy + b.shape[0], ox:ox + b.shape[1]], b)
top = canvas[:canvas.shape[0] // 2]                     # left-side instance
ys, xs = np.nonzero(top > 0.04)
crop = top[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
Image.fromarray((crop * 255).astype(np.uint8), 'L').save(f'{out}/embraer_190.png')
print('embraer_190', crop.shape[::-1], 'kit position U %d-%d V %d-%d' % (
    x0 + xs.min(), x0 + xs.max() + 1, y0 + ys.min(), y0 + ys.max() + 1))

ow = find(psd, '1024px-Oneworld_logo.svg', 'TEXT AND DECALS')
open(f'{out}/oneworld.png', 'wb').write(ow.smart_object.data)
print('oneworld', Image.open(f'{out}/oneworld.png').size)
