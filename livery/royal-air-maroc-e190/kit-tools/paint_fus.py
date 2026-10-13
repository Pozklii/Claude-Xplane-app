"""Project the Royal Air Maroc side-profile design onto the X-Crafts E190
fuselage texture (8192 px) and multiply it over the kit's E190 base.

usage: paint_fus.py <livery tools dir> <fonts dir> <out dir>
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
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


# Photo 1 was taken from about 8.6 deg below the aircraft. Each station is
# modelled as a circle seen from there: y = c - R cos(theta - 8.6 deg), with
# c and R set by the bottom outline and the cabin windows (68 deg), and around
# the rear door by the door itself (41 / 124 deg in the mesh). This lands the
# windows, overwing exit and rear door on their mesh angles to within ~2 deg;
# the earlier window-pinned stretch put the lower stripes up to 23 deg high.
CAM_BELOW = 8.6
_CW = math.cos(math.radians(68.2 - CAM_BELOW))
_DOOR_C, _DOOR_R = 582.3, 78.6


def _cR(x):
    x = np.asarray(x, float)
    b = belly_p(x)
    R_w = (b - axis_p(x)) / (1 + _CW)
    b14 = belly_p(1420.0); R14 = (b14 - axis_p(1420.0)) / (1 + _CW); c14 = b14 - R14
    w1 = np.clip((x - 1420) / 56, 0, 1)
    R_door = R14 + w1 * (_DOOR_R - R14)
    c_door = c14 + w1 * (_DOOR_C - c14)
    R_aft = (b - crown_p(x)) / 2
    w2 = np.clip((x - 1476) / 84, 0, 1)
    R_tail = _DOOR_R + w2 * (R_aft - _DOOR_R)
    R = np.where(x <= 1420, R_w, np.where(x <= 1476, R_door, R_tail))
    c = np.where(x <= 1420, b - R_w, np.where(x <= 1476, c_door, b - R_tail))
    return c, R


def theta_of(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    c, R = _cR(x)
    th = np.arccos(np.clip((c - y) / R, -1, 1)) + CAM_BELOW * DEG
    return np.clip(th, 0, math.pi)


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
E_B5 = edge_mixed(G.B5, 'B5', after=math.pi)   # red wraps the tail cone to the APU
# Behind the rear door the red's lower edge runs straight back in side view
# and the belly sweeps up into it at ~1738 (both photos). Photo 1 is taken
# from below the tail and sees more of the underside there than its
# door-fitted camera allows for, which put the edge too high; at eye level
# (photo 4, sections through the rear door and the APU nozzle) it sits
# 5-12 deg lower. These angles take the middle of the two, nearer the
# eye-level photo, joining the photo-1 edge at the door.
B5_AFT = [(1490, 118.2), (1520, 125.0), (1549, 131.0), (1580, 136.0), (1614, 141.0),
          (1650, 147.0), (1678, 154.0), (1711, 165.0), (1738, 180.0)]
_sel = XG >= B5_AFT[0][0]
E_B5[_sel] = np.interp(XG[_sel], [q[0] for q in B5_AFT], [q[1] * DEG for q in B5_AFT],
                       right=math.pi)
# Belly line: the green stops above a white belly (first E190 photo; the same
# scheme from under a 737). Traced off the photo like the other edges; the
# dark green runs out to a point where it meets the pinstripe at ~1555.
BL_PTS = [(1340, 659), (1360, 663), (1380, 661), (1400, 661), (1420, 658), (1440, 655),
          (1460, 653), (1480, 649), (1500, 645), (1520, 642), (1540, 638), (1556, 636)]
_bx = np.array([q[0] for q in BL_PTS], float)
_bt = theta_of(_bx, np.array([q[1] for q in BL_PTS], float))
E_BL = np.interp(XG, _bx, _bt, left=_bt[0], right=0.0)
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
#   lower edge leaves the crown gently and steepens a little towards the
#   rear door; inside the door the dark red narrows to a level spike, the
#   lower edge rising slightly to meet it;
# - its lower edge follows the pinstripe to the wing, then runs straight just
#   below the windows, with bright red between it and the pinstripe.
# Behind the wing both edges are traced off both photos: the first through
# its camera model, fitted to the left rear door (38.6-124.7 deg in the mesh),
# the eye-level one through its window row and crown line. Each photo's
# angles are weighted by how sharply it resolves them there (its px per deg,
# squared): near the crown the photo from below sees almost nothing, while
# towards the door the two agree to a few degrees.
DR_FRONT, DR_BACK = 1086.0, 1490.0
LA_BOT = [(1086, 29.5), (1090, 29.2), (1111, 27.4), (1131, 27.2), (1151, 25.3), (1172, 25.4),
          (1192, 27.4), (1212, 27.5), (1233, 29.4), (1253, 31.2), (1274, 34.4), (1294, 36.0),
          (1306, 35.5)]
# Leaf A's top: up to the crown at the front. From station 1159 the dark red
# from both sides meets along the crown in one slender forward-pointing V
# (the eye-level E190 photo's top edge darkens from here; the 737 shows the V
# from above), its sides becoming leaf A's top edge as measured further back.
LA_TOP = [(1086, 0.0), (1159, 0.0), (1195, 9.0), (1233, 18.7), (1253, 23.6), (1274, 27.7),
          (1294, 31.3), (1306, 35.5)]
LB_BOT = [(1306, 0.0), (1322, 0.0), (1332, 8.0), (1343, 15.5), (1356, 21.5), (1370, 27.5),
          (1380, 31.5), (1390, 34.8), (1400, 38.2), (1410, 41.2), (1420, 44.0), (1430, 48.6),
          (1440, 54.0), (1450, 59.0), (1456, 62.8), (1462, 67.0), (1467, 70.0), (1472, 72.4),
          (1477, 74.3), (1481, 75.5)]
DR_LOW = [(1290, 76.5), (1320, 76.5), (1360, 76.3), (1400, 75.8), (1430, 76.2), (1450, 77.0),
          (1462, 77.8), (1470, 77.6), (1476, 76.8), (1481, 75.5)]


def _to_door(pts):
    """Behind the last window the texture's station map (anchored on the
    windows and the tail) puts the rear door ~10 px further back than the
    photo shows it (frame at 1457-1497 at window height, against 1467-1505
    in the map), so points there are moved with the door: the tip stays
    halfway into it and the top edge meets its front frame a quarter down."""
    out = []
    for x, t in pts:
        d = 9.7 * min(max((x - 1420) / 37, 0), 1) - 1.7 * min(max((x - 1457) / 40, 0), 1)
        out.append((x + d, t))
    return out


LB_BOT, DR_LOW = _to_door(LB_BOT), _to_door(DR_LOW)


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
            LAT=E_LAT, LAB=E_LAB, BL=E_BL)
E_B1, E_B2, E_B3, E_B5, E_B43 = (smooth_edge(e) for e in (E_B1, E_B2, E_B3, E_B5, E_B43))
# the dark red's back edges are traced point by point already; smoothing them
# as hard as the photo traces would iron out the turn into the tip
E_DUP, E_DLO = (smooth_edge(e, rms_px=0.5) for e in (E_DUP, E_DLO))
E_LAT, E_LAB, E_BL = (smooth_edge(e) for e in (E_LAT, E_LAB, E_BL))
for k, e in zip(_raw, (E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB, E_BL)):
    print(f'smoothed {k}: max change {np.degrees(np.abs(e - _raw[k]).max()):.1f} deg', flush=True)


EDGES = [E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB, E_BL]
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
    L, B2, B3, B5, B43, DUP, DLO, LAT, LAB, BL = cov
    leaf_a = LAB * (1 - LAT)
    dark = B5 * DLO * (1 - DUP) * (1 - leaf_a)
    col = np.ones((len(rr), 3), np.float32) * C['W']
    for c_, a_ in ((C['L'], L * BL), (C['D'], np.clip(B2 - B3, 0, 1) * BL), (C['W'], B43),
                   (C['R'], B5), (C['DR'], dark)):
        col = col * (1 - a_[:, None]) + c_ * a_[:, None]
    paint[rs][rr, cc] = col
    print('rows', r0, flush=True)

# White fairing round each horizontal stabiliser root: a vase on its side,
# neck forward, wrapped round the root. Its outline is set against the
# stabiliser's root line, so the tail runs along the root above and below
# it. The root line is the centre of the kit's own root shadow (72.7 deg
# from the crown at station 1666, falling to 86 deg at 1781). Distances from
# it come from the first photo, measured from the root line as that photo
# shows it (its camera model puts the root ~12 deg lower and falling faster,
# which had dropped the tail under the stabiliser); the eye-level photo of
# the other side gives the same proportions:
# - neck, station 1638 to 1671: 20 deg above the root, 30 below;
# - shoulders stepping out to a body 47 above and 43 below;
# - the tail tapering along the root to a rounded tip at 1775, about 12 deg
#   above it (the stabiliser's own thickness) and 25 to 17 deg below.
def root_theta(x):
    return (72.7 + 0.1165 * (np.asarray(x, float) - 1666.0)) * DEG


VASE_REL = [  # (station, deg from the root line; + is below it)
    (1638, -15.0), (1638.8, -18.4), (1641.5, -19.6), (1655, -19.6), (1668, -19.6),
    (1671, -21.0), (1673.5, -27.0), (1676, -36.0), (1678.5, -43.0), (1681.5, -46.5),
    (1690, -47.5), (1696, -47.0), (1701, -43.8), (1706, -38.4), (1712, -33.0),
    (1718, -25.0), (1723, -18.0), (1730, -14.5), (1740, -13.0), (1750, -12.0),
    (1760, -11.0), (1767, -10.0), (1771, -8.0), (1773.6, -4.0), (1775.2, 0.5),
    (1775.6, 5.0), (1774.6, 10.0), (1772, 14.0), (1768, 16.6), (1760, 19.1),
    (1750, 21.4), (1740, 24.7), (1730, 28.5), (1720, 33.0), (1710, 37.6),
    (1700, 41.5), (1690, 43.0), (1681, 42.5), (1677.6, 41.0), (1675, 38.0),
    (1673, 34.0), (1670, 30.5), (1660, 30.0), (1650, 29.6), (1641, 29.2),
    (1638.8, 27.6), (1638, 24.0)]
_vx = np.array([q[0] for q in VASE_REL], float)
_vt = root_theta(_vx) + np.array([q[1] for q in VASE_REL]) * DEG
# rasterise it in the (station, angle) plane: 20 samples per photo px and
# per degree, smoothed through the points, edges softened to about a texel
VX0, VS = 1620.0, 20.0
_poly = G.catmull_rom(list(zip(_vx, _vt / DEG)) + [(_vx[0], _vt[0] / DEG)], 12)
_ras = Image.new('L', (int(180 * VS), int(180 * VS)), 0)
ImageDraw.Draw(_ras).polygon([((px_ - VX0) * VS, pt_ * VS) for px_, pt_ in _poly], fill=255)
_ras = np.asarray(_ras.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255
_c0, _c1 = int(x_to_u(VX0, True) * 2), int(x_to_u(VX0 + 180, True) * 2) + 1
_rows = np.nonzero(aft_row)[0]
_r0, _r1 = _rows.min(), _rows.max() + 1
_th = theta[_r0:_r1, _c0:_c1]
_xx = u_to_x(U8[_c0:_c1] / 2, True)[None, :].repeat(_r1 - _r0, 0)
_ok = mask8[_r0:_r1, _c0:_c1] & np.isfinite(_th)
_cov = np.zeros(_th.shape, np.float32)
_cov[_ok] = ndimage.map_coordinates(
    _ras, [np.degrees(_th[_ok]) * VS, (_xx[_ok] - VX0) * VS], order=1, mode='constant')
_blk = paint[_r0:_r1, _c0:_c1]
_blk[:] = _blk * (1 - _cov[..., None]) + C['W'] * _cov[..., None]
print('stabiliser fairings:', int((_cov > 0.5).sum()), 'texels')
del _ras, _th, _xx, _ok, _cov


# ---- titles, registration, flag: placed undistorted in texture space ------
def to_tex(x, y):
    """Left-side photo point -> 8K texture (u, v)."""
    aft = x > 1028
    U = x_to_u(x, aft)
    if x > 1100:
        th = float(theta_of(x, y))
    else:
        th = t_unwarp((y - G.crown(x)) / (G.belly(x) - G.crown(x)), x)
    if aft and U >= 1890:
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


# The texture isn't square on the skin: per metre it holds a little fewer
# texels round the fuselage than along it. Measured on the two doors, whose
# outlines the kit bakes in at their true shape, against photo 1 (its camera
# model puts both doors on their mesh angles; its length is foreshortened to
# 0.935 of the height, from the E190's 36.24 m by 3.35 m):
#   L1 door  45 x 103 px, 81 deg of girth -> 0.375 wide on the skin;
#            187 x 450 texels -> 0.416: ratio 0.90
#   aft door 42 x  99 px, 83 deg of girth -> 0.394; 160 x 400 texels -> 0.400:
#            ratio 0.985
# (the barrel from the jet's dimensions alone: 0.92). The marks are sized on
# the skin with this ratio so they keep their real proportions.
SKIN_X, SKIN_K = (304.5, 1477.0), (0.90, 0.985)


def skin_ratio(cx, cy):
    """Texels per metre round the fuselage over texels per metre along it,
    at a left-side photo point."""
    return float(np.interp(cx, SKIN_X, SKIN_K))


def stamp(art, cx, cy, w, ax_v, aspect=None, top=None, bottom=None, sides='LR', skin=False,
          tw8=None):
    """Centred on photo (cx, cy) on the left side, keeping its proportions
    (on the skin with skin=True, else in texels); mirrored onto the right
    side rotated 180. tw8 sets the width in 8K texels instead of w."""
    u0, _ = to_tex(cx - w / 2, cy)
    u1, _ = to_tex(cx + w / 2, cy)
    uc, vc = to_tex(cx, cy)
    tw = tw8 if tw8 is not None else u1 - u0
    th_ = tw / (aspect or art.width / art.height)
    if skin:
        k = skin_ratio(cx, cy)
        th_ *= k
        print(f'skin ratio at ({cx:.0f}, {cy:.0f}): {k:.3f}')
    if top is not None:
        vc = top + th_ / 2
    if bottom is not None:
        vc = bottom - th_ / 2
    if 'L' in sides:
        put(art, uc, vc, tw, th_, False)
    if 'R' in sides:
        put(art, uc, 2 * ax_v * 2 - vc, tw, th_, True)
    return tw, th_


en = E.words_layer(['Royal', 'Air', 'Maroc'], f'{FONTS}/outfit-latin-600-normal.woff', 600, G.RED)
# the airline's own Arabic logotype, traced from the photo (kit-tools/trace_ar.py)
ar_ = Image.open(f'{FONTS}/../artwork/ram_title_ar_logotype.png').convert('RGBA')


def reg_layer(text, font_path, px, fill, tracking=0.03, dash=0.40, ss=4):
    """Registration as painted on the jet: a DIN-like face, slightly letter-
    spaced, with a long thin dash about a letter wide. Cropped to the ink."""
    font = ImageFont.truetype(font_path, px * ss)
    probe = ImageDraw.Draw(Image.new('L', (1, 1)))
    _, cap_top, _, base = probe.textbbox((0, 0), 'H', font=font)
    bar = 0.12 * (base - cap_top)
    W = int(sum(font.getlength(c) for c in text) + len(text) * (tracking + dash) * px * ss) + 4 * px
    img = Image.new('L', (W, int(px * ss * 1.6)), 0)
    d = ImageDraw.Draw(img)
    x = px * ss * 0.2
    for i, ch in enumerate(text):
        if ch == '-':
            mid = (cap_top + base) / 2
            d.rectangle([x, mid - bar / 2, x + dash * px * ss, mid + bar / 2], fill=255)
            x += dash * px * ss
        else:
            bb = probe.textbbox((0, 0), ch, font=font)
            d.text((x - bb[0], 0), ch, font=font, fill=255)
            x += bb[2] - bb[0]
        if i < len(text) - 1:
            x += tracking * px * ss
    ys, xs = np.nonzero(np.asarray(img) > 8)
    img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    img = img.resize((img.width // ss, img.height // ss), Image.LANCZOS)
    out = Image.new('RGBA', img.size, tuple(fill) + (0,))
    out.putalpha(img)
    return out


reg = reg_layer('CN-RGO', f'{FONTS}/barlow-latin-500-normal.woff', 300, REG_BLACK)
print('registration natural aspect %.2f' % (reg.width / reg.height))
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
stamp(reg, rx, ry, G.REG['width'], AX_A, aspect=4.9, skin=True)   # 4.9:1 on the jet
# The small marks by the nose are sized against the forward doors, which the
# kit draws at their true size: near the nose the photos' scale along the
# fuselage doesn't match the window-anchored station map. Flag and text are
# the same size on both sides, so the two photos are averaged:
#   "EMBRAER 190": 0.94 of the L1 door's width (photo 1), 1.0 of the
#     smaller R1 door's (eye-level photo) -> 175 / 156 -> 165 4K texels;
#   flag: 0.50 of L1, 0.53 of R1 -> 94 / 83 -> 88 4K texels.
L1_W, R1_W = 187.0, 156.0          # 4K texels, frame outer
EMB_W8 = 2 * (0.94 * L1_W + 1.00 * R1_W) / 2
FLAG_W8 = 2 * (0.50 * L1_W + 0.53 * R1_W) / 2
ec = G.EMBRAER_190['center']
stamp(emb, ec[0], ec[1], G.EMBRAER_190['width'], AX_F, skin=True, tw8=EMB_W8)

# Moroccan flag: red field, green interlaced star
fw = 600
flag = Image.new('RGBA', (fw, int(fw * 2 / 3)), (193, 39, 45, 255))
star = E.woven_star(flag.size, fw / 2, flag.height / 2 + 6, flag.height * 0.36,
                    flag.height * 0.36 * 0.14, flag.height * 0.36 * 0.04)
flag.paste(Image.new('RGBA', flag.size, (0, 98, 51, 255)), mask=star)
fx0, fy0, fx1, fy1 = G.FLAG
fw8, fh8 = stamp(flag, (fx0 + fx1) / 2, (fy0 + fy1) / 2, fx1 - fx0, AX_F, sides='L', skin=True,
                 tw8=FLAG_W8)  # 3:2 on the jet
# Right side: not a mirror of the left. There the flag sits just ahead of the
# smaller service door (4K: U 803-959, top edge V 1709.5), level with its top
# and a third of a door width in front of it (eye-level photo of that side).
R1_FWD, R1_TOP = 803.0, 1709.5
put(flag, 2 * (R1_FWD - 0.32 * R1_W) - fw8 / 2, 2 * R1_TOP - fh8 / 2, fw8, fh8, True)

# oneworld emblem, left side only: a blue disc with the white globe and
# wordmark, between the L1 door and the first window (first photo: 15 px
# across, centred 0.35 of the way from the door's rear frame to the first
# window's centre and 6 px above it; the eye-level photo of the right side
# shows none there). Kit: door rear frame U 1086, first window U 1323.
OW_U8, OW_V8 = 2 * (1086 + 0.348 * (1323 - 1086)), 722.0
OW_W8 = 2 * 64.0
OW_H8 = OW_W8 * skin_ratio(360.4, 462.3)
ss = 8
ow = Image.new('RGBA', (512 * ss // 4, 512 * ss // 4), (0, 0, 0, 0))
od = ImageDraw.Draw(ow)
R0 = ow.width / 2
od.ellipse([0, 0, ow.width - 1, ow.height - 1], fill=(28, 88, 178, 255))
ftxt = ImageFont.truetype(f'{FONTS}/outfit-latin-600-normal.woff', int(ow.width * 0.15))
tb = od.textbbox((0, 0), 'oneworld', font=ftxt)
gl = int(ow.width * 0.11)                          # globe diameter
gap = int(ow.width * 0.025)
tot = gl + gap + (tb[2] - tb[0])
x0 = (ow.width - tot) / 2
cy_ = R0
lw = max(2, int(gl * 0.12))
od.ellipse([x0, cy_ - gl / 2, x0 + gl, cy_ + gl / 2], outline=(255, 255, 255, 255), width=lw)
od.arc([x0 - gl * 0.15, cy_ - gl * 0.28, x0 + gl * 1.15, cy_ + gl * 0.28], 200, 340,
       fill=(255, 255, 255, 255), width=lw)
od.text((x0 + gl + gap - tb[0], cy_ - (tb[1] + tb[3]) / 2), 'oneworld', font=ftxt,
        fill=(255, 255, 255, 255))
ow = ow.resize((512, 512), Image.LANCZOS)
put(ow, OW_U8, OW_V8, OW_W8, OW_H8, False)

paint[~mask8] = 1.0
# Seam padding: carry each painted strip's colour up to 12 (4K) texels out
# into the gutter around it, so texture filtering and mipmaps in the sim
# blend in the strip's own colour at its edges. The kit pads its islands with
# 3 texels of opaque white and leaves the rest of the gutter transparent
# white, which showed as pale lines along the tail-cone seams. Only texels
# off the mesh (outside the wireframe's islands) that are transparent, or
# white and within 4 texels, are filled: other parts packed into the gutters
# and details inside the islands are left alone.
_in4 = mask8[::2, ::2]
_dist, (_iy, _ix) = ndimage.distance_transform_edt(~_in4, return_indices=True)
_base4 = np.asarray(Image.open('layers/fus_base_e190.png'))
_off = np.asarray(Image.open('layers/fus__WIREFRAME_E190.png'))[..., 3] == 0
_white = _base4[..., :3].min(2) >= 240
_gutter = (_base4[..., 3] < 8) | (_white & (_dist <= 4))
_gv, _gu = np.nonzero(~_in4 & _off & _gutter & (_dist <= 12))
_sv, _su = 2 * _iy[_gv, _gu], 2 * _ix[_gv, _gu]
for _dy in (0, 1):
    for _dx in (0, 1):
        paint[2 * _gv + _dy, 2 * _gu + _dx] = paint[_sv + _dy, _su + _dx]
print('seam padding:', len(_gv), '4K texels')
del _dist, _iy, _ix, _base4
np.save(f'{OUT}/fus_paint8.npy', paint.astype(np.float16))
Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(f'{OUT}/fus_paint8.png')
print('done')
