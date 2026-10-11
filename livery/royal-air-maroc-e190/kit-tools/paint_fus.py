"""Project the Royal Air Maroc side-profile design onto the X-Crafts E190
fuselage texture (8192 px) and multiply it over the kit's E190 base.

usage: paint_fus.py <livery tools dir> <fonts dir> <out dir>
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.interpolate import splprep, splev

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


# Near the crown the first photo (taken from below) can't be trusted, so each
# edge's top part comes from the eye-level photo of the right side: points are
# (station in photo-1 px, degrees from the crown), matched through the windows.
# Below `switch` degrees the eye-level points are used, above it photo 1.
# The first point of each is the tip on the crown: the top ~15 deg sit within a
# pixel of the outline at eye level, so it is the straight-line continuation of
# the reliable points, giving the pointed V's the design shows from above.
CROWN = {
    'B1': ([(752.0, 0), (805.8, 14.0), (831.5, 19.8), (857.2, 28.2), (882.1, 33.2), (907.1, 38.9),
            (932.4, 45.3)], 45),
    'B2': ([(955.3, 30.8), (970.6, 36.1), (983.3, 40.3)], 40),
    'B3': ([(955.3, 30.8), (970.6, 31.0), (996.1, 31.6), (1021.6, 31.6), (1046.8, 32.4),
            (1059.3, 36.1), (1072.0, 39.6), (1085.0, 42.8), (1098.0, 45.9)], 45),
    'B5': ([(1002.0, 0), (1046.8, 15.6), (1059.3, 21.0), (1072.0, 25.3), (1085.0, 30.8),
            (1098.0, 33.9), (1111.0, 38.3)], 38),
}


def edge_mixed(pts, key, after=None):
    """photo-1 edge with its crown part replaced by eye-level points"""
    base = edge(pts, after=after)
    cpts, sw = CROWN[key]
    cx = np.array([p[0] for p in cpts]); ct = np.array([p[1] for p in cpts]) * DEG
    # extend the eye-level curve to where photo 1 reaches the switch angle
    xs_sw = XG[np.argmax(base >= sw * DEG)]
    cx = np.append(cx, xs_sw); ct = np.append(ct, sw * DEG)
    order = np.argsort(cx)
    crown = np.interp(XG, cx[order], ct[order], left=0.0)
    out = np.where(XG < xs_sw, crown, base)
    out[XG < cx.min()] = 0.0
    return out


E_B1 = edge_mixed(G.B1, 'B1', after=math.pi)
E_B2 = edge_mixed(G.B2, 'B2', after=math.pi)
E_B3 = edge_mixed(G.B3, 'B3', after=math.pi)
E_B5 = edge_mixed(G.B5, 'B5')
# the dark green ends in a point below the crown: no dark green ahead of it
APEX_X = 955.3
E_B2[XG < APEX_X] = 0.0
E_B3[XG < APEX_X] = 0.0
# thin light-green sliver over the dark green's tip, white above it (eye level)
B4_PTS = [(916.0, 0), (957.8, 9.9), (970.6, 14.0), (983.3, 17.1), (996.1, 19.8),
          (1008.8, 22.2), (1021.6, 26.3), (1034.3, 29.9), (1046.8, 32.4)]
b4 = np.interp(XG, [p[0] for p in B4_PTS], [p[1] * DEG for p in B4_PTS], left=0.0, right=0.0)
E_B43 = np.where(XG <= 1046.8, b4, E_B3)
# Darker red: one feather, matched between the eye-level photo of the right
# side, the first photo (from below) and the same design on a 737. Points are
# (station in photo-1 px, degrees from the crown).
# - front tip at the pinstripe just behind its crown junction;
# - above it, bright leaf A along the crown, its tip dipping back into the dark;
# - behind leaf A's tip the dark reaches the crown, until bright leaf B, whose
#   lower edge sweeps down to the back tip over the rear door, at window level;
# - its lower edge follows the pinstripe to the wing, then runs just below the
#   windows with bright red between it and the pinstripe.
DR_FRONT, DR_BACK = 1086.0, 1480.0
LA_BOT = [(1086, 29.5), (1090, 29.2), (1111, 27.4), (1131, 27.2), (1151, 25.3), (1172, 25.4),
          (1192, 27.4), (1212, 27.5), (1233, 29.4), (1253, 31.2), (1274, 34.4), (1294, 36.0),
          (1306, 35.5)]
# Leaf A's top: up to the crown at the front. From station 1159 the dark red
# from both sides meets along the crown in one slender forward-pointing V
# (the eye-level E190 photo's top edge darkens from here; the 737 shows the V
# from above), its sides becoming leaf A's top edge as measured further back.
LA_TOP = [(1086, 0.0), (1159, 0.0), (1195, 9.0), (1233, 18.7), (1253, 23.6), (1274, 27.7),
          (1294, 31.3), (1306, 35.5)]
LB_BOT = [(1306, 0.0), (1335, 0.0), (1344, 21.0), (1365, 29.5), (1385, 34.5), (1405, 40.5),
          (1426, 46.5), (1446, 52.5), (1462, 58.5), (1480, 66.0)]
DR_LOW = [(1290, 76.5), (1320, 76.4), (1360, 76.1), (1400, 74.6), (1430, 72.0), (1460, 69.6),
          (1480, 66.0)]


def curve(pts, lo, hi, outside):
    v = np.interp(XG, [q[0] for q in pts], [q[1] * DEG for q in pts])
    return np.where((XG >= lo) & (XG <= hi), v, outside)


E_LAB = curve(LA_BOT, DR_FRONT, 1306, 0.0)
E_LAT = curve(LA_TOP, DR_FRONT, 1306, 0.0)
E_DUP = np.where(XG < 1306, 0.0, curve(LB_BOT, 1306, DR_BACK, math.pi))
low = np.where(XG < 1290, math.pi, np.interp(XG, [q[0] for q in DR_LOW], [q[1] * DEG for q in DR_LOW]))
E_DLO = np.where((XG >= DR_FRONT) & (XG <= DR_BACK), np.minimum(E_B5, low), 0.0)
def smooth_edge(E, rms_px=2.0, px_per_deg=1.5):
    """Turn one colour edge theta(x) into a single smooth curve. Wherever it
    lies strictly between the crown and the belly, a parametric smoothing
    spline is fitted through it in surface units (photo px along the
    fuselage, ~1.5 px per degree around it) with its two ends pinned, so the
    measured points are followed to within ~rms_px while kinks between them
    and measurement wobble go; tips and belly crossings stay sharp."""
    act = (E > 0.2 * DEG) & (E < math.pi - 0.2 * DEG)
    idx = np.nonzero(act)[0]
    out = E.copy()
    for run in np.split(idx, np.nonzero(np.diff(idx) > 1)[0] + 1):
        if len(run) < 60:
            continue
        sub = run[::8]
        if sub[-1] != run[-1]:
            sub = np.append(sub, run[-1])
        x, y = XG[sub], E[sub] / DEG * px_per_deg
        w = np.ones(len(sub)); w[[0, -1]] = 50.0
        tck, _ = splprep([x, y], w=w, s=len(sub) * rms_px ** 2)
        xs, ys = splev(np.linspace(0, 1, len(run) * 2), tck)
        order = np.argsort(xs)
        out[run] = np.clip(np.interp(XG[run], xs[order], ys[order]) / px_per_deg * DEG,
                           0.0, math.pi)
    return out


_raw = dict(B1=E_B1, B2=E_B2, B3=E_B3, B5=E_B5, B43=E_B43, DUP=E_DUP, DLO=E_DLO,
            LAT=E_LAT, LAB=E_LAB)
E_B1, E_B2, E_B3, E_B5, E_B43 = (smooth_edge(e) for e in (E_B1, E_B2, E_B3, E_B5, E_B43))
E_DUP, E_DLO, E_LAT, E_LAB = (smooth_edge(e) for e in (E_DUP, E_DLO, E_LAT, E_LAB))
for k, e in zip(_raw, (E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB)):
    print(f'smoothed {k}: max change {np.degrees(np.abs(e - _raw[k]).max()):.1f} deg', flush=True)


EDGES = [E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB]
# slopes for edge anti-aliasing; capped so the cut-offs where a shape ends
# (a jump in the curve) stay sharp instead of leaving a faint line
DEDGES = [np.clip(np.gradient(e, XG), -0.25, 0.25) for e in EDGES]

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
    L, B2, B3, B5, B43, DUP, DLO, LAT, LAB = cov
    leaf_a = LAB * (1 - LAT)
    dark = B5 * DLO * (1 - DUP) * (1 - leaf_a)
    col = np.ones((len(rr), 3), np.float32) * C['W']
    for c_, a_ in ((C['L'], L), (C['D'], np.clip(B2 - B3, 0, 1)), (C['W'], B43),
                   (C['R'], B5), (C['DR'], dark)):
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
    if aft and U >= BLEND_U[0]:
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
# the airline's own Arabic logotype, traced from the photo (kit-tools/trace_ar.py)
ar_ = Image.open(f'{FONTS}/../artwork/ram_title_ar_logotype.png').convert('RGBA')
reg = E.text_layer('CN-RGO', f'{FONTS}/outfit-latin-600-normal.woff', 300, REG_BLACK, pad=0)
emb = E.text_layer('EMBRAER 190', f'{FONTS}/outfit-latin-600-normal.woff', 200, (30, 30, 30), pad=0)

# forward window row, 8K: left V 378 +/- 36, right V 1616 +/- 36 (crown side is +)
GAP8 = 30
WL_TOP8, WL_BOT8 = (378 - 36) * 2, (378 + 36) * 2
WR_CROWN8, WR_BELLY8 = (1616 + 36) * 2, (1616 - 36) * 2
# left side (photo 1): Arabic above the windows, English below
ex, ey = G.TITLE_EN['center']
stamp(en, ex, ey, G.TITLE_EN['width'], AX_F, top=WL_BOT8 + GAP8, sides='L')
stamp(ar_, G.TITLE_AR['center'][0], 458.5, G.TITLE_AR['width'], AX_F,
      bottom=WL_TOP8 - 25, sides='L')
# right side (eye-level photo of the right side, spans measured against its
# windows; U in 4K units): English above the windows, a smaller Arabic below
en_u0, en_u1 = 1457, 2934
en_w = (en_u1 - en_u0) * 2
en_h = en_w * en.height / en.width
put(en, en_u0 + en_u1, WR_CROWN8 + 15 + en_h / 2, en_w, en_h, True)
ar_u0, ar_u1 = 1457, 2525
ar_w = (ar_u1 - ar_u0) * 2
ar_h = ar_w * ar_.height / ar_.width
put(ar_, ar_u0 + ar_u1, WR_BELLY8 - 65 - ar_h / 2, ar_w, ar_h, True)

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
