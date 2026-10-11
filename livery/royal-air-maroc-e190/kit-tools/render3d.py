"""Rough 3D preview of the livery: the fuselage as a body of revolution built
from the photo's outline, plus the fin, splatted from the textures.

usage: render3d.py <livery tools dir> <fuselage 8K png> <tail 8K png> <out png> <azimuth> <elevation> [width]
  azimuth: 0 = left side, + = camera towards the tail; elevation: + = above
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, sys.argv[1])
import numpy as np
from PIL import Image
import geometry as G
import fusmap as F

Image.MAX_IMAGE_PIXELS = None
fus_png, tail_png, out = sys.argv[2], sys.argv[3], sys.argv[4]
az, el = math.radians(float(sys.argv[5])), math.radians(float(sys.argv[6]))
W = int(sys.argv[7]) if len(sys.argv) > 7 else 1800

pts, cols = [], []

# ---- fuselage ----
th = np.load('layers/theta4.npy').astype(np.float32)          # 4096^2
mask4 = np.asarray(Image.open('layers/fus__paintmask.png')) > 127
tex = np.asarray(Image.open(fus_png).convert('RGB').resize((4096, 4096), Image.BOX))
V4 = np.arange(4096) + 0.5
U4 = np.arange(4096) + 0.5
vv, uu = np.nonzero(mask4 & np.isfinite(th))
aft = V4[vv] >= F.SPLIT_V
x = np.where(aft, F.u_to_x(U4[uu], True), F.u_to_x(U4[uu], False))
right = np.where(aft, V4[vv] > F.AX_A, V4[vv] > F.AX_F)
t = th[vv, uu]
c, b = F.crown_p(x), F.belly_p(x)
r, zc = (b - c) / 2, (b + c) / 2
Y = np.where(right, -1, 1) * 0.9 * r * np.sin(t)
Z = -(zc - r * np.cos(t))
pts.append(np.stack([x, Y, Z], 1)); cols.append(tex[vv, uu])

# ---- fin (both faces, from the tail texture) ----
lab4 = np.load('layers/tail_fill_lab.npy')
ttex = np.asarray(Image.open(tail_png).convert('RGB').resize((4096, 4096), Image.BOX))
sys.argv = [sys.argv[0], sys.argv[1], 'layers']
PHOTO = dict(rootTE=(1783, 540), tipTE=(1845, 265), tipLE=(1785, 264), kink=(1592, 463), dorsal=(1440, 507))
SIDES = {6: (+1, dict(rootTE=(3409, 4089), tipTE=(4077, 1333), tipLE=(3283, 1386), kink=(1568, 3388), dorsal=(287, 3957))),
         5: (-1, dict(rootTE=(750, 985), tipTE=(80, 3737), tipLE=(877, 3687), kink=(2591, 1686), dorsal=(3872, 1118)))}
TRIS = [('rootTE', 'tipTE', 'tipLE'), ('rootTE', 'tipLE', 'kink'), ('rootTE', 'kink', 'dorsal')]


def bary(T, p):
    (x1, y1), (x2, y2), (x3, y3) = T
    det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    l1 = ((y2 - y3) * (p[:, 0] - x3) + (x3 - x2) * (p[:, 1] - y3)) / det
    l2 = ((y3 - y1) * (p[:, 0] - x3) + (x1 - x3) * (p[:, 1] - y3)) / det
    return np.stack([l1, l2, 1 - l1 - l2], 1)


for comp, (side, texp) in SIDES.items():
    yy, xx = np.nonzero(lab4 == comp)
    p = np.stack([xx + 0.5, yy + 0.5], 1)
    best = np.full(len(p), -1e9); ph = np.zeros_like(p)
    for tri in TRIS:
        bb = bary([texp[k] for k in tri], p)
        q = bb @ np.array([PHOTO[k] for k in tri], float)
        sc = bb.min(1); m = sc > best
        ph[m] = q[m]; best[m] = sc[m]
    # fin only above the fuselage crown
    keep = ph[:, 1] < F.crown_p(ph[:, 0]) + 2
    pts.append(np.stack([ph[keep, 0], np.full(keep.sum(), side * 2.0), -ph[keep, 1]], 1))
    cols.append(ttex[yy[keep], xx[keep]])

P = np.concatenate(pts).astype(np.float32)
C = np.concatenate(cols)
cam = np.array([math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)])
up = np.array([0, 0, 1.0])
rt = np.cross(cam, up); rt /= np.linalg.norm(rt)
iu = np.cross(rt, cam)
u, v, d = P @ rt, P @ iu, P @ cam
S = 2
pad = 20
umin, umax, vmin, vmax = u.min(), u.max(), v.min(), v.max()
sc = (W * S - 2 * pad) / (umax - umin)
H = int((vmax - vmin) * sc + 2 * pad)
px = ((u - umin) * sc + pad).astype(int)
py = ((vmax - v) * sc + pad).astype(int)
order = np.argsort(d)                       # far first, near last
img = np.zeros((H, W * S, 3), np.uint8); img[:] = (120, 160, 205)
for dx in (0, 1):
    for dy in (0, 1):
        img[np.clip(py[order] + dy, 0, H - 1), np.clip(px[order] + dx, 0, W * S - 1)] = C[order]
Image.fromarray(img).resize((W, H // S), Image.LANCZOS).save(out)
print('saved', out, W, H // S)
