"""Smooth mapping between the fin as traced on the first photo and each fin
side on the X-Crafts E-Jets tail texture.

Five points are matched: root and tip of the trailing edge, tip of the
leading edge, the dorsal/leading-edge kink, and the front of the dorsal. They
used to be joined by three flat triangles, which creases every curve that
crosses from one triangle into the next (the crescent bent where it crossed
the trailing-edge-root to leading-edge-tip line). Neither one affine nor one
perspective map fits all five (they miss by up to 125 and 370 texels), so the
map is a thin-plate spline: exact at the five points and smooth everywhere.
"""
import numpy as np

PHOTO = dict(rootTE=(1783, 540), tipTE=(1845, 265), tipLE=(1785, 264),
             kink=(1592, 463), dorsal=(1440, 507))
SIDES = {   # island label in tail_fill_lab -> texture points (4K)
    6: dict(rootTE=(3409, 4089), tipTE=(4077, 1333), tipLE=(3283, 1386),
            kink=(1568, 3388), dorsal=(287, 3957)),
    5: dict(rootTE=(750, 985), tipTE=(80, 3737), tipLE=(877, 3687),
            kink=(2591, 1686), dorsal=(3872, 1118)),
}
SIDE_SIGN = {6: +1, 5: -1}          # +1: left side of the aircraft
_S = 1000.0                          # coordinate scale for conditioning


def _u(r):
    with np.errstate(divide='ignore', invalid='ignore'):
        return np.where(r > 0, r * r * np.log(r), 0.0)


class _TPS:
    def __init__(self, src, dst):
        self.c = np.asarray(src, float) / _S
        dst = np.asarray(dst, float) / _S
        n = len(self.c)
        K = _u(np.hypot(*(self.c[:, None] - self.c[None]).transpose(2, 0, 1)))
        P = np.c_[np.ones(n), self.c]
        L = np.zeros((n + 3, n + 3))
        L[:n, :n], L[:n, n:], L[n:, :n] = K, P, P.T
        self.coef = np.linalg.solve(L, np.r_[dst, np.zeros((3, 2))])

    def __call__(self, pts):
        p = np.atleast_2d(np.asarray(pts, float)) / _S
        n = len(self.c)
        out = np.c_[np.ones(len(p)), p] @ self.coef[n:]
        for i in range(n):
            out += _u(np.hypot(p[:, 0] - self.c[i, 0], p[:, 1] - self.c[i, 1]))[:, None] * self.coef[i]
        return out * _S


class FinMap:
    """tex_to_photo and photo_to_tex for one fin side (4K texture units)."""

    def __init__(self, side):
        keys = list(PHOTO)
        tex = [SIDES[side][k] for k in keys]
        ph = [PHOTO[k] for k in keys]
        self.t2p = _TPS(tex, ph)
        self._p2t = _TPS(ph, tex)

    def tex_to_photo(self, pts):
        return self.t2p(pts)

    def photo_to_tex(self, pts, steps=3):
        """inverse of tex_to_photo (Newton steps from a fitted inverse)"""
        p = np.atleast_2d(np.asarray(pts, float))
        t = self._p2t(p)
        e = 0.5
        for _ in range(steps):
            f = self.t2p(t) - p
            jx = (self.t2p(t + [e, 0]) - self.t2p(t - [e, 0])) / (2 * e)
            jy = (self.t2p(t + [0, e]) - self.t2p(t - [0, e])) / (2 * e)
            det = jx[:, 0] * jy[:, 1] - jy[:, 0] * jx[:, 1]
            dt0 = (jy[:, 1] * f[:, 0] - jy[:, 0] * f[:, 1]) / det
            dt1 = (-jx[:, 1] * f[:, 0] + jx[:, 0] * f[:, 1]) / det
            t = t - np.stack([dt0, dt1], 1)
        return t
