"""Project the Royal Air Maroc side-profile design onto the X-Crafts E190
fuselage texture (8192 px) and multiply it over the kit's E190 base.

usage: paint_fus.py <livery tools dir> <fonts dir> <out dir>
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, sys.argv[1])
import geometry as G
import elements as E

FONTS, OUT = sys.argv[2], sys.argv[3]
N = 8192
Image.MAX_IMAGE_PIXELS = None

# ---- UV layout of the kit (4096 px units) --------------------------------
AX_F, CROWN_F = 997.0, 0.0            # forward section: belly axis, crown
AX_A, CROWN_A = 3096.9, 2100.0        # aft section
SPLIT_V = 2020.0                      # rows above: forward; below: aft
DART_U = 2050.0                       # aft columns from here use arc length

# texture U <-> photo x, from the cabin windows (and the L1 door, tail end)
FWD = ([993, 1323, 1499.5, 1675.5, 1852.5, 2029.5, 2206, 2382.5, 2559, 2735,
        2912.5, 3089, 3290.5, 3478, 3660.5, 3842.5],
       [316.5, 394.5, 436, 477.5, 519, 560, 602, 643.5, 684, 725, 766.5, 809,
        858.5, 902, 947, 991])
AFT = ([615, 797.5, 1807.5, 1976, 2144, 2310.5, 4090],
       [1030.5, 1070, 1299, 1339, 1379.5, 1420, 1845])
THETA_WIN = math.pi * 378 / 997        # window row angle from the crown


def interp_ex(x, xp, fp):
    """np.interp with linear extrapolation at both ends."""
    xp, fp = np.asarray(xp, float), np.asarray(fp, float)
    y = np.interp(x, xp, fp)
    lo, hi = x < xp[0], x > xp[-1]
    y = np.where(lo, fp[0] + (x - xp[0]) * (fp[1] - fp[0]) / (xp[1] - xp[0]), y)
    y = np.where(hi, fp[-1] + (x - xp[-1]) * (fp[-1] - fp[-2]) / (xp[-1] - xp[-2]), y)
    return y


def u_to_x(U, aft):
    return interp_ex(U, *(AFT if aft else FWD))


def x_to_u(x, aft):
    t, p = AFT if aft else FWD
    return float(interp_ex(np.array([x]), p, t)[0])


_cx, _cy = zip(*G.CROWN)
_bx, _by = zip(*G.BELLY)
_ax = np.arange(-50, 2000, 0.5)
_ay = np.array([G.axis(v) for v in _ax])


def crown_p(x):
    return np.interp(x, _cx, _cy)


def belly_p(x):
    return np.interp(x, _bx, _by)


def axis_p(x):
    return np.interp(x, _ax, _ay)


def t_warp(theta, x):
    """Angle from the crown -> fraction of the side-view height (0 crown,
    1 belly), pinned so the window row lands on the photo's window line."""
    tm = (1 - np.cos(theta)) / 2
    twm = (1 - math.cos(THETA_WIN)) / 2
    c, b = crown_p(x), belly_p(x)
    twp = (axis_p(x) - c) / (b - c)
    return np.where(tm <= twm, tm * twp / twm, twp + (tm - twm) * (1 - twp) / (1 - twm))


def t_unwarp(t, x):
    twm = (1 - math.cos(THETA_WIN)) / 2
    c, b = G.crown(x), G.belly(x)
    twp = (G.axis(x) - c) / (b - c)
    tm = t * twm / twp if t <= twp else twm + (t - twp) * (1 - twm) / (1 - twp)
    return math.acos(1 - 2 * tm)


# ---- skin mask and angle map at 8K ---------------------------------------
mask4 = np.asarray(Image.open('layers/fus__paintmask.png')) > 127
mask8 = np.repeat(np.repeat(mask4, 2, 0), 2, 1)
V4 = (np.arange(N) + 0.5) / 2
U4 = (np.arange(N) + 0.5) / 2

