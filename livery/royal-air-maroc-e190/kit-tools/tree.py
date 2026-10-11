import sys
from psd_tools import PSDImage

def walk(layer, depth=0):
    for l in layer:
        vis = 'V' if l.visible else '-'
        bb = l.bbox
        extra = f" blend={l.blend_mode.name}" if hasattr(l, 'blend_mode') else ''
        op = f" op={l.opacity}" if l.opacity != 255 else ''
        print(f"{'  '*depth}{vis} [{l.kind}] {l.name!r} bbox={bb}{extra}{op}")
        if l.is_group():
            walk(l, depth + 1)

for p in sys.argv[1:]:
    psd = PSDImage.open(p)
    print('=====', p.split('/')[-1], psd.width, 'x', psd.height, psd.color_mode, 'depth', psd.depth, 'channels', psd.channels)
    walk(psd)
