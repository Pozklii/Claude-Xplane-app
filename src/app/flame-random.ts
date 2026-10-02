// Randomly generated fractal flames for the landing page, in the style of
// the three hand-picked ones (flame-params.ts): built from the same kinds
// of transforms and variations, in a palette of two related hues on a near
// black ground, framed close so the veils sweep past the edges. Everything
// follows from a seed, so the server can pick one per visit, the browser
// rebuilds the same flame from it, and a favourite can be found again.
//
// Random flames are often duds (a speck, a thin line, a smear of fog), so
// each candidate is test-rendered on a small grid first and rejected unless
// its shape is spread out and varied; the first good one is used.

import type { FlameParams, FlameTransform, Variation } from "./flame-params";

type Rgb = [number, number, number];

// The variations the candidates draw from (all supported by flame-gl.ts).
const POOL: Variation[] = [
  "linear",
  "spherical",
  "julia",
  "swirl",
  "bubble",
  "eyefish",
  "handkerchief",
  "disc",
  "polar",
  "sinusoidal",
  "horseshoe",
  "spiral",
  "hyperbolic",
];
const FINALS: Variation[] = [
  "spherical",
  "julia",
  "bubble",
  "eyefish",
  "swirl",
];
const MAX_TRIES = 40;
// The stills' framing: they're 2400x1500, shown with background-size: cover.
const ASPECT = 1.6;