theta = np.full((N, N), np.nan, np.float32)
# forward: linear from the crown edges to the belly axis
fl = V4 < AX_F
fr = (V4 >= AX_F) & (V4 < SPLIT_V)
theta[fl, :] = (np.pi * (V4[fl] - CROWN_F) / (AX_F - CROWN_F))[:, None]
theta[fr, :] = (np.pi * (2 * AX_F - V4[fr]) / (AX_F - CROWN_F))[:, None]
# aft: linear before the darts...
al = (V4 >= SPLIT_V) & (V4 < AX_A)
ar = V4 >= AX_A
lin_cols = U4 < DART_U
th_l = np.clip(np.pi * (V4[al] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
th_r = np.clip(np.pi * (2 * AX_A - V4[ar] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
theta[np.ix_(al, lin_cols)] = th_l[:, None]
theta[np.ix_(ar, lin_cols)] = th_r[:, None]
# ...then arc length measured over the skin only, skipping the darts
dart_cols = np.nonzero(~lin_cols)[0]
rows_l, rows_r = np.nonzero(al)[0], np.nonzero(ar)[0]
ml = mask8[np.ix_(rows_l, dart_cols)].astype(np.float32)
cl = np.cumsum(ml, 0)
theta[np.ix_(rows_l, dart_cols)] = np.pi * cl / np.maximum(cl[-1:], 1)
mr = mask8[np.ix_(rows_r, dart_cols)][::-1].astype(np.float32)
cr = np.cumsum(mr, 0)
theta[np.ix_(rows_r, dart_cols)] = (np.pi * cr / np.maximum(cr[-1:], 1))[::-1]

# ---- design raster in photo space ----------------------------------------
K, X0, Y0, XW, YH = 10, 0, 380, 1900, 340
img = Image.new('RGB', (XW * K, YH * K), G.WHITE)
d = ImageDraw.Draw(img)


def P(pts):
    return [((x - X0) * K, (y - Y0) * K) for x, y in pts]


TOP, BOT = Y0 - 50, Y0 + YH + 50
b1, b2, b3 = G.catmull_rom(G.B1), G.catmull_rom(G.B2), G.catmull_rom(G.B3)
b4b3 = G.catmull_rom(G.B4 + G.B3[4:])
b5 = G.catmull_rom(G.B5)
d.polygon(P(b1 + [(2000, BOT), (2000, TOP), (b1[0][0], TOP)]), fill=G.LIGHT_GREEN)
d.polygon(P(b3 + [(1750, BOT), (1400, BOT)] + b2[::-1]), fill=G.DARK_GREEN)
d.polygon(P(b4b3 + [(1750, BOT), (2000, BOT), (2000, TOP), (b4b3[0][0], TOP)]), fill=G.WHITE)
d.polygon(P(b5 + [(2000, b5[-1][1]), (2000, TOP), (b5[0][0], TOP)]), fill=G.RED)
img = img.filter(ImageFilter.GaussianBlur(1.2))
design = np.asarray(img).astype(np.float32) / 255
del img, d

# ---- sample the design for every skin texel -------------------------------
paint = np.ones((N, N, 3), np.float32)
aft_row = V4 >= SPLIT_V
for r0 in range(0, N, 512):
    rs = slice(r0, r0 + 512)
    th = theta[rs]
    m = mask8[rs] & np.isfinite(th)
    if not m.any():
        continue
    rr, cc = np.nonzero(m)
    aft = aft_row[rs][rr]
    x = np.where(aft, u_to_x(U4[cc], True), u_to_x(U4[cc], False))
    t = t_warp(th[rr, cc], x)
    y = crown_p(x) + t * (belly_p(x) - crown_p(x))
    coords = [(y - Y0) * K, (x - X0) * K]
    blk = paint[rs]
    for ch in range(3):
        blk[rr, cc, ch] = ndimage.map_coordinates(design[..., ch], coords, order=1, mode='nearest')
    print('rows', r0, flush=True)
del design


# ---- titles, registration, flag: placed undistorted in texture space ------
def to_tex(x, y):
    """Left-side photo point -> 8K texture (u, v)."""
    aft = x > 1028
    U = x_to_u(x, aft)
    th = t_unwarp((y - G.crown(x)) / (G.belly(x) - G.crown(x)), x)
    if aft and U >= DART_U:
        col = int(U * 2)
        rows = np.nonzero(al)[0]
        v = np.interp(th, theta[rows, col], rows)
        return U * 2, v
    crown, ax = (CROWN_A, AX_A) if aft else (CROWN_F, AX_F)
    return U * 2, (crown + th / math.pi * (ax - crown)) * 2


def stamp(art, cx, cy, w, ax_v, aspect=None, top=None, bottom=None):
    """Multiply art (RGBA) into the paint on both sides, centred on photo
    (cx, cy) on the left side, keeping its proportions (the width comes from
    the photo); the right side gets it rotated 180."""
    u0, _ = to_tex(cx - w / 2, cy)
    u1, _ = to_tex(cx + w / 2, cy)
    uc, vc = to_tex(cx, cy)
    tw = int(round(u1 - u0))
    th_ = int(round(tw / (aspect or art.width / art.height)))
    if top is not None:
        vc = top + th_ / 2
    if bottom is not None:
        vc = bottom - th_ / 2
    a = art.convert('RGBA').resize((tw, th_), Image.LANCZOS)
    for side in ('L', 'R'):
        im = a if side == 'L' else a.rotate(180)
        v_c = vc if side == 'L' else 2 * ax_v * 2 - vc
        x0, y0 = int(round(uc - tw / 2)), int(round(v_c - th_ / 2))
        arr = np.asarray(im).astype(np.float32) / 255
        al_ = arr[..., 3:4]
        reg = paint[y0:y0 + th_, x0:x0 + tw]
        reg[:] = reg * (1 - al_) + arr[..., :3] * al_
        print('stamped', side, (x0, y0, tw, th_), 'v range', y0, y0 + th_)


en = E.words_layer(['Royal', 'Air', 'Maroc'], f'{FONTS}/outfit-latin-600-normal.woff', 600, G.RED)
ar_ = E.text_layer('الخطوط الملكية المغربية', f'{FONTS}/aref-ruqaa-arabic-700-normal.woff',
                   600, G.RED, direction='rtl', pad=0)
reg = E.text_layer('CN-RGO', f'{FONTS}/outfit-latin-600-normal.woff', 300, G.REG_RED, pad=0)
emb = E.text_layer('EMBRAER 190', f'{FONTS}/outfit-latin-600-normal.woff', 200, (30, 30, 30), pad=0)

ex, ey = G.TITLE_EN['center']; ew = G.TITLE_EN['width']
# titles hug the forward window row (V 378 +/- 36 at 4K): Arabic above, English below
WIN_TOP8, WIN_BOT8, GAP8 = (378 - 36) * 2, (378 + 36) * 2, 30
stamp(en, ex, ey, ew, AX_F, top=WIN_BOT8 + GAP8)
axx, ayy = G.TITLE_AR['center']
stamp(ar_, axx, 458.5, G.TITLE_AR['width'], AX_F, aspect=6.0, bottom=WIN_TOP8 - GAP8)
rx, ry = G.REG['center']; rw = G.REG['width']
stamp(reg, rx, ry, rw, AX_A)
ec = G.EMBRAER_190['center']; ewd = G.EMBRAER_190['width']
stamp(emb, ec[0], ec[1], ewd, AX_F)

# Moroccan flag: red field, green interlaced star
fw = 600
flag = Image.new('RGBA', (fw, int(fw * 2 / 3)), (193, 39, 45, 255))
star = E.woven_star(flag.size, fw / 2, flag.height / 2 + 6, flag.height * 0.36,
                    flag.height * 0.36 * 0.14, flag.height * 0.36 * 0.04)
flag.paste(Image.new('RGBA', flag.size, (0, 98, 51, 255)), mask=star)
fx0, fy0, fx1, fy1 = G.FLAG
stamp(flag, (fx0 + fx1) / 2, (fy0 + fy1) / 2, fx1 - fx0, AX_F)

paint[~mask8] = 1.0
np.save(f'{OUT}/fus_paint8.npy', paint.astype(np.float16))
Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(f'{OUT}/fus_paint8.png')
print('done')
