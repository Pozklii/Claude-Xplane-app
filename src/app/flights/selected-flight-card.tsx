"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { formatDate, formatDuration } from "@/lib/dates";
import { AirlineLogo } from "./airline-logo";
import { Flag } from "./flag";
import { useSelection } from "./selection-context";
import { ThumbnailPicker, type ThumbnailChoice } from "./thumbnail-picker";
import styles from "./selected-flight.module.css";

export type FlightDetails = {
  date: string;
  airline: string | null;
  aircraft: string;
  from: { code: string; city: string; country?: string | null };
  to: { code: string; city: string; country?: string | null };
  /** IATA code of the airline, for its logo. */
  airlineIata?: string | null;
  /** The user's 1–10 rating, if any. */
  rating?: number | null;
  hours: number;
  distanceNm: number;
  notes: string | null;
  /** Signed URL of the thumbnail to show: the user's chosen one, else the
   * flight's first uploaded image, else null (a drawn route instead). */
  thumbnailUrl: string | null;
  /** Storage path of the user's chosen thumbnail, if they've picked one. */
  customThumbnailPath: string | null;
  /** The flight's uploaded images, offered as thumbnail choices. */
  images: ThumbnailChoice[];
};

const KM_PER_NM = 1.852;
const COUNT_UP_MS = 900;

