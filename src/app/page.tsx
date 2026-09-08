import Link from "next/link";
import { findAirport } from "@/lib/airports";
import { FlightGlobe, type GlobeArc, type GlobePoint } from "./flights/flight-globe";
import { SelectionProvider } from "./flights/selection-context";
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

const EXAMPLE_ROUTE: [string, string][] = [
  ["JFK", "LHR"],
  ["LHR", "CDG"],
];

function buildExampleGlobeData(): { points: GlobePoint[]; arcs: GlobeArc[] } {
  const pointsByCode = new Map<string, GlobePoint>();
  const arcs: GlobeArc[] = [];

  EXAMPLE_ROUTE.forEach(([departure, arrival], index) => {
    const from = findAirport(departure);
    const to = findAirport(arrival);
    if (!from || !to) return;

    pointsByCode.set(from.code, {
      code: from.code,
      name: from.name,
      city: from.city,
      lat: from.lat,
      lng: from.lon,
    });
    pointsByCode.set(to.code, {
      code: to.code,
      name: to.name,
      city: to.city,
      lat: to.lat,
      lng: to.lon,
    });
    arcs.push({
      id: `example-${index}`,
      startLat: from.lat,
      startLng: from.lon,
      endLat: to.lat,
      endLng: to.lon,
      fromCode: from.code,
      toCode: to.code,
      label: `${from.code} → ${to.code}`,
    });
  });

  return { points: Array.from(pointsByCode.values()), arcs };
}

// Deterministic pseudo-random star field (fixed seed) so the night sky
// doesn't reshuffle on every request, without needing a client component.
function generateStars(count: number) {
  let seed = 1337;
  const next = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };
  return Array.from({ length: count }, () => {
    const size = (next() * 1.6 + 0.8).toFixed(2);
    return {
      left: `${(next() * 100).toFixed(2)}%`,
      top: `${(next() * 68).toFixed(2)}%`,
      width: `${size}px`,
      height: `${size}px`,
      opacity: (next() * 0.5 + 0.4).toFixed(2),
      animationDuration: `${(next() * 4 + 3).toFixed(2)}s`,
      animationDelay: `${(next() * 5).toFixed(2)}s`,
    };
  });
}

const CLOUDS = [
  { top: "12%", left: "6%", width: 260, height: 120, opacity: 0.55, duration: "120s" },
  { top: "22%", left: "58%", width: 320, height: 140, opacity: 0.4, duration: "150s" },
  { top: "44%", left: "20%", width: 200, height: 96, opacity: 0.35, duration: "100s" },
  { top: "6%", left: "74%", width: 180, height: 88, opacity: 0.3, duration: "135s" },
  { top: "58%", left: "66%", width: 240, height: 110, opacity: 0.3, duration: "110s" },
];

const STARS = generateStars(70);

export default function Home() {
  const { points, arcs } = buildExampleGlobeData();

  return (
    <div className="flex flex-1 flex-col bg-zinc-50 font-sans dark:bg-black">
      <section className={styles.hero}>
        <div className={styles.skyFx} aria-hidden="true">
          <div className={styles.sunGlow} />
          <div className={styles.moonGlow} />
          <div className={styles.moonCore} />
          {CLOUDS.map((cloud, i) => (
            <div
              key={i}
              className={styles.cloud}
              style={{
                top: cloud.top,
                left: cloud.left,
                width: cloud.width,
                height: cloud.height,
                opacity: cloud.opacity,
                animationDuration: cloud.duration,
              }}
            />
          ))}
          {STARS.map((star, i) => (
            <span key={i} className={styles.star} style={star} />
          ))}
        </div>

        <div
          className={`${styles.content} mx-auto grid w-full max-w-5xl grid-cols-1 items-start gap-14 px-6 py-16 sm:py-24 lg:grid-cols-[360px_1fr]`}
        >
          <div className="flex flex-col items-start gap-4 text-left">
            <h1
              className={`${styles.introHeading} text-4xl font-bold tracking-tight sm:text-5xl`}
            >
              Create your Flight World
            </h1>
            <p className={`${styles.introLede} max-w-[38ch] text-lg leading-8`}>
              Log the aircraft, route and time for each flight, and watch
              your own map fill in — like a personal atlas of everything
              you&apos;ve flown.
            </p>
            <Link
              href="/login"
              className={`${styles.cta} rounded-md px-5 py-2.5 text-sm font-semibold transition-colors`}
            >
              Get started
            </Link>
          </div>

          <div className={`${styles.mapPanel} overflow-hidden rounded-xl`}>
            <div
              className={`${styles.mapToolbar} flex items-center justify-between px-4 py-3`}
            >
              <span className="text-sm font-semibold">Example flights</span>
              <span className={`${styles.mapToolbarMeta} text-xs`}>
                {arcs.length} routes &middot; sample data
              </span>
            </div>
            <div className="p-4">
              <SelectionProvider>
                <FlightGlobe points={points} arcs={arcs} />
              </SelectionProvider>
            </div>
          </div>
        </div>
      </section>

      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-6 px-6 py-16">
        <div className="grid w-full grid-cols-1 gap-6 text-left sm:grid-cols-3">
          {features.map((feature) => (
            <div
              key={feature.title}
              className="flex flex-col gap-2 rounded-2xl border border-black/[.08] p-6 dark:border-white/[.145]"
            >
              <h2 className="font-semibold text-black dark:text-zinc-50">
                {feature.title}
              </h2>
              <p className="text-sm leading-6 text-zinc-600 dark:text-zinc-400">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
