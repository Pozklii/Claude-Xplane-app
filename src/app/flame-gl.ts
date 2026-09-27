// A live fractal flame for the landing page's background: the same chaos
// game the backgrounds were pre-rendered with (see flame-params.ts), run on
// the GPU every frame, with each transform slowly swaying so the veils curl
// and morph. WebGL2, no dependencies.
//
// Each frame, every point (one per vertex, no buffers) starts somewhere
// random and is run through ITERATIONS randomly chosen transforms, landing
// on the flame; it's then drawn as a single pixel, added into a float
// density/colour buffer. That buffer fades a little each frame instead of
// clearing, so it holds several frames' worth of points: enough to be
// smooth, and a soft motion trail as the flame changes. A last pass
// tone-maps it the way the stills were (log density, gamma, the dark
// ground, a vignette, the page's dimming).

import { VARIATIONS, type FlameParams } from "./flame-params";

const MAX_XFORMS = 4;
const NV = VARIATIONS.length;
const ITERATIONS = 18;
// How much of the buffer survives each frame.
const DECAY = 0.93;
// The buffer's resolution relative to the canvas's CSS size: the flame is
// soft, so a lower one spends the points on density rather than pixels.
const RESOLUTION = 0.6;
const MAX_WIDTH = 1400;
// The stills are 2400x1500, shown with background-size: cover; the live
// flame frames itself the same way.
const STILL_ASPECT = 1.6;

const POINTS_VS = `#version 300 es
precision highp float;
precision highp int;

uniform uint uSeed;
uniform int uCount;
uniform vec3 uRowA[${MAX_XFORMS}];
uniform vec3 uRowB[${MAX_XFORMS}];
uniform float uVar[${MAX_XFORMS * NV}];
uniform float uColor[${MAX_XFORMS}];
uniform float uCum[${MAX_XFORMS}];
uniform float uFinal[${NV}];
uniform bool uHasFinal;
uniform vec2 uCenter;
uniform float uRot;
uniform vec2 uClipScale;
uniform vec3 uPalette[5];
uniform float uPalettePos[5];

out vec3 vColor;

uint hash(uint x) {
  x ^= x >> 16u; x *= 0x7feb352du;
  x ^= x >> 15u; x *= 0x846ca68bu;
  x ^= x >> 16u;
  return x;
}
float rand(inout uint s) {
  s = hash(s);
  return float(s >> 8u) / 16777216.0;
}

vec2 variation(int k, vec2 p, inout uint s) {
  float r2 = dot(p, p) + 1e-9;
  float r = sqrt(r2);
  float th = atan(p.x, p.y);
  if (k == 0) { float sn = sin(r2), cs = cos(r2); return vec2(p.x * sn - p.y * cs, p.x * cs + p.y * sn); } // swirl
  if (k == 1) return vec2((p.x - p.y) * (p.x + p.y) / r, 2.0 * p.x * p.y / r); // horseshoe
  if (k == 2) return vec2(th / 3.14159265, r - 1.0); // polar
  if (k == 3) return r * vec2(sin(th + r), cos(th - r)); // handkerchief
  if (k == 4) return vec2(cos(th) + sin(r), sin(th) - cos(r)) / r; // spiral
  if (k == 5) return vec2(sin(th) / r, r * cos(th)); // hyperbolic
  if (k == 6) { float om = rand(s) < 0.5 ? 0.0 : 3.14159265; return sqrt(r) * vec2(cos(th / 2.0 + om), sin(th / 2.0 + om)); } // julia
  if (k == 7) return p * (4.0 / (r2 + 4.0)); // bubble
  return p * (2.0 / (r + 1.0)); // eyefish
}

vec3 palette(float t) {
  vec3 c = uPalette[0];
  for (int i = 1; i < 5; i++) {
    float a = uPalettePos[i - 1], b = uPalettePos[i];
    if (t >= a) c = mix(uPalette[i - 1], uPalette[i], clamp((t - a) / max(b - a, 1e-5), 0.0, 1.0));
  }
  return c;
}

void main() {
  uint s = hash(uint(gl_VertexID) * 747796405u + uSeed);
  vec2 p = vec2(rand(s), rand(s)) * 2.0 - 1.0;
  float c = rand(s);
  for (int it = 0; it < ${ITERATIONS}; it++) {
    float u = rand(s);
    int i = 0;
    for (int j = 0; j < ${MAX_XFORMS - 1}; j++) {
      if (j < uCount - 1 && u > uCum[j]) i = j + 1;
    }
    vec2 t = vec2(dot(uRowA[i], vec3(p, 1.0)), dot(uRowB[i], vec3(p, 1.0)));
    vec2 q = vec2(0.0);
    for (int k = 0; k < ${NV}; k++) {
      float w = uVar[i * ${NV} + k];
      if (w != 0.0) q += w * variation(k, t, s);
    }
    p = q;
    c = (c + uColor[i]) * 0.5;
    if (any(isnan(p)) || any(isinf(p)) || dot(p, p) > 1e12) p = vec2(rand(s), rand(s)) * 2.0 - 1.0;
  }
  vec2 f = p;
  if (uHasFinal) {
    vec2 q = vec2(0.0);
    for (int k = 0; k < ${NV}; k++) {
      if (uFinal[k] != 0.0) q += uFinal[k] * variation(k, p, s);
    }
    f = q;
  }
  vec2 d = f - uCenter;
  vec2 sc = vec2(d.x * cos(uRot) - d.y * sin(uRot), d.x * sin(uRot) + d.y * cos(uRot));
  gl_Position = vec4(sc.x * uClipScale.x, -sc.y * uClipScale.y, 0.0, 1.0);
  gl_PointSize = 1.0;
  vColor = palette(c);
}`;

