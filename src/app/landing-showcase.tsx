"use client";

import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import {
  DEFAULT_ARC_COLOR,
  FlightGlobe,
  type GlobePoint,
} from "./flights/flight-globe";
import { SelectedFlightCard } from "./flights/selected-flight-card";
import { SelectionProvider, useSelection } from "./flights/selection-context";
import {
  EXAMPLE_HISTORY_SIZE,
  generateExampleFlight,
  usableRoutes,
  type ExampleAirport,
  type ExampleFlight,
} from "@/lib/example-flights/generate";
import { isoDaysBefore, localToday } from "@/lib/dates";
import styles from "./home.module.css";

// How long each example flight stays up, and how long to wait for the globe
// to load before the first one.
const DWELL_MS = 7000;
const FIRST_DELAY_MS = 1500;

const noopSubscribe = () => () => {};

// The landing page hero's layout and example-flight tour: the heading (and
// under it, a summary card for the current example flight) on the left, the
// engine animation's anchor in the middle, the globe on the right, and the
// feature blurbs under those two; on a narrow screen, stacked in that order
// but with the engine second. The
// globe keeps the last few generated example flights drawn and, every few
// seconds, generates a new one (see generateExampleFlight — endless, from
// real airline routes) and flies onto it, until the visitor pauses it.
export function LandingShowcase(props: {
  header: React.ReactNode;
  engine: React.ReactNode;
  features: React.ReactNode;
  airports: Record<string, ExampleAirport>;
  initial: ExampleFlight[];
  /** Show the flights on a flat map instead of the globe. */
  flat?: boolean;
}) {
  return (
    <SelectionProvider>
      <Showcase {...props} />
    </SelectionProvider>
  );
}

function Showcase({
  header,
  engine,
  features,
  airports,
  initial,
  flat = false,
}: {
  header: React.ReactNode;
  engine: React.ReactNode;
  features: React.ReactNode;
  airports: Record<string, ExampleAirport>;
  initial: ExampleFlight[];
  flat?: boolean;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const [paused, setPaused] = useState(false);
  // Seeded by the server (so the first render matches it), then extended
  // one generated flight at a time from timer callbacks, never during
  // render.
  const [flights, setFlights] = useState(initial);
  const [generatedCount, setGeneratedCount] = useState(initial.length);
  const started = generatedCount > initial.length;

  // The viewer's own today (null during the server render and hydration,
  // before any card is showing), which every example flight's date counts
  // back from — so the newest can be today wherever and whenever they are.
  const today = useSyncExternalStore(noopSubscribe, localToday, () => null);

  const routes = useMemo(() => usableRoutes(airports), [airports]);
  const { arcs, points, details } = useMemo(() => {
    const pointsByCode = new Map<string, GlobePoint>();
    for (const flight of flights) {
      for (const point of flight.points) pointsByCode.set(point.code, point);
    }
    return {
      arcs: flights.map((flight) => flight.arc),
      points: Array.from(pointsByCode.values()),
      details: Object.fromEntries(
        flights.map((flight) => [
          flight.id,
          today
            ? { ...flight.details, date: isoDaysBefore(today, flight.daysAgo) }
            : flight.details,
        ]),
      ),
    };
  }, [flights, today]);

  const delay = started ? DWELL_MS : FIRST_DELAY_MS;

  useEffect(() => {
    if (paused) return;
    const timer = window.setTimeout(() => {
      const next = generateExampleFlight({
        id: `example-${generatedCount}`,
        airports,
        routes,
        recentRouteKeys: flights.map((flight) => flight.routeKey),
        recentNoteKeys: flights.flatMap((flight) => flight.noteKeys),
        today: localToday(),
      });
      setFlights([...flights.slice(-(EXAMPLE_HISTORY_SIZE - 1)), next]);
      setGeneratedCount(generatedCount + 1);
      setSelectedFlightId(next.id);
    }, delay);
    return () => window.clearTimeout(timer);
  }, [
    paused,
    delay,
    flights,
    generatedCount,
    airports,
    routes,
    setSelectedFlightId,
  ]);

  return (
    <div className={styles.heroGrid}>
      {/* Each passed-in element gets its own wrapper: one from a server
          component sitting beside siblings here otherwise trips React's
          missing-"key" warning. */}
      <div className={styles.heroHeader}>{header}</div>
      <div className={styles.heroEngine}>{engine}</div>

      <div className={`${styles.heroTour} flex flex-col gap-3`}>
        <div className="flex items-center justify-between gap-3">
          <p className={`${styles.showcaseLabel} tabular-nums`}>
            {selectedFlightId ? "Example flight" : "Example flights"}
          </p>
          <button
            type="button"
            onClick={() => setPaused((p) => !p)}
            aria-pressed={paused}
            className={`${styles.showcaseToggle} text-xs`}
          >
            {paused ? "Play tour" : "Pause tour"}
          </button>
        </div>
        <div className={styles.showcaseTrack} aria-hidden="true">
          {!paused && (
            // Restarted (by key) for every step, and sized to that
            // step's own delay, so it shows when the next flight lands.
            <div
              key={`${selectedFlightId}-${delay}`}
              className={styles.showcaseProgress}
              style={{ animationDuration: `${delay}ms` }}
            />
          )}
        </div>
        {/* A fixed minimum height so the layout doesn't shift as cards
            with different amounts of text swap in. */}
        <div className={`${styles.showcaseCardSlot} min-h-[270px]`}>
          <SelectedFlightCard
            details={details}
            arcColor={DEFAULT_ARC_COLOR}
            showThumbnail={false}
            closable={false}
            emptyHint="Example flights will appear here in a moment."
          />
        </div>
      </div>

      <div className={styles.heroGlobe}>
        {/* Display-only: the tour drives it, visitors can't drag or click
            it. Always shown whole, turning to face each flight. */}
        <FlightGlobe
          points={points}
          arcs={arcs}
          bare
          flat={flat}
          wholeGlobe
          interactive={false}
        />
      </div>
      <div className={styles.heroFeatures}>{features}</div>
    </div>
  );
}
