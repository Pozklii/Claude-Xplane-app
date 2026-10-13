"""Paint the fin (both sides) on the X-Crafts E-Jets tail texture at 8K.

Each fin side is mapped from the traced photo fin with a piecewise-affine
transform through five points: root and tip of the trailing edge, tip of the
leading edge, the dorsal/leading-edge kink, and the front of the dorsal.

usage: paint_tail.py <livery tools dir> <out dir>
"""
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, sys.argv[1])
import geometry as G
OUT = sys.argv[2]
N = 8192
Image.MAX_IMAGE_PIXELS = None

PHOTO = dict(rootTE=(1783, 540), tipTE=(1845, 265), tipLE=(1785, 264),
             kink=(1592, 463), dorsal=(1440, 507))
SIDES = {   # island label in tail_fill_lab -> texture points (4K)
    6: dict(rootTE=(3409, 4089), tipTE=(4077, 1333), tipLE=(3283, 1386),
            kink=(1568, 3388), dorsal=(287, 3957)),
    5: dict(rootTE=(750, 985), tipTE=(80, 3737), tipLE=(877, 3687),
            kink=(2591, 1686), dorsal=(3872, 1118)),
}
TRIS = [('rootTE', 'tipTE', 'tipLE'), ('rootTE', 'tipLE', 'kink'), ('rootTE', 'kink', 'dorsal')]

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


def bary(T, p):
    (x1, y1), (x2, y2), (x3, y3) = T
    det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    l1 = ((y2 - y3) * (p[:, 0] - x3) + (x3 - x2) * (p[:, 1] - y3)) / det
    l2 = ((y3 - y1) * (p[:, 0] - x3) + (x1 - x3) * (p[:, 1] - y3)) / det
    return np.stack([l1, l2, 1 - l1 - l2], 1)


def affine(src, dst):
    """3x2 affine taking src triangle to dst triangle."""
    A = np.array([[x, y, 1] for x, y in src], float)
    return np.linalg.solve(A, np.array(dst, float))


logo = Image.open(f'{sys.argv[1]}/../artwork/ram_tail_logo_4k.png').convert('RGBA')
for comp, tex in SIDES.items():
    m4 = lab4 == comp
    others = (lab4 != 0) & ~m4
    m4 = ndimage.binary_dilation(m4, iterations=6) & ~others
    m8 = np.repeat(np.repeat(m4, 2, 0), 2, 1)
    yy, xx = np.nonzero(m8)
    pt = np.stack([(xx + 0.5) / 2, (yy + 0.5) / 2], 1)
    best = np.full(len(pt), -1e9); photo = np.zeros_like(pt)
    for tri in TRIS:
        b = bary([tex[k] for k in tri], pt)
        q = b @ np.array([PHOTO[k] for k in tri], float)
        score = b.min(1)
        better = score > best
        photo[better] = q[better]; best[better] = score[better]
    coords = [(photo[:, 1] - Y0) * K, (photo[:, 0] - X0) * K]
    for ch in range(3):
        paint[yy, xx, ch] = ndimage.map_coordinates(design[..., ch], coords, order=1, mode='nearest')

    # tail logo: undistorted, scaled and turned to the local fin frame
    c = G.LOGO['center']
    for tri in TRIS:
        b = bary([PHOTO[k] for k in tri], np.array([c], float))[0]
        if b.min() >= -1e-6:
            break
    M = affine([PHOTO[k] for k in tri], [tex[k] for k in tri])     # photo -> tex4
    ctex = np.array([c[0], c[1], 1]) @ M
    J = M[:2].T                                                      # 2x2 linear part
    scale = math.sqrt(abs(np.linalg.det(J)))
    ang = math.degrees(math.atan2(J[1, 0], J[0, 0]))
    size8 = int(round(G.LOGO['size'] * scale * 2))
    lg = logo.resize((size8, size8), Image.LANCZOS).rotate(-ang, resample=Image.BICUBIC, expand=True)
    arr = np.asarray(lg).astype(np.float32) / 255
    x0 = int(round(ctex[0] * 2 - lg.width / 2)); y0 = int(round(ctex[1] * 2 - lg.height / 2))
    reg = paint[y0:y0 + lg.height, x0:x0 + lg.width]
    a = arr[..., 3:4]
    reg[:] = reg * (1 - a) + arr[..., :3] * a
    print('side', comp, 'logo at', (x0, y0), 'size', size8, 'angle', round(ang, 1), 'scale', round(scale, 2))

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
