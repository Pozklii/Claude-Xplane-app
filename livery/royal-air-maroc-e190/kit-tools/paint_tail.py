"""Paint the fin (both sides) on the X-Crafts E-Jets tail texture at 8K.

Each fin side is mapped from the traced photo fin through five points (root
and tip of the trailing edge, tip of the leading edge, the dorsal/leading-edge
kink, the front of the dorsal) with a smooth thin-plate spline (finmap.py).
The red base and the tail logo both go through it, so they keep the shapes
the photo shows and no curve is creased.

usage: paint_tail.py <livery tools dir> <out dir>
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, sys.argv[1])
import geometry as G
OUT = sys.argv[2]
N = 8192
Image.MAX_IMAGE_PIXELS = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from finmap import FinMap, SIDES

# fin design in photo space: white, red below the fin curve
K, X0, Y0, XW, YH = 10, 1380, 200, 520, 420
img = Image.new('RGB', (XW * K, YH * K), G.WHITE)
fin = G.catmull_rom(G.FIN_RED)
ImageDraw.Draw(img).polygon([((x - X0) * K, (y - Y0) * K) for x, y in
                             fin + [(1950, 700), (fin[0][0], 700)]], fill=G.RED)
img = img.filter(ImageFilter.GaussianBlur(1.2))
design = np.asarray(img).astype(np.float32) / 255

lab4 = np.load('layers/tail_fill_lab.npy')
paint = np.ones((N, N, 3), np.float32)

logo = np.asarray(Image.open(f'{sys.argv[1]}/../artwork/ram_tail_logo_4k.png').convert('RGBA')).astype(np.float32) / 255
LS = logo.shape[0]
lc, lsize = G.LOGO['center'], G.LOGO['size']
for comp in SIDES:
    fm = FinMap(comp)
    m4 = lab4 == comp
    others = (lab4 != 0) & ~m4
    m4 = ndimage.binary_dilation(m4, iterations=6) & ~others
    m8 = np.repeat(np.repeat(m4, 2, 0), 2, 1)
    yy, xx = np.nonzero(m8)
    photo = np.empty((len(xx), 2))
    for a in range(0, len(xx), 2_000_000):          # in chunks, to bound memory
        sl = slice(a, a + 2_000_000)
        photo[sl] = fm.tex_to_photo(np.stack([(xx[sl] + 0.5) / 2, (yy[sl] + 0.5) / 2], 1))
    coords = [(photo[:, 1] - Y0) * K, (photo[:, 0] - X0) * K]
    for ch in range(3):
        paint[yy, xx, ch] = ndimage.map_coordinates(design[..., ch], coords, order=1, mode='nearest')

    # tail logo, drawn in photo space: sample it through the same map
    lx = (photo[:, 0] - (lc[0] - lsize / 2)) * LS / lsize - 0.5
    ly = (photo[:, 1] - (lc[1] - lsize / 2)) * LS / lsize - 0.5
    on = (lx > -2) & (lx < LS + 1) & (ly > -2) & (ly < LS + 1)
    al = ndimage.map_coordinates(logo[..., 3], [ly[on], lx[on]], order=1, mode='constant')
    yo, xo = yy[on], xx[on]
    for ch in range(3):
        c = ndimage.map_coordinates(logo[..., ch] * logo[..., 3], [ly[on], lx[on]], order=1, mode='constant')
        paint[yo, xo, ch] = paint[yo, xo, ch] * (1 - al) + c
    print('side', comp, 'fin texels', len(xx), 'logo texels', int((al > 0.5).sum()))

# Horizontal stabilisers and elevators: grey on the jet (both photos), where
# the kit leaves them off-white. Their skins are the light blue-grey panels
# across the top of the texture, plus one stabiliser skin and one elevator
# skin turned on end (the tapered piece on the left, U 6-617; the strip with
# the elevator's marks at bottom right, U 3583-3878). They are found by their
# colour against the white gutters, keeping clear of the fin sides, the
# beacon (U 1524-1775, V 97-348) and the two plain strips at the edges. In
# the eye-level photo the lit top surface is ~0.7 as bright as the white fin;
# with the kit's panels at ~(205, 207, 210) this gives ~(158, 160, 164).
STAB_PAINT = np.array([0.77, 0.775, 0.78], np.float32)
base4 = np.asarray(Image.open('layers/tail_base.png').convert('RGB')).astype(np.int16)
panel = base4.max(2) < 238
panel = ndimage.binary_closing(panel, np.ones((9, 9), bool))
panel = ndimage.binary_fill_holes(panel)
panel = ndimage.binary_opening(panel, np.ones((15, 15), bool))
fin_near = ndimage.binary_dilation(np.isin(lab4, list(SIDES)), iterations=12)
panel &= ~fin_near
area = np.zeros_like(panel)
area[:2440, :] = True                       # top band and the stabiliser skin on end
area[2750:, 3583:3878] = True               # the elevator skin on end
area[97:348, 1524:1775] = False             # beacon
area[1990:, :170] = False                   # plain strip, left edge
stab4 = panel & area
plab, n = ndimage.label(stab4)
sizes = ndimage.sum(stab4, plab, range(1, n + 1))
stab4 = np.isin(plab, 1 + np.nonzero(sizes > 30000)[0])
stab8 = np.repeat(np.repeat(stab4, 2, 0), 2, 1)
stab8 = ndimage.gaussian_filter(stab8.astype(np.float32), 1.0)[..., None]
paint = paint * (1 - stab8) + STAB_PAINT * stab8
print('stabiliser and elevator panels:', int(stab4.sum()), '4K texels')

Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(f'{OUT}/tail_paint8.png')
print('done')
