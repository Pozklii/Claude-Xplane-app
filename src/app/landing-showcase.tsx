"use client";

import { useEffect, useState } from "react";
import {
  DEFAULT_ARC_COLOR,
  FlightGlobe,
  type GlobeArc,
  type GlobePoint,
} from "./flights/flight-globe";
import {
  SelectedFlightCard,
  type FlightDetails,
} from "./flights/selected-flight-card";
import { SelectionProvider, useSelection } from "./flights/selection-context";
import styles from "./home.module.css";

// How long each example flight stays up, how long to wait for the globe to
// load before the first one, and how long a flight the visitor picked
// themselves (or a deselect) holds before the tour carries on.
const DWELL_MS = 7000;
const FIRST_DELAY_MS = 1500;
const HOLD_AFTER_VISITOR_MS = 20000;

function shuffle<T>(items: T[]) {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

// The landing page hero's content: its heading/CTA and a summary card for
// the current example flight on the left, the globe on the right. The
// globe tours the example flights in a random order — selecting each in
// turn, which flies the camera onto it — until the visitor pauses it.
export function LandingShowcase(props: {
  header: React.ReactNode;
  points: GlobePoint[];
  arcs: GlobeArc[];
  details: Record<string, FlightDetails>;
}) {
  return (
    <SelectionProvider>
      <Showcase {...props} />
    </SelectionProvider>
  );
}

function Showcase({
  header,
  points,
  arcs,
  details,
}: {
  header: React.ReactNode;
  points: GlobePoint[];
  arcs: GlobeArc[];
  details: Record<string, FlightDetails>;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const [paused, setPaused] = useState(false);
  // Shuffled on the first advance (a timer callback, so never during
  // render, which keeps the server and client renders identical).
  const [order, setOrder] = useState<string[] | null>(null);
  // The flight the tour itself last selected — anything else selected
  // means the visitor chose it (or cleared it) themselves.
  const [tourFlightId, setTourFlightId] = useState<string | null>(null);

  const visitorChose = selectedFlightId !== tourFlightId;
  const delay =
    order === null
      ? FIRST_DELAY_MS
      : visitorChose
        ? HOLD_AFTER_VISITOR_MS
        : DWELL_MS;

  useEffect(() => {
    if (paused) return;
    const timer = window.setTimeout(() => {
      const tour = order ?? shuffle(arcs.map((arc) => arc.id));
      if (!order) setOrder(tour);
      const current = selectedFlightId ? tour.indexOf(selectedFlightId) : -1;
      const next = tour[(current + 1) % tour.length];
      setTourFlightId(next);
      setSelectedFlightId(next);
    }, delay);
    return () => window.clearTimeout(timer);
  }, [paused, delay, order, selectedFlightId, arcs, setSelectedFlightId]);

  const position =
    order && selectedFlightId ? order.indexOf(selectedFlightId) + 1 : 0;

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
              Example flight
              {position > 0 ? ` · ${position} of ${arcs.length}` : "s"}
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
          <div className="min-h-[248px]">
            <SelectedFlightCard
              details={details}
              arcColor={DEFAULT_ARC_COLOR}
              showThumbnail={false}
              closable={false}
              emptyHint="Click a route on the globe to see an example flight."
            />
          </div>
        </div>
      </div>

      <div className="w-[380px] max-w-full justify-self-center lg:justify-self-end">
        <FlightGlobe points={points} arcs={arcs} bare />
      </div>
    </div>
  );
}
