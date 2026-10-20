"""Paint the E190 belly fairing (belly.png) in the livery's white.

The fairing carries no stripes (no colour reaches it on the jet), but left as
the kit's bare base it was ~10 levels brighter and cooler than the painted
fuselage white round it (253 against 243), which shows as a lighter patch
edged by the fuselage. Its skin is multiplied by the same white as the
fuselage, over the kit's own paint mask (layers/belly__paintmask.png, from
extract.py), so the two match; gear bays, wheels and parts are left alone.

usage: paint_belly.py <livery tools dir> <belly base png> <out png>
"""
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, sys.argv[1])
import geometry as G

base = np.asarray(Image.open(sys.argv[2]).convert('RGBA')).astype(np.float32)
cov = np.asarray(Image.open('layers/belly__paintmask.png').convert('L')).astype(np.float32)[..., None] / 255
white = np.array(G.WHITE, np.float32) / 255
out = base.copy()
out[..., :3] = base[..., :3] * (1 - cov + cov * white)
# near-opaque kit alpha (240-254, a dither) made opaque, as in combine.py
out[..., 3] = np.where(base[..., 3] >= 240, 255, base[..., 3])
Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), 'RGBA').save(sys.argv[3], compress_level=6)
print('saved', sys.argv[3])
