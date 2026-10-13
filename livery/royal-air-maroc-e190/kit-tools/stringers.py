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


# ---- strip map -----------------------------------------------------------
# Many lengthwise lines can't be followed all the way back (they fade or run
# into neighbours), and a line picked up by its neighbour's track carries the
# wrong angle: inside one strip the traced map put 11 deg into 24 rows in one
# place and 36 deg into 131 in another. The seams are reliable, though: each
# dart's two edges are one mesh line at the angle of the line through its
# tip, and the lines that could be followed show V running evenly in angle
# between seams. So each column is mapped linearly, strip by strip, between
# the dart edges (followed down the paint mask from each tip and smoothed
# along U), the crown seam (V_TOP / V_BOT) and nothing else.

def dart_edges(mask4, Ut, Vt, U_end=4095, tol=6, max_gap=400):
    """Upper and lower edge (4K V) of a dart in each column from its tip on.
    Each edge is followed on its own, from one column to the next, to the
    nearest mask transition of its kind (strip -> gap for the upper edge,
    gap -> strip for the lower), so islands and holes nearby are ignored."""
    a, b = {}, {}
    pa = pb = float(Vt)
    sa = sb = 0.0
    ga = gb = 0
    for U in range(Ut, U_end + 1):
        col = mask4[:, U]
        d = np.diff(col.astype(np.int8))
        down = np.nonzero(d == -1)[0] + 1.0      # first gap row
        up = np.nonzero(d == 1)[0] + 1.0         # first strip row after a gap
        for edge in ('a', 'b'):
            cand = down if edge == 'a' else up
            pred = (pa + sa) if edge == 'a' else (pb + sb)
            k = np.abs(cand - pred)
            if len(cand) and k.min() <= tol:
                v = cand[np.argmin(k)]
                if edge == 'a':
                    sa = 0.9 * sa + 0.1 * (v - pa); pa, ga = v, 0
                else:
                    sb = 0.9 * sb + 0.1 * (v - pb); pb, gb = v, 0
            else:
                if edge == 'a':
                    pa, ga = pred, ga + 1
                else:
                    pb, gb = pred, gb + 1
        if ga > max_gap or gb > max_gap:
            break
        a[U], b[U] = pa, max(pb, pa)
    return a, b


def wire_strokes(wire_png):
    """the wireframe's drawn lines (dark, opaque) as a boolean image"""
    w = np.asarray(Image.open(wire_png)).astype(np.int16)
    return (w[..., 3] > 60) & (w[..., :3].mean(2) < 200)


def snap_edges(strokes, a, b, Ut, Vt, reach=10, min_gap=8):
    """Move followed dart edges from the paint mask onto the mesh.

    The kit's mask is padded 3-5 texels past each strip, so edges followed on
    it sit in the gutter, and each strip's angles were spread from there: at
    the real seam the two sides then disagreed by 2-3 deg, which showed in
    the sim as small steps wherever a colour edge crosses a dart. The
    wireframe draws each strip's edge as a stroke centred on it; each
    column's edge is moved to the centre of the nearest stroke inside the
    mask (upper edge: above the gap; lower edge: below it). Where the dart is
    too narrow to tell its two strokes apart, or no thin stroke is found (a
    few columns have other drawing there), the offset is interpolated from
    the neighbouring columns, falling to zero at the tip; a running median
    along the dart keeps odd columns from pulling it."""
    from scipy.ndimage import median_filter
    out = []
    for edge, sgn in ((a, -1), (b, +1)):
        ks = np.array(sorted(edge))
        offs = np.full(len(ks), np.nan)
        for i, U in enumerate(ks):
            v = edge[U]
            if b[U] - a[U] < min_gap:
                continue
            v0 = int(round(v))
            rows = np.arange(v0 - reach, v0 + 3) if sgn < 0 else np.arange(v0 - 2, v0 + reach)
            hit = strokes[rows, U]
            if not hit.any():
                continue
            r = rows[hit]
            runs = [g for g in np.split(r, np.nonzero(np.diff(r) > 1)[0] + 1)
                    if 2 <= len(g) <= 5 and g[0] > rows[0] and g[-1] < rows[-1]]
            if not runs:
                continue
            run = runs[-1] if sgn < 0 else runs[0]          # the one nearest the gap
            offs[i] = (run[0] + run[-1] + 1) / 2.0 - v
        ok = np.isfinite(offs)
        if ok.sum() >= 2:
            good = median_filter(offs[ok], size=51, mode='nearest')
            offs = np.interp(ks, np.r_[Ut, ks[ok]], np.r_[0.0, good])
        else:
            offs = np.zeros(len(ks))
        out.append({U: edge[U] + o for U, o in zip(ks, offs)})
    return out


def strip_phi_map(mask4, N=8192, U_from=U0, smooth=4.0, U_hold=3950, strokes=None):
    """phi for every 8K texel of the aft section from column U_from (4K) on,
    linear in V within each strip between seams. The left darts are followed
    on the mask (and moved onto the mesh's own edges when the wireframe's
    strokes are given); the layout is mirror-symmetric about the belly axis
    (checked to a texel or two), so the right ones are their mirror images,
    which keeps small UV islands that sit inside the right-hand darts from
    pulling them. Past U_hold the upper strips run out, so the seams are
    held there."""
    from scipy.ndimage import gaussian_filter1d
    Us = np.arange(U_from, N // 2)
    edges = []
    for Ut, Vt in DART_TIPS:
        if Vt > AX:
            continue
        a, b = dart_edges(mask4, Ut, Vt)
        if strokes is not None:
            a, b = snap_edges(strokes, a, b, Ut, Vt)
        ka = np.array(sorted(a))
        va = np.array([a[k] for k in ka]); vb = np.array([b[k] for k in ka])
        Uc = np.minimum(Us, U_hold)
        full_a = np.where(Us < Ut, Vt, np.interp(Uc, ka, va))
        full_b = np.where(Us < Ut, Vt, np.interp(Uc, ka, vb))
        full_a = gaussian_filter1d(full_a, smooth, mode='nearest')
        full_b = gaussian_filter1d(full_b, smooth, mode='nearest')
        phi = phi_lin(Vt)
        edges.append((phi, full_a, full_b))
        edges.append((2 * np.pi - phi, 2 * AX - full_b, 2 * AX - full_a))
    edges.sort(key=lambda e: e[0])
    out = np.full((N, N), np.nan, np.float32)
    r0 = int(2 * (V_TOP - 20))
    v4 = (np.arange(r0, N) + 0.5) / 2
    for j, U in enumerate(Us):
        vs, ps = [V_TOP], [0.0]
        for phi, fa, fb in edges:
            vs += [fa[j], fb[j]]; ps += [phi, phi]
        vs.append(V_BOT); ps.append(2 * np.pi)
        col = np.interp(v4, vs, ps)
        out[r0:, 2 * U] = col
        out[r0:, 2 * U + 1] = col
    return out
