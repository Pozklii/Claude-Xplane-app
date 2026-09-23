"use client";

import { useLayoutEffect, useRef } from "react";
import { useSelection } from "./selection-context";
import styles from "./selected-flight.module.css";

export type FlightDetails = {
  date: string;
  airline: string | null;
  aircraft: string;
  from: { code: string; city: string };
  to: { code: string; city: string };
  hours: number;
  distanceNm: number;
  /** A signed URL for the flight's first uploaded image, if it has one. */
  thumbnailUrl: string | null;
};

const KM_PER_NM = 1.852;
const COUNT_UP_MS = 900;

const formatInteger = (n: number) => Math.round(n).toLocaleString("en-US");

function formatDuration(hours: number) {
  const totalMinutes = Math.round(hours * 60);
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
}

// Counts up from 0 to `value` once on mount by writing straight to the
// DOM node, so it doesn't re-render the card every frame. The server/first
// render already holds the final text, so without motion (or JS) the
// resting state is correct; the layout effect resets it to 0 before the
// first paint so there's no flash of the final value.
function CountUp({
  value,
  format,
}: {
  value: number;
  format: (n: number) => string;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const formatRef = useRef(format);

  useLayoutEffect(() => {
    const node = ref.current;
    if (!node) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frame = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / COUNT_UP_MS);
      const eased = 1 - Math.pow(1 - t, 3);
      node.textContent = formatRef.current(value * eased);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    node.textContent = formatRef.current(0);
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value]);

  return <span ref={ref}>{format(value)}</span>;
}

// Stand-in thumbnail for a flight with no uploaded image: its route drawn
// as a great-circle-ish curve between the two airport codes.
function RoutePlaceholder({ from, to }: { from: string; to: string }) {
  return (
    <svg viewBox="0 0 320 180" role="img" aria-label={`${from} to ${to}`}>
      <defs>
        <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
          <path d="M20 0H0V20" fill="none" stroke="#12293b" strokeWidth="1" />
        </pattern>
      </defs>
      <rect width="320" height="180" fill="url(#grid)" />
      <path
        className={styles.routeLine}
        d="M48 128 Q160 20 272 128"
        fill="none"
        stroke="var(--arc-color)"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <circle cx="48" cy="128" r="4" fill="var(--arc-color)" />
      <circle cx="272" cy="128" r="4" fill="var(--arc-color)" />
      <text
        x="48"
        y="154"
        textAnchor="middle"
        fill="#dcedf7"
        fontSize="14"
        fontWeight="600"
      >
        {from}
      </text>
      <text
        x="272"
        y="154"
        textAnchor="middle"
        fill="#dcedf7"
        fontSize="14"
        fontWeight="600"
      >
        {to}
      </text>
    </svg>
  );
}

export function SelectedFlightCard({
  details,
  arcColor,
}: {
  details: Record<string, FlightDetails>;
  arcColor: string;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const flight = selectedFlightId ? details[selectedFlightId] : undefined;

  if (!selectedFlightId || !flight) {
    return (
      <p className={`${styles.hint} text-sm`}>
        Select a route on the globe, or a flight below, to see its details.
      </p>
    );
  }

  const distanceKm = flight.distanceNm * KM_PER_NM;
  const speedKts = flight.hours > 0 ? flight.distanceNm / flight.hours : null;

  return (
    // Keyed by flight so every new selection replays the entrance.
    <article
      key={selectedFlightId}
      className={styles.card}
      style={{ "--arc-color": arcColor } as React.CSSProperties}
      aria-live="polite"
    >
      <div className={styles.thumb}>
        {flight.thumbnailUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={flight.thumbnailUrl}
            alt={`${flight.from.code} to ${flight.to.code}`}
          />
        ) : (
          <RoutePlaceholder from={flight.from.code} to={flight.to.code} />
        )}
      </div>

      <div
        className={`${styles.reveal} flex items-start justify-between gap-3`}
        style={{ "--i": 0 } as React.CSSProperties}
      >
        <div className="flex flex-col gap-0.5">
          <h2 className={`${styles.route} text-lg font-semibold`}>
            {flight.from.code} &rarr; {flight.to.code}
          </h2>
          <p className={`${styles.soft} text-xs`}>
            {flight.from.city} to {flight.to.city}
          </p>
        </div>
        <button
          type="button"
          onClick={() => setSelectedFlightId(null)}
          className={styles.close}
          aria-label="Close flight details"
        >
          &times;
        </button>
      </div>

      <dl
        className={`${styles.reveal} grid grid-cols-3 gap-3`}
        style={{ "--i": 1 } as React.CSSProperties}
      >
        <div className="flex flex-col gap-1">
          <dt className={styles.label}>Distance</dt>
          <dd className={`${styles.stat} text-base font-semibold`}>
            <CountUp
              value={flight.distanceNm}
              format={(n) => `${formatInteger(n)} nm`}
            />
          </dd>
          <dd className={`${styles.soft} text-[11px] tabular-nums`}>
            <CountUp
              value={distanceKm}
              format={(n) => `${formatInteger(n)} km`}
            />
          </dd>
        </div>
        <div className="flex flex-col gap-1">
          <dt className={styles.label}>Flight time</dt>
          <dd className={`${styles.stat} text-base font-semibold`}>
            <CountUp value={flight.hours} format={formatDuration} />
          </dd>
        </div>
        <div className="flex flex-col gap-1">
          <dt className={styles.label}>Avg speed</dt>
          <dd className={`${styles.stat} text-base font-semibold`}>
            {speedKts === null ? (
              "—"
            ) : (
              <CountUp
                value={speedKts}
                format={(n) => `${formatInteger(n)} kt`}
              />
            )}
          </dd>
        </div>
      </dl>

      <p
        className={`${styles.reveal} ${styles.soft} text-xs`}
        style={{ "--i": 2 } as React.CSSProperties}
      >
        {flight.date} &middot; {flight.aircraft}
        {flight.airline ? ` · ${flight.airline}` : ""}
      </p>
    </article>
  );
}