const POINTS_FS = `#version 300 es
precision highp float;
in vec3 vColor;
out vec4 outColor;
void main() { outColor = vec4(vColor, 1.0); }`;

const QUAD_VS = `#version 300 es
out vec2 vUv;
void main() {
  vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
  vUv = p * 0.5 + 0.5;
  gl_Position = vec4(p, 0.0, 1.0);
}`;

const FADE_FS = `#version 300 es
precision highp float;
uniform sampler2D uPrev;
uniform float uDecay;
in vec2 vUv;
out vec4 outColor;
void main() { outColor = texture(uPrev, vUv) * uDecay; }`;

// Log density into an 8-bit channel, sampled small, for finding the
// exposure on the CPU.
const PROBE_FS = `#version 300 es
precision highp float;
uniform sampler2D uAcc;
in vec2 vUv;
out vec4 outColor;
void main() { outColor = vec4(log(1.0 + texture(uAcc, vUv).a) / 16.0, 0.0, 0.0, 1.0); }`;

const TONE_FS = `#version 300 es
precision highp float;
uniform sampler2D uAcc;
uniform float uRefLog;
uniform vec3 uBg;
uniform float uDim;
uniform vec2 uTexel;
uniform bool uBlur;
in vec2 vUv;
out vec4 outColor;
void main() {
  // A light 3x3 blur, like the stills' density-estimation blur (skipped
  // when sharp).
  vec4 a = vec4(0.0);
  if (uBlur) {
    for (int y = -1; y <= 1; y++)
      for (int x = -1; x <= 1; x++)
        a += texture(uAcc, vUv + vec2(x, y) * uTexel) * (x == 0 && y == 0 ? 0.25 : (x == 0 || y == 0 ? 0.125 : 0.0625));
  } else {
    a = texture(uAcc, vUv);
  }
  float dens = a.a;
  vec3 avg = dens > 0.0 ? a.rgb / dens : vec3(0.0);
  float alpha = clamp(log(1.0 + dens) / max(uRefLog, 1e-3), 0.0, 1.0);
  float ga = 0.85 * pow(alpha, 1.0 / 1.5);
  vec3 rgb = avg * ga + uBg * (1.0 - ga);
  vec2 v = (vUv - 0.5) * 2.0;
  rgb *= 1.0 - 0.45 * dot(v, v) / 2.0;
  outColor = vec4(rgb * uDim, 1.0);
}`;

