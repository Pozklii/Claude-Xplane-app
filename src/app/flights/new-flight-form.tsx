"use client";

import { useActionState, useEffect, useRef } from "react";
import { KNOWN_AIRCRAFT } from "@/lib/aircraft";
import { addFlight } from "./actions";
import { FlightExtrasFields } from "./flight-extras-fields";

export function NewFlightForm() {
  const [state, action, pending] = useActionState(addFlight, undefined);
  const formRef = useRef<HTMLFormElement>(null);
  const wasPending = useRef(false);

  useEffect(() => {
    if (wasPending.current && !pending && !state?.error) {
      formRef.current?.reset();
    }
    wasPending.current = pending;
  }, [pending, state]);

  return (
    <form
      ref={formRef}
      action={action}
      className="flex flex-col gap-3 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]"
    >
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-6">
        <input
          name="flownOn"
          type="date"
          required
          className="col-span-2 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 sm:col-span-1 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <input
          name="airline"
          type="text"
          placeholder="Airline"
          className="col-span-2 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 sm:col-span-1 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <input
          name="aircraft"
          type="text"
          placeholder="Aircraft (e.g. C172)"
          list="known-aircraft"
          required
          className="col-span-2 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 sm:col-span-1 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <input
          name="departure"
          type="text"
          placeholder="From (e.g. KSFO)"
          required
          maxLength={8}
          className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <input
          name="arrival"
          type="text"
          placeholder="To (e.g. KLAX)"
          required
          maxLength={8}
          className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <input
          name="hours"
          type="number"
          step="0.1"
          min="0.1"
          placeholder="Hours"
          required
          className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
      </div>
      <div className="flex flex-col gap-3 sm:flex-row">
        <input
          name="notes"
          type="text"
          placeholder="Notes (optional)"
          className="flex-1 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <select
          name="rating"
          defaultValue=""
          aria-label="Flight rating out of 10"
          className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        >
          <option value="">Flight rating</option>
          {Array.from({ length: 10 }, (_, i) => 10 - i).map((value) => (
            <option key={value} value={value}>
              {value}/10
            </option>
          ))}
        </select>
      </div>
      <FlightExtrasFields />
      <datalist id="known-aircraft">
        {KNOWN_AIRCRAFT.map((name) => (
          <option key={name} value={name} />
        ))}
      </datalist>
      {state?.error && (
        <p className="text-sm text-red-600 dark:text-red-400">{state.error}</p>
      )}
      {state?.notice && (
        <p className="text-sm text-amber-700 dark:text-amber-400">
          {state.notice}
        </p>
      )}
      <button
        type="submit"
        disabled={pending}
        className="self-start rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]"
      >
        {pending ? "Adding…" : "Add flight"}
      </button>
    </form>
  );
}
