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

pts, cols, nrm = [], [], []

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
sgn = np.where(right, -1, 1)
nv = np.stack([np.zeros_like(t), sgn * r * np.sin(t), 0.9 * r * np.cos(t)], 1)
nrm.append(nv / np.maximum(np.linalg.norm(nv, axis=1, keepdims=True), 1e-6))

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
    nrm.append(np.tile([0.0, side, 0.0], (keep.sum(), 1)))

# horizontal stabilisers: swept plates rooted on the stabiliser root line
# (the kit's root shadow: 72.7 deg from the crown at station 1666, falling
# 0.1165 deg per px), leading-edge root at 1663 as in the first photo
stab_x0, stab_c0, stab_c1, span, sweep = 1663.0, 135.0, 60.0, 290.0, 0.62
for side in (1, -1):
    for s_ in np.linspace(0, 1, 700):
        le = stab_x0 + sweep * span * s_
        c = stab_c0 + (stab_c1 - stab_c0) * s_
        xs_ = np.linspace(le, le + c, int(c * 3))
        xr = np.clip(xs_ - sweep * span * s_, stab_x0, stab_x0 + stab_c0)   # root station
        tr = np.radians(72.7 + 0.1165 * (xr - 1666.0))
        cc, bb = F.crown_p(xr), F.belly_p(xr)
        rr, zz = (bb - cc) / 2, (bb + cc) / 2
        yv = side * (0.9 * rr * np.sin(tr) + span * s_)
        zv = -(zz - rr * np.cos(tr)) + 14 * s_
        pts.append(np.stack([xs_, yv, zv], 1))
        # painted aircraft grey, as both photos show them
        shade = 168 - 16 * ((xs_ - le) / c)
        cols.append(np.stack([shade, shade + 2, shade + 7], 1).astype(np.uint8))
        nrm.append(np.tile([0.0, 0.0, 2.0], (len(xs_), 1)))

# APU exhaust nozzle: bare metal from where the fuselage texture ends
x_end = max(q[0] for q in G.SILHOUETTE)
x_tex = float(F.u_to_x(np.array([4096.0]), True)[0])
for xx in np.arange(x_tex, x_end, 0.25):
    cc, bb = F.crown_p(xx), F.belly_p(xx)
    rr, zz = (bb - cc) / 2, (bb + cc) / 2
    t = np.linspace(0, 2 * np.pi, 400, endpoint=False)
    pts.append(np.stack([np.full_like(t, xx), 0.9 * rr * np.sin(t), -(zz - rr * np.cos(t))], 1))
    cols.append(np.tile(np.array([104, 104, 110], np.uint8), (len(t), 1)))
    nv = np.stack([np.zeros_like(t), np.sin(t), 0.9 * np.cos(t)], 1)
    nrm.append(nv / np.linalg.norm(nv, axis=1, keepdims=True))

P = np.concatenate(pts).astype(np.float32)
C = np.concatenate(cols).astype(np.float32)
NR = np.concatenate(nrm)
two_sided = NR[:, 2] > 1.5
NR[two_sided, 2] = 1.0
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
# light from above, ahead and to the left; soft fill so shadows stay readable
Ld = np.array([-0.35, 0.45, 0.82]); Ld /= np.linalg.norm(Ld)
facing = np.sign(NR @ cam)[:, None]
Nf = NR * np.where(facing == 0, 1, facing)
diff = np.clip(Nf @ Ld, 0, 1)
H_ = Ld + cam; H_ /= np.linalg.norm(H_)
spec = np.clip(Nf @ H_, 0, 1) ** 40
lit = C * (0.80 + 0.26 * diff)[:, None] + 255 * 0.12 * spec[:, None]
C = np.clip(lit, 0, 255).astype(np.uint8)
vis = two_sided | ((NR @ cam) > -0.02)
P, C, d, px, py = P[vis], C[vis], d[vis], px[vis], py[vis]
order = np.argsort(d)
img = np.zeros((H, W * S, 4), np.uint8)
# 3x3 splats, so no texel spacing shows as gaps at any scale
for dx in (-1, 0, 1):
    for dy in (-1, 0, 1):
        iy, ix = np.clip(py[order] + dy, 0, H - 1), np.clip(px[order] + dx, 0, W * S - 1)
        img[iy, ix, :3] = C[order]
        img[iy, ix, 3] = 255
Image.fromarray(img, 'RGBA').resize((W, H // S), Image.LANCZOS).save(out)
print('saved', out, W, H // S)
