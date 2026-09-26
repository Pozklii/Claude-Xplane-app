"use client";

import { useMemo, useState } from "react";
import { estimateHours, KNOWN_AIRCRAFT, matchAircraft } from "@/lib/aircraft";
import { formatDuration } from "@/lib/dates";
import { AirlineLogo } from "./airline-logo";
import { AirportLink } from "./airport-link";
import type { SuggestionRoute } from "./planner-data";

const QUICK_TYPES = [
  "A320",
  "737-800",
  "A350",
  "777",
  "787",
  "E175",
  "Dash 8",
  "Twin Otter",
];
const PAGE_SIZE = 12;

/** Real-world routes flown with a given aircraft type, from the route
 * table, favouring the user's favourite airline and routes they haven't
 * logged yet. */
export function FlightSuggestions({
  routes,
  defaultAircraft,
  favouriteAirline,
  flownRouteKeys,
}: {
  routes: SuggestionRoute[];
  defaultAircraft: string;
  favouriteAirline: { name: string; iata: string | null } | null;
  /** Pair keys (see routePairKey) of routes the user has logged. */
  flownRouteKeys: string[];
}) {
  const [query, setQuery] = useState(defaultAircraft);
  const [showAll, setShowAll] = useState(false);
  const flown = useMemo(() => new Set(flownRouteKeys), [flownRouteKeys]);

  const matches = useMemo(() => matchAircraft(query), [query]);
  const results = useMemo(() => {
    const matched = new Set(matches.map((m) => m.name as string));
    const exact = new Set(
      matches.filter((m) => m.exact).map((m) => m.name as string),
    );
    return routes
      .filter((route) => route.aircraft.some((type) => matched.has(type)))
      .map((route) => {
        const types = route.aircraft.filter((type) => matched.has(type));
        return {
          route,
          types,
          exact: types.some((type) => exact.has(type)),
          favourite:
            favouriteAirline !== null &&
            ((favouriteAirline.iata !== null &&
              route.airlineIata === favouriteAirline.iata) ||
              route.airline?.toLowerCase() ===
                favouriteAirline.name.toLowerCase()),
          flown: flown.has(route.pairKey),
        };
      })
      .sort(
        (a, b) =>
          Number(b.exact) - Number(a.exact) ||
          Number(b.favourite) - Number(a.favourite) ||
          Number(a.flown) - Number(b.flown) ||
          a.route.distanceNm - b.route.distanceNm,
      );
  }, [routes, matches, favouriteAirline, flown]);

  const visible = showAll ? results : results.slice(0, PAGE_SIZE);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <label
          htmlFor="suggest-aircraft"
          className="text-sm text-zinc-600 dark:text-zinc-400"
        >
          Real routes airlines fly with your aircraft — type a model or ICAO
          designator (e.g. A20N, B738, Q400).
        </label>
        <div className="flex flex-wrap items-center gap-2">
          <input
            id="suggest-aircraft"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setShowAll(false);
            }}
            list="suggest-aircraft-types"
            placeholder="Aircraft type"
            className="w-64 max-w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
          />
          <datalist id="suggest-aircraft-types">
            {KNOWN_AIRCRAFT.map((name) => (
              <option key={name} value={name} />
            ))}
          </datalist>
          {QUICK_TYPES.map((type) => (
            <button
              key={type}
              type="button"
              onClick={() => {
                setQuery(type);
                setShowAll(false);
              }}
              className="rounded-full border border-black/[.08] px-2.5 py-1 text-xs text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
            >
              {type}
            </button>
          ))}
        </div>
      </div>

      {results.length === 0 ? (
        <p className="text-sm text-zinc-500">
          {query.trim()
            ? `No real-world routes in our list for “${query.trim()}” yet — try an airliner or regional type like those above.`
            : "Enter an aircraft type to see routes."}
        </p>
      ) : (
        <>
          <p className="text-xs text-zinc-500">
            {results.length} route{results.length === 1 ? "" : "s"} for{" "}
            {matches
              .filter((m) => m.exact)
              .map((m) => m.name)
              .join(", ") || "that family"}
            . Flyable in either direction. Airlines&apos; schedules and fleets
            change, so treat these as ideas rather than a timetable.
          </p>
          <ul className="flex flex-col gap-2">
            {visible.map(({ route, types, favourite, flown: done }) => (
              <li
                key={route.key}
                className="flex flex-col gap-2 rounded-xl border border-black/[.08] p-3 sm:flex-row sm:items-center sm:justify-between dark:border-white/[.145]"
              >
                <div className="flex min-w-0 items-center gap-3">
                  <AirlineLogo
                    name={route.airline ?? "Private"}
                    iata={route.airlineIata}
                  />
                  <div className="flex min-w-0 flex-col gap-0.5">
                    <div className="flex flex-wrap items-center gap-1.5 text-sm">
                      <AirportLink airport={route.from} />
                      <span className="text-zinc-400">&harr;</span>
                      <AirportLink airport={route.to} />
                      <span className="text-zinc-500">
                        {route.from.city} &ndash; {route.to.city}
                      </span>
                    </div>
                    <p className="text-xs text-zinc-600 dark:text-zinc-400">
                      {route.airline ?? "Private / general aviation"} &middot;{" "}
                      {types.join(", ")}
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-1.5 text-xs sm:justify-end">
                  <span className="tabular-nums text-zinc-600 dark:text-zinc-400">
                    {route.distanceNm.toLocaleString("en-US")} nm &middot; ~
                    {formatDuration(
                      estimateHours(
                        types[0] as Parameters<typeof estimateHours>[0],
                        route.distanceNm,
                      ),
                    )}
                  </span>
                  {favourite && (
                    <span className="rounded-full bg-amber-100 px-2 py-0.5 text-amber-800 dark:bg-amber-950/50 dark:text-amber-300">
                      &#9733; Favourite airline
                    </span>
                  )}
                  {route.challenging && (
                    <span className="rounded-full bg-red-100 px-2 py-0.5 text-red-800 dark:bg-red-950/50 dark:text-red-300">
                      Challenging
                    </span>
                  )}
                  {done && (
                    <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-emerald-800 dark:bg-emerald-950/50 dark:text-emerald-300">
                      Flown
                    </span>
                  )}
                </div>
              </li>
            ))}
          </ul>
          {results.length > PAGE_SIZE && (
            <button
              type="button"
              onClick={() => setShowAll((all) => !all)}
              className="self-start text-sm text-blue-600 underline dark:text-blue-400"
            >
              {showAll ? "Show fewer" : `Show all ${results.length}`}
            </button>
          )}
        </>
      )}
    </div>
  );
}
