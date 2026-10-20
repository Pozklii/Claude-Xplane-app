"""final 8K = kit base (upscaled 2x) multiplied by the 8K paint, with the base's alpha.

usage: combine.py <base 4k png> <paint 8k png> <out png>

The kit's alpha is a hair under opaque (254, rarely 240-253) along its panel
lines, access panels and rivets, and in a dither over the forward belly and
nose-gear doors. X-Plane draws those texels apart from the opaque ones, so
they showed as grey circles and lines on the fin and grey speckle on the gear
doors. They are made fully opaque; real transparency (under 240) is kept.
"""
import sys
import numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
base = Image.open(sys.argv[1]).convert('RGBA').resize((8192, 8192), Image.LANCZOS)
paint = Image.open(sys.argv[2]).convert('RGB')
out = np.empty((8192, 8192, 4), np.uint8)
B = np.asarray(base)
P = np.asarray(paint)
for r in range(0, 8192, 1024):
    b = B[r:r + 1024].astype(np.float32)
    p = P[r:r + 1024].astype(np.float32) / 255
    out[r:r + 1024, :, :3] = np.clip(b[..., :3] * p + 0.5, 0, 255).astype(np.uint8)
    a = B[r:r + 1024, :, 3]
    out[r:r + 1024, :, 3] = np.where(a >= 240, 255, a)
Image.fromarray(out, 'RGBA').save(sys.argv[3], compress_level=6)
print('saved', sys.argv[3])
