import Link from "next/link";
import { buildExampleShowcase } from "./example-flights";
import { LandingShowcase } from "./landing-showcase";
import styles from "./home.module.css";

const features = [
  {
    title: "Log every flight",
    description:
      "Capture aircraft, route, times, and notes for each flight as soon as you land.",
  },
  {
    title: "See your history",
    description:
      "Browse past flights, filter by aircraft or route, and track hours over time.",
  },
  {
    title: "Your data, backed up",
    description:
      "Flights are stored in Supabase and tied to your account, accessible from anywhere.",
  },
];

// --- Decorative SVG chrome: brushed-metal seams, HUD corners, converging
// livery lines feeding into a turbofan engine graphic. All static/
// deterministic (no per-request randomness), computed once at module load
// so this stays a server component.

type Point = [number, number];

function pt(cx: number, cy: number, r: number, deg: number): Point {
  const rad = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

function arcPath(cx: number, cy: number, r: number, fromDeg: number, toDeg: number) {
  const [ax, ay] = pt(cx, cy, r, fromDeg);
  const [bx, by] = pt(cx, cy, r, toDeg);
  const large = ((toDeg - fromDeg) % 360) > 180 ? 1 : 0;
  return `M ${ax.toFixed(1)} ${ay.toFixed(1)} A ${r} ${r} 0 ${large} 1 ${bx.toFixed(1)} ${by.toFixed(1)}`;
}

// Position of the engine in the outer (1440x900) background space, and the
// size of the small square sub-viewport it's drawn into at that position —
// nesting it in its own <svg> with a uniform "meet" fit keeps its circles
// truly circular even though the outer background SVGs are stretched
// non-uniformly (preserveAspectRatio="none") to fill the hero edge to edge
// without cropping.
const ENGINE_CX = 1280;
const ENGINE_CY = 760;
// Fractional position within the 1440x900 background space — since the
// background SVGs use preserveAspectRatio="none" (pure non-uniform scale,
// no letterboxing offset), a point's fractional position always maps to
// the same fractional position on screen. Positioning the CSS engineBox
// at this same fraction (see the .engineBox style below) keeps it exactly
// where the livery curves converge, at any viewport width.
const ENGINE_X_PCT = (ENGINE_CX / 1440) * 100;
const ENGINE_Y_PCT = (ENGINE_CY / 900) * 100;
const ENGINE_BOX_R = 130;
const ENGINE_LOCAL_CX = ENGINE_BOX_R;
const ENGINE_LOCAL_CY = ENGINE_BOX_R;
const NACELLE_R = 118;
const CASE_OUTER_R = 104;
const CASE_INNER_R = 92;
const STATOR_R = 88;
const HUB_R = 24;
const BLADE_INNER_R = 28;
const BLADE_OUTER_R = 84;
const BLADE_COUNT = 20;
const RIVET_COUNT = 32;
const STATOR_COUNT = 40;
const HUB_BOLT_COUNT = 6;
const HALF_WIDTH_DEG = 5.2;
const SWEEP_DEG = 11;

const nacelleRivets = Array.from({ length: RIVET_COUNT }, (_, i) =>
  pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, NACELLE_R, (360 / RIVET_COUNT) * i),
);

const statorVanes = Array.from({ length: STATOR_COUNT }, (_, i) => {
  const theta0 = (360 / STATOR_COUNT) * i;
  return {
    q1: pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_INNER_R - 4, theta0),
    q2: pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, STATOR_R, theta0),
  };
});

