"""Render an 8K left-side profile of the Royal Air Maroc E190 design.

usage: profile.py <elements dir> <out png> [width]
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image, ImageChops, ImageDraw

import geometry as G

ELEM, OUT = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 8192
SS = 2
X0, X1, Y0 = 8, 1882, 232
s = W / (X1 - X0)                      # canvas px per photo px
H = int(round((708 - Y0) * s / 64)) * 64
SW, SH, ss = W * SS, H * SS, s * SS


def P(pts):
    return [((x - X0) * ss, (y - Y0) * ss) for x, y in pts]


def mask(poly):
    m = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(m).polygon(P(poly), fill=255)
    return m


def fill(img, colour, m):
    img.paste(Image.new("RGBA", img.size, tuple(colour) + (255,)), mask=m)


TOP, BOT = Y0 - 50, 760
sil = mask(G.catmull_rom(G.SILHOUETTE, 8))
img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
fill(img, G.WHITE, sil)

b1 = G.catmull_rom(G.B1)
b2 = G.catmull_rom(G.B2)
b3 = G.catmull_rom(G.B3)
b4b3 = G.catmull_rom(G.B4 + G.B3[4:])
b5 = G.catmull_rom(G.B5)
fin = G.catmull_rom(G.FIN_RED)

# painter's order, each region clipped to the silhouette
layers = [
    (G.LIGHT_GREEN, b1 + [(1950, BOT), (1950, TOP), (b1[0][0], TOP)]),
    (G.DARK_GREEN, b3 + [(1750, BOT), (1400, BOT)] + b2[::-1]),
    (G.WHITE, b4b3 + [(1750, BOT), (1950, BOT), (1950, TOP), (b4b3[0][0], TOP)]),
    (G.RED, b5 + [(1950, b5[-1][1]), (1950, TOP), (b5[0][0], TOP)]),
    (G.WHITE, fin + [(1950, TOP), (fin[0][0], TOP)]),
]
for colour, poly in layers:
    fill(img, colour, ImageChops.multiply(mask(poly), sil))

# metallic tail cone
cap = ImageChops.multiply(mask([(G.TAIL_CAP_X, 552), (1950, 552), (1950, BOT),
                                (G.TAIL_CAP_X, BOT)]), sil)
fill(img, (120, 122, 126), cap)

d = ImageDraw.Draw(img)
line = max(2, int(0.9 * ss))


def rrect(box, slope, r, **kw):
    x0, y0, x1, y1 = box
    # a rounded rectangle sheared to follow the fuselage slope
    pts = []
    import math
    corners = [(x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)]
    for cx, cy, a0 in corners:
        for k in range(0, 91, 10):
            a = math.radians(a0 + k)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    xm = (x0 + x1) / 2
    pts = [(x, y + slope * (x - xm)) for x, y in pts]
    d.polygon(P(pts), **kw)


# doors: thin panel lines
for box, slope in G.DOORS:
    rrect(box, slope, 4, outline=(60, 60, 60, 110), width=line)
# windows
ww, wh = G.WINDOW_SIZE
for x in G.WINDOW_X:
    y = G.window_y(x)
    rrect((x - ww / 2, y - wh / 2, x + ww / 2, y + wh / 2), 0.0, 5,
          fill=(38, 44, 54, 255), outline=(150, 150, 150, 255), width=line)
for poly in G.COCKPIT:
    d.polygon(P(poly), fill=(30, 38, 48, 255))
# small Moroccan flag by the cockpit
fx0, fy0, fx1, fy1 = G.FLAG
d.rectangle(P([(fx0, fy0), (fx1, fy1)]), fill=(193, 39, 45, 255))

def place(name, center, width, angle, height=None):
    art = Image.open(os.path.join(ELEM, name)).convert("RGBA")
    tw = int(width * ss)
    th = int(height * ss) if height else int(art.height * tw / art.width)
    art = art.resize((tw, th), Image.LANCZOS).rotate(-angle, resample=Image.BICUBIC, expand=True)
    cx, cy = (center[0] - X0) * ss, (center[1] - Y0) * ss
    img.alpha_composite(art, (int(cx - art.width / 2), int(cy - art.height / 2)))


place("ram_title_en.png", G.TITLE_EN["center"], G.TITLE_EN["width"], G.TITLE_EN["angle"])
place("ram_title_ar.png", G.TITLE_AR["center"], G.TITLE_AR["width"], G.TITLE_AR["angle"],
      G.TITLE_AR["height"])
place("ram_reg.png", G.REG["center"], G.REG["width"], G.REG["angle"])
logo = Image.open(os.path.join(ELEM, "ram_tail_logo_4k.png"))
lw = int(G.LOGO["size"] * ss)
logo = logo.resize((lw, lw), Image.LANCZOS)
# keep the logo on the fin
logo_layer = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
lx, ly = (G.LOGO["center"][0] - X0) * ss - lw / 2, (G.LOGO["center"][1] - Y0) * ss - lw / 2
logo_layer.alpha_composite(logo, (int(lx), int(ly)))
la = ImageChops.multiply(logo_layer.getchannel("A"), sil)
logo_layer.putalpha(la)
img.alpha_composite(logo_layer)

img = img.resize((W, H), Image.LANCZOS)

# soft cylinder shading so the flat paint reads as a fuselage
a = np.asarray(img).astype(np.float32)
alpha = a[..., 3] > 8
shade = np.ones(alpha.shape, np.float32)
xs = np.arange(W) / s + X0
crown = np.interp(xs, *zip(*[(x, y) for x, y in G.SILHOUETTE[:30]]))
belly_pts = sorted([(x, y) for x, y in G.SILHOUETTE[50:]])
belly = np.interp(xs, *zip(*belly_pts))
ys = (np.arange(H)[:, None] / s + Y0)
v = (ys - crown[None, :]) / np.maximum(belly - crown, 1)[None, :]
v = np.clip(v, 0, 1)
shade = 1.04 - 0.22 * np.clip(v - 0.55, 0, 1) ** 1.4 - 0.05 * np.clip(0.15 - v, 0, 1) / 0.15
a[..., :3] *= shade[..., None]
img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
img.save(OUT)
print("saved", OUT, img.size)
