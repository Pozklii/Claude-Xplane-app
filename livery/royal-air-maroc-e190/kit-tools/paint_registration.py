"""REGISTRATION.png for the X-Crafts E-Jets: the cockpit registration
placard and the registration under the left wing, CN-RGO.

The kit's registration sheet (2048 px) holds a cockpit placard, a few
placards for the wheels and wing walk, and four wing slots: the lower and
upper surface of each wing (without the flaps and ailerons, which are
separate parts), root on the left, tip on the right, leading edge at the
top. Its examples (OE-LWD) are swapped for CN-RGO:
- cockpit placard: white, at the size and place of the kit's example;
- under the left wing only (the jet has none under the right wing, nor on
  top): black, reading root to tip with the letters' tops to the leading
  edge, as on the jet. Measured off a photo from below, the letters stand
  0.45 of the local chord (leading edge to flap line), centred on it, and
  the registration ends just short of the tip, about a fifth of its own
  length in from it (the kit's example stands 0.47 of the chord).
Lettering in the fuselage registration's face (Barlow), a weight bolder.

usage: paint_registration.py <REGISTRATION psd> <fonts dir> <out png>
"""
import sys, warnings
warnings.filterwarnings('ignore')
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from psd_tools import PSDImage

psd_path, FONTS, OUT = sys.argv[1:4]
REG = 'CN-RGO'
FONT = f'{FONTS}/barlow-latin-600-normal.woff'

# bottom-left wing slot, fitted to the kit's wireframe (texture px):
LE = (0.06924, 1141.6)          # leading edge  y = a x + b
TE = (-0.05370, 1595.7)         # flap line     y = a x + b
TIP_X = 2029.0                   # the tip rib, at mid chord
CHORD_FRAC, TIP_GAP = 0.45, 0.18
# cockpit placard: the kit's example lettering (cap height 74 px, centred)
PLACARD_C, PLACARD_CAP = (800.0, 87.0), 74.0


def reg_layer(text, font_path, px, tracking=0.03, dash=0.40, ss=4):
    """White-on-transparent lettering as in paint_fus.reg_layer: slightly
    letter-spaced, a long thin dash about a letter wide, cropped to the ink.
    Returns (alpha image, cap height in its px)."""
    font = ImageFont.truetype(font_path, px * ss)
    probe = ImageDraw.Draw(Image.new('L', (1, 1)))
    _, cap_top, _, base = probe.textbbox((0, 0), 'H', font=font)
    bar = 0.12 * (base - cap_top)
    W = int(sum(font.getlength(c) for c in text) + len(text) * (tracking + dash) * px * ss) + 4 * px
    img = Image.new('L', (W, int(px * ss * 1.6)), 0)
    d = ImageDraw.Draw(img)
    x = px * ss * 0.2
    for i, ch in enumerate(text):
        if ch == '-':
            mid = (cap_top + base) / 2
            d.rectangle([x, mid - bar / 2, x + dash * px * ss, mid + bar / 2], fill=255)
            x += dash * px * ss
        else:
            bb = probe.textbbox((0, 0), ch, font=font)
            d.text((x - bb[0], 0), ch, font=font, fill=255)
            x += bb[2] - bb[0]
        if i < len(text) - 1:
            x += tracking * px * ss
    ys, xs = np.nonzero(np.asarray(img) > 8)
    img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return img, (base - cap_top), ss


def stamp(canvas, text_img, cap_px, ss, cx, cy, cap, colour):
    """Put the lettering on the canvas centred at (cx, cy), cap height cap."""
    k = cap / (cap_px / 1.0)
    w, h = max(1, round(text_img.width * k)), max(1, round(text_img.height * k))
    a = text_img.resize((w, h), Image.LANCZOS)
    layer = Image.new('RGBA', a.size, tuple(colour) + (0,))
    layer.putalpha(a)
    canvas.alpha_composite(layer, (round(cx - w / 2), round(cy - h / 2)))
    return w, h


psd = PSDImage.open(psd_path)
show = {'BASE': True, 'COCKPIT REGISTRATION': True, 'WING REGISTRATION': False,
        'WING POSITIONS': False, 'WIREFRAME': False}
for l in psd:
    l.visible = show.get(l.name, l.visible)
for l in next(g for g in psd if g.name == 'COCKPIT REGISTRATION'):
    l.visible = l.kind != 'type'                     # keep the frame, drop the examples
sheet = psd.composite(force=True).convert('RGBA')

text, cap_px, ss = reg_layer(REG, FONT, 300)
aspect = text.width / cap_px                         # length per cap height

# cockpit placard
stamp(sheet, text, cap_px, ss, *PLACARD_C, PLACARD_CAP, (255, 255, 255))

# under the left wing: solve for the place where the lettering's cap height
# is CHORD_FRAC of the chord at its centre and its end sits TIP_GAP of its
# length in from the tip
chord = lambda x: (TE[0] - LE[0]) * x + (TE[1] - LE[1])
xc = 1650.0
for _ in range(50):
    cap = CHORD_FRAC * chord(xc)
    length = aspect * cap
    xc = TIP_X - TIP_GAP * length - length / 2
cy = ((LE[0] + TE[0]) * xc + LE[1] + TE[1]) / 2       # on the chord's mid line
w, h = stamp(sheet, text, cap_px, ss, xc, cy, cap, (16, 16, 18))
print(f'wing: {REG} centred at ({xc:.0f}, {cy:.0f}), cap height {cap:.0f} px '
      f'(chord {chord(xc):.0f}), {w} px long, ends {TIP_X - xc - w / 2:.0f} px from the tip')
sheet.save(OUT)
print('saved', OUT, sheet.size)
