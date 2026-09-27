// The landing page hero's animation, drawn on a canvas covering the hero: a
// shaded low-poly gold turbofan draws itself in place, ring by ring from the
// intake back (a band of light sweeping along each ring as it appears), grows
// its fan, spools up, and sends near-straight exhaust lines off into the
// distance, converging on a vanishing point up towards the sun.
// Plain canvas 2D, no dependencies.
//
// The engine is centred on (and sized by) an anchor element positioned with
// CSS, so its place in the layout stays in the stylesheet.

type Vec3 = [number, number, number];

// A point of the engine (e), and for points that spin with the fan, their
// angle and radius about the axis.
type Anchor = {
  e: Vec3;
  a: number;
  r: number;
  spin: boolean;
  grow: boolean;
};

type Pose = {
  yaw: number;
  pitch: number;
  roll: number;
  pivot: number;
  dx: number;
  dy: number;
  scale: number;
  cam: number;
};

type Projected = { x: number; y: number; X: number; Y: number; Z: number };
type Placed = Projected & { m: number };
type LinePoint = [number, number, number]; // screen x, y and a depth fade

const TAU = Math.PI * 2;
const ease = (t: number) => t * t * (3 - 2 * t);
const clamp01 = (t: number) => Math.max(0, Math.min(1, t));
const mix = (a: number, b: number, t: number) => a + (b - a) * t;

// Gold edges and faces with amber exhaust lines — the golden-hour palette of
// the landing page.
const EDGE_RGB = "240,200,120";
const FACE_RGB = "236,196,104";
const LINE_RGB = "240,170,100";
const SPARK_RGB = "255,220,160";
const FAN_RGB = "255,210,140";
const GLOW_RGB = "255,200,120";

// ---- The engine: rings of N points, joined into a shaded shell ----
const N = 20;

function buildModel() {
  const A: Anchor[] = [];
  const E: [number, number, number][] = [];
  const F: [number, number, number, number, number][] = [];
  const ring = (n: number, r: number, z: number, { spin = false, grow = false } = {}) => {
    const start = A.length;
    for (let i = 0; i < n; i++) {
      const a = ((i + 0.5) / n) * TAU;
      A.push({ e: [Math.cos(a) * r, Math.sin(a) * r, z], a, r, spin, grow });
    }
    return start;
  };
  const ringEdges = (s: number, n: number, w: number) => {
    for (let i = 0; i < n; i++) E.push([s + i, s + ((i + 1) % n), w]);
  };
  const bandEdges = (a: number, b: number, n: number, w: number) => {
    for (let i = 0; i < n; i++) {
      E.push([a + i, b + i, w]);
      if (i % 2 === 0) E.push([a + i, b + ((i + 1) % n), w * 0.4]);
    }
  };
  const bandFaces = (a: number, b: number, n: number, gain = 1) => {
    for (let i = 0; i < n; i++) {
      F.push([a + i, a + ((i + 1) % n), b + ((i + 1) % n), b + i, gain]);
    }
  };

  // The nacelle's shell: five rings, joined by bands with shaded faces.
  const shellZ = [0.0, 0.25, 0.8, 1.35, 1.8];
  const shellR = [1.0, 1.06, 1.04, 0.92, 0.74];
  const shell = shellZ.map((z, k) => ring(N, shellR[k], z));
  shell.forEach((s) => ringEdges(s, N, 0.7));
  for (let k = 0; k < shell.length - 1; k++) {
    bandEdges(shell[k], shell[k + 1], N, 0.45);
    bandFaces(shell[k], shell[k + 1], N);
  }
  const intake = ring(N, 0.88, 0.07);
  ringEdges(intake, N, 0.55);
  bandEdges(intake, shell[0], N, 0.4);
  bandFaces(intake, shell[0], N, 1.2);
  const fanCase = ring(N, 0.86, 0.3);
  ringEdges(fanCase, N, 0.45);
  for (let i = 0; i < N; i += 5) E.push([fanCase + i, intake + i, 0.3]);
  const core = ring(10, 0.46, 1.98);
  ringEdges(core, 10, 0.5);
  const plugTip = A.length;
  A.push({ e: [0, 0, 2.45], a: 0, r: 0, spin: false, grow: false });
  for (let i = 0; i < 10; i++) {
    E.push([plugTip, core + i, 0.4]);
    F.push([plugTip, core + i, core + ((i + 1) % 10), plugTip, 0.9]);
  }

  // Spinner and fan: grown out of the fan's centre once the shell has formed.
  const spinBase = ring(8, 0.22, 0.3, { spin: true, grow: true });
  ringEdges(spinBase, 8, 0.5);
  const tip = A.length;
  A.push({ e: [0, 0, -0.12], a: 0, r: 0, spin: true, grow: true });
  for (let i = 0; i < 8; i++) {
    E.push([tip, spinBase + i, 0.5]);
    F.push([tip, spinBase + i, spinBase + ((i + 1) % 8), tip, 1.3]);
  }
  const BLADES = 16;
  const bladeEdges: [number, number][] = [];
  for (let b = 0; b < BLADES; b++) {
    const base = (b / BLADES) * TAU;
    const s = A.length;
    for (const [r, off, z] of [
      [0.24, 0, 0.3],
      [0.54, 0.17, 0.28],
      [0.83, 0.38, 0.26],
    ]) {
      A.push({
        e: [Math.cos(base + off) * r, Math.sin(base + off) * r, z],
        a: base + off,
        r,
        spin: true,
        grow: true,
      });
    }
    bladeEdges.push([s, s + 1], [s + 1, s + 2]);
  }
  return { A, E, F, bladeEdges };
}

