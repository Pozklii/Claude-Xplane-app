"""Project the Royal Air Maroc side-profile design onto the X-Crafts E190
fuselage texture (8192 px) and multiply it over the kit's E190 base.

usage: paint_fus.py <livery tools dir> <fonts dir> <out dir>
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage
from scipy.interpolate import PchipInterpolator, UnivariateSpline, splprep, splev
from scipy.optimize import curve_fit

sys.path.insert(0, sys.argv[1])
import geometry as G
import elements as E

FONTS, OUT = sys.argv[2], sys.argv[3]
KITART = 'kitart'                 # kit-tools/kitart.py output (kit artwork)
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
# (station in photo-1 px, degrees from the crown).
# Below `switch` degrees the eye-level points are used, above it photo 1.
# The first point of each is the tip on the crown: the top ~15 deg sit within a
# pixel of the outline at eye level, so it is the straight-line continuation of
# the reliable points, giving the pointed V's the design shows from above.
# Eye-level photo, re-measured: its stations now come from its own window row
# (station = 1998.57 - 1.2690 x, within ~1 px of every window centre; the
# earlier straight scale ran 13-25 px short ahead of the wing), and its
# angles from a level camera fitted to the windows (68.25 deg in the mesh)
# and the fuselage depth, h = A (1 - cos(theta - 0.65 deg)) below the top
# outline with A from the window row. The earlier camera, 5 deg above, put
# the windows at 61 deg and every edge near the crown 4-8 deg too high; on
# the steep edges the short stations had cancelled that, on the near-level
# ones (the dark green's and dark red's tops) they had not.
CROWN = {
    'B1': ([(752.0, 0), (805.8, 14.0), (831.5, 19.8), (857.2, 28.2), (882.1, 33.2), (907.1, 38.9),
            (932.4, 45.3)], 45),
    # The dark green ends in a point at ~937 (eye level; the first photo's
    # trace starts at 938), its top edge running on nearly level from there
    # (29.5 deg at the point, 34 where the white stripe closes over it at
    # ~1040), its lower edge curling up into the point.
    'B2': ([(937.0, 29.5), (942.8, 32.1), (947.5, 33.0), (952.6, 34.4), (957.5, 35.7),
            (962.4, 36.8), (967.5, 38.3), (972.6, 39.7), (977.5, 40.7), (982.4, 41.7)], 40),
    'B3': ([(937.0, 29.5), (943.0, 30.1), (953.0, 30.6), (963.0, 31.3), (973.0, 31.6),
            (983.0, 32.6), (993.0, 32.9), (1003.0, 33.3), (1013.0, 33.5), (1023.0, 33.6),
            (1033.0, 33.8)], 45),
    'B5': ([(1002.0, 0), (1046.8, 15.6), (1059.3, 21.0), (1072.0, 25.3), (1085.0, 30.8),
            (1098.0, 33.9), (1111.0, 38.3)], 38),
}
# The white stripe's edges at eye level, behind the dark green's point: the
# lower edge (over the dark green) to where the windows meet it, the upper
# (under the red) to the wing tip, which hides 1250-1345 at the crown. The
# first photo can't see either between ~1140 and ~1300 (the wing is in
# front), where they had been carried across 3-8 deg too high; where it can
# see them again (its own camera, column by column) it agrees with the
# eye-level photo to ~1.5 deg.
STRIPE_LO = [(1042.5, 34.1), (1052.5, 36.7), (1062.5, 39.3), (1072.5, 42.1), (1082.5, 44.8),
             (1092.5, 47.2), (1102.5, 49.6), (1112.5, 52.2), (1122.5, 55.2), (1132.5, 57.6),
             (1142.5, 59.9), (1152.5, 62.1), (1162.6, 64.7), (1172.5, 66.7), (1197.5, 72.5),
             (1207.5, 74.5), (1218.9, 77.2), (1227.3, 78.9)]
STRIPE_HI = [(1032.5, 14.1), (1042.5, 19.1), (1052.5, 22.4), (1062.5, 26.1), (1072.5, 29.6),
             (1082.5, 32.8), (1092.5, 35.9), (1102.5, 39.0), (1112.5, 42.3), (1122.5, 45.0),
             (1132.5, 47.6), (1142.5, 50.5), (1152.5, 53.3), (1162.6, 55.9), (1172.5, 58.5),
             (1182.6, 61.1), (1192.4, 63.5), (1202.6, 65.7), (1228.4, 71.5), (1237.5, 73.5),
             (1242.6, 74.5), (1300.0, 84.1)]
STRIPE_HI_P1 = [(1310, 84.0), (1320, 85.7), (1330, 87.3), (1340, 88.6), (1350, 89.9), (1360, 91.6),
                (1370, 93.3), (1390, 96.1), (1400, 97.9), (1410, 99.5)]


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
APEX_X = CROWN['B2'][0][0][0]
E_B2[XG < APEX_X] = 0.0
E_B3[XG < APEX_X] = 0.0
# thin light-green sliver over the dark green's tip, white above it (eye level)
B4_PTS = [(919.0, 0), (954.2, 10.2), (962.4, 14.0), (967.5, 15.0), (972.6, 15.9), (977.5, 16.7),
          (982.4, 17.9), (987.5, 19.7), (992.6, 21.3), (997.5, 22.3), (1002.4, 23.3),
          (1007.5, 24.7), (1012.6, 26.1), (1017.5, 27.5), (1022.4, 29.1), (1027.5, 30.1),
          (1032.5, 31.7), (1035.6, 32.6)]
b4 = np.interp(XG, [p[0] for p in B4_PTS], [p[1] * DEG for p in B4_PTS], left=0.0, right=0.0)
E_B43 = np.where(XG <= B4_PTS[-1][0], b4, E_B3)
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
# Re-measured on the eye-level photo through its window-fitted camera (see
# CROWN), directly against the crown line, column by column:
# - the feather begins as a sliver on top of the white stripe at ~1046 and
#   opens from ~1075, where leaf A's lower edge leaves the stripe at ~30 deg;
# - leaf A's lower edge then runs nearly level, 26.5-30 deg (highest at
#   ~1145), on the line of the dark green's top edge ahead of the stripe
#   (29.5-34 deg): the two dark shades' upper edges line up across the white;
# - from ~1190 the dark V on the crown is clearly deeper than the photo's
#   1-2 px sharpening rim along the outline (the same rim lines every white
#   edge), its lower edge leaf A's top, meeting the lower edge in leaf A's
#   tip at ~1308, 40 deg;
# - the wing tip hides 1250-1345 at the crown; behind it leaf B's lower edge
#   is already 29 deg down at 1348 and runs ~6 deg below the earlier trace,
#   meeting it again by ~1450.
# These stations are the texture's own (from the eye-level window row), so
# unlike the first photo's points they need no shift to the rear door.
DR_FRONT, DR_BACK = 1046.0, 1490.0
LA_TIP = 1308.0
LA_BOT = [(1046, 20.3), (1055, 23.0), (1064, 25.8), (1072, 28.2), (1080, 29.8), (1088, 30.4),
          (1094, 30.0), (1100, 29.2), (1110, 28.4), (1120, 27.6), (1130, 27.2), (1140, 26.6),
          (1150, 26.6), (1160, 26.9), (1170, 27.2), (1180, 27.9), (1190, 28.6), (1200, 29.2),
          (1210, 30.3), (1220, 31.3), (1230, 32.4), (1240, 33.6), (1250, 34.3), (1260, 35.4),
          (1270, 36.6), (1280, 37.9), (1290, 38.8), (1298, 39.6), (1304, 40.0), (LA_TIP, 40.1)]
# Leaf A's top: up to the crown at the front. From station ~1155 the dark red
# from both sides meets along the crown in one forward-pointing V (the 737
# shows it from above), its sides becoming leaf A's top edge further back.
LA_TOP = [(1046, 0.0), (1155, 0.0), (1175, 9.0), (1190, 14.5), (1200, 17.3), (1210, 19.3),
          (1220, 21.6), (1230, 22.9), (1240, 25.0), (1250, 26.9), (1260, 28.4), (1270, 30.8),
          (1280, 32.9), (1290, 35.0), (1298, 37.0), (1304, 38.8), (LA_TIP, 40.1)]
LB_BOT = [(LA_TIP, 0.0), (1316, 0.0), (1322, 6.5), (1328, 13.0), (1334, 19.0), (1340, 24.0),
          (1347.6, 29.1), (1357.4, 31.8), (1367.6, 34.3), (1377.4, 37.6), (1387.5, 40.3),
          (1397.4, 42.8), (1407.5, 45.9), (1417.5, 48.9), (1427.5, 51.9), (1437.5, 54.2),
          (1442.4, 55.8)]
LB_DOOR = [(1450, 59.0), (1456, 62.8), (1462, 67.0), (1467, 70.0), (1472, 72.4), (1477, 74.3),
           (1481, 75.5)]                     # first photo, into the rear door
# the line below the windows, carried forward to where the (lower) stripe
# reaches it
DR_LOW = [(1200, 76.5), (1290, 76.5), (1320, 76.5), (1360, 76.3), (1400, 75.8), (1430, 76.2),
          (1450, 77.0), (1462, 77.8), (1470, 77.6), (1476, 76.8), (1481, 75.5)]


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


LB_BOT, DR_LOW = LB_BOT + _to_door(LB_DOOR), _to_door(DR_LOW)


def curve(pts, lo, hi, outside):
    v = np.interp(XG, [q[0] for q in pts], [q[1] * DEG for q in pts])
    return np.where((XG >= lo) & (XG <= hi), v, outside)


E_LAB = curve(LA_BOT, DR_FRONT, LA_TIP, 0.0)
E_LAT = curve(LA_TOP, DR_FRONT, LA_TIP, 0.0)
E_DUP = np.where(XG < LA_TIP, 0.0, curve(LB_BOT, LA_TIP, DR_BACK, math.pi))
low = np.where(XG < DR_LOW[0][0], math.pi,
               np.interp(XG, [q[0] for q in DR_LOW], [q[1] * DEG for q in DR_LOW]))
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
# The dark green's lower edge, which the light green runs along, is in both
# photos a straight line in angle from just behind its tip back past the
# wing (~0.26 deg per px), curling up into the tip over its last few px.
# Built from the traced points it wavered, its slope dipping and rising
# again by 1000, which showed as a kink in the light green beside it. So up
# to 1100 it is one curve of that shape: a line plus a curl over ~12 px,
# which gives the point the depth the eye-level photo shows (~2 deg at 943,
# ~4 at 953). It is fitted to both photos' column-by-column measurements
# and to the smoothed edge behind, sits within ~1 deg of each photo and
# eases into the smoothed edge over 1100-1200.
B2_P4 = [(942.8, 32.1), (947.5, 33.0), (952.6, 34.4), (957.5, 35.7), (962.4, 36.8), (967.5, 38.3),
         (972.6, 39.7), (977.5, 40.7), (982.4, 41.7), (987.5, 43.2), (992.6, 44.3), (997.5, 45.9)]
B2_P1 = [(950, 33.2), (960, 36.2), (970, 38.9), (980, 41.4), (990, 43.7), (1000, 46.9),
         (1010, 48.9), (1020, 51.7), (1030, 54.3), (1040, 56.8)]
_bx0, _by0 = CROWN['B2'][0][0]           # the tip


def _b2(x, s, A, tau=12.0):
    return _by0 * DEG + s * (x - _bx0) + A * (1 - np.exp(-(x - _bx0) / tau))


_fx = np.array([q[0] for q in B2_P4 + B2_P1] + list(range(1060, 1141, 10)), float)
_fy = np.r_[[q[1] * DEG for q in B2_P4 + B2_P1], np.interp(_fx[len(B2_P4 + B2_P1):], XG, E_B2)]
_sig = np.r_[np.ones(len(B2_P4 + B2_P1)), np.full(len(_fx) - len(B2_P4 + B2_P1), 1 / 3)]
_pb, _ = curve_fit(_b2, _fx, _fy, p0=[0.26 * DEG, 3.0 * DEG], sigma=_sig)
_w = np.clip((XG - 1100.0) / 100.0, 0, 1)
_w = _w * _w * (3 - 2 * _w)
E_B2 = np.where(XG < _bx0, E_B2, (1 - _w) * _b2(XG, *_pb) + _w * E_B2)
# Behind ~1040 the traced edge ran ~2 deg high and then steepened late
# towards the belly, so from the side it bent up behind the wing where both
# photos show it running on almost straight. There it is a gentle curve
# fitted to both photos column by column (the eye-level one to 1150, the one
# from below where it sees under the wing from 1180), carrying on from the
# edge at 1040 with its slope (0.26 deg per px) and steepening steadily to
# 0.30 by 1300 (the belly end, from 1295, carries on from it).
B2_AFT = [(1040, 56.8), (1050, 59.6), (1060, 62.3), (1080, 68.5), (1090, 70.9), (1100, 73.6),
          (1110, 76.8), (1120, 79.0), (1130, 82.1), (1140, 85.3), (1150, 87.8), (1180, 94.6),
          (1190, 97.3), (1200, 100.7), (1210, 102.8), (1220, 106.2), (1230, 109.0),
          (1240, 111.9), (1250, 114.8), (1260, 117.8), (1270, 121.5), (1280, 124.7),
          (1290, 128.0), (1300, 131.4)]
_x0 = 1040.0
_i0 = np.searchsorted(XG, _x0)
_y0, _m0 = E_B2[_i0], (E_B2[_i0 + 4] - E_B2[_i0 - 4]) / (XG[_i0 + 4] - XG[_i0 - 4])
_t = np.array([q[0] for q in B2_AFT]) - _x0
_ca = np.linalg.lstsq(np.stack([_t ** 2, _t ** 3], 1),
                      np.array([q[1] * DEG for q in B2_AFT]) - _y0 - _m0 * _t, rcond=None)[0]
_t = XG - _x0
E_B2 = np.where((XG > _x0) & (XG <= 1300.0),
                _y0 + _m0 * _t + _ca[0] * _t ** 2 + _ca[1] * _t ** 3, E_B2)
# The light green under the dark green is a line of steady width, running
# parallel to the dark green's lower edge down to the belly: 16.3 deg from the
# dark green's tip to ~1040 in both photos, then narrowing smoothly to ~11.5
# deg behind the wing (16-17 at 1040-1060 and 15 at 1080-1090 at eye level,
# 11.5 at 1200-1230 from below). Traced on its own, its lower edge had drifted
# from the dark green's: up to 4 deg too wide by the tip and, behind the wing,
# dipping towards the belly so the line widened to 16 deg before the belly cut
# it. So behind 1000 it is rebuilt from the dark-green edge plus that width, and
# ahead of it the traced edge over the crown is eased onto it from 850 (the
# eye-level photo has it ~2 deg higher there too), which leaves it running
# straight, at the photos' 0.24-0.25 deg per px, past the dark green's tip.
_lw = np.where(XG <= 1040.0, 16.3, 11.0 + 5.3 / (1 + ((XG - 1040.0) / 75.0) ** 2)) * DEG
_off = np.clip(E_B2 + _lw, 0.0, math.pi) - E_B1
_x0, _x1 = 850.0, 1000.0
_i1 = np.searchsorted(XG, _x1)
_d1, _m1 = _off[_i1], np.gradient(_off, XG)[_i1] * (_x1 - _x0)
_t = np.clip((XG - _x0) / (_x1 - _x0), 0, 1)
_ease = (3 * _t ** 2 - 2 * _t ** 3) * _d1 + (_t ** 3 - _t ** 2) * _m1   # Hermite: 0 -> offset, matching its slope
E_B1 = np.clip(E_B1 + np.where(XG >= _x1, _off, _ease), 0.0, math.pi)
# Behind the wing both greens run down to the belly line, where the dark
# green carries on along it to its point. In the first photo the light green
# doesn't meet the belly line at an angle: from ~1295 its lower edge bends
# round to run along it and the band tapers out to a point at ~1362, where
# the dark green's lower edge, still running down almost straight, meets the
# belly line too; the dark green then follows the belly line to its own point.
# Cut off by the belly line instead, the two had ended in a blunt slanted
# step. So from 1295, where both still match the photo, each is eased onto
# the belly line: the light green's lower edge arriving along it, the dark
# green's crossing it just steeply enough to close the taper.
XB0, XB1 = 1295.0, 1362.0


def _ease_to(E, x0, x1, y1, m1):
    """E up to x0, then a Hermite curve keeping its slope there and
    arriving at y1 with slope m1 at x1"""
    i0 = np.searchsorted(XG, x0)
    y0, m0, L_ = E[i0], np.gradient(E, XG)[i0], x1 - x0
    t = np.clip((XG - x0) / L_, 0, 1)
    h = ((2 * t ** 3 - 3 * t ** 2 + 1) * y0 + (t ** 3 - 2 * t ** 2 + t) * L_ * m0
         + (3 * t ** 2 - 2 * t ** 3) * y1 + (t ** 3 - t ** 2) * L_ * m1)
    return np.where(XG <= x0, E, h)


_ie = np.searchsorted(XG, XB1)
_ble, _bms = E_BL[_ie], np.gradient(E_BL, XG)[_ie]
E_B1 = np.where(XG <= XB1, _ease_to(E_B1, XB0, XB1, _ble, _bms), E_BL)
E_B2 = np.where(XG <= XB1, _ease_to(E_B2, XB0, XB1, _ble, _bms + 0.15 * DEG),
                np.minimum(E_BL + 0.15 * DEG * (XG - XB1), math.pi))
# The white stripe's lower edge, over the light-green sliver ahead of the
# dark green's top and along the dark green behind it, is one smooth line in
# both photos. Built from the sliver's traced points and the dark green's
# smoothed edge, it had bulged down by up to 4 deg where the two met (the
# smoothing had rounded the corner where the dark green's flat top runs into
# it), which showed as a bend in the line just where the light green meets
# the dark green. So it is one smoothing spline through the eye-level points
# (within ~1 deg of each) from the crown at 919 to where the windows meet it
# (~1230), easing into the first photo's edge, which it sees again behind the
# wing, over 1290-1340; and the dark green's top ahead of it runs on nearly
# flat, as both photos show (a cubic through the eye-level points from the
# tip), until it meets the line in a clean point at ~1040.
_sp = list(B4_PTS) + STRIPE_LO
_xe = np.arange(1285.0, 1346.0, 10.0)
_x4a = B4_PTS[0][0]
_line = UnivariateSpline(np.r_[[q[0] for q in _sp], _xe],
                         np.r_[[q[1] * DEG for q in _sp], np.interp(_xe, XG, E_B3)],
                         w=np.r_[np.ones(len(_sp)), np.full(len(_xe), 3.0)], k=3,
                         s=(len(_sp) + len(_xe)) * (0.5 * DEG) ** 2)(np.clip(XG, _x4a, 1350.0))
_w = np.clip((XG - 1290.0) / 50.0, 0, 1)
_w = _w * _w * (3 - 2 * _w)
_line = np.where(XG < _x4a, 0.0, np.clip((1 - _w) * _line + _w * E_B3, 0.0, math.pi))
_cb = list(CROWN['B3'][0])
_cx0, _cy0 = _cb[0]                                   # the tip
_ct = np.array([q[0] - _cx0 for q in _cb[1:]])
_ca = np.linalg.lstsq(np.stack([_ct, _ct ** 2, _ct ** 3], 1),
                      np.array([(q[1] - _cy0) * DEG for q in _cb[1:]]), rcond=None)[0]
_tt = XG - _cx0
_flat = _cy0 * DEG + _ca[0] * _tt + _ca[1] * _tt ** 2 + _ca[2] * _tt ** 3
X_C = float(XG[np.argmax((XG > _cx0) & (_flat <= _line))])     # where the sliver closes
E_B3 = np.where(XG < APEX_X, 0.0, np.where(XG < X_C, _flat, _line))
E_B43 = _line
# The white stripe's upper edge (the red's lower edge) likewise: one
# smoothing spline from its crown crossing through the eye-level points to
# the wing tip and the first photo's points behind it, easing into the
# smoothed edge over 1430-1460, where the two photos meet it.
_hp = [(CROWN['B5'][0][0][0], 0.0)] + STRIPE_HI + STRIPE_HI_P1
_xe = np.arange(1440.0, 1471.0, 10.0)
_x5a = _hp[0][0]
_hi = UnivariateSpline(np.r_[[q[0] for q in _hp], _xe],
                       np.r_[[q[1] * DEG for q in _hp], np.interp(_xe, XG, E_B5)],
                       w=np.r_[10.0, np.ones(len(_hp) - 1), np.full(len(_xe), 3.0)], k=3,
                       s=(len(_hp) + len(_xe)) * (0.5 * DEG) ** 2)(np.clip(XG, _x5a, 1475.0))
_w = np.clip((XG - 1430.0) / 30.0, 0, 1)
_w = _w * _w * (3 - 2 * _w)
E_B5 = np.where(XG < _x5a, 0.0, np.clip((1 - _w) * _hi + _w * E_B5, 0.0, math.pi))
# Up to where it leaves for the line below the windows (~1255, behind the
# wing), the dark red's lower edge is the pinstripe's upper edge: both photos
# show the dark red sitting right on the white. Built from the raw pinstripe
# curve and smoothed on its own, it had drifted up to 2 deg above the
# smoothed one, leaving a thin bright-red line along the white. So it is
# rebuilt from the smoothed pinstripe edge and the line below the windows,
# joined by a smooth minimum over the last 1.5 deg where it leaves.
def _smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0, k) / k
    return np.minimum(a, b) - h * h * k / 4


_dlx = [q[0] for q in DR_LOW]
_low_s = np.where(XG < _dlx[0], math.pi,
                  PchipInterpolator(_dlx, [q[1] * DEG for q in DR_LOW])(np.clip(XG, _dlx[0], _dlx[-1])))
# From 1400 to the tip in the rear door the line below the windows runs
# straight in side view, as on the jet: the traced points dipped ~2 deg
# under the windows and rose again into the tip, a slight curve that showed
# in the sim. Straight between its height at 1400 and the tip's.
def _side_y(x, th):
    c, b = crown_p(x), belly_p(x)
    return (b + c) / 2 - (b - c) / 2 * np.cos(th)


def _side_th(x, y):
    c, b = crown_p(x), belly_p(x)
    return np.arccos(np.clip(((b + c) / 2 - y) / ((b - c) / 2), -1, 1))


_x0, _x1 = 1400.0, _dlx[-1]
_y0 = float(_side_y(_x0, np.interp(_x0, XG, _low_s)))
_y1 = float(_side_y(_x1, DR_LOW[-1][1] * DEG))
_st = (XG >= _x0) & (XG <= _x1)
_low_s[_st] = _side_th(XG[_st], _y0 + (_y1 - _y0) * (XG[_st] - _x0) / (_x1 - _x0))
# The two darker shades read as one shading line running under the white
# stripe: the dark red's top edge carries on the line of the dark green's.
# Where the stripe closes over the dark green its top edge is level, ~34 deg
# from the crown; carried straight on, that line leaves the stripe's upper
# edge at ~1085, where the dark red now begins, in a point on the stripe, its
# top edge running on along the line until it meets leaf A's lower edge as
# measured (~1250) and following that into leaf A's tip. Taken from the
# eye-level photo alone, the dark red's top edge sat up to ~7 deg above the
# line (26-30 deg at 1080-1200): from the side that reads as one line, but
# seen from above the dark red stood clearly above the dark green. The
# sliver it had run forward along the stripe from 1046 was mostly the
# photo's dark sharpening rim along the white.
_lvl = float(E_B3[np.searchsorted(XG, X_C) - 1])       # the dark green's top at the closure
DR_FRONT = float(XG[np.argmax((XG > X_C) & (E_B5 >= _lvl))])
E_LAB = np.where((XG < DR_FRONT) | (XG > LA_TIP), 0.0,
                 -_smin(-np.full_like(XG, _lvl), -E_LAB, 3.0 * DEG))
E_DLO = np.where((XG >= DR_FRONT) & (XG <= DR_BACK), _smin(E_B5, _low_s, 1.5 * DEG), 0.0)
for k, e in zip(_raw, (E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB, E_BL)):
    print(f'smoothed {k}: max change {np.degrees(np.abs(e - _raw[k]).max()):.1f} deg', flush=True)


# Where two shapes share an edge, blending each over the last by its own
# edge coverage leaves a quarter of the colour underneath in the shared edge
# texel (a faint line of it). So the shape below runs a hair (0.2 deg, about
# two texels) on under the one drawn over it: the dark green under the white
# behind its tip, and the dark red down to the pinstripe within the red, red
# and dark red being drawn as one layer.
_HAIR = 0.2 * DEG
E_B3D = np.where(XG > X_C, E_B3 - _HAIR, E_B3)
_in_dr = (XG >= DR_FRONT) & (XG <= DR_BACK)
E_DLOP = E_DLO + _HAIR * _in_dr * np.clip(1 - (E_B5 - E_DLO) / (0.5 * DEG), 0, 1)
EDGES = [E_B1, E_B2, E_B3, E_B5, E_B43, E_DUP, E_DLO, E_LAT, E_LAB, E_BL, E_B3D, E_DLOP]
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
    L, B2, B3, B5, B43, DUP, DLO, LAT, LAB, BL, B3D, DLOP = cov
    leaf_a = LAB * (1 - LAT)
    dark = DLOP * (1 - DUP) * (1 - leaf_a)          # share of the red that is dark
    reds = C['R'] * (1 - dark[:, None]) + C['DR'] * dark[:, None]
    col = np.ones((len(rr), 3), np.float32) * C['W']
    for c_, a_ in ((C['L'], L * BL), (C['D'], np.clip(B2 - B3D, 0, 1) * BL), (C['W'], B43),
                   (reds, B5)):
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
    aft = x > fusmap.X_JOIN
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
# The flag is sized against the forward doors, which the kit draws at their
# true size: near the nose the photos' scale along the fuselage doesn't match
# the window-anchored station map. It is the same size on both sides, so the
# two photos are averaged: 0.50 of L1's width, 0.53 of the smaller R1's.
L1_W, R1_W = 187.0, 156.0          # 4K texels, frame outer
FLAG_W8 = 2 * (0.50 * L1_W + 0.53 * R1_W) / 2

# "EMBRAER 190": the kit's own artwork of Embraer's italic lettering
# (kit-tools/kitart.py), placed against the cockpit side window, which the
# kit's mask cuts out at U 404-585, V 294-416 (4K; mirrored on the right).
# The two photos agree to ~10%: the title runs from 0.12 to 1.12 window
# widths aft of the window's front edge (175 texels, averaged with its width
# against the forward doors), centred 51 rows below the window, and reads
# about 12.4:1 on the jet; the texture holds ~0.96 as many texels round the
# nose as along it, so its letters are 14 rows tall, a little flatter than
# the kit's 10.3:1.
EMB_U4, EMB_V4, EMB_W4, EMB_H4 = 516.5, 467.0, 175.0, 14.0
emb_mask = Image.open(f'{KITART}/embraer_190.png').convert('L')
emb = Image.new('RGBA', emb_mask.size, (40, 40, 44, 0))
emb.putalpha(emb_mask)
put(emb, 2 * EMB_U4, 2 * EMB_V4, 2 * EMB_W4, 2 * EMB_H4, False)
put(emb, 2 * EMB_U4, 4 * AX_F - 2 * EMB_V4, 2 * EMB_W4, 2 * EMB_H4, True)

# Nose-gear doors: "GO", the end of CN-RGO, at the front of each door, as in
# both photos (the red stripe at their rear edge is already in the kit's
# base). The doors are U 635-840, V 900-997 on the left (hinged at 900, so
# with the gear down they hang with that edge at the top) and 997-1093 on the
# right. In the photos the letters start 0.035 of the door's length behind
# its front edge, run 0.345 of it and stand 0.46 of its height, centred on
# it; black, in the registration's face, a weight bolder.
NG_U0, NG_U1, NG_HINGE, NG_W, NG_H = 635.0, 840.0, 900.0, 0.345, 0.46
ng = reg_layer('GO', f'{FONTS}/barlow-latin-600-normal.woff', 300, REG_BLACK, tracking=0.0)
ng_w4 = NG_W * (NG_U1 - NG_U0)
ng_h4 = NG_H * (AX_F - NG_HINGE)
ng_u4 = NG_U0 + 0.035 * (NG_U1 - NG_U0) + ng_w4 / 2
ng_v4 = (NG_HINGE + AX_F) / 2
put(ng, 2 * ng_u4, 2 * ng_v4, 2 * ng_w4, 2 * ng_h4, False)
put(ng, 2 * ng_u4, 4 * AX_F - 2 * ng_v4, 2 * ng_w4, 2 * ng_h4, True)

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

# oneworld emblem, left side only: the official emblem from the kit (a
# shaded sphere with the wordmark across it), between the L1 door and the
# first window (first photo: 15.5 px across, about a third of the door's width,
# centred 0.35 of the way from the door's rear frame to the first window's
# centre and 6 px above it, in the kit's own logo-by-the-door area; the
# eye-level photo of the right side shows none there). Kit: door rear frame
# U 1086, first window U 1323. Kept in the official colours (a purple-blue,
# hue 241); the first photo shows it brighter and more azure (hue 216).
OW_U8, OW_V8 = 2 * (1086 + 0.348 * (1323 - 1086)), 722.0
OW_W8 = 2 * 65.0                   # 15.5 px at the door's 4.2 texels per px
OW_H8 = OW_W8 * skin_ratio(360.4, 462.3)
ow = Image.open(f'{KITART}/oneworld.png').convert('RGBA')
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
