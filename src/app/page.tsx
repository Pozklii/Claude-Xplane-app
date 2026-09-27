import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AppButtons } from "./app-links";
import { buildExampleShowcase } from "./example-flights";
import { EngineCanvas } from "./engine-canvas";
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

export default async function Home(props: PageProps<"/">) {
  // ?map=2d previews the example flights on a flat map instead of the globe.
  const { map } = await props.searchParams;
  const flat = map === "2d";
  const { airports, initial } = buildExampleShowcase();
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className={`${styles.page} ${styles.landing} flex flex-1 flex-col font-sans`}>
      {/* The golden-hour sky behind the whole page, and its light shafts
          (pre-rendered; see .sky in home.module.css). */}
      <div className={styles.sky} aria-hidden="true" />
      <div className={styles.skyRays} aria-hidden="true" />
      <section className={styles.hero}>
        <EngineCanvas />

        <div
          className={`${styles.content} ${styles.heroGrid} mx-auto w-full max-w-6xl px-6 py-10`}
        >
          <div className="flex flex-col items-center gap-4">
            <h1
              className={`${styles.introHeading} text-4xl font-bold tracking-tight sm:text-5xl`}
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
          {/* Where the engine animation sits; it's drawn on the canvas above,
              which covers the whole hero so its exhaust can stream across. */}
          <div className={styles.engineBox} data-engine-anchor aria-hidden="true" />
        </div>
      </section>

      <section
        aria-label="Example flights"
        className={`${styles.content} mx-auto w-full max-w-5xl px-6 py-10`}
      >
        <LandingShowcase
          airports={airports}
          initial={initial}
          flat={flat}
          header={
            <h2 className={`${styles.introHeading} text-2xl font-semibold tracking-tight`}>
              Every flight, on your {flat ? "map" : "globe"}
            </h2>
          }
        />
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
