"""Angle around the fuselage on the tail cone, read from the model's mesh.

The kit's wireframe draws the mesh. Its lengthwise lines (stringers) each sit
at a fixed angle around the fuselage. Ahead of the tail-cone darts the aft
section's V coordinate is linear in that angle, so each stringer's angle is
known there; each is then followed back along U through the darts. Where a
seam splits, both branches are followed (the line is tracked once biased up
and once biased down), so both sides of every seam carry the same angle.

phi runs 0 (left crown) -> pi (belly) -> 2 pi (right crown).
"""
import numpy as np
from PIL import Image
from scipy import ndimage

V_TOP, V_BOT, AX = 2100.0, 4094.0, 3097.0     # aft section, 4K texels
U0 = 1890                                      # start column (still linear)


def line_masks(wire_png):
    w = np.asarray(Image.open(wire_png)).astype(int)
    L = (w[..., 3] > 60) & ((w[..., 2] - w[..., 0]) > 30)
    # keep near-horizontal strokes only: drops ring lines and most outlines
    H = ndimage.binary_opening(L, structure=np.ones((1, 7), bool))
    return L, H


def column_centres(H, U, v0=2080, v1=4096):
    col = H[v0:v1, U]
    idx = np.nonzero(col)[0]
    if len(idx) == 0:
        return np.zeros(0)
    br = np.nonzero(np.diff(idx) > 1)[0]
    starts = np.r_[idx[0], idx[br + 1]]
    ends = np.r_[idx[br], idx[-1]]
    ok = (ends - starts) <= 6
    return ((starts + ends) / 2.0 + v0)[ok]


# Darts: where each opens (U, V at its tip); both of its edges are one seam,
# so they carry the angle of the line through the tip.
DART_TIPS = [(1955, 2876.0), (1955, 3316.0), (2535, 2309.0), (2535, 3883.0)]


def phi_lin(v):
    return np.pi * (v - V_TOP) / (AX - V_TOP)


def _follow(cent, U_start, v_start, U_end, tol, max_gap):
    V, slope, gap = v_start, 0.0, 0
    Us, Vs = [U_start], [v_start]
    for U in range(U_start + 1, U_end + 1):
        pred = V + slope
        c = cent[U]
        d = np.abs(c - pred)
        if len(c) and d.min() <= tol:
            nv = c[np.argmin(d)]
            slope = 0.92 * slope + 0.08 * (nv - V)
            V, gap = nv, 0
            Us.append(U); Vs.append(V)
        else:
            V, gap = pred, gap + 1
            if gap > max_gap:
                break
    return np.array(Us), np.array(Vs)


def track(H, skin, U_end=4095, tol=1.5, max_gap=250):
    cent = [column_centres(H, U) for U in range(H.shape[1])]
    seeds = []
    c0 = cent[U0]
    for v in c0[(c0 >= V_TOP - 2) & (c0 <= V_BOT + 2)]:
        seeds.append((phi_lin(v), U0, v))
    # both edges of every dart, picked up where the dart is 8+ px wide
    for Ut, Vt in DART_TIPS:
        found = {}
        for U in range(Ut, Ut + 500):
            col = skin[int(Vt) - 40:int(Vt) + 40, U]
            gap = np.nonzero(~col)[0]
            if not len(gap) or gap.max() - gap.min() < 8:
                continue
            g0, g1 = gap.min() + int(Vt) - 40, gap.max() + int(Vt) - 40
            c = cent[U]
            for side, edge in (('a', g0 - 1), ('b', g1 + 1)):
                near = c[np.abs(c - edge) <= 4]
                if side not in found and len(near):
                    found[side] = (U, near[np.argmin(np.abs(near - edge))])
            if len(found) == 2:
                break
        for U, v in found.values():
            seeds.append((phi_lin(Vt), U, v))
    tracks = []
    for phi, Us0, v in seeds:
        Us, Vs = _follow(cent, Us0, v, U_end, tol, max_gap)
        tracks.append((phi, Us, Vs))
    return tracks


def lnds(phis):
    """indices of a longest non-decreasing subsequence"""
    import bisect
    tails, tail_idx, prev = [], [], [-1] * len(phis)
    for i, p in enumerate(phis):
        k = bisect.bisect_right(tails, p)
        if k == len(tails):
            tails.append(p); tail_idx.append(i)
        else:
            tails[k] = p; tail_idx[k] = i
        prev[i] = tail_idx[k - 1] if k else -1
    res, i = [], tail_idx[-1] if tail_idx else -1
    while i >= 0:
        res.append(i); i = prev[i]
    return res[::-1]


def phi_columns(tracks, U_list, smooth=3.0):
    """For each column, the (V, phi) control points of the live tracks."""
    from scipy.ndimage import gaussian_filter1d
    sm = []
    for phi, Us, Vs in tracks:
        if len(Us) < 20:
            continue
        full_U = np.arange(Us[0], Us[-1] + 1)
        full_V = np.interp(full_U, Us, Vs)
        sm.append((phi, full_U, gaussian_filter1d(full_V, smooth, mode='nearest')))
    cols = {}
    for U in U_list:
        pts = []
        for phi, fu, fv in sm:
            if fu[0] <= U <= fu[-1]:
                pts.append((fv[U - fu[0]], phi))
        if len(pts) < 3:
            continue
        pts.sort()
        vs = np.array([p[0] for p in pts]); ps = np.array([p[1] for p in pts])
        keep = lnds(list(ps))
        cols[U] = (vs[keep], ps[keep])
    return cols


def phi_map(tracks, N=8192, U_from=U0, smooth=3.0):
    """phi for every 8K texel of the aft section from column U_from (4K) on;
    NaN elsewhere. Interpolates between the tracked lines in each column."""
    from scipy.ndimage import gaussian_filter1d
    out = np.full((N, N), np.nan, np.float32)
    cols = phi_columns(tracks, range(U_from, N // 2), smooth=smooth)
    r0, r1 = int(2 * (V_TOP - 20)), N
    v4 = (np.arange(r0, r1) + 0.5) / 2
    for U, (vs, ps) in cols.items():
        col = np.interp(v4, vs, ps)
        out[r0:r1, 2 * U] = col
        out[r0:r1, 2 * U + 1] = col
    # smooth the column-to-column quantisation a little along U
    blk = out[r0:r1, 2 * U_from:]
    m = np.isfinite(blk)
    num = gaussian_filter1d(np.where(m, blk, 0), 2.0, axis=1)
    den = gaussian_filter1d(m.astype(np.float32), 2.0, axis=1)
    out[r0:r1, 2 * U_from:] = np.where(m, num / np.maximum(den, 1e-6), np.nan)
    return out
