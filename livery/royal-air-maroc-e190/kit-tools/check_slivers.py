"""List every thin sliver in the fuselage design: a colour band narrower than
2.5 photo px between two others, at any station. Pointed tips show up here
by design (where a shape runs out to a point); anything else is two shapes
that are meant to share an edge but don't quite (e.g. a hairline of bright
red between the dark red and the white pinstripe).

Run from the same working folder as paint_fus.py:
usage: check_slivers.py <livery tools dir> <fonts dir>
"""
import contextlib, io, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# the edge curves exactly as paint_fus.py builds them (it is run up to its
# paint loop; nothing is written)
sys.argv = ['paint_fus.py', sys.argv[1], sys.argv[2], os.devnull]
src = open(os.path.join(HERE, 'paint_fus.py')).read().split('paint = np.ones((N, N, 3)')[0]
src = src.replace("np.save('layers/theta4.npy', theta[::2, ::2].astype(np.float16))", '')
ns = {'__file__': os.path.join(HERE, 'paint_fus.py'), '__name__': 'check_slivers'}
with contextlib.redirect_stdout(io.StringIO()):
    exec(compile(src, 'paint_fus.py', 'exec'), ns)

XG, DEG, F = ns['XG'], math.pi / 180, ns['fusmap']
E = dict(zip(['B1', 'B2', 'B3', 'B5', 'B43', 'DUP', 'DLO', 'LAT', 'LAB', 'BL', 'B3D', 'DLOP'],
             ns['EDGES']))
NAMES = ['white', 'light green', 'dark green', 'red', 'dark red']
th = np.arange(0.02, 180, 0.02) * DEG
found = {}
for x in np.arange(760, 1800, 1.0):
    i = np.searchsorted(XG, x)
    below = {k: th < v[i] for k, v in E.items()}
    c = np.zeros(len(th), int)
    c[below['B1'] & below['BL']] = 1
    c[below['B2'] & ~below['B3'] & below['BL']] = 2
    c[below['B43']] = 0
    c[below['B5']] = 3
    leaf = below['LAB'] & ~below['LAT']
    c[below['B5'] & below['DLO'] & ~below['DUP'] & ~leaf] = 4
    R = float((F.belly_p(x) - F.crown_p(x)) / 2)
    b = np.nonzero(np.diff(c))[0]
    for s, e in zip(np.r_[0, b + 1], np.r_[b, len(c) - 1]):
        if s == 0 or e == len(c) - 1:
            continue
        w = R * (th[e] - th[s] + 0.02 * DEG)
        if w < 2.5:
            key = (NAMES[c[s]], NAMES[c[s - 1]], NAMES[c[e + 1]])
            found.setdefault(key, []).append((x, w, np.degrees(th[s])))
for (col, above, under), hits in found.items():
    groups = []
    for x, w, t in hits:
        if groups and x - groups[-1][1] <= 2:
            groups[-1][1] = x
            groups[-1][2] = max(groups[-1][2], w)
        else:
            groups.append([x, x, w, t])
    for x0, x1, w, t in groups:
        print(f'{col:11s} between {above:11s} and {under:11s}: stations {x0:.0f}-{x1:.0f}, '
              f'up to {w:.2f} px wide, ~{t:.0f} deg from the crown')