const formatInteger = (n: number) => Math.round(n).toLocaleString("en-US");

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
  userId,
  showThumbnail = true,
  closable = true,
  emptyHint = "Select a route on the globe, or a flight below, to see its details.",
  prominent = false,
}: {
  details: Record<string, FlightDetails>;
  arcColor: string;
  /** The signed-in user; thumbnail editing is only offered when set. */
  userId?: string;
  showThumbnail?: boolean;
  closable?: boolean;
  emptyHint?: React.ReactNode;
  /** The flights page's version: bigger, with the airline (its logo large)
   * heading the card and a glow in the route colour, so the selected
   * flight is the focus. */
  prominent?: boolean;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const flight = selectedFlightId ? details[selectedFlightId] : undefined;
  // Which flight the thumbnail picker is open for, so it closes by itself
  // when a different flight is selected.
  const [pickerFlightId, setPickerFlightId] = useState<string | null>(null);

  if (!selectedFlightId || !flight) {
    return <p className={`${styles.hint} text-sm`}>{emptyHint}</p>;
  }

  const distanceKm = flight.distanceNm * KM_PER_NM;
  const pickerOpen = pickerFlightId === selectedFlightId;
  const hasThumbnail = flight.thumbnailUrl !== null;

  return (
    // Keyed by flight so every new selection replays the entrance.
    <article
      key={selectedFlightId}
      className={`${styles.card} ${prominent ? styles.prominent : ""}`}
      style={{ "--arc-color": arcColor } as React.CSSProperties}
      aria-live="polite"
    >
      {prominent && flight.airline && (
        <div
          className={`${styles.reveal} ${styles.airlineHeader} flex items-center gap-3`}
          style={{ "--i": 0 } as React.CSSProperties}
        >
          <AirlineLogo name={flight.airline} iata={flight.airlineIata ?? null} size="lg" />
          <div className="flex min-w-0 flex-col">
            <span className={`${styles.route} text-base font-semibold`}>
              {flight.airline}
            </span>
            <span className={`${styles.soft} text-xs`}>{flight.aircraft}</span>
          </div>
        </div>
      )}

      {showThumbnail && (
        <div className={styles.thumb}>
          {flight.thumbnailUrl ? (
            // Keyed by URL so a newly chosen thumbnail eases in too.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={flight.thumbnailUrl}
              src={flight.thumbnailUrl}
              alt={`${flight.from.code} to ${flight.to.code}`}
            />
          ) : (
            <RoutePlaceholder from={flight.from.code} to={flight.to.code} />
          )}
          {userId && !pickerOpen && (
            <button
              type="button"
              onClick={() => setPickerFlightId(selectedFlightId)}
              className={styles.thumbButton}
            >
              <svg viewBox="0 0 16 16" aria-hidden="true">
                <rect x="1.5" y="2.5" width="13" height="11" rx="1.5" />
                <circle cx="5.5" cy="6.5" r="1.3" />
                <path d="M2 12l3.8-3.6 2.7 2.4 2.2-2 3.3 3.2" />
              </svg>
              {hasThumbnail ? "Change thumbnail" : "Add thumbnail"}
            </button>
          )}
        </div>
      )}

      {userId && pickerOpen && (
        <ThumbnailPicker
          userId={userId}
          flightId={selectedFlightId}
          images={flight.images}
          currentThumbnailPath={flight.customThumbnailPath}
          onDone={() => setPickerFlightId(null)}
        />
      )}

      <div
        className={`${styles.reveal} flex items-start justify-between gap-3`}
        style={{ "--i": 0 } as React.CSSProperties}
      >
        <div className="flex flex-col gap-0.5">
          <h2
            className={`${styles.route} ${prominent ? "text-2xl" : "text-lg"} font-semibold`}
          >
            {flight.from.code} &rarr; {flight.to.code}
          </h2>
          <p
            className={`${styles.soft} flex flex-wrap items-center gap-1 ${prominent ? "text-sm" : "text-xs"}`}
          >
            <span className="inline-flex items-center gap-1.5">
              <Flag country={flight.from.country} />
              {flight.from.city}
            </span>
            <span>to</span>
            <span className="inline-flex items-center gap-1.5">
              <Flag country={flight.to.country} />
              {flight.to.city}
            </span>
          </p>
        </div>
        {closable && (
          <button
            type="button"
            onClick={() => setSelectedFlightId(null)}
            className={styles.close}
            aria-label="Close flight details"
          >
            &times;
          </button>
        )}
      </div>

      <dl
        className={`${styles.reveal} grid grid-cols-2 gap-3`}
        style={{ "--i": 1 } as React.CSSProperties}
      >
        <div className="flex flex-col gap-1">
          <dt className={styles.label}>Distance</dt>
          <dd
            className={`${styles.stat} ${prominent ? "text-xl" : "text-base"} font-semibold`}
          >
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
          <dd
            className={`${styles.stat} ${prominent ? "text-xl" : "text-base"} font-semibold`}
          >
            <CountUp value={flight.hours} format={formatDuration} />
          </dd>
          {flight.rating != null && (
            <dd className={`${styles.soft} text-[11px] tabular-nums`}>
              Rated {flight.rating}/10
            </dd>
          )}
        </div>
      </dl>

      <p
        className={`${styles.reveal} ${styles.soft} flex flex-wrap items-center gap-1.5 text-xs`}
        style={{ "--i": 2 } as React.CSSProperties}
      >
        {prominent && flight.airline ? (
          // The airline and aircraft already head the prominent card.
          formatDate(flight.date)
        ) : (
          <>
            {/* Only a real logo here, not the monogram fallback, which
                would read as clutter on the card (e.g. the landing page's
                examples). */}
            {flight.airline && flight.airlineIata && (
              <AirlineLogo name={flight.airline} iata={flight.airlineIata} />
            )}
            {formatDate(flight.date)} &middot; {flight.aircraft}
            {flight.airline ? ` · ${flight.airline}` : ""}
          </>
        )}
      </p>

      <section
        className={`${styles.reveal} flex flex-col gap-1`}
        style={{ "--i": 3 } as React.CSSProperties}
      >
        <h3 className={styles.label}>Notes</h3>
        {flight.notes ? (
          <p className={`${styles.notes} text-sm`}>{flight.notes}</p>
        ) : (
          <p className={`${styles.soft} text-sm`}>No notes for this flight.</p>
        )}
      </section>
    </article>
  );
}