/** A small, fast, seedable random number generator (mulberry32). */
function seeded(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hsl(h: number, s: number, l: number): Rgb {
  const hue = ((h % 360) + 360) % 360;
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = l - c / 2;
  const [r, g, b] =
    hue < 60
      ? [c, x, 0]
      : hue < 120
        ? [x, c, 0]
        : hue < 180
          ? [0, c, x]
          : hue < 240
            ? [0, x, c]
            : hue < 300
              ? [x, 0, c]
              : [c, 0, x];
  return [
    Math.round((r + m) * 255),
    Math.round((g + m) * 255),
    Math.round((b + m) * 255),
  ];
}

/** A generated flame's colours: its palette (as the hand-picked ones have
 * it: deep, then vivid, a pale bridge, the second hue, a bright accent),
 * its dark ground, how much the page dims it, and colours for the motes.
 * Cheap, so the server can use it to paint the page before the flame. */
export function generatedPalette(seed: number) {
  const rnd = seeded(seed ^ 0x9e3779b9);
  // The main hue: teal round through blue, violet and pink to red (a dark
  // yellow or green base comes out olive).
  const h1 = 160 + rnd() * 185;
  const dir = rnd() < 0.5 ? -1 : 1;
  const spread = 70 + rnd() * 90;
  const h2 = h1 + dir * spread;
  const h3 = h2 + dir * (25 + rnd() * 50);
  const palette: [number, Rgb][] = [
    [0, hsl(h1, 0.5 + rnd() * 0.15, 0.28)],
    [0.35, hsl(h1, 0.62 + rnd() * 0.15, 0.58)],
    [0.6, hsl(h1 + dir * spread * 0.5, 0.45, 0.76)],
    [0.85, hsl(h2, 0.75 + rnd() * 0.15, 0.6)],
    [1, hsl(h3, 0.85, 0.72)],
  ];
  const bg = hsl(h1 + dir * spread * 0.3, 0.45, 0.06 + rnd() * 0.03);
  const motes = [hsl(h1, 0.9, 0.78), hsl(h2, 0.9, 0.75), hsl(h3, 0.9, 0.8)].map(
    (c) => c.join(","),
  );
  return { palette, bg, motes, dim: 0.62 + rnd() * 0.1 };
}

// The variations, as in flame-gl.ts (and the renderer the stills came
// from), by index into VARS; each writes its result to vx, vy (no
// allocation, since the chaos game calls these millions of times).
const VARS: Variation[] = [...POOL];
let vx = 0;
let vy = 0;
function vary(k: number, x: number, y: number, rnd: () => number) {
  const r2 = x * x + y * y + 1e-9;
  const r = Math.sqrt(r2);
  switch (VARS[k]) {
    case "linear":
      vx = x;
      vy = y;
      return;
    case "sinusoidal":
      vx = Math.sin(x);
      vy = Math.sin(y);
      return;
    case "spherical":
      vx = x / r2;
      vy = y / r2;
      return;
    case "swirl": {
      const s = Math.sin(r2);
      const c = Math.cos(r2);
      vx = x * s - y * c;
      vy = x * c + y * s;
      return;
    }
    case "horseshoe":
      vx = ((x - y) * (x + y)) / r;
      vy = (2 * x * y) / r;
      return;
    case "bubble": {
      const f = 4 / (r2 + 4);
      vx = f * x;
      vy = f * y;
      return;
    }
    case "eyefish": {
      const f = 2 / (r + 1);
      vx = f * x;
      vy = f * y;
      return;
    }
  }
  const th = Math.atan2(x, y);
  switch (VARS[k]) {
    case "polar":
      vx = th / Math.PI;
      vy = r - 1;
      return;
    case "handkerchief":
      vx = r * Math.sin(th + r);
      vy = r * Math.cos(th - r);
      return;
    case "disc":
      vx = (th / Math.PI) * Math.sin(Math.PI * r);
      vy = (th / Math.PI) * Math.cos(Math.PI * r);
      return;
    case "spiral":
      vx = (Math.cos(th) + Math.sin(r)) / r;
      vy = (Math.sin(th) - Math.cos(r)) / r;
      return;
    case "hyperbolic":
      vx = Math.sin(th) / r;
      vy = r * Math.cos(th);
      return;
    case "julia": {
      const sr = Math.sqrt(r);
      const om = rnd() < 0.5 ? 0 : Math.PI;
      vx = sr * Math.cos(th / 2 + om);
      vy = sr * Math.sin(th / 2 + om);
      return;
    }
  }
}

// A transform's variations as parallel index/weight arrays, for the loop.
function compile(variations: Partial<Record<Variation, number>>) {
  const entries = Object.entries(variations) as [Variation, number][];
  return {
    ks: entries.map(([name]) => VARS.indexOf(name)),
    ws: entries.map(([, w]) => w),
  };
}

type Shape = Pick<FlameParams, "xforms" | "final">;

function randomShape(rnd: () => number): Shape {
  const n = [2, 2, 3, 3, 4][Math.floor(rnd() * 5)];
  const xforms: FlameTransform[] = [];
  for (let i = 0; i < n; i++) {
    const ang = rnd() * Math.PI * 2;
    const sc = 0.4 + rnd() * 0.7;
    const sk = rnd() * 0.8 - 0.4;
    let b = -sc * Math.sin(ang) + sk;
    let e = sc * Math.cos(ang);
    if (rnd() < 0.5) {
      b = -b;
      e = -e;
    }
    const count = [1, 2, 2, 3][Math.floor(rnd() * 4)];
    const names = [...POOL].sort(() => rnd() - 0.5).slice(0, count);
    const weights = names.map(() => 0.2 + rnd() * 0.8);
    const total = weights.reduce((s, w) => s + w, 0);
    xforms.push({
      affine: [
        sc * Math.cos(ang),
        b,
        rnd() * 2 - 1,
        sc * Math.sin(ang),
        e,
        rnd() * 2 - 1,
      ],
      variations: Object.fromEntries(
        names.map((name, k) => [name, weights[k] / total]),
      ),
      color: i / Math.max(1, n - 1),
      weight: 0.3 + rnd() * 0.7,
    });
  }
  const final =
    rnd() < 0.4
      ? { variations: { [FINALS[Math.floor(rnd() * FINALS.length)]]: 1 } }
      : null;
  return { xforms, final };
}

/** Runs the chaos game on the CPU: `walkers` points, each taken through
 * `iterations` random transforms, recording where they land (x, y, colour
 * index) after the first few. Points that escape are restarted. */
function chaos(
  shape: Shape,
  walkers: number,
  iterations: number,
  rnd: () => number,
) {
  const skip = 10;
  const out = new Float32Array(walkers * (iterations - skip) * 3);
  const cum: number[] = [];
  const total = shape.xforms.reduce((s, x) => s + x.weight, 0);
  let acc = 0;
  for (const x of shape.xforms) cum.push((acc += x.weight / total));
  const xfs = shape.xforms.map((xf) => ({
    ...compile(xf.variations),
    a: xf.affine,
    color: xf.color,
  }));
  const fin = shape.final ? compile(shape.final.variations) : null;
  let n = 0;
  let escaped = 0;
  for (let w = 0; w < walkers; w++) {
    let x = rnd() * 2 - 1;
    let y = rnd() * 2 - 1;
    let c = rnd();
    for (let it = 0; it < iterations; it++) {
      const u = rnd();
      let i = 0;
      while (i < cum.length - 1 && u > cum[i]) i++;
      const xf = xfs[i];
      const af = xf.a;
      const tx = af[0] * x + af[1] * y + af[2];
      const ty = af[3] * x + af[4] * y + af[5];
      let nx = 0;
      let ny = 0;
      for (let v = 0; v < xf.ks.length; v++) {
        vary(xf.ks[v], tx, ty, rnd);
        nx += xf.ws[v] * vx;
        ny += xf.ws[v] * vy;
      }
      x = nx;
      y = ny;
      c = (c + xf.color) / 2;
      if (!Number.isFinite(x) || !Number.isFinite(y) || x * x + y * y > 1e12) {
        escaped++;
        x = rnd() * 2 - 1;
        y = rnd() * 2 - 1;
        continue;
      }
      if (it < skip) continue;
      let px = x;
      let py = y;
      if (fin) {
        px = 0;
        py = 0;
        for (let v = 0; v < fin.ks.length; v++) {
          vary(fin.ks[v], x, y, rnd);
          px += fin.ws[v] * vx;
          py += fin.ws[v] * vy;
        }
        if (!Number.isFinite(px) || !Number.isFinite(py)) continue;
      }
      out[n++] = px;
      out[n++] = py;
      out[n++] = c;
    }
  }
  return {
    points: out.subarray(0, n),
    escapedShare: escaped / (walkers * iterations),
  };
}

function percentile(sorted: Float32Array, p: number) {
  return sorted[
    Math.min(sorted.length - 1, Math.max(0, Math.floor(sorted.length * p)))
  ];
}

/** Frames a shape like the hand-picked flames, and judges it: a camera
 * zoomed so the middle of the flame fills the screen, or null if the shape
 * is a dud. */
function frame(shape: Shape, rnd: () => number) {
  const { points, escapedShare } = chaos(shape, 1400, 30, rnd);
  if (escapedShare > 0.2 || points.length < 3 * 1400 * 20 * 0.7) return null;
  const rotate = rnd() * 360;
  const rad = (rotate * Math.PI) / 180;
  const cs = Math.cos(rad);
  const sn = Math.sin(rad);
  const count = points.length / 3;
  const qx = new Float32Array(count);
  const qy = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const x = points[i * 3];
    const y = points[i * 3 + 1];
    qx[i] = x * cs - y * sn;
    qy[i] = x * sn + y * cs;
  }
  const sx = Float32Array.from(qx).sort();
  const sy = Float32Array.from(qy).sort();
  const x0 = percentile(sx, 0.05);
  const x1 = percentile(sx, 0.95);
  const y0 = percentile(sy, 0.05);
  const y1 = percentile(sy, 0.95);
  const halfW = (x1 - x0) / 2;
  const halfH = (y1 - y0) / 2;
  if (
    !(halfW > 1e-3 && halfH > 1e-3) ||
    halfW / halfH > 10 ||
    halfH / halfW > 10
  )
    return null;
  const cqx = (x0 + x1) / 2;
  const cqy = (y0 + y1) / 2;
  const zoom = 1.15 + rnd() * 0.35;
  // Clip x = (rotated x - centre) * scale / 2; fill the frame with the box.
  const scale = (2 / Math.max(halfW, halfH * ASPECT)) * zoom;

  // Judge it on a coarse grid of the framed view: enough of the screen
  // covered, the density varied (structure, not fog), and not all in a
  // few cells (a speck).
  const GW = 64;
  const GH = 40;
  const grid = new Float32Array(GW * GH);
  let inside = 0;
  for (let i = 0; i < count; i++) {
    const cx = ((qx[i] - cqx) * scale) / 2;
    const cy = ((qy[i] - cqy) * scale * ASPECT) / 2;
    const gx = Math.floor((cx * 0.5 + 0.5) * GW);
    const gy = Math.floor((cy * 0.5 + 0.5) * GH);
    if (gx < 0 || gx >= GW || gy < 0 || gy >= GH) continue;
    grid[gy * GW + gx]++;
    inside++;
  }
  const lit = Array.from(grid)
    .filter((v) => v > 0)
    .sort((a, b) => b - a);
  const coverage = lit.length / grid.length;
  const top = lit
    .slice(0, Math.max(1, Math.floor(grid.length * 0.02)))
    .reduce((s, v) => s + v, 0);
  const concentration = top / Math.max(1, inside);
  const logs = lit.map((v) => Math.log1p(v));
  const mean = logs.reduce((s, v) => s + v, 0) / Math.max(1, logs.length);
  const spread = Math.sqrt(
    logs.reduce((s, v) => s + (v - mean) ** 2, 0) / Math.max(1, logs.length),
  );
  // How much of the lit area is near the brightest: high for solid,
  // filled-in shapes rather than veils.
  const p98 = Math.log1p(lit[Math.floor(lit.length * 0.02)] ?? 0);
  const fill =
    logs.filter((v) => v > 0.7 * p98).length / Math.max(1, logs.length);
  if (coverage < 0.45 || concentration > 0.3 || spread < 0.8 || fill > 0.45)
    return null;

  // The camera centre, back in the flame's own (unrotated) coordinates.
  const center: [number, number] = [cqx * cs + cqy * sn, -cqx * sn + cqy * cs];
  return { scale, rotate, center };
}

