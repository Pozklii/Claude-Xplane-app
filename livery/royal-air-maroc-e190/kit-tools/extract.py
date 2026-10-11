"""Pull the masks the painters need out of the X-Crafts E-Jets paint kit.

Writes into ./layers: the fuselage paintable-skin mask and the labelled fin
islands of the tail wireframe.

usage: extract.py <FUSELAGE psd> <TAIL psd>
"""
import os, sys, warnings
warnings.filterwarnings('ignore')
import numpy as np
from PIL import Image
from psd_tools import PSDImage
from scipy import ndimage

os.makedirs('layers', exist_ok=True)


def node(psd, path):
    cur = psd
    for p in path:
        cur = next(l for l in cur if l.name == p)
    return cur


fus = PSDImage.open(sys.argv[1])
m = node(fus, ['LIVERIES', 'TEMPLATE (PAINT HERE)', 'PAINT COLOR HERE (MULTIPLIED)']).mask
full = Image.new('L', fus.size, m.background_color)
full.paste(m.topil(), m.bbox[:2])
full.save('layers/fus__paintmask.png')

tail = PSDImage.open(sys.argv[2])
w = node(tail, ['WIREFRAME', 'Layer 761'])
can = Image.new('RGBA', tail.size, (0, 0, 0, 0))
can.paste(w.topil().convert('RGBA'), w.bbox[:2])
a = np.asarray(can).astype(int)
lines = (a[..., 3] > 60) & ((a[..., 2] - a[..., 0]) > 30)
filled = ndimage.binary_fill_holes(ndimage.binary_closing(lines, iterations=3))
lab, n = ndimage.label(filled)
np.save('layers/tail_fill_lab.npy', lab.astype(np.int32))
sizes = ndimage.sum(filled, lab, range(1, n + 1))
print('fin islands (largest two):', [int(i) + 1 for i in np.argsort(sizes)[::-1][:2]])
