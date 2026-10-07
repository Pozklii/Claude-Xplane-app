"use client";

import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { KNOWN_AIRCRAFT } from "@/lib/aircraft";
import { formatDuration, localToday } from "@/lib/dates";
import { addFlight } from "./actions";
import { AirlineLogo } from "./airline-logo";
import type { SavedConfirmedFlight } from "./confirmed-flight-actions";
import {
  setConfirmedFlight,
  syncConfirmedFlight,
  useConfirmedFlight,
  type ConfirmedFlight,
} from "./confirmed-flight-store";
import { Flag } from "./flag";
import { FlightExtrasFields } from "./flight-extras-fields";
import { usePlanner } from "./planner-context";
import { SimbriefPlanSummary } from "./simbrief-import";

export const CONFIRMED_FLIGHT_ID = "confirmed-flight";

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const labelClass = "text-xs font-medium uppercase tracking-wide text-zinc-500";
const secondaryButton =
  "rounded-full border border-black/[.08] px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";
const primaryButton =
  "rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]";

/** Hours rounded to the log's tenths (at least 0.1). */
const tenths = (hours: number) => Math.max(0.1, Math.round(hours * 10) / 10);

/** Hours from an ISO timestamp until now. */
const hoursSince = (iso: string) => (Date.now() - Date.parse(iso)) / 3_600_000;

type Logging = {
  flight: ConfirmedFlight;
  today: string;
  /** Hours since the flight was confirmed, when that's a plausible flight
   * time (offered as a quick fill). */
  elapsed: number | null;
};

// The Flight Plan page's confirmed flight: once a planned route is
// confirmed it waits here (kept in this browser and saved with the
// account, so it's still here after going off to fly it, on any device), with a "Flight completed" button that opens the
// flight's Flight Log entry, filled in from the plan, to check and add.
export function ConfirmedFlightPanel({
  saved,
}: {
  /** The confirmed flight saved with the account, to bring this browser
   * into step with (undefined: the account can't hold one yet). */
  saved?: SavedConfirmedFlight;
}) {
  const confirmed = useConfirmedFlight();
  useEffect(() => {
    if (saved !== undefined) syncConfirmedFlight(saved);
  }, [saved]);
  const { loadPlan } = usePlanner();
  const [logging, setLogging] = useState<Logging | null>(null);
  const [cancelling, setCancelling] = useState(false);

  if (logging) {
    return (
      <LogCompletedFlight
        key={logging.flight.confirmedAt}
        {...logging}
        onClose={() => setLogging(null)}
      />
    );
  }
  if (!confirmed) return null;

  const confirmedAt = new Date(confirmed.confirmedAt);
  const completed = () => {
    const elapsed = hoursSince(confirmed.confirmedAt);
    setLogging({
      flight: confirmed,
      today: localToday(),
      elapsed: elapsed >= 0.1 && elapsed <= 24 ? elapsed : null,
    });
  };

  return (
    <div
      id={CONFIRMED_FLIGHT_ID}
      className="flex scroll-mt-6 flex-col gap-4 rounded-xl border border-emerald-600/25 bg-emerald-50/70 p-4 dark:border-emerald-400/25 dark:bg-emerald-950/30"
    >
      <div className="flex flex-wrap items-center gap-2 text-xs">
        <span className="rounded-full bg-emerald-600 px-2 py-0.5 font-semibold uppercase tracking-wide text-white dark:bg-emerald-500 dark:text-emerald-950">
          Confirmed
        </span>
        <span className="text-zinc-600 dark:text-zinc-400">
          Ready to fly &middot; confirmed{" "}
          {confirmedAt.toLocaleString(undefined, {
            weekday: "short",
            hour: "2-digit",
            minute: "2-digit",
          })}
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <p className="flex flex-wrap items-center gap-2 text-2xl font-semibold tracking-wide text-black dark:text-zinc-50">
          <Flag country={confirmed.fromCountry} />
          {confirmed.from}
          <span className="text-zinc-400">&rarr;</span>
          <Flag country={confirmed.toCountry} />
          {confirmed.to}
        </p>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {confirmed.fromName} to {confirmed.toName}
        </p>
        <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-zinc-700 dark:text-zinc-300">
          {confirmed.airline && (
            <>
              <AirlineLogo
                name={confirmed.airline}
                iata={confirmed.airlineIata}
              />
              <span>{confirmed.airline}</span>
              <span className="text-zinc-400">&middot;</span>
            </>
          )}
          <span>{confirmed.aircraft}</span>
          <span className="text-zinc-400">&middot;</span>
          <span className="tabular-nums">
            {Math.round(confirmed.nm).toLocaleString("en-US")} nm, about{" "}
            {formatDuration(confirmed.hours)}
          </span>
        </p>
      </div>

      {confirmed.plan && <SimbriefPlanSummary plan={confirmed.plan} />}

      {cancelling ? (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm text-zinc-700 dark:text-zinc-300">
            Cancel this flight? It won&apos;t be logged.
          </span>
          <button
            type="button"
            onClick={() => {
              setConfirmedFlight(null);
              setCancelling(false);
            }}
            className={secondaryButton}
          >
            Yes, cancel it
          </button>
          <button
            type="button"
            onClick={() => setCancelling(false)}
            className={secondaryButton}
          >
            Keep it
          </button>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={completed} className={primaryButton}>
            Flight completed
          </button>
          <button
            type="button"
            onClick={() => {
              loadPlan({
                from: confirmed.from,
                to: confirmed.to,
                airline: confirmed.airline,
                aircraft: confirmed.aircraft,
                simbrief: confirmed.plan ?? null,
              });
              setConfirmedFlight(null);
            }}
            className={secondaryButton}
          >
            Change plan
          </button>
          <button
            type="button"
            onClick={() => setCancelling(true)}
            className={secondaryButton}
          >
            Cancel flight
          </button>
        </div>
      )}
    </div>
  );
}