/** The flame for a seed: the first random shape that passes, framed, in
 * the seed's palette. Deterministic; costs a few to a few dozen
 * milliseconds, so it runs in the browser rather than on every request. */
export function generateFlame(seed: number): FlameParams {
  const rnd = seeded(seed);
  const { palette, bg, dim } = generatedPalette(seed);
  for (let attempt = 0; attempt < MAX_TRIES; attempt++) {
    const shape = randomShape(rnd);
    const camera = frame(shape, rnd);
    if (camera) return { ...shape, ...camera, palette, bg, dim };
  }
  // Practically never reached; a simple, known-good spherical swirl.
  return {
    xforms: [
      {
        affine: [0.6, -0.4, 0.3, 0.4, 0.6, -0.2],
        variations: { spherical: 0.6, swirl: 0.4 },
        color: 0,
        weight: 1,
      },
      {
        affine: [-0.5, 0.3, -0.4, 0.5, 0.7, 0.3],
        variations: { julia: 1 },
        color: 1,
        weight: 0.8,
      },
    ],
    final: null,
    scale: 1.2,
    rotate: 0,
    center: [0, 0],
    palette,
    bg,
    dim,
  };
}

/** Renders a still of a flame on the CPU, tone-mapped like flame-gl.ts:
 * the page's first paint for a generated flame, and all there is where
 * the live one can't run. Returns RGBA pixels, `width` x `height`. */
