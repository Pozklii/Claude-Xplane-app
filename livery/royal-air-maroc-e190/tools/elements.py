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


# Crescent centreline (x, y, stroke width) in tail-crop pixels.
CRESCENT = [(509, 324, 0), (511, 292, 20), (520, 262, 26), (536, 236, 31),
            (565, 195, 36), (600, 167, 33), (640, 156, 27), (672, 166, 24),
            (690, 197, 22), (694, 240, 21), (688, 290, 20), (675, 330, 18),
            (655, 366, 15), (630, 399, 12), (605, 423, 8), (577, 441, 0)]
STAR_C, STAR_R = (487, 370), 85
STAR_W, STAR_GAP = 0.16 * 85, 0.04 * 85


def _resample(pts, n):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    out, j = [], 0
    for i in range(n):
        t = d[-1] * i / (n - 1)
        while j < len(d) - 2 and d[j + 1] < t:
            j += 1
        f = (t - d[j]) / ((d[j + 1] - d[j]) or 1)
        out.append((pts[j][0] + f * (pts[j + 1][0] - pts[j][0]),
                    pts[j][1] + f * (pts[j + 1][1] - pts[j][1])))
    return out


def crescent_width(u):
    """Thin pointed start at the star, fattest over the upper left, then a
    long taper down the right-hand side to a point."""
    peak, wmax = 0.16, 37.0
    if u < peak:
        return wmax * math.sin(math.pi / 2 * u / peak) ** 0.6
    return wmax * max(0.0, 1 - (u - peak) / (1 - peak)) ** 0.85


def crescent_polygon(k, ox, oy, n=1200):
    pts = _resample(catmull_rom([(x, y) for x, y, _ in CRESCENT], 30), n)
    win = 130
    sm = []
    for i in range(n):
        a, b = max(0, i - win), min(n, i + win + 1)
        # shrink the window at the ends so the endpoints stay put
        h = min(i - a, b - 1 - i)
        seg = pts[i - h:i + h + 1]
        sm.append((sum(p[0] for p in seg) / len(seg), sum(p[1] for p in seg) / len(seg)))
    left, right = [], []
    for i, (x, y) in enumerate(sm):
        p, q = sm[max(i - 2, 0)], sm[min(i + 2, n - 1)]
        dx, dy = q[0] - p[0], q[1] - p[1]
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        hw = crescent_width(i / (n - 1)) / 2
        left.append(((x + nx * hw) * k + ox, (y + ny * hw) * k + oy))
        right.append(((x - nx * hw) * k + ox, (y - ny * hw) * k + oy))
    return left + right[::-1]


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


def woven_star(size, cx, cy, R, w, gap):
    """Interlaced pentagram mask: sharp mitred tips, alternating over/under."""
    V = [(cx + R * math.sin(math.radians(72 * i)), cy - R * math.cos(math.radians(72 * i)))
         for i in range(5)]
    path = [0, 2, 4, 1, 3]
    lines = [(V[path[i]], V[path[(i + 1) % 5]]) for i in range(5)]

    # outline: the pentagram whose edges are the lines pushed out by w/2
    s = (R * math.cos(math.radians(72)) + w / 2) / (R * math.cos(math.radians(72)))
    r_in = R * math.sin(math.radians(18)) / math.sin(math.radians(54))
    outline = []
    for i in range(5):
        a = math.radians(72 * i)
        outline.append((cx + R * s * math.sin(a), cy - R * s * math.cos(a)))
        a2 = math.radians(72 * i + 36)
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
    img.paste(red, mask=mask_poly((S, S), crescent_polygon(k, ox, oy)))
    star = woven_star((S, S), STAR_C[0] * k + ox, STAR_C[1] * k + oy, STAR_R * k,
                      STAR_W * k, STAR_GAP * k)
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
