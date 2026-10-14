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

# texture U <-> photo x, anchored on the cabin windows (and the L1 door, tail
# end): (U, photo station) per section.
FWD = ([993, 1323, 1499.5, 1675.5, 1852.5, 2029.5, 2206, 2382.5, 2559, 2735,
        2912.5, 3089, 3290.5, 3478, 3660.5, 3842.5],
       [316.5, 394.5, 436, 477.5, 519, 560, 602, 643.5, 684, 725, 766.5, 809,
        858.5, 902, 947, 991])
AFT = ([615, 797.5, 1807.5, 1976, 2144, 2310.5, 4090],
       [1030.5, 1070, 1299, 1339, 1379.5, 1420, 1845])
THETA_WIN = math.pi * 378 / 997        # window row angle from the crown

# The two sections meet on one ring of the mesh: the forward one ends at
# U 3948, 105.5 texels behind its last window, the aft one starts at U 537.5,
# 77.5 ahead of its first (one window pitch apart, as along the cabin). Laid
# end to end on one axis, both sections share one map: a smoothing spline
# through all the anchors, within 0.9 px of each (rms 0.3, about how well a
# window centre can be read off the photo). Joined straight from anchor to
# anchor instead, the map's slope jumped at every window by up to 6% (and the
# two sections disagreed by 2.7 px at the seam), which put a slight corner
# into every colour edge crossing those columns.
JOIN_F, JOIN_A = 3948.0, 537.5
_S = np.r_[FWD[0], np.asarray(AFT[0], float) + (JOIN_F - JOIN_A)]
_X = np.r_[FWD[1], AFT[1]]


def _fit():
    from scipy.interpolate import make_smoothing_spline
    return make_smoothing_spline(_S, _X, lam=1e6)


_SPL = _fit()
_DSPL = _SPL.derivative()


def _x_of_s(s):
    """photo station along the joined axis; straight on past the end anchors"""
    s = np.asarray(s, float)
    lo, hi = _S[0], _S[-1]
    y = _SPL(np.clip(s, lo, hi))
    y = np.where(s < lo, _SPL(lo) + (s - lo) * _DSPL(lo), y)
    return np.where(s > hi, _SPL(hi) + (s - hi) * _DSPL(hi), y)


_SG = np.arange(-4000.0, 12001.0, 0.5)      # dense table for the inverse
_XG = _x_of_s(_SG)
assert np.all(np.diff(_XG) > 0)
X_JOIN = float(_x_of_s(JOIN_F))              # photo station of the section seam


def u_to_x(U, aft):
    U = np.asarray(U, float)
    return _x_of_s(U + (JOIN_F - JOIN_A) if aft else U)


def x_to_u(x, aft):
    s = float(np.interp(x, _XG, _SG))
    return s - (JOIN_F - JOIN_A) if aft else s


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
    lin_cols = U4 < 10 ** 6         # linear everywhere first; mesh angles replace the tail cone below
    th_l = np.clip(np.pi * (V4[al] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
    th_r = np.clip(np.pi * (2 * AX_A - V4[ar] - CROWN_A) / (AX_A - CROWN_A), 0, np.pi)
    theta[np.ix_(al, lin_cols)] = th_l[:, None]
    theta[np.ix_(ar, lin_cols)] = th_r[:, None]
    # ...then the tail cone, strip by strip between the model's seams (the
    # dart edges, followed down the mask from each tip; see stringers.py).
    import stringers as S
    phi = S.strip_phi_map(mask4, N, strokes=S.wire_strokes('layers/fus__WIREFRAME_E190.png'))
    th_mesh = np.where(phi <= np.pi, phi, 2 * np.pi - phi)
    aft_rows = al | ar
    cols = U4 >= S.U0
    blk = th_mesh[np.ix_(aft_rows, cols)]
    old = theta[np.ix_(aft_rows, cols)]
    theta[np.ix_(aft_rows, cols)] = np.where(np.isfinite(blk), blk, old)

    # The ventral antenna (a long blade under the aft belly, from a swept
    # mast at ~1380 back to the tail) is a separate part packed into the
    # gutter below the right-hand lower strip, inside the paint mask. Mapped
    # by its V it took the angle of the strip beside it (143-168 deg), so it
    # came out green at the mast and striped along its length. It hangs on
    # the belly centreline, so it gets that colour: white, red under the tail
    # (set a hair inside it: at exactly pi the edges that run to the belly
    # would each cover it by half).
    ant = antenna_island(mask4)
    theta[np.repeat(np.repeat(ant, 2, 0), 2, 1)] = np.pi - 0.01

    return theta, mask8, V4, U4, al, ar


def antenna_island(mask4, wire_path='layers/fus__WIREFRAME_E190.png', seed=(3320, 2700)):
    """4K mask of the antenna's island: the piece of the paint mask that the
    fuselage wireframe doesn't cover, around the seed (V, U)."""
    from scipy import ndimage
    off = mask4 & (np.asarray(Image.open(wire_path))[..., 3] == 0)
    lab, _ = ndimage.label(off)
    return lab == lab[seed]