function compile(gl: WebGL2RenderingContext, vs: string, fs: string) {
  const program = gl.createProgram();
  for (const [type, src] of [
    [gl.VERTEX_SHADER, vs],
    [gl.FRAGMENT_SHADER, fs],
  ] as const) {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("shader");
    gl.shaderSource(shader, src);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader) ?? "compile");
    }
    gl.attachShader(program, shader);
  }
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(program) ?? "link");
  }
  return program;
}

/**
 * Starts the live flame on `canvas`. Calls `onReady` once it has built up
 * enough to show, and `onFail` if it can't run here (no WebGL2 or float
 * buffers, or it's too slow), in which case the page keeps its still.
 * Returns a cleanup function.
 */
export function startFlame(
  canvas: HTMLCanvasElement,
  flame: FlameParams,
  {
    onReady,
    onFail,
    sharp = false,
  }: {
    onReady: () => void;
    onFail: () => void;
    /** Crisper: full resolution (up to the screen's pixel density), more
     * points, no blur and a shorter trail; costs more. */
    sharp?: boolean;
  },
): () => void {
  const gl = canvas.getContext("webgl2", {
    alpha: false,
    antialias: false,
    depth: false,
    powerPreference: "low-power",
  });
  if (!gl || !gl.getExtension("EXT_color_buffer_float")) {
    onFail();
    return () => {};
  }

  let points: WebGLProgram,
    fade: WebGLProgram,
    probe: WebGLProgram,
    tone: WebGLProgram;
  try {
    points = compile(gl, POINTS_VS, POINTS_FS);
    fade = compile(gl, QUAD_VS, FADE_FS);
    probe = compile(gl, QUAD_VS, PROBE_FS);
    tone = compile(gl, QUAD_VS, TONE_FS);
  } catch (error) {
    if (process.env.NODE_ENV !== "production")
      console.warn("Live flame shaders failed:", error);
    onFail();
    return () => {};
  }
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);

  const loc = (p: WebGLProgram, name: string) => gl.getUniformLocation(p, name);

  // The flame's fixed uniforms.
  gl.useProgram(points);
  const n = Math.min(MAX_XFORMS, flame.xforms.length);
  const total = flame.xforms.slice(0, n).reduce((sum, x) => sum + x.weight, 0);
  let cum = 0;
  const cums: number[] = [];
  const vars: number[] = [];
  for (let i = 0; i < MAX_XFORMS; i++) {
    const x = flame.xforms[i];
    cum += x && i < n ? x.weight / total : 0;
    cums.push(cum);
    for (const v of VARIATIONS) vars.push(x?.variations[v] ?? 0);
  }
  gl.uniform1i(loc(points, "uCount"), n);
  gl.uniform1fv(loc(points, "uCum"), cums);
  gl.uniform1fv(loc(points, "uVar"), vars);
  gl.uniform1fv(
    loc(points, "uColor"),
    Array.from({ length: MAX_XFORMS }, (_, i) => flame.xforms[i]?.color ?? 0),
  );
  gl.uniform1i(loc(points, "uHasFinal"), flame.final ? 1 : 0);
  gl.uniform1fv(
    loc(points, "uFinal"),
    VARIATIONS.map((v) => flame.final?.variations[v] ?? 0),
  );
  gl.uniform3fv(
    loc(points, "uPalette"),
    flame.palette.flatMap(([, rgb]) => rgb.map((c) => c / 255)),
  );
  gl.uniform1fv(
    loc(points, "uPalettePos"),
    flame.palette.map(([pos]) => pos),
  );
  gl.uniform2f(loc(points, "uCenter"), 0, 0);
  gl.useProgram(tone);
  gl.uniform3f(
    loc(tone, "uBg"),
    flame.bg[0] / 255,
    flame.bg[1] / 255,
    flame.bg[2] / 255,
  );
  gl.uniform1f(loc(tone, "uDim"), flame.dim);
  gl.uniform1i(loc(tone, "uBlur"), sharp ? 0 : 1);
  const resolution = sharp
    ? Math.min(1.5, window.devicePixelRatio || 1)
    : RESOLUTION;
  const maxWidth = sharp ? 2600 : MAX_WIDTH;
  const decay = sharp ? 0.9 : DECAY;

  // Two float accumulation buffers, ping-ponged, and a small probe buffer.
  let W = 0;
  let H = 0;
  let count = 0;
  const targets = [0, 1].map(() => ({
    tex: gl.createTexture(),
    fb: gl.createFramebuffer(),
  }));
  const probeTarget = { tex: gl.createTexture(), fb: gl.createFramebuffer() };
  const PROBE_W = 128;
  const PROBE_H = 80;
  const probePixels = new Uint8Array(PROBE_W * PROBE_H * 4);
  const setup = (
    t: { tex: WebGLTexture; fb: WebGLFramebuffer },
    w: number,
    h: number,
    float: boolean,
  ) => {
    gl.bindTexture(gl.TEXTURE_2D, t.tex);
    if (float)
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA16F,
        w,
        h,
        0,
        gl.RGBA,
        gl.HALF_FLOAT,
        null,
      );
    else
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA8,
        w,
        h,
        0,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        null,
      );
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
    gl.framebufferTexture2D(
      gl.FRAMEBUFFER,
      gl.COLOR_ATTACHMENT0,
      gl.TEXTURE_2D,
      t.tex,
      0,
    );
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
  };
  setup(probeTarget, PROBE_W, PROBE_H, false);

  const resize = () => {
    const cssW = canvas.clientWidth;
    const cssH = canvas.clientHeight;
    const scale = Math.min(resolution, maxWidth / Math.max(1, cssW));
    const w = Math.max(64, Math.round(cssW * scale));
    const h = Math.max(64, Math.round(cssH * scale));
    if (w === W && h === H) return;
    W = w;
    H = h;
    canvas.width = W;
    canvas.height = H;
    for (const t of targets) setup(t, W, H, true);
    // Points per frame scale with the area, within bounds that keep
    // phones light.
    count = sharp
      ? Math.round(Math.min(900_000, Math.max(150_000, W * H * 0.5)))
      : Math.round(Math.min(360_000, Math.max(90_000, W * H * 0.55)));
    // Frame it like the still: covering the canvas at the still's aspect.
    const effW = Math.max(W, H * STILL_ASPECT);
    gl.useProgram(points);
    gl.uniform2f(
      loc(points, "uClipScale"),
      (flame.scale / 2) * (effW / W),
      (flame.scale / 2) * (effW / H),
    );
    gl.useProgram(tone);
    gl.uniform2f(loc(tone, "uTexel"), 1 / W, 1 / H);
  };
  resize();
  const observer = new ResizeObserver(resize);
  observer.observe(canvas);

  // Each transform sways: its linear part turns back and forth and its
  // offset drifts, each at its own slow pace, starting from the still's
  // exact shape.
  const sway = flame.xforms.slice(0, n).map((_, i) => ({
    turnSpeed: (Math.PI * 2) / (26 + i * 9),
    turn: 0.26 + 0.04 * i,
    driftSpeed: (Math.PI * 2) / (37 + i * 7),
    drift: 0.13,
  }));
  const rowA = new Float32Array(MAX_XFORMS * 3);
  const rowB = new Float32Array(MAX_XFORMS * 3);

  let current = 0;
  let refLog = 0;
  let frames = 0;
  let ready = false;
  let seed = 1;
  let slowFrames = 0;
  let frame = 0;
  let last = 0;
  const start = performance.now();

  const render = (t: number) => {
    // Transforms at time t.
    for (let i = 0; i < n; i++) {
      const [a, b, c, d, e, f] = flame.xforms[i].affine;
      const s = sway[i];
      const ang = s.turn * Math.sin(t * s.turnSpeed);
      const cs = Math.cos(ang);
      const sn = Math.sin(ang);
      rowA.set(
        [
          a * cs - d * sn,
          b * cs - e * sn,
          c + s.drift * Math.sin(t * s.driftSpeed),
        ],
        i * 3,
      );
      rowB.set(
        [
          a * sn + d * cs,
          b * sn + e * cs,
          f + s.drift * Math.cos(t * s.driftSpeed * 0.8),
        ],
        i * 3,
      );
    }
    const prev = targets[current];
    const next = targets[1 - current];

    // Fade the previous frame into the next buffer...
    gl.bindFramebuffer(gl.FRAMEBUFFER, next.fb);
    gl.viewport(0, 0, W, H);
    gl.disable(gl.BLEND);
    gl.useProgram(fade);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, prev.tex);
    gl.uniform1i(loc(fade, "uPrev"), 0);
    gl.uniform1f(loc(fade, "uDecay"), decay);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    // ...then add this frame's points.
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE);
    gl.useProgram(points);
    gl.uniform3fv(loc(points, "uRowA"), rowA);
    gl.uniform3fv(loc(points, "uRowB"), rowB);
    gl.uniform1ui(loc(points, "uSeed"), (seed = (seed * 16807) % 2147483647));
    gl.uniform1f(
      loc(points, "uRot"),
      ((flame.rotate + 6 * Math.sin((t * Math.PI * 2) / 96)) * Math.PI) / 180,
    );
    gl.drawArrays(gl.POINTS, 0, count);
    gl.disable(gl.BLEND);
    current = 1 - current;

    // Every so often, measure the exposure: the 99.9th percentile of log
    // density over a sample of the lit pixels, as the stills used.
    if (frames % 20 === 0) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, probeTarget.fb);
      gl.viewport(0, 0, PROBE_W, PROBE_H);
      gl.useProgram(probe);
      gl.bindTexture(gl.TEXTURE_2D, next.tex);
      gl.uniform1i(loc(probe, "uAcc"), 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.readPixels(
        0,
        0,
        PROBE_W,
        PROBE_H,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        probePixels,
      );
      const lit: number[] = [];
      for (let i = 0; i < probePixels.length; i += 4)
        if (probePixels[i] > 0) lit.push(probePixels[i]);
      if (lit.length > 50) {
        lit.sort((x, y) => x - y);
        const measured = (lit[Math.floor(lit.length * 0.999) - 1] / 255) * 16;
        refLog = refLog ? refLog + (measured - refLog) * 0.35 : measured;
      }
    }

    // Tone-map to the screen.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, W, H);
    gl.useProgram(tone);
    gl.bindTexture(gl.TEXTURE_2D, next.tex);
    gl.uniform1i(loc(tone, "uAcc"), 0);
    gl.uniform1f(loc(tone, "uRefLog"), refLog || 1);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    frames++;
    // Built up enough to look like the still.
    if (!ready && frames > 40 && refLog) {
      ready = true;
      onReady();
    }
  };

  const tick = (now: number) => {
    frame = requestAnimationFrame(tick);
    // About 30 frames a second is plenty for something this slow.
    if (now - last < 30) return;
    const took = last ? now - last : 33;
    last = now;
    render((now - start) / 1000);
    // Give up (back to the still) if the device can't keep up.
    slowFrames = took > 90 ? slowFrames + 1 : Math.max(0, slowFrames - 1);
    if (slowFrames > 40) {
      stop();
      onFail();
    }
  };
  frame = requestAnimationFrame(tick);

  const onLost = (event: Event) => {
    event.preventDefault();
    stop();
    onFail();
  };
  canvas.addEventListener("webglcontextlost", onLost);

  function stop() {
    cancelAnimationFrame(frame);
    observer.disconnect();
    canvas.removeEventListener("webglcontextlost", onLost);
  }
  return stop;
}
