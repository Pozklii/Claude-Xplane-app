"use client";

import { useEffect, useState } from "react";
import { estimateHours, KNOWN_AIRCRAFT } from "@/lib/aircraft";
import { formatDuration } from "@/lib/dates";
import { distanceNm, initialCourse } from "@/lib/geo";
import { lookupAirport, type AirportLookup } from "./airport-actions";
import { AirlineLogo } from "./airline-logo";
import { Flag } from "./flag";
import { ROUTE_PLAN_ID, usePlanner } from "./planner-context";

const KM_PER_NM = 1.852;
const MI_PER_NM = 1.15078;
// A typical airliner's average ground speed over a whole trip, for a rough
// flight time.
const AVERAGE_KT = 450;

const CODE = /^[A-Z0-9]{3,4}$/;
const fmt = (n: number) => Math.round(n).toLocaleString("en-US");

// Looks an airport code up as it's typed (once it's a plausible code).
function useAirport(code: string) {
  const [result, setResult] = useState<{
    code: string;
    airport: AirportLookup | null;
  } | null>(null);
  useEffect(() => {
    if (!CODE.test(code)) return;
    let cancelled = false;
    lookupAirport(code).then((airport) => {
      if (!cancelled) setResult({ code, airport });
    });
    return () => {
      cancelled = true;
    };
  }, [code]);
  if (!CODE.test(code)) return { state: "empty" as const };
  if (result?.code !== code) return { state: "loading" as const };
  return result.airport
    ? { state: "found" as const, airport: result.airport }
    : { state: "missing" as const };
}

function AirportField({
  label,
  value,
  onChange,
  lookup,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  lookup: ReturnType<typeof useAirport>;
}) {
  const id = `route-${label.toLowerCase()}`;
  return (
    <div className="flex min-w-0 flex-1 flex-col gap-1.5">
      <label
        htmlFor={id}
        className="text-xs font-medium uppercase tracking-wide text-zinc-500"
      >
        {label}
      </label>
      <input
        id={id}
        value={value}
        onChange={(event) =>
          onChange(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))
        }
        placeholder="e.g. EGLL or LHR"
        maxLength={4}
        autoComplete="off"
        className="w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-base font-semibold uppercase tracking-wide text-black outline-none placeholder:font-normal placeholder:normal-case placeholder:tracking-normal focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
      />
      <p className="flex min-h-5 items-center gap-1.5 truncate text-xs text-zinc-500">
        {lookup.state === "found" && (
          <>
            <Flag country={lookup.airport.country?.code} />
            <span className="truncate">
              {lookup.airport.name}
              {lookup.airport.city ? `, ${lookup.airport.city}` : ""}
            </span>
          </>
        )}
        {lookup.state === "loading" && "Looking up…"}
        {lookup.state === "missing" && "No airport with that code."}
      </p>
    </div>
  );
}

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";

