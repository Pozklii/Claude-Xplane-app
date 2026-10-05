"use client";

import { useEffect, useId, useRef, useState } from "react";
import {
  airborneHours,
  CONDITIONS,
  shortTime,
  WEATHER_OPTIONS,
  type FlightExtras,
} from "@/lib/flight-fields";

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const labelClass = "text-xs font-medium uppercase tracking-wide text-zinc-500";
const chipClass =
  "rounded-full border border-black/[.08] px-2.5 py-0.5 text-xs text-zinc-700 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

/** Hours rounded to the log's tenths (at least 0.1). */
const tenths = (hours: number) => Math.max(0.1, Math.round(hours * 10) / 10);

// The optional extra details of a logged flight, as part of the forms that
// log and edit flights (field names read by parseExtras in
// flight-fields.ts): takeoff and landing times (offering the time between
// them as the flight's hours), landing rate, day or night, and the weather,
// picked from a list.
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
  const airborne = airborneHours(takeoff || null, landing || null);
  // An older entry's own words for the weather, kept as a choice.
  const savedWeather = defaults?.weather ?? "";
  const weatherOptions =
    savedWeather &&
    !(WEATHER_OPTIONS as readonly string[]).includes(savedWeather)
      ? [savedWeather, ...WEATHER_OPTIONS]
      : WEATHER_OPTIONS;

  // The form's reset (after logging a flight) clears the times too, like
  // its other fields.
  const sectionRef = useRef<HTMLFieldSetElement>(null);
  useEffect(() => {
    const form = sectionRef.current?.closest("form");
    if (!form) return;
    const reset = () => {
      setTakeoff(shortTime(defaults?.takeoff_time ?? null) ?? "");
      setLanding(shortTime(defaults?.landing_time ?? null) ?? "");
    };
    form.addEventListener("reset", reset);
    return () => form.removeEventListener("reset", reset);
  }, [defaults]);

  const fillHours = (button: HTMLButtonElement) => {
    if (airborne === null) return;
    const hours = tenths(airborne);
    if (onUseHours) onUseHours(hours);
    else {
      const input = button
        .closest("form")
        ?.elements.namedItem("hours") as HTMLInputElement | null;
      if (input) input.value = hours.toFixed(1);
    }
  };

  return (
    <fieldset
      ref={sectionRef}
      className="flex flex-col gap-3 rounded-xl bg-zinc-50 p-3 dark:bg-zinc-900/60"
    >
      <legend className="sr-only">More details</legend>
      <p className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
        More details{" "}
        <span className="font-normal text-zinc-500">(optional)</span>
      </p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
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
            Landing rate
          </label>
          <input
            id={`${id}-rate`}
            name="landingRate"
            type="number"
            inputMode="numeric"
            min="0"
            max="5000"
            step="1"
            placeholder="fpm, e.g. 180"
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
        <div className="col-span-2 flex min-w-0 flex-col gap-1.5 sm:col-span-1">
          <label htmlFor={`${id}-weather`} className={labelClass}>
            Weather
          </label>
          <select
            id={`${id}-weather`}
            name="weather"
            defaultValue={savedWeather}
            className={fieldClass}
          >
            <option value="">Not set</option>
            {weatherOptions.map((value) => (
              <option key={value} value={value}>
                {value}
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
            Use as hours ({tenths(airborne).toFixed(1)}h)
          </button>
        </p>
      )}
    </fieldset>
  );
}
