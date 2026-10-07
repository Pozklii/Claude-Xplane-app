"use client";

import Link from "next/link";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { formatDate, formatDuration } from "@/lib/dates";
import type { RecordingSummary } from "@/lib/recording";
import { formatAltitude, type SimbriefPlan } from "@/lib/simbrief";
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
  /** Gate and runway times (example flights), in minutes after midnight
   * on the flight's date; past 1440 is the next day. The card shows the
   * takeoff and landing times, as plain clock times. */
  times?: {
    departure?: number;
    takeoff?: number;
    landing?: number;
    arrival?: number;
  };
  /** Logged flights' extra details, where filled in. */
  landingRateFpm?: number | null;
  /** e.g. "Night". */
  conditions?: string | null;
  weather?: string | null;
  /** The SimBrief plan it was flown to, and the flown route's summary
   * (logged flights), for planned against actual. */
  plan?: SimbriefPlan | null;
  recording?: RecordingSummary | null;
  notes: string | null;
  /** Signed URL of the thumbnail to show: the user's chosen one, else the
   * flight's first uploaded image, else null (a drawn route instead). */
  thumbnailUrl: string | null;
  /** Storage path of the user's chosen thumbnail, if they've picked one. */
  customThumbnailPath: string | null;
  /** The flight's uploaded images, offered as thumbnail choices. */
  images: ThumbnailChoice[];
};

const MI_PER_NM = 1.15078;
const COUNT_UP_MS = 900;

const formatInteger = (n: number) => Math.round(n).toLocaleString("en-US");

