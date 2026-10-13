"""Royal Air Maroc livery elements as clean high-res artwork.

usage: elements.py <out dir> <fonts dir>

Geometry is measured off the reference photo (tail crop coordinates, 2x the
photo) and drawn supersampled for smooth edges.
"""
import math
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageChops, ImageDraw, ImageFont

from geometry import RED, REG_RED, STAR_GREEN, catmull_rom

SS = 4


# Crescent, traced edge to edge off the first photo (tail-crop pixels, 2x the
# photo): a centreline whose curvature varies smoothly (fitted to the traced
# one to within 0.35 px of the photo, kept clear of the photo's ripples, which
# the inner edge would magnify), a smooth stroke width along it, and a
# straight cut where it meets the star. The points are kept to 0.001 px:
# 12 px apart, rounding to 0.1 px would ripple the gentle curvature of the
# right-hand side. The stroke is ~36 wide over the upper left and the top,
# narrows round the top right to ~21, then tapers evenly down the
# right-hand side to a point; at the star it ends full width, cut along the
# star's arm with a gap (crescent_cut).
CRESCENT = [(516.800, 272.000), (523.088, 261.691), (529.769, 251.634), (536.882, 241.876),
            (544.379, 232.411), (552.180, 223.194), (560.214, 214.179), (568.452, 205.351),
            (576.919, 196.741), (585.696, 188.450), (594.924, 180.665), (604.780, 173.698),
            (615.413, 167.996), (626.830, 164.116), (638.789, 162.629), (650.759, 163.966),
            (662.013, 168.254), (671.822, 175.241), (679.658, 184.393), (685.284, 195.053),
            (688.750, 206.603), (690.309, 218.567), (690.322, 230.636), (689.166, 242.653),
            (687.173, 254.561), (684.587, 266.355), (681.535, 278.038), (678.043, 289.597),
            (674.077, 301.001), (669.582, 312.208), (664.525, 323.172), (658.925, 333.869),
            (652.848, 344.303), (646.381, 354.500), (639.615, 364.502), (632.625, 374.348),
            (625.453, 384.063), (618.106, 393.646), (610.554, 403.069), (602.734, 412.269),
            (594.838, 421.177), (586.719, 429.889), (578.600, 438.600)]
# stroke width against the fraction of the way along, from the first point
CRESCENT_WIDTH = [(0.00, 36.17), (0.05, 35.44), (0.10, 35.41), (0.15, 35.61), (0.20, 35.55), (0.25, 34.75),
                  (0.30, 32.73), (0.35, 29.30), (0.40, 25.41), (0.45, 22.14), (0.50, 20.00), (0.55, 18.39),
                  (0.60, 16.32), (0.65, 14.05), (0.70, 12.00), (0.75, 10.10), (0.80, 8.13), (0.85, 5.94),
                  (0.90, 3.71), (0.95, 1.65), (1.00, 0.00)]
# Star, fitted to the first photo as a regular interlaced pentagram: centre,
# radius to the bands' centrelines, band width and tilt (clockwise, as the
# crescent is traced, so the two keep their places on the jet).
STAR_C, STAR_R, STAR_ROT = (489.0, 367.4), 69.7, 3.1
STAR_W, STAR_GAP = 0.15 * STAR_R, 0.04 * STAR_R


