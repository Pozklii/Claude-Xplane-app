import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AppButtons } from "./app-links";
import { buildExampleShowcase } from "./example-flights";
import { EngineCanvas } from "./engine-canvas";
import { FlameMotes } from "./flame-motes";
import { FlameLive } from "./flame-live";
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

// The page's backgrounds: pre-rendered fractal flames (public/sky/flame-*),
// one picked at random for each visit, set in motion by the classes and
// motes below; or the golden-hour sky. ?bg=<name> picks one.
const FLAMES = {
  veil: { className: styles.flameVeil, motes: ["255,150,200", "150,190,255", "190,255,150"] },
  ember: { className: styles.flameEmber, motes: ["255,190,110", "255,140,60", "120,190,255"] },
  vortex: { className: styles.flameVortex, motes: ["110,240,210", "130,160,255", "150,255,170"] },
};
type FlameName = keyof typeof FLAMES;
const FLAME_NAMES = Object.keys(FLAMES) as FlameName[];

// A different flame on each visit: this page renders per request (it reads
// the visitor's session), on the server, so the pick is made once per
// page view and the browser gets the same one it was rendered with.
function randomFlame(): FlameName {
  return FLAME_NAMES[Math.floor(Math.random() * FLAME_NAMES.length)];
}

export default async function Home(props: PageProps<"/">) {
  // ?map=2d previews the example flights on a flat map instead of the globe.
  const { map, bg, sharp: sharpParam } = await props.searchParams;
  // ?sharp=1 previews crisper backgrounds: sharper stills, the live flame
  // at full resolution without blur, and no soft glow over them.
  const sharp = sharpParam === "1";
  const flat = map === "2d";
  const flame: FlameName | null =
    bg === "golden"
      ? null
      : typeof bg === "string" && Object.hasOwn(FLAMES, bg)
        ? (bg as FlameName)
        : randomFlame();
  const { airports, initial } = buildExampleShowcase();
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div
      className={`${styles.page} ${styles.landing} ${flame ? FLAMES[flame].className : ""} flex flex-1 flex-col font-sans`}
    >
      {flame ? (
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
          <FlameLive flame={flame} sharp={sharp} />
          {!sharp && <div className={styles.flameGlow} />}
          <FlameMotes colors={FLAMES[flame].motes} />
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

        <div className={`${styles.content} mx-auto w-full max-w-[1400px] px-6 py-8 min-[1100px]:py-4`}>
          <LandingShowcase
            airports={airports}
            initial={initial}
            flat={flat}
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
              <div className={styles.engineBox} data-engine-anchor aria-hidden="true" />
            }
          />
        </div>
      </main>

    </div>
  );
}
