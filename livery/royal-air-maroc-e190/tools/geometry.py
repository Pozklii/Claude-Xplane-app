"""Royal Air Maroc E190 livery geometry, traced from the reference photo.

All coordinates are reference-photo pixels (2000x1144, left side view).
Nose tip ~ (20, 531), tail-cone end ~ (1870, 585).
"""
import math

RED = (200, 16, 46)
DARK_GREEN = (0, 112, 74)
LIGHT_GREEN = (93, 178, 58)
STAR_GREEN = (0, 105, 80)
WHITE = (244, 244, 242)
REG_RED = (150, 10, 35)

# Fuselage + fin outline, clockwise from the nose tip.
SILHOUETTE = [
    (20, 531), (30, 513), (40, 505), (50, 497), (60, 491), (70, 485), (80, 479),
    (90, 473), (100, 467), (110, 462), (130, 450), (150, 438), (175, 425),
    (200, 417), (250, 412), (300, 411), (350, 414), (400, 418), (450, 422),
    (500, 428), (600, 437), (700, 446), (800, 454), (900, 461), (1000, 468),
    (1100, 477), (1200, 485), (1300, 493), (1400, 503), (1440, 507),
    # dorsal fillet and fin leading edge
    (1500, 499), (1550, 482), (1590, 464), (1600, 457), (1650, 402),
    (1700, 345), (1750, 289), (1768, 273), (1782, 265), (1798, 262),
    # fin tip and trailing edge
    (1845, 265), (1838, 300), (1825, 360), (1810, 420), (1795, 480), (1783, 540),
    # tail cone
    (1800, 549), (1830, 561), (1855, 569), (1868, 576), (1871, 588), (1858, 597),
    # belly back to the nose
    (1800, 613), (1750, 622), (1700, 629), (1650, 637), (1600, 645), (1550, 654),
    (1500, 661), (1450, 667), (1400, 671), (1300, 675), (1200, 671), (1100, 668),
    (1000, 664), (900, 655), (800, 645), (700, 632), (600, 620), (500, 612),
    (400, 604), (300, 597), (200, 588), (150, 579), (110, 572), (100, 570),
    (90, 568), (80, 565), (70, 562), (60, 559), (50, 555), (40, 551), (30, 545),
    (20, 535),
]

# Colour boundaries, each running from above the crown down past the belly.
# B1: front edge of the light green band.
B1 = [(840, 452), (880, 465), (920, 480), (960, 494), (1000, 509), (1040, 526),
      (1120, 563), (1200, 602), (1240, 620), (1280, 639), (1320, 658), (1380, 688)]
# Dark green wedge: apex just under the crown, upper edge B3, lower edge B2.
APEX = (938, 470)
B3 = [APEX, (960, 473.5), (1000, 478.5), (1040, 482.5), (1080, 494),
      (1160, 522), (1240, 550), (1280, 566.5), (1320, 583), (1360, 596),
      (1400, 608), (1440, 620), (1480, 628.5), (1520, 633), (1540, 634.5),
      (1556, 635.5), (1600, 645), (1700, 690)]
B2 = [APEX, (960, 477.5), (1000, 490.5), (1040, 505.5), (1080, 520),
      (1120, 540), (1160, 561), (1200, 582.5), (1240, 603.5), (1280, 623.5),
      (1320, 644), (1360, 665), (1420, 696)]
# The light green reaches the crown until the thin white stripe takes over.
B4 = [(1018, 462), (1030, 476), (1040, 482.5)]
# B5: front/lower edge of the red. Behind the rear door it runs flat back
# over a white belly strip that tapers out under the tail cone at ~1735;
# from there the red wraps the whole cone back to the APU (both photos).
B5 = [(1062, 466), (1080, 485), (1160, 510), (1240, 532), (1280, 546),
      (1320, 568.5), (1360, 580), (1400, 591), (1440, 601), (1480, 609),
      (1520, 614), (1560, 618), (1600, 620), (1640, 621.5), (1680, 622.5),
      (1710, 623.5), (1735, 626)]
# White fin over the red: the curve from the fin root up to the trailing edge.
FIN_RED = [(1410, 504), (1440, 509), (1480, 514), (1520, 521), (1560, 527),
           (1600, 533), (1640, 537), (1660, 533), (1680, 524), (1700, 515),
           (1720, 503), (1740, 489), (1760, 471), (1780, 449), (1800, 422),
           # runs straight on into the trailing edge, meeting it in a sharp
           # point just below the star's top point (0.12 of the star's height
           # below it in the eye-level photo, 0.24 in photo 1), and only turns
           # out once past the edge, so the red can't run on up it
           (1806, 413), (1812, 404), (1818, 395), (1824, 386), (1838, 381), (1870, 379)]
TAIL_CAP_X = 1840            # metallic APU exhaust behind this