def crescent_polygon(k, ox, oy, n=1500, ext=70.0):
    """Outline of the stroke, run on past its star end so that the cut
    (crescent_cut) ends it there."""
    import numpy as np
    from scipy.interpolate import make_interp_spline, splev, splprep
    c = np.array(CRESCENT, float)
    t0 = c[0] - c[1]
    t0 /= np.linalg.norm(t0)
    c = np.vstack([c[0] + t0 * ext, c])
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(c, axis=0).T))]
    tck, _ = splprep(c.T, u=s / s[-1], s=0, k=3)
    u = np.linspace(0, 1, n)
    x, y = splev(u, tck)
    dx, dy = splev(u, tck, der=1)
    L = np.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    s0 = ext / s[-1]
    f = np.clip((u - s0) / (1 - s0), 0, 1)
    hw = make_interp_spline(*zip(*CRESCENT_WIDTH), k=3)(f) / 2
    left = [((a + b * h) * k + ox, (c_ + d * h) * k + oy) for a, b, c_, d, h in zip(x, nx, y, ny, hw)]
    right = [((a - b * h) * k + ox, (c_ - d * h) * k + oy) for a, b, c_, d, h in zip(x, nx, y, ny, hw)]
    return left + right[::-1]


def crescent_cut(k, ox, oy, big=2000.0):
    """Half-plane on the stroke's side of the cut at the star: parallel to the
    star's arm from its top point, clear of it by the weave's gap (the photo
    shows the same ~1.5 px of white there)."""
    sx, sy = STAR_C
    V = [(sx + STAR_R * math.sin(math.radians(72 * i + STAR_ROT)),
          sy - STAR_R * math.cos(math.radians(72 * i + STAR_ROT))) for i in (0, 2)]
    dx, dy = V[1][0] - V[0][0], V[1][1] - V[0][1]
    L = math.hypot(dx, dy)
    dx, dy = dx / L, dy / L
    nx, ny = -dy, dx
    bx, by = CRESCENT[2]
    if (bx - V[0][0]) * nx + (by - V[0][1]) * ny < 0:
        nx, ny = -nx, -ny
    off = STAR_W / 2 + STAR_GAP
    cx, cy = V[0][0] + nx * off, V[0][1] + ny * off
    p1, p2 = (cx - dx * big, cy - dy * big), (cx + dx * big, cy + dy * big)
    quad = [p1, p2, (p2[0] + nx * big, p2[1] + ny * big), (p1[0] + nx * big, p1[1] + ny * big)]
    return [(x * k + ox, y * k + oy) for x, y in quad]


def line_intersect(p1, p2, p3, p4):
    d = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0])
    t = ((p1[0] - p3[0]) * (p3[1] - p4[1]) - (p1[1] - p3[1]) * (p3[0] - p4[0])) / d
    return (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1])), t


def band(p1, p2, hw, ext=10.0):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = -uy * hw, ux * hw
    a = (p1[0] - ux * L * ext, p1[1] - uy * L * ext)
    b = (p2[0] + ux * L * ext, p2[1] + uy * L * ext)
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def mask_poly(size, poly):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return m


def woven_star(size, cx, cy, R, w, gap, rot=0.0):
    """Interlaced pentagram mask: sharp mitred tips, alternating over/under;
    rot turns it clockwise, in degrees."""
    V = [(cx + R * math.sin(math.radians(72 * i + rot)), cy - R * math.cos(math.radians(72 * i + rot)))
         for i in range(5)]
    path = [0, 2, 4, 1, 3]
    lines = [(V[path[i]], V[path[(i + 1) % 5]]) for i in range(5)]

    # outline: the pentagram whose edges are the lines pushed out by w/2
    s = (R * math.cos(math.radians(72)) + w / 2) / (R * math.cos(math.radians(72)))
    r_in = R * math.sin(math.radians(18)) / math.sin(math.radians(54))
    outline = []
    for i in range(5):
        a = math.radians(72 * i + rot)
        outline.append((cx + R * s * math.sin(a), cy - R * s * math.cos(a)))
        a2 = math.radians(72 * i + 36 + rot)
        outline.append((cx + r_in * s * math.sin(a2), cy - r_in * s * math.cos(a2)))
    clip = mask_poly(size, outline)

    strips = Image.new("L", size, 0)
    for p1, p2 in lines:
        strips = ImageChops.lighter(strips, mask_poly(size, band(p1, p2, w / 2)))

    # crossings in traversal order, alternating over / under
    events = []
    for i in range(5):
        hits = []
        for j in range(5):
            if j in (i, (i + 1) % 5, (i - 1) % 5):
                continue
            P, t = line_intersect(*lines[i], *lines[j])
            hits.append((t, j, P))
        for t, j, P in sorted(hits):
            events.append((i, j, P))
    over = {}
    for n, (i, j, P) in enumerate(events):
        key = frozenset((i, j))
        if n % 2 == 0:
            over[key] = (i, P)
    for key, (i, P) in over.items():
        disk = Image.new("L", size, 0)
        rr = w * 1.6
        ImageDraw.Draw(disk).ellipse((P[0] - rr, P[1] - rr, P[0] + rr, P[1] + rr), fill=255)
        p1, p2 = lines[i]
        cut = ImageChops.multiply(mask_poly(size, band(p1, p2, w / 2 + gap)), disk)
        keep = ImageChops.multiply(mask_poly(size, band(p1, p2, w / 2)), disk)
        strips = ImageChops.subtract(strips, cut)
        strips = ImageChops.lighter(strips, keep)
    return ImageChops.multiply(strips, clip)