// Minutes after midnight as a 24-hour time (a time past midnight, on the
// next day, just reads as that time).
function formatClock(minutes: number) {
  const m = ((Math.round(minutes) % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

const TIME_LABELS = [
  ["takeoff", "Takeoff"],
  ["landing", "Landing"],
] as const;

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

export function SelectedFlightCard({
  details,
  arcColor,
  userId,
  showThumbnail = true,
  closable = true,
  emptyHint = "Select a flight to see its details.",
  prominent = false,
  mapLink = false,
  aside,
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
  /** Link to the flight on the Flight Map page (from the Flight Log). */
  mapLink?: boolean;
  /** Shown beside the route and figures (e.g. the landing page's mini
   * globe), which then take the rest of the width. */
  aside?: React.ReactNode;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const flight = selectedFlightId ? details[selectedFlightId] : undefined;
  // Which flight the thumbnail picker is open for, so it closes by itself
  // when a different flight is selected.
  const [pickerFlightId, setPickerFlightId] = useState<string | null>(null);
  const cardRef = useRef<HTMLElement>(null);

  // On the flights page, choosing a flight (say, from the log further down)
  // brings its summary into view, unless it's already on screen.
  useEffect(() => {
    const card = cardRef.current;
    if (!prominent || !selectedFlightId || !card) return;
    const { top } = card.getBoundingClientRect();
    if (top >= 0 && top < window.innerHeight * 0.6) return;
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    card.scrollIntoView({
      behavior: reduce ? "auto" : "smooth",
      block: "start",
    });
  }, [prominent, selectedFlightId]);

  if (!selectedFlightId || !flight) {
    // A null hint: nothing at all until a flight is picked.
    if (emptyHint === null) return null;
    return <p className={`${styles.hint} text-sm`}>{emptyHint}</p>;
  }

  const distanceMi = flight.distanceNm * MI_PER_NM;
  const pickerOpen = pickerFlightId === selectedFlightId;
  const hasThumbnail = flight.thumbnailUrl !== null;

  return (
    // Keyed by flight so every new selection replays the entrance.
    <article
      key={selectedFlightId}
      ref={cardRef}
      className={`${styles.card} ${prominent ? styles.prominent : ""}`}
      style={{ "--arc-color": arcColor } as React.CSSProperties}
      aria-live="polite"
    >
      {prominent && flight.airline && (
        <div
          className={`${styles.reveal} ${styles.airlineHeader} flex items-center gap-3`}
          style={{ "--i": 0 } as React.CSSProperties}
        >
          <AirlineLogo
            name={flight.airline}
            iata={flight.airlineIata ?? null}
            size="lg"
          />
          <div className="flex min-w-0 flex-col">
            <span className={`${styles.route} text-base font-semibold`}>
              {flight.airline}
            </span>
            <span className={`${styles.soft} text-xs`}>{flight.aircraft}</span>
          </div>
        </div>
      )}

      {showThumbnail && (
        // Without an image of its own, a flight gets a slim block in its
        // route colour rather than a picture (the map already shows the
        // route).
        <div
          className={`${styles.thumb} ${flight.thumbnailUrl ? "" : styles.thumbBlock}`}
        >
          {flight.thumbnailUrl ? (
            // Keyed by URL so a newly chosen thumbnail eases in too.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={flight.thumbnailUrl}
              src={flight.thumbnailUrl}
              alt={`${flight.from.code} to ${flight.to.code}`}
            />
          ) : null}
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

      {/* With an aside, the route and figures form a column beside it;
          without, these wrappers drop out of the layout. */}
      <div className={aside ? "flex items-start gap-3" : "contents"}>
        <div
          className={aside ? "flex min-w-0 flex-1 flex-col gap-4" : "contents"}
        >
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
                  value={distanceMi}
                  format={(n) => `${formatInteger(n)} mi`}
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
                  Flight rating {flight.rating}/10
                </dd>
              )}
            </div>
            {flight.times &&
              TIME_LABELS.map(([key, label]) => {
                if (flight.times?.[key] == null) return null;
                return (
                  <div key={key} className="flex flex-col gap-1">
                    <dt className={styles.label}>{label}</dt>
                    <dd
                      className={`${styles.stat} text-base font-semibold tabular-nums`}
                    >
                      {formatClock(flight.times![key]!)}
                    </dd>
                  </div>
                );
              })}
            {flight.landingRateFpm != null && (
              <div className="flex flex-col gap-1">
                <dt className={styles.label}>Landing rate</dt>
                <dd
                  className={`${styles.stat} text-base font-semibold tabular-nums`}
                >
                  {formatInteger(flight.landingRateFpm)} fpm
                </dd>
              </div>
            )}
          </dl>
        </div>
        {aside && (
          <div
            className={`${styles.reveal} shrink-0`}
            style={{ "--i": 1 } as React.CSSProperties}
          >
            {aside}
          </div>
        )}
      </div>
      <p
        className={`${styles.reveal} ${styles.soft} flex flex-wrap items-center gap-1.5 text-xs`}
        style={{ "--i": 2 } as React.CSSProperties}
      >
        {prominent && flight.airline ? (
          // The airline and aircraft already head the prominent card.
          <>
            {formatDate(flight.date)}
            {flight.conditions ? ` · ${flight.conditions}` : ""}
          </>
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
            {flight.conditions ? ` · ${flight.conditions}` : ""}
          </>
        )}
      </p>

      {(flight.plan || flight.recording) && (
        <PlannedVsFlown flight={flight} showLegend={prominent} />
      )}

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
        {flight.weather && (
          <p className={`${styles.soft} text-xs`}>Weather: {flight.weather}</p>
        )}
      </section>

      {mapLink && (
        <Link
          href={`/flights?flight=${encodeURIComponent(selectedFlightId)}`}
          className={`${styles.reveal} ${styles.mapLink} self-start text-sm font-medium`}
          style={{ "--i": 4 } as React.CSSProperties}
        >
          Show on Flight Map &rarr;
        </Link>
      )}
    </article>
  );
}

const KG_TO_LB = 2.20462;

// A logged flight's SimBrief plan against how it was flown (its logged
// times and recorded route), row by row where either side is known; and,
// on the Flight Map, a key to the flown route drawn beside the arc.
function PlannedVsFlown({
  flight,
  showLegend,
}: {
  flight: FlightDetails;
  showLegend: boolean;
}) {
  const { plan, recording } = flight;
  const airborneMinutes =
    flight.times?.takeoff != null && flight.times?.landing != null
      ? (flight.times.landing - flight.times.takeoff + 1440) % 1440 || null
      : null;
  const fuelUnit = plan?.fuelUnit ?? "kg";
  const fuel = (amount: number) =>
    `${Math.round(amount).toLocaleString("en-US")} ${fuelUnit}`;
  const fuelUsed =
    recording?.fuelUsedKg != null
      ? recording.fuelUsedKg * (fuelUnit === "lb" ? KG_TO_LB : 1)
      : null;
  const nm = (n: number) => `${formatInteger(n)} nm`;
  const rows = (
    [
      [
        "Block time",
        plan?.blockMinutes != null
          ? formatDuration(plan.blockMinutes / 60)
          : null,
        plan ? formatDuration(flight.hours) : null,
      ],
      [
        "Time in the air",
        plan?.eteMinutes != null ? formatDuration(plan.eteMinutes / 60) : null,
        airborneMinutes !== null ? formatDuration(airborneMinutes / 60) : null,
      ],
      [
        "Distance",
        plan?.distanceNm != null ? nm(plan.distanceNm) : null,
        recording ? nm(recording.distanceNm) : null,
      ],
      [
        plan ? "Cruise" : "Highest",
        plan?.cruiseAltitudeFt != null
          ? formatAltitude(plan.cruiseAltitudeFt)
          : null,
        recording?.maxAltitudeFt != null
          ? formatAltitude(recording.maxAltitudeFt)
          : null,
      ],
      [
        "Fuel burned",
        plan?.fuelBurn != null ? fuel(plan.fuelBurn) : null,
        fuelUsed !== null ? fuel(fuelUsed) : null,
      ],
    ] as [string, string | null, string | null][]
  ).filter(([, planned, flown]) => planned !== null || flown !== null);

  return (
    <section
      className={`${styles.reveal} flex flex-col gap-1.5`}
      style={{ "--i": 3 } as React.CSSProperties}
    >
      <h3 className={styles.label}>
        {plan ? "Planned vs flown" : "As flown"}
        {plan ? " (SimBrief)" : ""}
      </h3>
      {rows.length > 0 && (
        <table className="w-full text-xs tabular-nums">
          {plan && (
            <thead>
              <tr className={styles.soft}>
                <th className="py-0.5 text-left font-normal" />
                <th className="py-0.5 text-right font-normal">Planned</th>
                <th className="py-0.5 text-right font-normal">Flown</th>
              </tr>
            </thead>
          )}
          <tbody>
            {rows.map(([label, planned, flown]) => (
              <tr key={label}>
                <th className={`${styles.soft} py-0.5 text-left font-normal`}>
                  {label}
                </th>
                {plan && (
                  <td className={`${styles.stat} py-0.5 text-right`}>
                    {planned ?? "–"}
                  </td>
                )}
                <td className={`${styles.stat} py-0.5 text-right font-semibold`}>
                  {flown ?? "–"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {plan?.route && (
        <p className={`${styles.soft} break-words font-mono text-[10px]`}>
          {plan.route}
        </p>
      )}
      {showLegend && recording && (
        <p className={`${styles.soft} flex flex-wrap items-center gap-3 text-[11px]`}>
          <span className="inline-flex items-center gap-1.5">
            <span
              className="inline-block h-0.5 w-4 rounded"
              style={{ background: "rgb(255 214 140)" }}
            />
            Flown route
            {recording.source === "xplane" ? " (X-Plane)" : ""}
          </span>
          <span className="inline-flex items-center gap-1.5">
            <span
              className="inline-block h-0.5 w-4 rounded"
              style={{ background: "var(--arc-color)" }}
            />
            Great circle
          </span>
        </p>
      )}
    </section>
  );
}
