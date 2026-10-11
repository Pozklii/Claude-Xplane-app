"""Composite a kit PSD with only the named top-level groups visible.

usage: base_generic.py <psd> <out png> <visible group> [...]
"""
import sys, warnings
warnings.filterwarnings('ignore')
from psd_tools import PSDImage
psd = PSDImage.open(sys.argv[1])
keep = set(sys.argv[3:])
for l in psd:
    l.visible = l.name in keep
img = psd.composite(force=True)
img.save(sys.argv[2])
print(sys.argv[2], img.mode, img.size)