# Cabin windows: centres along the window line, ~14 x 16 px.
WINDOW_X = [394.5, 436, 477.5, 519, 560, 602, 643.5, 684, 725, 766.5, 809,
            858.5, 902, 947, 991, 1030.5, 1070, 1115.8, 1161.6, 1207.4,
            1253.2, 1299, 1339, 1379.5, 1420]
_WY = [(394.5, 469), (1030.5, 520.5), (1339, 547), (1420, 554.5)]


def window_y(x):
    for (x0, y0), (x1, y1) in zip(_WY, _WY[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return _WY[-1][1]


WINDOW_SIZE = (14, 16)
# Doors (x0, y0, x1, y1) and the slope of the fuselage at each.
DOORS = [((288, 416, 345, 522), 0.03), ((846, 487, 871, 534), 0.07),
         ((1452, 516, 1500, 616), 0.06)]
COCKPIT = [[(102, 463), (128, 447), (166, 435), (178, 435), (161, 458)],
           [(172, 436), (214, 436), (216, 461), (168, 460)]]

# Titles and marks: centre, width (photo px, unrotated), slope in degrees.
TITLE_EN = dict(center=(555, 507), width=262, angle=4.2)
TITLE_AR = dict(center=(597, 452), width=348, height=41, angle=3.8)
REG = dict(center=(1547, 569), width=68, angle=4.0)
# Tail logo canvas (4096 px) is centred here, at this many photo px across.
LOGO = dict(center=(1727.5, 396.5), size=182.5)
# The flag's red field, about half the width of the L1 door behind it.
FLAG = (252.5, 432.5, 276.5, 445.5)


def catmull_rom(pts, samples=24):
    if len(pts) < 3:
        return list(pts)
    out = []
    p = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t +
                                    (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 +
                                    (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                             for k in range(len(p1))))
    out.append(tuple(pts[-1]))
    return out


# ---- reference lines for surface detail ----------------------------------

# Fuselage crown without the fin (under the fin it follows the fin root).
CROWN = SILHOUETTE[:30] + [(1500, 516), (1560, 526), (1640, 536), (1720, 543),
                           (1783, 548), (1800, 549), (1830, 561), (1855, 569),
                           (1868, 576)]
BELLY = sorted(SILHOUETTE[SILHOUETTE.index((1858, 597)) + 1:]) + [(1858, 597)]


def _interp(pts, x):
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / ((x1 - x0) or 1)
    return pts[-1][1]


def crown(x):
    return _interp(CROWN, x)


def belly(x):
    return _interp(BELLY, x)


def axis(x):
    """The window line, extended along the fuselage axis at both ends."""
    if x < _WY[0][0]:
        return _WY[0][1] + 0.08 * (x - _WY[0][0])
    if x > _WY[-1][0]:
        return _WY[-1][1] + 0.08 * (x - _WY[-1][0])
    return window_y(x)


# Circumferential butt joints: major section breaks, then lighter frames.
JOINTS_MAJOR = [240, 560, 830, 1110, 1250, 1450, 1640, 1790]
JOINTS_MINOR = [400, 700, 975, 1350, 1545, 1715]
RADOME = [(93, 470), (86, 490), (80, 512), (76, 535), (74, 562)]
# Longitudinal lap joints, as offsets from the window line.
LAPS = [-38, -13, 13, 50, 90]
FAIRING = [(790, 641), (850, 629), (1000, 622), (1200, 627), (1350, 640),
           (1470, 663)]

# Small items: (x, y) on the skin.
STATIC_PORTS = [(232, 506), (232, 516)]
PROBES = [(88, 486, 3.0, 2.0), (104, 515, 2.6, 1.8), (88, 532, 2.6, 1.8)]
AOA_VANE = (117, 488)
# Blade antennas on the crown: (x, length, height); negative height = belly.
ANTENNAS = [(372, 5, 4), (408, 5, 4), (508, 13, 14), (1232, 10, 10),
            (1440, 8, 8), (460, 8, -7), (1060, 10, -8)]
BEACONS = [(450, 1), (650, -1)]        # x, +1 on top / -1 under the belly
DOOR_FITTINGS = {                      # viewport (x, y) and handle (x, y)
    0: ((316, 440), (333, 466)),
    2: ((1476, 540), (1492, 566)),
}
EXIT_HANDLE = (866, 495)
ACCESS_PANELS = [(395, 586, 425, 597), (700, 600, 722, 611), (1560, 626, 1586, 637)]
# Fin: rudder hinge line, rudder bottom and split, static dischargers.
RUDDER_HINGE = [(1824, 268), (1742, 532)]
RUDDER_SPLIT_Y = 400
FIN_TE = [(1845, 265), (1783, 540)]
FIN_LE = [(1592, 463), (1782, 265)]
DISCHARGERS = [(1845, 271), (1832, 340), (1818, 410), (1806, 470)]
EMBRAER_190 = dict(center=(199, 476), width=46)
