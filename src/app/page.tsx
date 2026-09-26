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

export default async function Home() {
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

        <div className={`${styles.content} mx-auto w-full max-w-5xl px-6 py-10`}>
          <LandingShowcase
            airports={airports}
            initial={initial}
            header={
              <div className="flex flex-col items-start gap-4">
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
