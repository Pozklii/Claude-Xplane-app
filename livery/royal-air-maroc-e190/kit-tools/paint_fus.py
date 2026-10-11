"""Project the Royal Air Maroc side-profile design onto the X-Crafts E190
fuselage texture (8192 px) and multiply it over the kit's E190 base.

usage: paint_fus.py <livery tools dir> <fonts dir> <out dir>
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, sys.argv[1])
import geometry as G
import elements as E

FONTS, OUT = sys.argv[2], sys.argv[3]
N = 8192
Image.MAX_IMAGE_PIXELS = None

from fusmap import *            # noqa: F401,F403  (layout constants and mapping)
import fusmap
theta, mask8, V4, U4, al, ar = fusmap.build_theta()
np.save('layers/theta4.npy', theta[::2, ::2].astype(np.float16))

# ---- design as boundaries around the fuselage ---------------------------
# Each colour edge is a curve theta_b(x): the angle from the crown at which
# it crosses photo station x. Regions lie "above" an edge (theta < theta_b).
# The photo is taken from below, so near the crown its edges bend sharply;
# there each edge is replaced by a smooth curve that carries it straight over
# the top to where the photo from above shows it crossing the crown.
DEG = math.pi / 180
XG = np.arange(0, 2000, 0.25)
DARK_RED = (142, 10, 32)
REG_BLACK = (22, 22, 24)


def theta_of(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    c, b = crown_p(x), belly_p(x)
    t = np.clip((y - c) / (b - c), 0, 1)
    twm = (1 - math.cos(THETA_WIN)) / 2
    twp = (axis_p(x) - c) / (b - c)
    tm = np.where(t <= twp, t * twm / twp, twm + (t - twp) * (1 - twm) / (1 - twp))
    return np.arccos(np.clip(1 - 2 * tm, -1, 1))


def edge(pts, crown_x=None, blend=50 * DEG, after=None):
    """theta_b on the XG grid for a photo polyline."""
    cr = np.array(G.catmull_rom(pts, 24))
    xs, th = cr[:, 0], theta_of(cr[:, 0], cr[:, 1])
    out = np.interp(XG, xs, th)
    out[XG < xs[0]] = 0.0
    if after is not None:
        out[XG > xs[-1]] = after
    if crown_x is not None:
        i = int(np.argmax(th >= blend))
        xa = np.interp(blend, th[:i + 1], xs[:i + 1])
        seg = slice(max(i - 40, 0), i + 40)          # monotonic stretch around the blend
        m1 = np.interp(blend + 1 * DEG, th[seg], xs[seg]) - np.interp(blend - 1 * DEG, th[seg], xs[seg])
        m1 /= 2 * DEG
        m0 = (xa - crown_x) / blend
        tt = np.linspace(0, 1, 400)
        h00, h10, h01, h11 = 2*tt**3 - 3*tt**2 + 1, tt**3 - 2*tt**2 + tt, -2*tt**3 + 3*tt**2, tt**3 - tt**2
        xh = h00 * crown_x + h10 * blend * m0 + h01 * xa + h11 * blend * m1
        thh = tt * blend
        sel = XG <= xa
        out[sel] = np.interp(XG[sel], xh, thh, left=0.0)
    return out


E_B1 = edge(G.B1, crown_x=750, after=math.pi)
E_B2 = edge(G.B2, crown_x=830, after=math.pi)
E_B3 = edge(G.B3, crown_x=955, after=math.pi)
E_B5 = edge(G.B5, crown_x=985)
# darker red: a wedge at the front of the red, tapering to a point ahead of
# the rear door (traced from the photo's dark/bright red)
DR_UP = [(1383, 503), (1400, 519.5), (1420, 527.5), (1440, 535.5), (1462, 548), (1486, 556.5)]
DR_LOW = [(1300, 556.5), (1320, 557.5), (1360, 560.5), (1400, 561.5), (1440, 560.5), (1470, 558.5), (1486, 556.5)]
E_DRU = edge(DR_UP, after=math.pi)
E_DRL = np.where(XG <= 1300, E_B5, edge(DR_LOW, after=0.0))
E_DRL[XG > 1486] = 0.0
EDGES = [E_B1, E_B2, E_B3, E_B5, E_DRU, E_DRL]
DEDGES = [np.gradient(e, XG) for e in EDGES]

# U (8K) per photo px, for each section
U8 = (np.arange(N) + 0.5)
dxdu = {aft: np.gradient(u_to_x(U8 / 2, aft), U8) for aft in (False, True)}


def coverage(k, x, th, gv, dudx):
    tb = np.interp(x, XG, EDGES[k])
    slope = np.interp(x, XG, DEDGES[k]) / dudx / gv
    d = (tb - th) / gv / np.sqrt(1 + slope ** 2)
    return np.clip(0.5 + d, 0, 1)


paint = np.ones((N, N, 3), np.float32)
aft_row = V4 >= SPLIT_V
C = {k: np.array(v, np.float32) / 255 for k, v in
     dict(L=G.LIGHT_GREEN, D=G.DARK_GREEN, W=G.WHITE, R=G.RED, DR=DARK_RED).items()}
for r0 in range(0, N, 512):
    rs = slice(r0, r0 + 512)
    th = theta[rs]
    m = mask8[rs] & np.isfinite(th)
    if not m.any():
        continue
    lo, hi = max(r0 - 1, 0), min(r0 + 513, N)
    thp = np.nan_to_num(theta[lo:hi])
    gfull = np.abs(np.gradient(thp, axis=0))
    gv = gfull[r0 - lo:r0 - lo + th.shape[0]]
    rr, cc = np.nonzero(m)
    aft = aft_row[rs][rr]
    x = np.where(aft, u_to_x(U4[cc], True), u_to_x(U4[cc], False))
    dudx = 1 / np.where(aft, dxdu[True][cc], dxdu[False][cc])
    t_ = th[rr, cc]
    g_ = np.maximum(gv[rr, cc], math.pi / 4000)
    cov = [coverage(k, x, t_, g_, dudx) for k in range(len(EDGES))]
    L, B2, B3, B5, DRU, DRL = cov
    col = np.ones((len(rr), 3), np.float32) * C['W']
    for c_, a_ in ((C['L'], L), (C['D'], np.clip(B2 - B3, 0, 1)), (C['W'], B3),
                   (C['R'], B5), (C['DR'], B5 * DRL * (1 - DRU))):
        col = col * (1 - a_[:, None]) + c_ * a_[:, None]
    paint[rs][rr, cc] = col
    print('rows', r0, flush=True)

# white fairing around the horizontal stabiliser roots, placed on the kit's
# own root shadow (4K: U 3307-4068, V 2330-2585 left, mirrored right)
pm = Image.new('L', (N, N), 0)
pd = ImageDraw.Draw(pm)
for side_v in (lambda v: v, lambda v: 2 * AX_A - v):
    v_a, v_b = sorted((side_v(2322), side_v(2570)))
    pd.rounded_rectangle([3382 * 2, v_a * 2, 4100 * 2, v_b * 2], radius=90, fill=255)
    v_a, v_b = sorted((side_v(2348), side_v(2544)))
    pd.rounded_rectangle([3223 * 2, v_a * 2, 3460 * 2, v_b * 2], radius=80, fill=255)
pm = np.asarray(pm.filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
# keep it on the side panel: off the crown strip and the belly strip
side_run = np.zeros((N, N), bool)
for vr0, vr1 in ((2325, 2594), (2 * AX_A - 2594, 2 * AX_A - 2325)):
    side_run[int(vr0 * 2):int(vr1 * 2) + 1, 3200 * 2:] = True
pm *= (mask8 & side_run)
paint = paint * (1 - pm[..., None]) + C['W'] * pm[..., None]
del pm, side_run


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


def put(art, u_c, v_c, tw, th_, rot180):
    a = art.convert('RGBA').resize((int(tw), int(th_)), Image.LANCZOS)
    if rot180:
        a = a.rotate(180)
    arr = np.asarray(a).astype(np.float32) / 255
    x0, y0 = int(round(u_c - a.width / 2)), int(round(v_c - a.height / 2))
    al_ = arr[..., 3:4]
    reg = paint[y0:y0 + a.height, x0:x0 + a.width]
    reg[:] = reg * (1 - al_) + arr[..., :3] * al_
    print('put', (x0, y0, a.width, a.height), 'rot' if rot180 else '')


def stamp(art, cx, cy, w, ax_v, aspect=None, top=None, bottom=None, sides='LR'):
    """Centred on photo (cx, cy) on the left side, keeping its proportions;
    mirrored onto the right side rotated 180."""
    u0, _ = to_tex(cx - w / 2, cy)
    u1, _ = to_tex(cx + w / 2, cy)
    uc, vc = to_tex(cx, cy)
    tw = u1 - u0
    th_ = tw / (aspect or art.width / art.height)
    if top is not None:
        vc = top + th_ / 2
    if bottom is not None:
        vc = bottom - th_ / 2
    if 'L' in sides:
        put(art, uc, vc, tw, th_, False)
    if 'R' in sides:
        put(art, uc, 2 * ax_v * 2 - vc, tw, th_, True)


en = E.words_layer(['Royal', 'Air', 'Maroc'], f'{FONTS}/outfit-latin-600-normal.woff', 600, G.RED)
ar_ = E.text_layer('الخطوط الملكية المغربية', f'{FONTS}/aref-ruqaa-arabic-700-normal.woff',
                   600, G.RED, direction='rtl', pad=0)
reg = E.text_layer('CN-RGO', f'{FONTS}/outfit-latin-600-normal.woff', 300, REG_BLACK, pad=0)
emb = E.text_layer('EMBRAER 190', f'{FONTS}/outfit-latin-600-normal.woff', 200, (30, 30, 30), pad=0)

# forward window row, 8K: left V 378 +/- 36, right V 1616 +/- 36 (crown side is +)
GAP8 = 30
WL_TOP8, WL_BOT8 = (378 - 36) * 2, (378 + 36) * 2
WR_CROWN8, WR_BELLY8 = (1616 + 36) * 2, (1616 - 36) * 2
# left side: Arabic above the windows, English below (photo 1)
ex, ey = G.TITLE_EN['center']
stamp(en, ex, ey, G.TITLE_EN['width'], AX_F, top=WL_BOT8 + GAP8, sides='L')
stamp(ar_, G.TITLE_AR['center'][0], 458.5, G.TITLE_AR['width'], AX_F, aspect=6.0,
      bottom=WL_TOP8 - GAP8, sides='L')
# right side: English above the windows and larger, Arabic below (photo 2);
# spans measured in windows, U in 4K units
en_w = (2750 - 1215) * 2
put(en, (1215 + 2750), WR_CROWN8 + GAP8 + en_w * en.height / en.width / 2,
    en_w, en_w * en.height / en.width, True)
ar_w = (2358 - 1294) * 2
put(ar_, (1294 + 2358), WR_BELLY8 - GAP8 - ar_w / 6.0 / 2, ar_w, ar_w / 6.0, True)

rx, ry = G.REG['center']
stamp(reg, rx, ry, G.REG['width'], AX_A)
ec = G.EMBRAER_190['center']
stamp(emb, ec[0], ec[1], G.EMBRAER_190['width'], AX_F)

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
