"""final 8K = kit base (upscaled 2x) multiplied by the 8K paint; base alpha kept.

usage: combine.py <base 4k png> <paint 8k png> <out png>
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
    out[r:r + 1024, :, 3] = B[r:r + 1024, :, 3]
Image.fromarray(out, 'RGBA').save(sys.argv[3], compress_level=6)
print('saved', sys.argv[3])
