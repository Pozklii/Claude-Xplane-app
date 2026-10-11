"""UV <-> side-profile mapping for the X-Crafts E190 fuselage texture.

build_theta() gives, for every 8K texel, the angle around the fuselage from
the crown (0) to the belly (pi); u_to_x() gives the photo station.
"""
import math
import numpy as np
from PIL import Image
import geometry as G

N = 8192
# ---- UV layout of the kit (4096 px units) --------------------------------
AX_F, CROWN_F = 997.0, 0.0            # forward section: belly axis, crown
AX_A, CROWN_A = 3096.9, 2100.0        # aft section
SPLIT_V = 2020.0                      # rows above: forward; below: aft
BLEND_U = (1850.0, 2250.0)            # ...blended in over this range (4K U)

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



def build_theta(mask_path='layers/fus__paintmask.png'):
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
    lin_cols = U4 < BLEND_U[0]
    th_l = np.clip(np.pi * (V4[al] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
    th_r = np.clip(np.pi * (2 * AX_A - V4[ar] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
    theta[np.ix_(al, lin_cols)] = th_l[:, None]
    theta[np.ix_(ar, lin_cols)] = th_r[:, None]
    # ...then arc length measured over the skin only, skipping the darts,
    # blended in over BLEND_U so the edges don't jump where the methods meet
    dart_cols = np.nonzero(U4 >= BLEND_U[0])[0]
    w = np.clip((U4[dart_cols] - BLEND_U[0]) / (BLEND_U[1] - BLEND_U[0]), 0, 1)
    w = (w * w * (3 - 2 * w))[None, :]
    rows_l, rows_r = np.nonzero(al)[0], np.nonzero(ar)[0]
    ml = mask8[np.ix_(rows_l, dart_cols)].astype(np.float32)
    cl = np.cumsum(ml, 0)
    arc_l = np.pi * cl / np.maximum(cl[-1:], 1)
    theta[np.ix_(rows_l, dart_cols)] = (1 - w) * th_l[:, None] + w * arc_l
    mr = mask8[np.ix_(rows_r, dart_cols)][::-1].astype(np.float32)
    cr = np.cumsum(mr, 0)
    arc_r = (np.pi * cr / np.maximum(cr[-1:], 1))[::-1]
    theta[np.ix_(rows_r, dart_cols)] = (1 - w) * th_r[:, None] + w * arc_r

    return theta, mask8, V4, U4, al, ar