// ---- Timeline (seconds) ----
const DRAW_AT = 0.4; // the intake ring starts drawing in here, the tail WAVE later
const WAVE = 1.0;
const DRAW = 0.9;
const GROW_AT = DRAW_AT + WAVE + DRAW - 0.3;
const GROW = 0.9;
const BUILT_AT = GROW_AT + GROW;
const SPOOL_TIME = 2.2;
const IDLE_RPS = 0.3;
const FULL_RPS = 3.2;
const CAM = 10;
const LINES = 20; // an outer ring of 12 exhaust streams at the nozzle's edge and an inner ring of 8

export function startEngineFx(canvas: HTMLCanvasElement, anchor: HTMLElement): () => void {
  const ctx = canvas.getContext("2d");
  const host = canvas.parentElement;
  if (!ctx || !host) return () => {};
  const { A, E, F, bladeEdges } = buildModel();

  let seed = 9;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const sparks: { c: number; t: number; v: number }[] = [];
  for (let c = 0; c < LINES; c++) {
    for (let i = 0; i < 3; i++) sparks.push({ c, t: rnd(), v: 0.07 + rnd() * 0.05 });
  }

  // ---- Layout: the canvas covers the hero; the engine sits on the anchor. ----
  let W = 0;
  let H = 0;
  let CX = 0;
  let CY = 0;
  let R = 0;
  let SCALE = 0;
  let aimPitch = 0;
  let aimYaw = 0;
  const layout = () => {
    const rect = host.getBoundingClientRect();
    const box = anchor.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    W = rect.width;
    H = rect.height;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    CX = box.x + box.width / 2 - rect.x;
    CY = box.y + box.height / 2 - rect.y;
    R = box.width / 2;
    SCALE = R * 0.72;
    // The engine faces mostly towards the viewer, turned just enough that its
    // tail axis points straight at the vanishing point: a line along the axis
    // heads for screen offset scale*cam*(dx/dz, dy/dz), so solve pitch and yaw
    // for that offset. The exhaust lines, drawn along the same axis, then
    // always meet there.
    // On a wide screen, where the engine sits between the heading and the
    // globe, the vanishing point is up and to the right, in the open sky
    // above the globe; on a narrow one, where it sits under the heading,
    // below it instead. Either way the exhaust stays clear of the text.
    const wide = W >= 1100;
    const vpX = wide ? W * 0.92 : CX + W * 0.25;
    const vpY = wide ? H * 0.02 : H * 1.25;
    aimPitch = Math.atan(-(vpY - CY) / (SCALE * CAM));
    aimYaw = Math.atan(((vpX - CX) / (SCALE * CAM)) * Math.cos(aimPitch));
  };

  let time = 0;
  let fanAngle = 0;
  // How far each point has drawn in (0..1): the intake first, the tail last.
  const drawnOf = (an: Anchor) =>
    an.grow ? 1 : ease(clamp01((time - DRAW_AT - clamp01(an.e[2] / 2.45) * WAVE) / DRAW));
  const growOf = () => ease(clamp01((time - GROW_AT) / GROW));
  const spool = () => ease(clamp01((time - BUILT_AT) / SPOOL_TIME));
  const rps = () => IDLE_RPS + (FULL_RPS - IDLE_RPS) * spool();

  // Aimed at the vanishing point, with a slow, gentle sway.
  const pose = (): Pose => ({
    yaw: aimYaw + 0.05 * Math.sin(time * 0.8),
    pitch: aimPitch + 0.025 * Math.sin(time * 0.55),
    roll: 0,
    pivot: 0.35,
    dx: 0,
    dy: 0,
    scale: SCALE,
    cam: CAM,
  });
  const view = ([x0, y0, z0]: Vec3, p: Pose): Projected => {
    const z = z0 - p.pivot;
    const cr = Math.cos(p.roll);
    const sr = Math.sin(p.roll);
    const x = x0 * cr - y0 * sr;
    const y = x0 * sr + y0 * cr;
    const x1 = x * Math.cos(p.yaw) + z * Math.sin(p.yaw);
    const z1 = -x * Math.sin(p.yaw) + z * Math.cos(p.yaw);
    const y2 = y * Math.cos(p.pitch) - z1 * Math.sin(p.pitch);
    const z2 = y * Math.sin(p.pitch) + z1 * Math.cos(p.pitch);
    const s = p.cam / (p.cam + z2);
    return { x: CX + p.dx + x1 * p.scale * s, y: CY + p.dy + y2 * p.scale * s, X: x1, Y: y2, Z: z2 };
  };
  const place = (an: Anchor, spin: number, p: Pose): Placed => {
    const m = drawnOf(an);
    let [ex, ey, ez] = an.e;
    if (an.spin) {
      const a = an.a + spin;
      ex = Math.cos(a) * an.r;
      ey = Math.sin(a) * an.r;
    }
    if (an.grow) {
      const g = growOf();
      ex *= g;
      ey *= g;
      ez = mix(0.3, ez, g);
    }
    return { ...view([ex, ey, ez], p), m };
  };

  const step = (dt: number) => {
    time += dt;
    if (time > GROW_AT) fanAngle += rps() * TAU * dt;
    const boost = 1 + 1.8 * spool();
    for (const s of sparks) {
      s.t += s.v * boost * dt;
      if (s.t > 1) s.t -= 1;
    }
  };

  // Exhaust lines: straight 3D streams leaving the nozzle along the engine's
  // axis, so they converge on the vanishing point the engine is aimed at.
  const buildLines = (p: Pose) => {
    const lines: LinePoint[][] = [];
    for (let k = 0; k < LINES; k++) {
      const outer = k < 12;
      const j = outer ? k : k - 12;
      const n = outer ? 12 : 8;
      const a = (j / n) * TAU + (outer ? 0.35 : 0.1);
      const rho = outer ? 0.55 : 0.3;
      const pts: LinePoint[] = [];
      for (let i = 0; i <= 120; i++) {
        const t = i / 120;
        const L = 400 * Math.pow(t, 3); // far enough to reach (almost) the vanishing point
        const q = view([Math.cos(a) * rho, Math.sin(a) * rho, 1.85 + L], p);
        pts.push([q.x, q.y, 1 - 0.7 * Math.pow(t, 0.9)]);
      }
      lines.push(pts);
    }
    return lines;
  };
  const along = (pts: LinePoint[], t: number): LinePoint => {
    const f = clamp01(t) * (pts.length - 1);
    const i = Math.floor(f);
    const k = f - i;
    const a = pts[i];
    const b = pts[Math.min(i + 1, pts.length - 1)];
    return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
  };

  const draw = () => {
    ctx.clearRect(0, 0, W, H);
    const p = pose();
    const P = A.map((an) => place(an, fanAngle, p));
    const grow = growOf();
    const sp = spool();

    // Exhaust lines, clipped out of the engine's silhouette (the convex hull
    // of its shell) so they stream from behind it rather than through the fan.
    const reveal = ease(clamp01((time - BUILT_AT) / 1.6));
    if (reveal > 0) {
      const lines = buildLines(p);
      const hullPts = P.filter((_, i) => !A[i].grow)
        .map((q): [number, number] => [q.x, q.y])
        .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      const cross = (o: number[], a: number[], b: number[]) =>
        (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
      const lower: [number, number][] = [];
      const upper: [number, number][] = [];
      for (const q of hullPts) {
        while (lower.length > 1 && cross(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) lower.pop();
        lower.push(q);
      }
      for (const q of hullPts.slice().reverse()) {
        while (upper.length > 1 && cross(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) upper.pop();
        upper.push(q);
      }
      const hull = [...lower.slice(0, -1), ...upper.slice(0, -1)];
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, W, H);
      hull.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.closePath();
      ctx.clip("evenodd");
      for (const pts of lines) {
        const upto = Math.max(2, Math.floor(reveal * (pts.length - 1)));
        for (let i = 0; i < upto; i += 2) {
          const a = pts[i];
          const b = pts[Math.min(i + 2, upto)];
          const u = i / (pts.length - 1);
          const alpha = 0.62 * Math.pow(a[2], 0.9) * (1 - Math.pow(u, 6));
          ctx.strokeStyle = `rgba(${LINE_RGB},${alpha.toFixed(3)})`;
          ctx.lineWidth = 0.4 + 1.3 * a[2];
          ctx.beginPath();
          ctx.moveTo(a[0], a[1]);
          ctx.lineTo(b[0], b[1]);
          ctx.stroke();
        }
      }
      // Bright streaks travelling out along the lines, faster once spooled up.
      for (const s of sparks) {
        if (s.t > reveal) continue;
        const pts = lines[s.c];
        const [x, y, d] = along(pts, s.t);
        const [tx, ty] = along(pts, s.t - 0.03 * (1 + sp));
        const fade = Math.min(1, s.t / 0.04) * Math.pow(d, 1.2);
        const g = ctx.createLinearGradient(tx, ty, x, y);
        g.addColorStop(0, `rgba(${SPARK_RGB},0)`);
        g.addColorStop(1, `rgba(${SPARK_RGB},${(0.85 * fade).toFixed(3)})`);
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.9 * d;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(tx, ty);
        ctx.lineTo(x, y);
        ctx.stroke();
      }
      ctx.restore();
    }

    // Shaded faces, far to near, each fading in as its points draw in.
    const light = [-0.45, -0.6, -0.66];
    const faces = F.map(([a, b, c, d, gain]) => {
      const q4 = [P[a], P[b], P[c], P[d]];
      const q = d === a ? q4[2] : q4[3];
      const ux = q4[1].X - q4[0].X;
      const uy = q4[1].Y - q4[0].Y;
      const uz = q4[1].Z - q4[0].Z;
      const vx = q.X - q4[0].X;
      const vy = q.Y - q4[0].Y;
      const vz = q.Z - q4[0].Z;
      let nx = uy * vz - uz * vy;
      let ny = uz * vx - ux * vz;
      let nz = ux * vy - uy * vx;
      const nl = Math.hypot(nx, ny, nz) || 1;
      nx /= nl;
      ny /= nl;
      nz /= nl;
      return {
        q4,
        nx,
        ny,
        nz,
        m: Math.min(q4[0].m, q4[1].m, q4[2].m, q4[3].m),
        depth: (q4[0].Z + q4[1].Z + q4[2].Z + q4[3].Z) / 4,
        gain: gain * (A[a].grow ? grow : 1),
      };
    }).sort((f1, f2) => f2.depth - f1.depth);
    for (const f of faces) {
      const lambert = Math.abs(f.nx * light[0] + f.ny * light[1] + f.nz * light[2]);
      const alpha = f.gain * (0.035 + 0.13 * lambert) * (0.5 + 0.5 * Math.abs(f.nz)) * f.m;
      ctx.fillStyle = `rgba(${FACE_RGB},${alpha.toFixed(3)})`;
      ctx.beginPath();
      ctx.moveTo(f.q4[0].x, f.q4[0].y);
      for (const q of f.q4.slice(1)) ctx.lineTo(q.x, q.y);
      ctx.closePath();
      ctx.fill();
    }
    if (sp > 0.05) {
      // The fan blurs into a disc at speed.
      const rim: Projected[] = [];
      const hub: Projected[] = [];
      for (let i = 0; i < 24; i++) {
        const a = (i / 24) * TAU;
        rim.push(view([Math.cos(a) * 0.83, Math.sin(a) * 0.83, 0.27], p));
        hub.push(view([Math.cos(a) * 0.24, Math.sin(a) * 0.24, 0.3], p));
      }
      ctx.fillStyle = `rgba(${FAN_RGB},${(0.1 * sp).toFixed(3)})`;
      ctx.beginPath();
      rim.forEach((q, i) => (i ? ctx.lineTo(q.x, q.y) : ctx.moveTo(q.x, q.y)));
      ctx.closePath();
      hub.slice().reverse().forEach((q, i) => (i ? ctx.lineTo(q.x, q.y) : ctx.moveTo(q.x, q.y)));
      ctx.closePath();
      ctx.fill("evenodd");
    }

    // Edges, depth-cued. Where a ring is drawing in, a bright band runs along it.
    ctx.lineCap = "round";
    const drawEdge = (a: Placed, b: Placed, w: number, alphaScale: number) => {
      const m = Math.min(a.m, b.m);
      const depth = (a.Z + b.Z) / 2;
      const near = Math.max(0.25, Math.min(1, 0.62 - depth * 0.32));
      const scan = Math.sin(Math.PI * clamp01(Math.max(a.m, b.m))) * (m < 1 ? 1 : 0);
      const alpha = alphaScale * (0.3 + 0.6 * w) * near * m;
      if (scan > 0.05) {
        ctx.strokeStyle = `rgba(255,236,190,${(0.35 * scan).toFixed(3)})`;
        ctx.lineWidth = 5 * scan;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }
      if (alpha < 0.004) return;
      ctx.strokeStyle = `rgba(${EDGE_RGB},${alpha.toFixed(3)})`;
      ctx.lineWidth = (0.6 + w * 0.9) * (0.7 + near * 0.5);
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();
    };
    for (const [i, j, w] of E) drawEdge(P[i], P[j], w, A[i].grow ? grow : 1);
    // Fan blades, with a few fading motion ghosts once they're spinning.
    const SHUTTER = 1 / 30;
    const GHOSTS = 5;
    if (grow > 0) {
      for (const [i, j] of bladeEdges) {
        for (let g = 0; g < GHOSTS; g++) {
          if (g > 0 && sp < 0.02) break;
          const back = -rps() * TAU * SHUTTER * (g / GHOSTS);
          const a = g ? place(A[i], fanAngle + back, p) : P[i];
          const b = g ? place(A[j], fanAngle + back, p) : P[j];
          drawEdge(a, b, 0.9, grow * (g ? (1 - g / GHOSTS) * 0.45 : 1) * 1.1);
        }
      }
    }

    // A warm core glow as it spools up.
    const glowA = 0.16 * sp;
    if (glowA > 0.005) {
      const c = view([0, 0, 0.3], p);
      const gr = ctx.createRadialGradient(c.x, c.y, 0, c.x, c.y, R * 0.75);
      gr.addColorStop(0, `rgba(${GLOW_RGB},${glowA.toFixed(3)})`);
      gr.addColorStop(1, `rgba(${GLOW_RGB},0)`);
      ctx.fillStyle = gr;
      ctx.beginPath();
      ctx.arc(c.x, c.y, R * 0.75, 0, TAU);
      ctx.fill();
    }
  };

  layout();
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let frame = 0;
  if (reduceMotion) {
    // No animation: show the finished, spooled-up engine as a still.
    time = BUILT_AT + SPOOL_TIME + 1.6;
    fanAngle = 0.4;
    draw();
  } else {
    let last = performance.now();
    const tick = (now: number) => {
      step(Math.min(0.05, (now - last) / 1000)); // (a background tab pauses rather than jumps ahead)
      last = now;
      draw();
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
  }
  const resize = new ResizeObserver(() => {
    layout();
    draw();
  });
  resize.observe(host);
  resize.observe(anchor);
  return () => {
    cancelAnimationFrame(frame);
    resize.disconnect();
  };
}
