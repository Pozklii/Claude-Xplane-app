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

// The landing page hero's content: its heading/CTA and a summary card for
// the current example flight on the left, the globe on the right. The
// globe keeps the last few generated example flights drawn and, every few
// seconds, generates a new one (see generateExampleFlight — endless, from
// real airline routes) and flies onto it, until the visitor pauses it.
export function LandingShowcase(props: {
  header: React.ReactNode;
  airports: Record<string, ExampleAirport>;
  initial: ExampleFlight[];
}) {
  return (
    <SelectionProvider>
      <Showcase {...props} />
    </SelectionProvider>
  );
}

function Showcase({
  header,
  airports,
  initial,
}: {
  header: React.ReactNode;
  airports: Record<string, ExampleAirport>;
  initial: ExampleFlight[];
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
    <div className="grid w-full grid-cols-1 items-center gap-14 lg:grid-cols-[1fr_380px]">
      <div className="flex flex-col items-start gap-6 text-left">
        {/* Its own wrapper: an element passed in from a server component
            that sits beside siblings here otherwise trips React's
            missing-"key" warning. */}
        <div>{header}</div>

        <div className="flex w-full max-w-sm flex-col gap-3">
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
          {/* A fixed minimum height so the heading above doesn't shift up
              and down as cards with different amounts of text swap in. */}
          <div className="min-h-[290px]">
            <SelectedFlightCard
              details={details}
              arcColor={DEFAULT_ARC_COLOR}
              showThumbnail={false}
              closable={false}
              emptyHint="Example flights will appear here in a moment."
            />
          </div>
        </div>
      </div>

      <div className="w-[380px] max-w-full justify-self-center lg:justify-self-end">
        {/* Display-only: the tour drives it, visitors can't drag or click it. */}
        <FlightGlobe points={points} arcs={arcs} bare interactive={false} />
      </div>
    </div>
  );
}
