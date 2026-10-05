"use client";

import { useActionState, useId, useState } from "react";
import { KNOWN_AIRCRAFT } from "@/lib/aircraft";
import type { FlightExtras } from "@/lib/flight-fields";
import { updateFlight, type FlightFormState } from "./actions";
import { FlightExtrasFields } from "./flight-extras-fields";

/** What the edit form needs of a logged flight (see Flight). */
export type EditableFlightData = {
  id: string;
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
  rating: number | null;
} & FlightExtras;

const fieldClass =
  "w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const labelClass = "text-xs font-medium uppercase tracking-wide text-zinc-500";
const smallButton =
  "rounded-full border border-black/[.08] px-3 py-1 text-xs font-medium text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]";
const primaryButton =
  "rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]";
const secondaryButton =
  "rounded-full border border-black/[.08] px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

// A logged flight's row in the Flight Log: its summary (`children`) with
// an Edit button beside its other actions (`actions`, e.g. Delete), or,
// while editing, a form with every field filled in, in its place. Clicks
// on the buttons and the form don't reach the row (which selects the
// flight).
export function EditableFlight({
  flight,
  actions,
  children,
}: {
  flight: EditableFlightData;
  actions: React.ReactNode;
  children: React.ReactNode;
}) {
  const [editing, setEditing] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  if (editing) {
    return (
      <div onClick={(event) => event.stopPropagation()}>
        <EditFlightForm
          flight={flight}
          onDone={(message) => {
            setNotice(message ?? null);
            setEditing(false);
          }}
          onCancel={() => setEditing(false)}
        />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        {children}
        <div
          className="flex shrink-0 gap-2 self-start"
          onClick={(event) => event.stopPropagation()}
        >
          <button
            type="button"
            onClick={() => {
              setNotice(null);
              setEditing(true);
            }}
            className={smallButton}
          >
            Edit
          </button>
          {actions}
        </div>
      </div>
      {notice && (
        <p className="text-xs text-amber-700 dark:text-amber-400">{notice}</p>
      )}
    </div>
  );
}

function EditFlightForm({
  flight,
  onDone,
  onCancel,
}: {
  flight: EditableFlightData;
  onDone: (notice?: string) => void;
  onCancel: () => void;
}) {
  const id = useId();
  const [state, action, pending] = useActionState<FlightFormState, FormData>(
    async (prev, formData) => {
      const result = await updateFlight(flight.id, prev, formData);
      if (result?.saved) onDone(result.notice);
      return result;
    },
    undefined,
  );

  const field = (
    label: string,
    name: string,
    input: React.ReactNode,
    wide = false,
  ) => (
    <div
      key={name}
      className={`flex min-w-0 flex-col gap-1.5 ${wide ? "col-span-2" : ""}`}
    >
      <label htmlFor={`${id}-${name}`} className={labelClass}>
        {label}
      </label>
      {input}
    </div>
  );

  return (
    <form action={action} className="flex flex-col gap-3">
      <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
        Edit flight
      </h3>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {field(
          "Date",
          "flownOn",
          <input
            id={`${id}-flownOn`}
            name="flownOn"
            type="date"
            required
            defaultValue={flight.flown_on}
            className={fieldClass}
          />,
        )}
        {field(
          "From",
          "departure",
          <input
            id={`${id}-departure`}
            name="departure"
            required
            maxLength={8}
            defaultValue={flight.departure}
            className={`${fieldClass} uppercase`}
          />,
        )}
        {field(
          "To",
          "arrival",
          <input
            id={`${id}-arrival`}
            name="arrival"
            required
            maxLength={8}
            defaultValue={flight.arrival}
            className={`${fieldClass} uppercase`}
          />,
        )}
        {field(
          "Hours",
          "hours",
          <input
            id={`${id}-hours`}
            name="hours"
            type="number"
            step="0.1"
            min="0.1"
            required
            defaultValue={Number(flight.hours).toFixed(1)}
            className={`${fieldClass} tabular-nums`}
          />,
        )}
        {field(
          "Airline",
          "airline",
          <input
            id={`${id}-airline`}
            name="airline"
            placeholder="Optional"
            defaultValue={flight.airline ?? ""}
            className={fieldClass}
          />,
          true,
        )}
        {field(
          "Aircraft",
          "aircraft",
          <>
            <input
              id={`${id}-aircraft`}
              name="aircraft"
              list={`${id}-aircraft-types`}
              required
              defaultValue={flight.aircraft}
              className={fieldClass}
            />
            <datalist id={`${id}-aircraft-types`}>
              {KNOWN_AIRCRAFT.map((name) => (
                <option key={name} value={name} />
              ))}
            </datalist>
          </>,
          true,
        )}
      </div>

      <FlightExtrasFields defaults={flight} />

      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <label htmlFor={`${id}-notes`} className={labelClass}>
            Notes
          </label>
          <textarea
            id={`${id}-notes`}
            name="notes"
            rows={2}
            defaultValue={flight.notes ?? ""}
            className={`${fieldClass} resize-y`}
          />
        </div>
        <div className="flex min-w-0 flex-col gap-1.5">
          <label htmlFor={`${id}-rating`} className={labelClass}>
            Rating
          </label>
          <select
            id={`${id}-rating`}
            name="rating"
            defaultValue={flight.rating ?? ""}
            className={fieldClass}
          >
            <option value="">No rating</option>
            {Array.from({ length: 10 }, (_, i) => 10 - i).map((value) => (
              <option key={value} value={value}>
                {value}/10
              </option>
            ))}
          </select>
        </div>
      </div>

      {state?.error && (
        <p className="text-sm text-red-600 dark:text-red-400">{state.error}</p>
      )}

      <div className="flex flex-wrap gap-2">
        <button type="submit" disabled={pending} className={primaryButton}>
          {pending ? "Saving…" : "Save changes"}
        </button>
        <button
          type="button"
          onClick={onCancel}
          disabled={pending}
          className={secondaryButton}
        >
          Cancel
        </button>
      </div>
    </form>
  );
}
