"use client";

import { useMemo } from "react";
import { AirportExplorer } from "./airport-explorer";
import { ChallengingFlights } from "./challenging-flights";
import { ConfirmedFlightPanel } from "./confirmed-flight";
import type { SavedConfirmedFlight } from "./confirmed-flight-actions";
import { FlightSuggestions } from "./flight-suggestions";
import type { ChallengeCardData, SuggestionRoute } from "./planner-data";
import { PLANNER_ID, usePlanner, type PlannerTab } from "./planner-context";
import { RoutePlanner } from "./route-planner";

const TABS: { id: PlannerTab; label: string }[] = [
  { id: "airport", label: "Airports" },
  { id: "suggestions", label: "Real-world routes" },
  { id: "challenges", label: "Challenging flights" },
];

export function FlightPlanner({
  quickCodes,
  routes,
  challenges,
  defaultAircraft,
  favouriteAirline,
  flownRouteKeys,
  savedConfirmedFlight,
}: {
  quickCodes: string[];
  routes: SuggestionRoute[];
  challenges: ChallengeCardData[];
  defaultAircraft: string;
  favouriteAirline: { name: string; iata: string | null } | null;
  flownRouteKeys: string[];
  /** The confirmed flight saved with the account (see
   * ConfirmedFlightPanel). */
  savedConfirmedFlight?: SavedConfirmedFlight;
}) {
  const { tab, setTab, visited } = usePlanner();
  // The airlines on the suggested routes (the favourite first), for the
  // route panel's airline field.
  const airlines = useMemo(() => {
    const byName = new Map<string, string | null>();
    if (favouriteAirline)
      byName.set(favouriteAirline.name, favouriteAirline.iata);
    for (const route of routes) {
      if (route.airline && !byName.has(route.airline))
        byName.set(route.airline, route.airlineIata);
    }
    return [...byName].map(([name, iata]) => ({ name, iata }));
  }, [routes, favouriteAirline]);

  return (
    <section
      id={PLANNER_ID}
      className="flex scroll-mt-6 flex-col gap-4 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]"
    >
      <h2 className="text-lg font-semibold text-black dark:text-zinc-50">
        Plan your next flight
      </h2>

      <ConfirmedFlightPanel saved={savedConfirmedFlight} />
      <RoutePlanner airlines={airlines} />

      <div className="flex">
        <div
          role="tablist"
          aria-label="Flight planning tools"
          className="flex flex-wrap gap-1 rounded-full bg-zinc-100 p-1 dark:bg-zinc-900"
        >
          {TABS.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              role="tab"
              id={`planner-tab-${id}`}
              aria-selected={tab === id}
              aria-controls={`planner-panel-${id}`}
              onClick={() => setTab(id)}
              className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                tab === id
                  ? "bg-white text-black shadow-sm dark:bg-zinc-700 dark:text-zinc-50"
                  : "text-zinc-600 hover:text-black dark:text-zinc-400 dark:hover:text-zinc-50"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {/* Each tab mounts the first time it's opened (so live weather is
          only fetched when wanted), then stays mounted but hidden, keeping
          its state when switching back. */}
      <div
        role="tabpanel"
        id="planner-panel-airport"
        aria-labelledby="planner-tab-airport"
        hidden={tab !== "airport"}
      >
        <AirportExplorer quickCodes={quickCodes} />
      </div>
      <div
        role="tabpanel"
        id="planner-panel-suggestions"
        aria-labelledby="planner-tab-suggestions"
        hidden={tab !== "suggestions"}
      >
        {visited.has("suggestions") && (
          <FlightSuggestions
            routes={routes}
            defaultAircraft={defaultAircraft}
            favouriteAirline={favouriteAirline}
            flownRouteKeys={flownRouteKeys}
          />
        )}
      </div>
      <div
        role="tabpanel"
        id="planner-panel-challenges"
        aria-labelledby="planner-tab-challenges"
        hidden={tab !== "challenges"}
      >
        {visited.has("challenges") && (
          <ChallengingFlights challenges={challenges} />
        )}
      </div>
    </section>
  );
}
