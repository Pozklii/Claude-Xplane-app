"use client";

import { useEffect, useId, useRef, useState } from "react";
import {
  airborneHours,
  CONDITIONS,
  normalizeTime,
  shortTime,
  WEATHER_OPTIONS,
  type FlightExtras,
} from "@/lib/flight-fields";

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const invalidClass = "border-red-400 dark:border-red-500/70";
const labelClass = "text-xs font-medium uppercase tracking-wide text-zinc-500";
const chipClass =
  "rounded-full border border-black/[.08] px-2.5 py-0.5 text-xs text-zinc-700 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

/** Hours rounded to the log's tenths (at least 0.1). */
const tenths = (hours: number) => Math.max(0.1, Math.round(hours * 10) / 10);

type Values = {
  takeoff: string;
  landing: string;
  rate: string;
  conditions: string;
  weather: string;
};

const valuesFrom = (defaults?: Partial<FlightExtras>): Values => ({
  takeoff: shortTime(defaults?.takeoff_time ?? null) ?? "",
  landing: shortTime(defaults?.landing_time ?? null) ?? "",
  rate:
    defaults?.landing_rate_fpm != null ? String(defaults.landing_rate_fpm) : "",
  conditions: defaults?.conditions ?? "",
  weather: defaults?.weather ?? "",
});
const EMPTY: Values = valuesFrom();

// The optional extra details of a logged flight, as part of the forms that
// log and edit flights (field names read by parseExtras in
// flight-fields.ts): takeoff and landing times (typed freely, offering the
// time between them as the flight's hours), landing rate, day or night,
// and the weather, picked from a list. Any of them can be emptied, or all
// cleared at once, and saving then removes them from the flight.
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
  const [values, setValues] = useState(() => valuesFrom(defaults));
  const set = (changes: Partial<Values>) =>
    setValues((prev) => ({ ...prev, ...changes }));

  const takeoff = normalizeTime(values.takeoff);
  const landing = normalizeTime(values.landing);
  const airborne = airborneHours(takeoff ?? null, landing ?? null);
  const rateText = values.rate.trim().replace(/,/g, "");
  const rateInvalid =
    rateText !== "" &&
    !(/^-?\d{1,4}$/.test(rateText) && Math.abs(Number(rateText)) <= 5000);
  const anyEntered = Object.values(values).some((value) => value.trim());
  // An older entry's own words for the weather, kept as a choice.
  const savedWeather = defaults?.weather ?? "";
  const weatherOptions =
    savedWeather &&
    !(WEATHER_OPTIONS as readonly string[]).includes(savedWeather)
      ? [savedWeather, ...WEATHER_OPTIONS]
      : WEATHER_OPTIONS;

  // The form's reset (after logging a flight) puts these back too, like
  // its other fields.
  const sectionRef = useRef<HTMLFieldSetElement>(null);
  useEffect(() => {
    const form = sectionRef.current?.closest("form");
    if (!form) return;
    const reset = () => setValues(valuesFrom(defaults));
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

  // A time box: typed freely (no picker or scroll wheel), tidied to HH:MM
  // when left, and cleared by emptying it.
  const timeField = (key: "takeoff" | "landing", label: string) => {
    const invalid = normalizeTime(values[key]) === undefined;
    return (
      <div className="flex min-w-0 flex-col gap-1.5">
        <label htmlFor={`${id}-${key}`} className={labelClass}>
          {label}
        </label>
        <input
          id={`${id}-${key}`}
          name={key === "takeoff" ? "takeoffTime" : "landingTime"}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          placeholder="HH:MM"
          maxLength={8}
          value={values[key]}
          onChange={(event) => set({ [key]: event.target.value })}
          onBlur={() => {
            const tidy = normalizeTime(values[key]);
            if (tidy) set({ [key]: tidy });
          }}
          aria-invalid={invalid || undefined}
          aria-describedby={invalid ? `${id}-${key}-hint` : undefined}
          className={`${fieldClass} tabular-nums ${invalid ? invalidClass : ""}`}
        />
        {invalid && (
          <p
            id={`${id}-${key}-hint`}
            className="text-xs text-red-600 dark:text-red-400"
          >
            24-hour time, like 14:05
          </p>
        )}
      </div>
    );
  };

  return (
    <fieldset
      ref={sectionRef}
      className="flex flex-col gap-3 rounded-xl bg-zinc-50 p-3 dark:bg-zinc-900/60"
    >
      <legend className="sr-only">More details</legend>
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
          More details{" "}
          <span className="font-normal text-zinc-500">(optional)</span>
        </p>
        {anyEntered && (
          <button
            type="button"
            onClick={() => setValues(EMPTY)}
            className={chipClass}
          >
            Clear details
          </button>
        )}
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        {timeField("takeoff", "Takeoff")}
        {timeField("landing", "Landing")}
        <div className="flex min-w-0 flex-col gap-1.5">
          <label htmlFor={`${id}-rate`} className={labelClass}>
            Landing rate
          </label>
          <input
            id={`${id}-rate`}
            name="landingRate"
            type="text"
            inputMode="numeric"
            autoComplete="off"
            placeholder="fpm, e.g. 180"
            maxLength={6}
            value={values.rate}
            onChange={(event) => set({ rate: event.target.value })}
            aria-invalid={rateInvalid || undefined}
            aria-describedby={rateInvalid ? `${id}-rate-hint` : undefined}
            className={`${fieldClass} tabular-nums ${rateInvalid ? invalidClass : ""}`}
          />
          {rateInvalid && (
            <p
              id={`${id}-rate-hint`}
              className="text-xs text-red-600 dark:text-red-400"
            >
              A whole number of fpm, up to 5000
            </p>
          )}
        </div>
        <div className="flex min-w-0 flex-col gap-1.5">
          <label htmlFor={`${id}-conditions`} className={labelClass}>
            Conditions
          </label>
          <select
            id={`${id}-conditions`}
            name="conditions"
            value={values.conditions}
            onChange={(event) => set({ conditions: event.target.value })}
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
            value={values.weather}
            onChange={(event) => set({ weather: event.target.value })}
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
