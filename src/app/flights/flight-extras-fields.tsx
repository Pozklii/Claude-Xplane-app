"use client";

import { useEffect, useId, useRef, useState } from "react";
import {
  airborneHours,
  CONDITIONS,
  FUEL_UNITS,
  shortTime,
  type FlightExtras,
} from "@/lib/flight-fields";
import { lookupAirport } from "./airport-actions";

const EXTRA_KEYS = [
  "takeoff_time",
  "landing_time",
  "landing_rate_fpm",
  "fuel_used",
  "conditions",
  "weather",
] as const;

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const labelClass = "text-xs font-medium uppercase tracking-wide text-zinc-500";
const chipClass =
  "rounded-full border border-black/[.08] px-2.5 py-0.5 text-xs text-zinc-700 transition-colors hover:bg-black/[.04] disabled:opacity-50 dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

/** The form a field sits in, for reading or setting its siblings. */
const formOf = (element: HTMLElement) => element.closest("form");
const formField = (form: HTMLFormElement | null, name: string) =>
  form?.elements.namedItem(name) as HTMLInputElement | null;

// The optional extra details of a logged flight, as a collapsible part of
// the forms that log and edit flights (field names read by parseExtras in
// flight-fields.ts): takeoff and landing times (offering the time between
// them as the flight's hours), landing rate, fuel used, day or night, and
// the weather (with the arrival airport's current METAR a click away).
export function FlightExtrasFields({
  defaults,
  onUseHours,
}: {
  defaults?: Partial<FlightExtras>;
  /** Fills the form's hours from the takeoff and landing times; without
   * it, the form's "hours" input is set directly. */
  onUseHours?: (hours: number) => void;
}) {
  const id = useId();
  const [takeoff, setTakeoff] = useState(
    shortTime(defaults?.takeoff_time ?? null) ?? "",
  );
  const [landing, setLanding] = useState(
    shortTime(defaults?.landing_time ?? null) ?? "",
  );
  const [weather, setWeather] = useState(defaults?.weather ?? "");
  const [metarState, setMetarState] = useState<
    { status: "idle" | "loading" } | { status: "error"; message: string }
  >({ status: "idle" });
  const airborne = airborneHours(takeoff || null, landing || null);

  // The form's reset (after logging a flight) clears these too, like its
  // other fields.
  const detailsRef = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const form = detailsRef.current?.closest("form");
    if (!form) return;
    const reset = () => {
      setTakeoff(shortTime(defaults?.takeoff_time ?? null) ?? "");
      setLanding(shortTime(defaults?.landing_time ?? null) ?? "");
      setWeather(defaults?.weather ?? "");
      setMetarState({ status: "idle" });
    };
    form.addEventListener("reset", reset);
    return () => form.removeEventListener("reset", reset);
  }, [defaults]);
  const hasDefaults =
    defaults != null &&
    EXTRA_KEYS.some((key) => defaults[key] != null && defaults[key] !== "");

  const fillHours = (button: HTMLButtonElement) => {
    if (airborne === null) return;
    const hours = Math.max(0.1, Math.round(airborne * 10) / 10);
    if (onUseHours) onUseHours(hours);
    else {
      const input = formField(formOf(button), "hours");
      if (input) input.value = hours.toFixed(1);
    }
  };

  const fetchMetar = async (button: HTMLButtonElement) => {
    const code = formField(formOf(button), "arrival")
      ?.value.trim()
      .toUpperCase();
    if (!code || !/^[A-Z0-9]{3,4}$/.test(code)) {
      setMetarState({
        status: "error",
        message: "Enter the arrival airport first.",
      });
      return;
    }
    setMetarState({ status: "loading" });
    try {
      // NOAA's reports are by ICAO code; an IATA one is looked up first.
      const station = (await lookupAirport(code))?.icao ?? code;
      const res = await fetch(`/api/metar?ids=${encodeURIComponent(station)}`);
      if (!res.ok) throw new Error(`METAR ${res.status}`);
      const body = (await res.json()) as {
        metars?: Record<string, { raw: string }>;
      };
      const raw = body.metars?.[station]?.raw;
      if (!raw) {
        setMetarState({
          status: "error",
          message: `No current METAR for ${station}.`,
        });
        return;
      }
      setWeather(raw);
      setMetarState({ status: "idle" });
    } catch {
      setMetarState({
        status: "error",
        message: "The weather service is unavailable right now.",
      });
    }
  };

  return (
    <details
      ref={detailsRef}
      open={hasDefaults || undefined}
      className="group rounded-xl bg-zinc-50 px-3 py-2 dark:bg-zinc-900/60"
    >
      <summary className="cursor-pointer select-none py-1 text-sm font-medium text-zinc-700 dark:text-zinc-300">
        More details{" "}
        <span className="font-normal text-zinc-500">
          (optional: times, landing rate, fuel, conditions, weather)
        </span>
      </summary>
      <div className="flex flex-col gap-3 pb-2 pt-3">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-takeoff`} className={labelClass}>
              Takeoff
            </label>
            <input
              id={`${id}-takeoff`}
              name="takeoffTime"
              type="time"
              value={takeoff}
              onChange={(event) => setTakeoff(event.target.value)}
              className={fieldClass}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-landing`} className={labelClass}>
              Landing
            </label>
            <input
              id={`${id}-landing`}
              name="landingTime"
              type="time"
              value={landing}
              onChange={(event) => setLanding(event.target.value)}
              className={fieldClass}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-rate`} className={labelClass}>
              Landing rate (fpm)
            </label>
            <input
              id={`${id}-rate`}
              name="landingRate"
              type="number"
              inputMode="numeric"
              min="0"
              max="5000"
              step="1"
              placeholder="e.g. 180"
              defaultValue={defaults?.landing_rate_fpm ?? ""}
              className={`${fieldClass} tabular-nums`}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-conditions`} className={labelClass}>
              Conditions
            </label>
            <select
              id={`${id}-conditions`}
              name="conditions"
              defaultValue={defaults?.conditions ?? ""}
              className={fieldClass}
            >
              <option value="">Not set</option>
              {CONDITIONS.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </div>
        </div>

        {airborne !== null && (
          <p className="flex flex-wrap items-center gap-2 text-xs text-zinc-600 dark:text-zinc-400">
            <span>
              Takeoff to landing: {Math.floor(airborne)}h{" "}
              {String(Math.round((airborne % 1) * 60)).padStart(2, "0")}m.
            </span>
            <button
              type="button"
              onClick={(event) => fillHours(event.currentTarget)}
              className={chipClass}
            >
              Use as hours (
              {Math.max(0.1, Math.round(airborne * 10) / 10).toFixed(1)}h)
            </button>
          </p>
        )}

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-fuel`} className={labelClass}>
              Fuel used
            </label>
            <input
              id={`${id}-fuel`}
              name="fuelUsed"
              type="number"
              inputMode="decimal"
              min="0"
              step="any"
              placeholder="e.g. 2400"
              defaultValue={defaults?.fuel_used ?? ""}
              className={`${fieldClass} tabular-nums`}
            />
          </div>
          <div className="flex min-w-0 flex-col gap-1.5">
            <label htmlFor={`${id}-unit`} className={labelClass}>
              Unit
            </label>
            <select
              id={`${id}-unit`}
              name="fuelUnit"
              defaultValue={defaults?.fuel_unit ?? "kg"}
              className={fieldClass}
            >
              {FUEL_UNITS.map((unit) => (
                <option key={unit} value={unit}>
                  {unit}
                </option>
              ))}
            </select>
          </div>
          <div className="col-span-2 flex min-w-0 flex-col gap-1.5">
            <div className="flex items-center justify-between gap-2">
              <label htmlFor={`${id}-weather`} className={labelClass}>
                Weather
              </label>
              <button
                type="button"
                disabled={metarState.status === "loading"}
                onClick={(event) => fetchMetar(event.currentTarget)}
                className={chipClass}
              >
                {metarState.status === "loading"
                  ? "Fetching…"
                  : "Arrival's current METAR"}
              </button>
            </div>
            <input
              id={`${id}-weather`}
              name="weather"
              maxLength={500}
              placeholder="METAR, or a few words"
              value={weather}
              onChange={(event) => setWeather(event.target.value)}
              className={`${fieldClass} font-mono text-xs`}
            />
            {metarState.status === "error" && (
              <p className="text-xs text-red-600 dark:text-red-400">
                {metarState.message}
              </p>
            )}
          </div>
        </div>
      </div>
    </details>
  );
}