def tail_logo(size=4096):
    S = size * SS
    # crop-space bbox of the logo ~ x 398..712, y 140..447
    k = S * 0.86 / 314
    ox = S / 2 - 555 * k
    oy = S / 2 - 293 * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    red = Image.new("RGBA", (S, S), RED + (255,))
    green = Image.new("RGBA", (S, S), STAR_GREEN + (255,))
    img.paste(red, mask=ImageChops.multiply(mask_poly((S, S), crescent_polygon(k, ox, oy)),
                                            mask_poly((S, S), crescent_cut(k, ox, oy))))
    star = woven_star((S, S), STAR_C[0] * k + ox, STAR_C[1] * k + oy, STAR_R * k,
                      STAR_W * k, STAR_GAP * k, STAR_ROT)
    img.paste(green, mask=star)
    return img.resize((size, size), Image.LANCZOS)


def text_layer(text, font_path, px, fill, direction=None, pad=0.15):
    font = ImageFont.truetype(font_path, px * SS)
    tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    bbox = tmp.textbbox((0, 0), text, font=font, direction=direction)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    p = int(h * pad)
    img = Image.new("RGBA", (w + 2 * p, h + 2 * p), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((p - bbox[0], p - bbox[1]), text, font=font,
                             fill=tuple(fill) + (255,), direction=direction)
    return img.resize((img.width // SS, img.height // SS), Image.LANCZOS)


def words_layer(words, font_path, px, fill, gap=0.16):
    """Words set with a tighter space than the font's own, as on the jet,
    aligned on a common baseline."""
    font = ImageFont.truetype(font_path, px)
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tops = [probe.textbbox((0, 0), w, font=font)[1] for w in words]
    parts = [text_layer(w, font_path, px, fill, pad=0) for w in words]
    t0 = min(tops)
    space = int(px * gap)
    W = sum(p.width for p in parts) + space * (len(parts) - 1)
    H = max(t - t0 + p.height for t, p in zip(tops, parts))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = 0
    for t, p in zip(tops, parts):
        img.alpha_composite(p, (x, t - t0))
        x += p.width + space
    return img


def build(out, fonts):
    tail_logo().save(f"{out}/ram_tail_logo_4k.png")
    words_layer(["Royal", "Air", "Maroc"], f"{fonts}/outfit-latin-600-normal.woff", 600,
                RED).save(f"{out}/ram_title_en.png")
    text_layer("الخطوط الملكية المغربية", f"{fonts}/aref-ruqaa-arabic-700-normal.woff",
               600, RED, direction="rtl", pad=0).save(f"{out}/ram_title_ar.png")
    text_layer("CN-RGO", f"{fonts}/outfit-latin-600-normal.woff", 300, REG_RED,
               pad=0).save(f"{out}/ram_reg.png")


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2])
    print("ok")