type LogState =
  | { error: string }
  | { saved: true; notice?: string }
  | undefined;

// The completed flight's Flight Log entry, filled in from the plan: the
// route and aircraft as flown can still be changed (a diversion, a
// different airframe), and the hours start at the planned time.
function LogCompletedFlight({
  flight,
  today,
  elapsed,
  onClose,
}: Logging & { onClose: () => void }) {
  const [hours, setHours] = useState(String(tenths(flight.hours)));
  const [state, action, pending] = useActionState<LogState, FormData>(
    async (_prev, formData) => {
      const result = await addFlight(undefined, formData);
      if (result?.error) return { error: result.error };
      // Logged: the flight is done with.
      setConfirmedFlight(null);
      return { saved: true, notice: result?.notice };
    },
    undefined,
  );

  if (state && "saved" in state) {
    return (
      <div
        id={CONFIRMED_FLIGHT_ID}
        role="status"
        className="flex flex-col gap-3 rounded-xl border border-emerald-600/25 bg-emerald-50/70 p-4 dark:border-emerald-400/25 dark:bg-emerald-950/30"
      >
        <p className="text-sm font-medium text-black dark:text-zinc-50">
          {flight.from} &rarr; {flight.to} is in your Flight Log.
        </p>
        {state.notice && (
          <p className="text-sm text-amber-700 dark:text-amber-400">
            {state.notice}
          </p>
        )}
        <div className="flex flex-wrap gap-2">
          <Link href="/log" className={primaryButton}>
            Open Flight Log
          </Link>
          <button type="button" onClick={onClose} className={secondaryButton}>
            Plan another flight
          </button>
        </div>
      </div>
    );
  }

  return (
    <form
      id={CONFIRMED_FLIGHT_ID}
      action={action}
      className="flex flex-col gap-4 rounded-xl border border-emerald-600/25 bg-emerald-50/70 p-4 dark:border-emerald-400/25 dark:bg-emerald-950/30"
    >
      <div className="flex flex-col gap-1">
        <h3 className="text-base font-semibold text-black dark:text-zinc-50">
          Log your flight
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          Filled in from your plan. Check the details, add your time and any
          notes, then add it to your Flight Log.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Field label="Date" htmlFor="log-date">
          <input
            id="log-date"
            name="flownOn"
            type="date"
            required
            defaultValue={today}
            className={fieldClass}
          />
        </Field>
        <Field label="From" htmlFor="log-from">
          <input
            id="log-from"
            name="departure"
            required
            maxLength={8}
            defaultValue={flight.from}
            className={`${fieldClass} uppercase`}
          />
        </Field>
        <Field label="To" htmlFor="log-to">
          <input
            id="log-to"
            name="arrival"
            required
            maxLength={8}
            defaultValue={flight.to}
            className={`${fieldClass} uppercase`}
          />
        </Field>
        <Field label="Hours" htmlFor="log-hours">
          <input
            id="log-hours"
            name="hours"
            type="number"
            step="0.1"
            min="0.1"
            required
            value={hours}
            onChange={(event) => setHours(event.target.value)}
            className={`${fieldClass} tabular-nums`}
          />
        </Field>
        <Field label="Airline" htmlFor="log-airline" wide>
          <input
            id="log-airline"
            name="airline"
            defaultValue={flight.airline}
            className={fieldClass}
          />
        </Field>
        <Field label="Aircraft" htmlFor="log-aircraft" wide>
          <input
            id="log-aircraft"
            name="aircraft"
            list="log-aircraft-types"
            required
            defaultValue={flight.aircraft}
            className={fieldClass}
          />
          <datalist id="log-aircraft-types">
            {KNOWN_AIRCRAFT.map((name) => (
              <option key={name} value={name} />
            ))}
          </datalist>
        </Field>
      </div>

      <p className="flex flex-wrap items-center gap-2 text-xs text-zinc-600 dark:text-zinc-400">
        <span>Hours start at the planned {formatDuration(flight.hours)}.</span>
        {elapsed !== null && (
          <button
            type="button"
            onClick={() => setHours(String(tenths(elapsed)))}
            className="rounded-full border border-black/[.08] px-2.5 py-0.5 text-xs text-zinc-700 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]"
          >
            Use time since confirming ({tenths(elapsed).toFixed(1)}h)
          </button>
        )}
      </p>

      {flight.plan && (
        <input type="hidden" name="plan" value={JSON.stringify(flight.plan)} />
      )}
      <FlightExtrasFields onUseHours={(value) => setHours(value.toFixed(1))} />

      <div className="flex flex-col gap-3 sm:flex-row">
        <Field label="Notes" htmlFor="log-notes" grow>
          <textarea
            id="log-notes"
            name="notes"
            rows={2}
            placeholder="How did it go? (optional)"
            className={`${fieldClass} resize-y`}
          />
        </Field>
        <Field label="Flight rating" htmlFor="log-rating">
          <select
            id="log-rating"
            name="rating"
            defaultValue=""
            className={fieldClass}
          >
            <option value="">Not rated</option>
            {Array.from({ length: 10 }, (_, i) => 10 - i).map((value) => (
              <option key={value} value={value}>
                {value}/10
              </option>
            ))}
          </select>
        </Field>
      </div>

      {state && "error" in state && (
        <p className="text-sm text-red-600 dark:text-red-400">{state.error}</p>
      )}

      <div className="flex flex-wrap gap-2">
        <button type="submit" disabled={pending} className={primaryButton}>
          {pending ? "Adding…" : "Add to Flight Log"}
        </button>
        <button
          type="button"
          onClick={onClose}
          disabled={pending}
          className={secondaryButton}
        >
          Back
        </button>
      </div>
    </form>
  );
}

function Field({
  label,
  htmlFor,
  wide = false,
  grow = false,
  children,
}: {
  label: string;
  htmlFor: string;
  wide?: boolean;
  grow?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`flex min-w-0 flex-col gap-1.5 ${wide ? "col-span-2" : ""} ${grow ? "flex-1" : ""}`}
    >
      <label htmlFor={htmlFor} className={labelClass}>
        {label}
      </label>
      {children}
    </div>
  );
}
