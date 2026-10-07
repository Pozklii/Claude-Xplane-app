"use client";

import { useState, useTransition } from "react";
import { formatDuration } from "@/lib/dates";
import { formatAltitude, type SimbriefPlan } from "@/lib/simbrief";
import { usePlanner } from "./planner-context";
import { importSimbriefPlan } from "./simbrief-actions";

const PILOT_KEY = "flight-world:simbrief-pilot";

function readPilot() {
  try {
    return window.localStorage.getItem(PILOT_KEY) ?? "";
  } catch {
    return "";
  }
}

// The Flight Plan page's SimBrief import: the pilot's latest SimBrief plan
// (by username or Pilot ID, remembered in this browser) loaded into the
// route panel, its route, cruise level, fuel and times kept with it.
export function SimbriefImport() {
  const { loadPlan } = usePlanner();
  // Read on first click into the field rather than while rendering, so the
  // server and browser render the same.
  const [pilot, setPilot] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const value = (pilot ?? readPilot()).trim();
    if (!value) {
      setError("Enter your SimBrief username or Pilot ID.");
      return;
    }
    setError(null);
    startTransition(async () => {
      const result = await importSimbriefPlan(value);
      if ("error" in result) {
        setError(result.error);
        return;
      }
      try {
        window.localStorage.setItem(PILOT_KEY, value);
      } catch {
        // Not remembered; it still imported.
      }
      loadPlan({
        from: result.plan.origin,
        to: result.plan.destination,
        airline: result.airline,
        aircraft: result.aircraft,
        simbrief: result.plan,
      });
    });
  };

  return (
    <form onSubmit={submit} className="flex flex-col gap-1.5">
      <label
        htmlFor="simbrief-pilot"
        className="text-xs font-medium uppercase tracking-wide text-zinc-500"
      >
        Import from SimBrief
      </label>
      <div className="flex flex-wrap gap-2">
        <input
          id="simbrief-pilot"
          value={pilot ?? ""}
          onFocus={() => {
            if (pilot === null) setPilot(readPilot());
          }}
          onChange={(event) => setPilot(event.target.value)}
          placeholder="SimBrief username or Pilot ID"
          autoComplete="off"
          className="min-w-0 flex-1 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <button
          type="submit"
          disabled={pending}
          className="rounded-full border border-black/[.08] px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]"
        >
          {pending ? "Importing…" : "Import latest plan"}
        </button>
      </div>
      {error ? (
        <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
      ) : (
        <p className="text-xs text-zinc-500">
          Loads the last plan you generated on SimBrief: route, cruise level,
          fuel and times.
        </p>
      )}
    </form>
  );
}

/** A SimBrief plan's figures, for the route panel and confirmed flight. */
export function SimbriefPlanSummary({ plan }: { plan: SimbriefPlan }) {
  const fuel = (amount: number) =>
    `${Math.round(amount).toLocaleString("en-US")} ${plan.fuelUnit}`;
  const items = [
    plan.cruiseAltitudeFt !== null && [
      "Cruise",
      formatAltitude(plan.cruiseAltitudeFt),
    ],
    plan.distanceNm !== null && [
      "Route distance",
      `${Math.round(plan.distanceNm).toLocaleString("en-US")} nm`,
    ],
    plan.eteMinutes !== null && [
      "Time en route",
      formatDuration(plan.eteMinutes / 60),
    ],
    plan.blockMinutes !== null && [
      "Block time",
      formatDuration(plan.blockMinutes / 60),
    ],
    plan.fuelRamp !== null && ["Block fuel", fuel(plan.fuelRamp)],
    plan.fuelBurn !== null && ["Trip burn", fuel(plan.fuelBurn)],
  ].filter(Boolean) as [string, string][];

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-sky-600/20 bg-sky-50/60 p-3 dark:border-sky-400/20 dark:bg-sky-950/30">
      <p className="flex flex-wrap items-center gap-2 text-xs">
        <span className="rounded-full bg-sky-600 px-2 py-0.5 font-semibold uppercase tracking-wide text-white dark:bg-sky-500 dark:text-sky-950">
          SimBrief
        </span>
        <span className="text-zinc-600 dark:text-zinc-400">
          {[
            plan.airlineIcao && plan.flightNumber
              ? `${plan.airlineIcao}${plan.flightNumber}`
              : null,
            `${plan.origin} → ${plan.destination}`,
            plan.aircraftIcao,
          ]
            .filter(Boolean)
            .join(" · ")}
        </span>
      </p>
      {items.length > 0 && (
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 sm:grid-cols-3">
          {items.map(([label, value]) => (
            <div key={label} className="flex flex-col">
              <dt className="text-[11px] uppercase tracking-wide text-zinc-500">
                {label}
              </dt>
              <dd className="text-sm font-medium tabular-nums text-black dark:text-zinc-50">
                {value}
              </dd>
            </div>
          ))}
        </dl>
      )}
      {plan.route && (
        <p className="break-words font-mono text-[11px] leading-relaxed text-zinc-600 dark:text-zinc-400">
          {plan.route}
        </p>
      )}
    </div>
  );
}