const bladesData = Array.from({ length: BLADE_COUNT }, (_, i) => {
  const theta = (360 / BLADE_COUNT) * i;
  const p1 = pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_INNER_R, theta - HALF_WIDTH_DEG);
  const p2 = pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_OUTER_R, theta - HALF_WIDTH_DEG + SWEEP_DEG);
  const p3 = pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_OUTER_R, theta + HALF_WIDTH_DEG + SWEEP_DEG);
  const p4 = pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_INNER_R, theta + HALF_WIDTH_DEG);
  const rootPt = pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, BLADE_INNER_R - 1, theta);
  return {
    i,
    d: `M ${p1[0].toFixed(1)} ${p1[1].toFixed(1)} L ${p2[0].toFixed(1)} ${p2[1].toFixed(1)} L ${p3[0].toFixed(1)} ${p3[1].toFixed(1)} L ${p4[0].toFixed(1)} ${p4[1].toFixed(1)} Z`,
    edgeD: `M ${p1[0].toFixed(1)} ${p1[1].toFixed(1)} L ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`,
    rootPt,
    fill: i % 2 === 0 ? "rgba(220,232,240,0.18)" : "rgba(79,143,199,0.16)",
  };
});

const hubBolts = Array.from({ length: HUB_BOLT_COUNT }, (_, i) =>
  pt(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, HUB_R - 6, (360 / HUB_BOLT_COUNT) * i + 15),
);

const cowlSheenD = arcPath(ENGINE_LOCAL_CX, ENGINE_LOCAL_CY, CASE_OUTER_R, -55, 15);

function pathFrom(pts: [Point, Point, Point, Point, Point, Point, Point]) {
  const [p0, p1, p2, p3, p4, p5, p6] = pts;
  return (
    `M ${p0[0]} ${p0[1]} C ${p1[0]} ${p1[1]}, ${p2[0]} ${p2[1]}, ${p3[0]} ${p3[1]}` +
    ` C ${p4[0]} ${p4[1]}, ${p5[0]} ${p5[1]}, ${p6[0]} ${p6[1]}`
  );
}

const LIVERY_COLORS = ["#3f7fb5", "#5a9fd4", "#8fd0f5"];
const LIVERY_CURVE_COUNT = 9;

// Lines start at the engine and sweep outward to the left edge, like
// motion/thrust streaks trailing off it — reversed from the original
// "gathering toward the nose" so the path (and its draw-in animation)
// reads as originating from the engine rather than feeding into it.
const liveryCurves = Array.from({ length: LIVERY_CURVE_COUNT }, (_, i) => {
  const t = i / (LIVERY_CURVE_COUNT - 1);
  const p0: Point = [-120, 30 + t * 760];
  const p1: Point = [300, -230 + t * 700 * 0.35];
  const p2: Point = [640, 250 + t * 220];
  const p3: Point = [900, 410 + t * 190];
  const p4: Point = [1140, 560 + t * 170];
  const p5: Point = [1360, 700 + t * 100];
  const jx = ((i % 3) - 1) * 12;
  const jy = ((i % 4) - 1.5) * 16;
  const p6: Point = [ENGINE_CX + jx, ENGINE_CY + jy];
  return {
    d: pathFrom([p6, p5, p4, p3, p2, p1, p0]),
    stroke: LIVERY_COLORS[i % LIVERY_COLORS.length],
    strokeWidth: i === 2 || i === 5 ? 2.2 : 1.2,
    opacity: i === 2 || i === 5 ? 0.6 : 0.32,
    delay: `${(i * 0.05).toFixed(2)}s`,
  };
});