// The Flight Plan page's route: a From and To airport, the airline and
// aircraft, and the distance between the airports (great circle), with the
// initial heading and a flight time for the aircraft. Choosing a suggested
// route or a challenge further down the page loads it here (see loadPlan).
// Each airport's details and weather are a click away.
export function RoutePlanner({
  airlines,
}: {
  /** Airlines to suggest, with IATA codes for their logos. */
  airlines: { name: string; iata: string | null }[];
}) {
  const { openAirport, plan, updatePlan, planLoads } = usePlanner();
  const { from, to, airline, aircraft } = plan;
  const setFrom = (value: string) => updatePlan({ from: value });
  const setTo = (value: string) => updatePlan({ to: value });
  const fromLookup = useAirport(from);
  const toLookup = useAirport(to);
  const airlineIata =
    airlines.find((a) => a.name.toLowerCase() === airline.trim().toLowerCase())
      ?.iata ?? null;
  const knownAircraft = KNOWN_AIRCRAFT.find(
    (name) => name.toLowerCase() === aircraft.trim().toLowerCase(),
  );

  const both =
    fromLookup.state === "found" && toLookup.state === "found"
      ? { a: fromLookup.airport, b: toLookup.airport }
      : null;
  const nm = both ? distanceNm(both.a, both.b) : null;
  const course = both ? initialCourse(both.a, both.b) : null;
  // The chosen aircraft's own cruise speed and overheads, when it's one we
  // know; otherwise a typical airliner's average.
  const hours =
    nm === null
      ? null
      : knownAircraft
        ? estimateHours(knownAircraft, nm)
        : nm / AVERAGE_KT;

  return (
    <div
      id={ROUTE_PLAN_ID}
      // Keyed by loads, so a newly loaded flight replays the highlight.
      key={planLoads}
      className={`flex scroll-mt-6 flex-col gap-4 rounded-xl bg-zinc-50 p-4 dark:bg-zinc-900/60 ${planLoads > 0 ? "motion-safe:animate-[planLoaded_1.6s_ease-out]" : ""}`}
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start">
        <AirportField
          label="From"
          value={from}
          onChange={setFrom}
          lookup={fromLookup}
        />
        <button
          type="button"
          onClick={() => {
            setFrom(to);
            setTo(from);
          }}
          aria-label="Swap From and To"
          title="Swap"
          className="self-center rounded-full border border-black/[.08] p-2 text-zinc-600 transition-colors hover:bg-black/[.04] sm:mt-6 dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
        >
          <svg
            viewBox="0 0 16 16"
            width="14"
            height="14"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d="M3 5h9l-2.5-2.5M13 11H4l2.5 2.5" />
          </svg>
        </button>
        <AirportField
          label="To"
          value={to}
          onChange={setTo}
          lookup={toLookup}
        />
      </div>

      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <label
            htmlFor="route-airline"
            className="text-xs font-medium uppercase tracking-wide text-zinc-500"
          >
            Airline
          </label>
          <div className="flex items-center gap-2">
            {airline.trim() && (
              <AirlineLogo name={airline.trim()} iata={airlineIata} />
            )}
            <input
              id="route-airline"
              list="route-airlines"
              value={airline}
              onChange={(event) => updatePlan({ airline: event.target.value })}
              placeholder="Any airline, or private"
              autoComplete="off"
              className={fieldClass}
            />
          </div>
          <datalist id="route-airlines">
            {airlines.map((a) => (
              <option key={a.name} value={a.name} />
            ))}
          </datalist>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <label
            htmlFor="route-aircraft"
            className="text-xs font-medium uppercase tracking-wide text-zinc-500"
          >
            Aircraft
          </label>
          <input
            id="route-aircraft"
            list="route-aircraft-types"
            value={aircraft}
            onChange={(event) => updatePlan({ aircraft: event.target.value })}
            placeholder="e.g. Boeing 737-800"
            autoComplete="off"
            className={fieldClass}
          />
          <datalist id="route-aircraft-types">
            {KNOWN_AIRCRAFT.map((name) => (
              <option key={name} value={name} />
            ))}
          </datalist>
        </div>
      </div>

      {both && nm !== null && course !== null && hours !== null ? (
        <div className="flex flex-col gap-3 border-t border-black/[.06] pt-4 sm:flex-row sm:items-end sm:justify-between dark:border-white/[.08]">
          <div className="flex flex-col gap-1">
            <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">
              {both.a.code} &rarr; {both.b.code} distance
            </p>
            <p className="text-3xl font-semibold tabular-nums text-black dark:text-zinc-50">
              {fmt(nm)} nm
            </p>
            <p className="text-sm tabular-nums text-zinc-500">
              {fmt(nm * KM_PER_NM)} km &middot; {fmt(nm * MI_PER_NM)} mi
              &middot; initial heading{" "}
              {String(Math.round(course) % 360).padStart(3, "0")}&deg; &middot;
              about {formatDuration(hours)}{" "}
              {knownAircraft ? `in a ${knownAircraft}` : `at ${AVERAGE_KT} kt`}
            </p>
          </div>
          <div className="flex gap-2">
            {[both.a, both.b].map((airport) => (
              <button
                key={airport.code}
                type="button"
                onClick={() => openAirport(airport.code)}
                className="whitespace-nowrap rounded-full border border-black/[.08] px-3 py-1.5 text-xs text-zinc-700 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]"
              >
                {airport.code} weather &amp; info
              </button>
            ))}
          </div>
        </div>
      ) : (
        <p className="text-sm text-zinc-500">
          Enter two airports (ICAO or IATA codes) to see the distance between
          them.
        </p>
      )}
    </div>
  );
}