export function renderFlameStill(
  flame: FlameParams,
  width: number,
  height: number,
  walkers = 12000,
) {
  const rnd = seeded(7);
  const { points } = chaos(flame, walkers, 60, rnd);
  const rad = (flame.rotate * Math.PI) / 180;
  const cs = Math.cos(rad);
  const sn = Math.sin(rad);
  const [cx0, cy0] = flame.center ?? [0, 0];
  const effW = Math.max(width, height * ASPECT);
  const kx = ((flame.scale / 2) * (effW / width) * width) / 2;
  const ky = ((flame.scale / 2) * (effW / height) * height) / 2;
  const stops = flame.palette;
  const lut = new Float32Array(256 * 3);
  for (let q = 0; q < 256; q++) {
    const t = q / 255;
    let c = stops[0][1];
    for (let i = 1; i < stops.length; i++) {
      const [a, ca] = stops[i - 1];
      const [b, cb] = stops[i];
      if (t >= a) {
        const k = Math.min(1, Math.max(0, (t - a) / Math.max(b - a, 1e-5)));
        c = [
          ca[0] + (cb[0] - ca[0]) * k,
          ca[1] + (cb[1] - ca[1]) * k,
          ca[2] + (cb[2] - ca[2]) * k,
        ];
      }
    }
    lut.set(c, q * 3);
  }
  const dens = new Float32Array(width * height);
  const rgb = new Float32Array(width * height * 3);
  for (let i = 0; i < points.length; i += 3) {
    const dx = points[i] - cx0;
    const dy = points[i + 1] - cy0;
    const px = Math.floor((dx * cs - dy * sn) * kx + width / 2);
    const py = Math.floor((dx * sn + dy * cs) * ky + height / 2);
    if (px < 0 || px >= width || py < 0 || py >= height) continue;
    const j = py * width + px;
    const q = Math.min(255, Math.max(0, Math.floor(points[i + 2] * 255))) * 3;
    dens[j]++;
    rgb[j * 3] += lut[q];
    rgb[j * 3 + 1] += lut[q + 1];
    rgb[j * 3 + 2] += lut[q + 2];
  }
  // A light 3x3 blur, then the stills' tone curve.
  const blur = (src: Float32Array, stride: number) => {
    const dst = new Float32Array(src.length);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        for (let k = 0; k < stride; k++) {
          let sum = 0;
          let wsum = 0;
          for (let oy = -1; oy <= 1; oy++) {
            for (let ox = -1; ox <= 1; ox++) {
              const xx = x + ox;
              const yy = y + oy;
              if (xx < 0 || xx >= width || yy < 0 || yy >= height) continue;
              const w = ox === 0 && oy === 0 ? 4 : ox === 0 || oy === 0 ? 2 : 1;
              sum += src[(yy * width + xx) * stride + k] * w;
              wsum += w;
            }
          }
          dst[(y * width + x) * stride + k] = sum / wsum;
        }
      }
    }
    return dst;
  };
  const d = blur(dens, 1);
  const c = blur(rgb, 3);
  const lit = Array.from(d)
    .filter((v) => v > 0)
    .map((v) => Math.log1p(v))
    .sort((a, b) => a - b);
  const ref = lit.length
    ? lit[Math.floor(lit.length * 0.999) - 1] || lit[lit.length - 1]
    : 1;
  const out = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const j = y * width + x;
      const alpha = Math.min(1, Math.log1p(d[j]) / ref);
      const ga = 0.85 * Math.pow(alpha, 1 / 1.5);
      const vx = (x / width - 0.5) * 2;
      const vy = (y / height - 0.5) * 2;
      const vig = (1 - (0.45 * (vx * vx + vy * vy)) / 2) * flame.dim;
      for (let k = 0; k < 3; k++) {
        const avg = d[j] > 0 ? c[j * 3 + k] / d[j] : 0;
        out[j * 4 + k] = (avg * ga + flame.bg[k] * (1 - ga)) * vig;
      }
      out[j * 4 + 3] = 255;
    }
  }
  return out;
}