export default function Home() {
  const { points, arcs, details } = buildExampleShowcase();

  return (
    <div className={`${styles.page} flex flex-1 flex-col font-sans`}>
      <section className={styles.hero}>
        <div className={styles.mechBg} aria-hidden="true">
          <svg viewBox="0 0 1440 900" preserveAspectRatio="none">
            <defs>
              <linearGradient id="sheen" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stopColor="#bcd9ef" stopOpacity="0" />
                <stop offset="50%" stopColor="#bcd9ef" stopOpacity="0.06" />
                <stop offset="100%" stopColor="#bcd9ef" stopOpacity="0" />
              </linearGradient>
            </defs>

            <g transform="rotate(-8 720 450)">
              <rect x="-200" y="60" width="2000" height="140" fill="url(#sheen)" />
              <rect x="-200" y="400" width="2000" height="190" fill="url(#sheen)" opacity="0.75" />
              <rect x="-200" y="700" width="2000" height="110" fill="url(#sheen)" opacity="0.55" />
            </g>

            <path d="M -40 180 Q 500 120 1480 220" fill="none" stroke="#3d5a70" strokeWidth="1" opacity="0.16" />
            <path
              d="M -40 180 Q 500 120 1480 220"
              fill="none"
              stroke="#cdd9e2"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeDasharray="1 18"
              opacity="0.18"
            />
            <path d="M -40 620 Q 620 690 1480 600" fill="none" stroke="#3d5a70" strokeWidth="1" opacity="0.14" />
            <path
              d="M -40 620 Q 620 690 1480 600"
              fill="none"
              stroke="#cdd9e2"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeDasharray="1 18"
              opacity="0.16"
            />
            <path d="M 260 -40 Q 300 450 240 940" fill="none" stroke="#3d5a70" strokeWidth="1" opacity="0.12" />
            <path
              d="M 260 -40 Q 300 450 240 940"
              fill="none"
              stroke="#cdd9e2"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeDasharray="1 18"
              opacity="0.14"
            />

            <g stroke="#8fd0f5" strokeWidth="2" fill="none" opacity="0.3">
              <path d="M 34 74 L 34 34 L 74 34" />
              <path d="M 1406 74 L 1406 34 L 1366 34" />
              <path d="M 34 826 L 34 866 L 74 866" />
              <path d="M 1406 826 L 1406 866 L 1366 866" />
            </g>
          </svg>
        </div>

        <div className={styles.liveryFx} aria-hidden="true">
          <svg viewBox="0 0 1440 900" preserveAspectRatio="none">
            <defs>
              <radialGradient id="noseGlow" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor="#3f7fb5" stopOpacity="0.35" />
                <stop offset="100%" stopColor="#3f7fb5" stopOpacity="0" />
              </radialGradient>
            </defs>

            <circle cx={ENGINE_CX} cy={ENGINE_CY} r="320" fill="url(#noseGlow)" />
            <circle cx={ENGINE_CX} cy={ENGINE_CY} r="230" fill="none" stroke="#8fd0f5" strokeWidth="1" opacity="0.09" />
            <circle cx="1220" cy="700" r="340" fill="none" stroke="#5a9fd4" strokeWidth="1" opacity="0.08" />
            <circle cx={ENGINE_CX} cy={ENGINE_CY} r="460" fill="none" stroke="#8fd0f5" strokeWidth="1" opacity="0.07" />
            <circle cx="1200" cy="820" r="580" fill="none" stroke="#3f7fb5" strokeWidth="1" opacity="0.06" />
            <circle cx={ENGINE_CX} cy={ENGINE_CY} r="700" fill="none" stroke="#5a9fd4" strokeWidth="1" opacity="0.05" />

            {liveryCurves.map((c, i) => (
              <path
                key={i}
                className={styles.curve}
                d={c.d}
                stroke={c.stroke}
                strokeWidth={c.strokeWidth}
                strokeLinecap="round"
                opacity={c.opacity}
                style={{ animationDelay: c.delay }}
              />
            ))}
          </svg>
        </div>

        {/* Turbofan intake: recessed nacelle, riveted cowl, fan-case rings,
            static stator vanes, a ring of spinning swept blades with lit
            leading edges and root bolts, and a shaded spinner hub — the
            livery lines above read as motion streaks trailing off it. Its
            own independent, CSS-sized-and-positioned <svg> (not nested
            inside the non-uniformly stretched background SVGs above), so
            its circles stay genuinely circular no matter how the hero's
            own aspect ratio varies with viewport width. Centered at the
            same fractional position (ENGINE_X_PCT/ENGINE_Y_PCT) the
            livery curves converge to, so the two stay aligned. */}
        <div
          className={styles.engineBox}
          aria-hidden="true"
          style={{ left: `${ENGINE_X_PCT}%`, top: `${ENGINE_Y_PCT}%` }}
        >
          <svg viewBox={`0 0 ${ENGINE_BOX_R * 2} ${ENGINE_BOX_R * 2}`} width="100%" height="100%">
            <defs>
              <radialGradient id="engineHub" cx="38%" cy="32%" r="70%">
                <stop offset="0%" stopColor="#eef5fa" />
                <stop offset="55%" stopColor="#5f8fac" />
                <stop offset="100%" stopColor="#132a3c" />
              </radialGradient>
              <radialGradient id="engineRecess" cx="50%" cy="50%" r="50%">
                <stop offset="55%" stopColor="#000000" stopOpacity="0" />
                <stop offset="100%" stopColor="#000000" stopOpacity="0.55" />
              </radialGradient>
            </defs>
            <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r={NACELLE_R} fill="url(#engineRecess)" />
            <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r={NACELLE_R} fill="none" stroke="#2c4d68" strokeWidth="1.5" opacity="0.5" />
            <g fill="#a9c0d0" opacity="0.4">
              {nacelleRivets.map(([x, y], i) => (
                <circle key={i} cx={x.toFixed(1)} cy={y.toFixed(1)} r="1.4" />
              ))}
            </g>
            <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r={CASE_OUTER_R} fill="none" stroke="#5a9fd4" strokeWidth="2" opacity="0.4" />
            <path d={cowlSheenD} fill="none" stroke="#dcedf7" strokeWidth="2" strokeLinecap="round" opacity="0.45" />
            <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r={CASE_INNER_R} fill="none" stroke="#8fd0f5" strokeWidth="1.5" opacity="0.5" />
            <g stroke="#3d6584" strokeWidth="1" opacity="0.35">
              {statorVanes.map(({ q1, q2 }, i) => (
                <line key={i} x1={q1[0].toFixed(1)} y1={q1[1].toFixed(1)} x2={q2[0].toFixed(1)} y2={q2[1].toFixed(1)} />
              ))}
            </g>
            <g className={styles.engineBlades}>
              {bladesData.map((b) => (
                <g key={b.i}>
                  <path d={b.d} fill={b.fill} stroke="#a9c0d0" strokeWidth="0.5" opacity="0.8" />
                  <path d={b.edgeD} fill="none" stroke="#e8f2fa" strokeWidth="0.8" strokeLinecap="round" opacity="0.4" />
                  <circle cx={b.rootPt[0].toFixed(1)} cy={b.rootPt[1].toFixed(1)} r="1.3" fill="#0e1e2c" opacity="0.7" />
                </g>
              ))}
            </g>
            <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r={HUB_R} fill="url(#engineHub)" stroke="#b9c8d4" strokeWidth="1" opacity="0.9" />
            <g fill="#0e2434" opacity="0.55">
              {hubBolts.map(([x, y], i) => (
                <circle key={i} cx={x.toFixed(1)} cy={y.toFixed(1)} r="1.6" />
              ))}
              <circle cx={ENGINE_LOCAL_CX} cy={ENGINE_LOCAL_CY} r="2.4" />
            </g>
          </svg>
        </div>

        <div className={`${styles.content} mx-auto w-full max-w-5xl px-6 py-10`}>
          <LandingShowcase
            points={points}
            arcs={arcs}
            details={details}
            header={
              <div className="flex flex-col items-start gap-4">
                <h1
                  className={`${styles.introHeading} text-4xl font-bold tracking-tight sm:text-5xl`}
                >
                  Create your Flight World
                </h1>
                <Link
                  href="/login"
                  className={`${styles.cta} rounded-md px-5 py-2.5 text-sm font-semibold transition-colors`}
                >
                  Sign in
                </Link>
              </div>
            }
          />
        </div>
      </section>

      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col justify-center gap-6 px-6 py-8">
        <div className="grid w-full grid-cols-1 gap-8 text-left sm:grid-cols-3">
          {features.map((feature) => (
            <div key={feature.title} className="flex flex-col gap-2">
              <h2 className={`${styles.introHeading} font-semibold`}>
                {feature.title}
              </h2>
              <p className={`${styles.featureText} text-sm leading-6`}>
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
