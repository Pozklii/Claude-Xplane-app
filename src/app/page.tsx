import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AppButtons } from "./app-links";
import { buildExampleShowcase } from "./example-flights";
import { EngineCanvas } from "./engine-canvas";
import { FlameMotes } from "./flame-motes";
import { FlameLive } from "./flame-live";
import { generatedPalette } from "./flame-random";
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

// The page's backgrounds: on each visit, either one of three hand-picked
// fractal flames (pre-rendered stills in public/sky/flame-*, set in motion
// by the classes and motes below) or, half the time, a new one generated in
// their style from a random seed (flame-random.ts). ?bg=<name> picks a
// hand-picked one, ?bg=random a generated one, ?seed=<n> a particular
// generated one, and ?bg=golden the earlier golden-hour sky.
const FLAMES = {
  veil: {
    className: styles.flameVeil,
    motes: ["255,150,200", "150,190,255", "190,255,150"],
  },
  ember: {
    className: styles.flameEmber,
    motes: ["255,190,110", "255,140,60", "120,190,255"],
  },
  vortex: {
    className: styles.flameVortex,
    motes: ["110,240,210", "130,160,255", "150,255,170"],
  },
};
type FlameName = keyof typeof FLAMES;
const FLAME_NAMES = Object.keys(FLAMES) as FlameName[];

// A different background on each visit: this page renders per request (it
// reads the visitor's session), on the server, so the pick is made once
// per page view and the browser gets the same one it was rendered with.
function randomFlame(): FlameName {
  return FLAME_NAMES[Math.floor(Math.random() * FLAME_NAMES.length)];
}
function randomSeed() {
  return 100000 + Math.floor(Math.random() * 900000);
}
function coinFlip() {
  return Math.random() < 0.5;
}

export default async function Home(props: PageProps<"/">) {
  const {
    bg,
    seed: seedParam,
    sharp: sharpParam,
    style,
  } = await props.searchParams;
  // ?style=lines previews a sharper style: the flame as fine bright lines
  // over dark space, floating, with the motes drifting upward.
  const lines = style === "lines";
  // ?sharp=1 previews crisper backgrounds: sharper stills, the live flame
  // at full resolution without blur, and no soft glow over them.
  const sharp = sharpParam === "1" || lines;
  const pinned = typeof bg === "string" && Object.hasOwn(FLAMES, bg);
  const seedNumber =
    typeof seedParam === "string" ? Number.parseInt(seedParam, 10) : NaN;
  // A generated flame's seed, or null for a hand-picked one (or the sky).
  const seed: number | null =
    bg === "golden" || pinned
      ? null
      : Number.isFinite(seedNumber) && seedNumber >= 0
        ? seedNumber
        : bg === "random" || coinFlip()
          ? randomSeed()
          : null;
  const flame: FlameName | null =
    bg === "golden" || seed !== null
      ? null
      : pinned
        ? (bg as FlameName)
        : randomFlame();
  const generated = seed !== null ? generatedPalette(seed) : null;
  const { airports, initial } = buildExampleShowcase();
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div
      className={`${styles.page} ${styles.landing} ${flame ? FLAMES[flame].className : ""} flex flex-1 flex-col font-sans`}
      style={
        generated ? { background: `rgb(${generated.bg.join(",")})` } : undefined
      }
    >
      {seed !== null && generated ? (
        // A flame generated for this visit: rendered live, morphing, over
        // the page's dark ground (or, where it can't run, a still drawn in
        // the browser), with motes in its colours. Its number lets a
        // favourite be found again (?seed=).
        <div className={styles.flameSky} aria-hidden="true">
          <FlameLive seed={seed} sharp={sharp} lines={lines} />
          <FlameMotes colors={generated.motes} float={lines} />
          <p className={styles.flameLabel}>Background no. {seed}</p>
        </div>
      ) : flame ? (
        // A fractal flame behind the whole page: rendered live, its shapes
        // slowly morphing (over the still, which shows first and stands in
        // wherever the live one can't run, gently drifting), under a soft
        // glow pulsing and turning, with twinkling motes orbiting its
        // middle (see .flameSky).
        <div
          className={`${styles.flameSky} ${sharp ? styles.flameSharp : ""}`}
          aria-hidden="true"
        >
          <div className={styles.flameBase} />
          <FlameLive flame={flame} sharp={sharp} lines={lines} />
          {!sharp && <div className={styles.flameGlow} />}
          <FlameMotes colors={FLAMES[flame].motes} float={lines} />
        </div>
      ) : (
        <>
          {/* The golden-hour sky, and its light shafts (pre-rendered; see
              .sky in home.module.css). */}
          <div className={styles.sky} aria-hidden="true" />
          <div className={styles.skyRays} aria-hidden="true" />
        </>
      )}
      <main className={styles.hero}>
        <EngineCanvas />

        <div
          className={`${styles.content} mx-auto w-full max-w-[1400px] px-6 py-8 min-[1100px]:py-4`}
        >
          <LandingShowcase
            airports={airports}
            initial={initial}
            header={
              <div className={styles.heroIntro}>
                <h1
                  className={`${styles.introHeading} text-4xl font-bold tracking-tight sm:text-5xl min-[1100px]:text-4xl 2xl:text-5xl`}
                >
                  Create your Flight World
                </h1>
                {!user && (
                  <Link
                    href="/login"
                    className={`${styles.cta} rounded-md px-5 py-2.5 text-sm font-semibold transition-colors`}
                  >
                    Sign in
                  </Link>
                )}
                <AppButtons signedIn={Boolean(user)} />
              </div>
            }
            features={
              <div className="grid w-full grid-cols-1 gap-6 text-left sm:grid-cols-3">
                {features.map((feature) => (
                  <div key={feature.title} className="flex flex-col gap-1.5">
                    <h2 className={`${styles.introHeading} font-semibold`}>
                      {feature.title}
                    </h2>
                    <p className={`${styles.featureText} text-sm leading-6`}>
                      {feature.description}
                    </p>
                  </div>
                ))}
              </div>
            }
            engine={
              // Where the engine animation sits; it's drawn on the canvas
              // above, which covers the whole hero so its exhaust can
              // stream across.
              <div
                className={styles.engineBox}
                data-engine-anchor
                aria-hidden="true"
              />
            }
          />
        </div>
      </main>
    </div>
  );
}
