"""Composite the fuselage kit for an E190 with a neutral (white) paint layer.

Keeps: base texture, dirt, E190 emergency exits, door outlines, and from the
template only the nose-gear stripe. The template's oneworld logo is left out:
it sits in the kit's high-res patch that the model shows beside the main door,
so it doubled up with the livery's own emblem painted there.
"""
import sys, warnings
warnings.filterwarnings('ignore')
from psd_tools import PSDImage

psd = PSDImage.open(sys.argv[1])

def node(path):
    cur = psd
    for p in path.split('/'):
        cur = next(l for l in cur if l.name == p)
    return cur

show = {
    'SHOW THIS ONLY FOR E175': False,
    'SHOW THIS ONLY FOR E170': False,
    'SHOW THIS ONLY FOR LINEAGE': False,
    'SHOW THIS ONLY FOR E195': False,
    'SHOW THIS ONLY FOR E190': True,
    'DOOR OUTLINES INSIDE LINEAGE': False,
    'TOOLS (HIDE THIS ON EXPORT)': False,
    '* READ THIS ONCE AND THEN DELETE IT FOREVER * ': False,
    'WIREFRAME': False,
}
for l in psd:
    if l.name in show:
        l.visible = show[l.name]
liv = node('LIVERIES')
for l in liv:
    l.visible = (l.name == 'TEMPLATE (PAINT HERE)')
tpl = node('LIVERIES/TEMPLATE (PAINT HERE)')
for l in tpl:
    if l.name.startswith('OPTIONAL HIGH RES'):
        l.visible = False
    if l.name == 'MAKE HORIZONTAL STABILIZER DEGREES WHITE':
        l.visible = False
node('LIVERIES/TEMPLATE (PAINT HERE)/PAINT COLOR HERE (MULTIPLIED)').visible = False
keep = {'NOSE GEAR RED STRIPE'}
for l in node('LIVERIES/TEMPLATE (PAINT HERE)/TEXT AND DECALS'):
    l.visible = l.name in keep

img = psd.composite(force=True)
img.save(sys.argv[2])
print(img.mode, img.size)
