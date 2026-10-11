"""Rebuild the Royal Air Maroc Arabic logotype from the photo: high-res red
mask, outlines extracted and smoothed as curves, refilled crisply.

usage: trace_ar.py <photo png> <out png> <aspect> [threshold]
"""
import sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage import measure

src, out, aspect = sys.argv[1], sys.argv[2], float(sys.argv[3])
thr = float(sys.argv[4]) if len(sys.argv) > 4 else 0.40
ph = Image.open(src).convert('RGB')
box = (414, 426, 782, 490)
K = 8
c = ph.crop(box).resize(((box[2] - box[0]) * K, (box[3] - box[1]) * K), Image.BICUBIC)
c = c.rotate(3.8, resample=Image.BICUBIC, fillcolor=(242, 242, 240))
a = np.asarray(c).astype(float)
red = np.clip((a[..., 0] - (a[..., 1] + a[..., 2]) / 2 - 20) / 60, 0, 1)
field = ndimage.gaussian_filter(red, 2.0)
m = field > thr
lab, n = ndimage.label(m)
sizes = ndimage.sum(m, lab, range(1, n + 1))
keep = np.isin(lab, np.nonzero(sizes > 90)[0] + 1)
field = np.where(ndimage.binary_dilation(keep, iterations=6), field, 0)

ys, xs = np.nonzero(keep)
y0, y1, x0, x1 = ys.min() - 10, ys.max() + 11, xs.min() - 10, xs.max() + 11
field = field[y0:y1, x0:x1]
h, w = field.shape
S = 4                                   # supersample the refill
sy = (w / aspect) / h                   # vertical stretch to the real proportions
H, W = int(round(h * sy * S)), w * S
img = Image.new('L', (W, H), 0)
d = ImageDraw.Draw(img)


def smooth(cnt, win):
    """moving average along a closed contour (wraps around)"""
    n = len(cnt)
    if n < 3 * win:
        return cnt
    k = np.ones(win) / win
    ext = np.concatenate([cnt[-win:], cnt, cnt[:win]])
    sm = np.stack([np.convolve(ext[:, i], k, mode='same') for i in range(2)], 1)
    return sm[win:-win]


contours = measure.find_contours(np.pad(field, 1), thr)
polys = []
for cnt in contours:
    cnt = cnt - 1
    area = 0.5 * np.sum(cnt[:-1, 1] * cnt[1:, 0] - cnt[1:, 1] * cnt[:-1, 0])
    cnt = smooth(cnt, 9)
    pts = [(p[1] * S, p[0] * sy * S) for p in cnt]
    polys.append((abs(area), area, pts))
# outer shapes first, then holes (find_contours gives holes the other winding)
outer_sign = np.sign(max(polys, key=lambda p: p[0])[1])
for _, ar, pts in sorted(polys, key=lambda p: -p[0]):
    if len(pts) >= 3:
        d.polygon(pts, fill=255 if np.sign(ar) == outer_sign else 0)
alpha = img.resize((W // S, H // S), Image.LANCZOS)
rgba = Image.new('RGBA', alpha.size, (200, 16, 46, 255))
rgba.putalpha(alpha)
rgba.save(out)
print(out, rgba.size, 'aspect', round(rgba.width / rgba.height, 1))
