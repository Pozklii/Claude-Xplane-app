// The landing page's three fractal flames (see flame-gl.ts), exactly as
// pre-rendered into public/sky/flame-*.webp: each transform's affine
// coefficients [a, b, c, d, e, f] (x' = a·x + b·y + c, y' = d·x + e·y + f)
// and its blend of variations, plus the camera, palette, dark ground and
// how much the page dims it. Generated from the renderer's parameters.

export const VARIATIONS = [
  "swirl",
  "horseshoe",
  "polar",
  "handkerchief",
  "spiral",
  "hyperbolic",
  "julia",
  "bubble",
  "eyefish",
] as const;
export type Variation = (typeof VARIATIONS)[number];

export type FlameTransform = {
  affine: [number, number, number, number, number, number];
  variations: Partial<Record<Variation, number>>;
  color: number;
  weight: number;
};

export type FlameParams = {
  xforms: FlameTransform[];
  final: { variations: Partial<Record<Variation, number>> } | null;
  scale: number;
  rotate: number;
  palette: [number, [number, number, number]][];
  bg: [number, number, number];
  dim: number;
};

export const FLAME_PARAMS: Record<"veil" | "ember" | "vortex", FlameParams> = {
  veil: {
    xforms: [
      {
        affine: [0.05508, -1.38435, -0.70816, -0.98794, -0.05508, 0.86258],
        variations: { hyperbolic: 0.50184, handkerchief: 0.49816 },
        color: 0.0,
        weight: 0.6637,
      },
      {
        affine: [-0.44911, -1.03388, 0.72754, 0.69312, -0.44911, -0.18045],
        variations: { eyefish: 0.54486, polar: 0.45514 },
        color: 0.3333,
        weight: 0.3728,
      },
      {
        affine: [0.48353, 1.16403, 0.52618, 0.77801, -0.48353, -0.02708],
        variations: { bubble: 0.52348, swirl: 0.47652 },
        color: 0.6667,
        weight: 0.8001,
      },
      {
        affine: [0.17842, -0.8768, -0.4819, -0.6112, -0.17842, -0.82122],
        variations: { eyefish: 1.0 },
        color: 1.0,
        weight: 0.6219,
      },
    ],
    final: { variations: { swirl: 1.0 } },
    scale: 0.71012,
    rotate: 47.576,
    palette: [
      [0, [90, 40, 90]],
      [0.35, [205, 85, 145]],
      [0.6, [160, 175, 230]],
      [0.85, [70, 160, 255]],
      [1, [170, 255, 120]],
    ],
    bg: [30, 22, 36],
    dim: 0.72,
  },
  ember: {
    xforms: [
      {
        affine: [0.29529, -0.42063, 0.73211, -0.30832, -0.29529, 0.52123],
        variations: { swirl: 0.75341, handkerchief: 0.24659 },
        color: 0.0,
        weight: 0.4671,
      },
      {
        affine: [0.48414, -0.21082, -0.06083, -0.26144, -0.48414, -0.4303],
        variations: { horseshoe: 0.67321, handkerchief: 0.32679 },
        color: 0.5,
        weight: 0.3108,
      },
      {
        affine: [-0.97638, -0.1192, 0.94307, 0.33806, -0.97638, -0.22668],
        variations: { swirl: 0.57536, julia: 0.42464 },
        color: 1.0,
        weight: 0.6126,
      },
    ],
    final: null,
    scale: 1.64097,
    rotate: 100.037,
    palette: [
      [0, [20, 60, 150]],
      [0.3, [60, 160, 230]],
      [0.55, [240, 205, 120]],
      [0.8, [240, 120, 40]],
      [1, [255, 240, 190]],
    ],
    bg: [14, 18, 38],
    dim: 0.5,
  },
  vortex: {
    xforms: [
      {
        affine: [0.59578, -1.14668, 0.64041, 0.89035, 0.59578, -0.65598],
        variations: { spiral: 0.19995, swirl: 0.80005 },
        color: 0.0,
        weight: 0.6464,
      },
      {
        affine: [0.00144, -0.9771, -0.23945, -1.01714, -0.00144, -0.48162],
        variations: { swirl: 0.27339, polar: 0.72661 },
        color: 0.5,
        weight: 0.877,
      },
      {
        affine: [-0.15369, -0.75281, -0.87963, -0.63678, 0.15369, 0.51939],
        variations: { polar: 1.0 },
        color: 1.0,
        weight: 0.8179,
      },
    ],
    final: { variations: { bubble: 1.0 } },
    scale: 1.46801,
    rotate: 71.974,
    palette: [
      [0, [45, 55, 130]],
      [0.4, [85, 115, 225]],
      [0.7, [60, 205, 195]],
      [1, [95, 235, 145]],
    ],
    bg: [8, 10, 24],
    dim: 0.66,
  },
};
