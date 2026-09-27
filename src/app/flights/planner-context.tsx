"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from "react";

export type PlannerTab = "airport" | "suggestions" | "challenges";

type PlannerContextValue = {
  tab: PlannerTab;
  setTab: (tab: PlannerTab) => void;
  /** Tabs opened at least once. */
  visited: ReadonlySet<PlannerTab>;
  /** The airport shown in the airport panel (ICAO/IATA code). */
  airportCode: string | null;
  /** Shows an airport in the airport panel; `scroll` brings it into view. */
  openAirport: (code: string, options?: { scroll?: boolean }) => void;
};

const PlannerContext = createContext<PlannerContextValue | null>(null);

export const PLANNER_ID = "flight-planner";

// Shared by the planner's tabs and its suggestion/challenge lists (clicking
// an airport code), so any of them can bring up an airport's details and
// METAR, and by the flights page's globe, where clicking an airport offers
// a link to it on the Flight Plan page (which then opens with
// `initialAirport` shown).
export function PlannerProvider({
  children,
  initialAirport = null,
}: {
  children: React.ReactNode;
  initialAirport?: string | null;
}) {
  const [tab, setTabState] = useState<PlannerTab>("airport");
  const [visited, setVisited] = useState<ReadonlySet<PlannerTab>>(
    () => new Set<PlannerTab>(["airport"]),
  );
  const [airportCode, setAirportCode] = useState<string | null>(
    initialAirport ? initialAirport.toUpperCase() : null,
  );

  const setTab = useCallback((next: PlannerTab) => {
    setTabState(next);
    setVisited((prev) => (prev.has(next) ? prev : new Set(prev).add(next)));
  }, []);

  const openAirport = useCallback(
    (code: string, { scroll = true }: { scroll?: boolean } = {}) => {
      setAirportCode(code.toUpperCase());
      setTab("airport");
      if (scroll) {
        const reduce = window.matchMedia(
          "(prefers-reduced-motion: reduce)",
        ).matches;
        document.getElementById(PLANNER_ID)?.scrollIntoView({
          behavior: reduce ? "auto" : "smooth",
          block: "start",
        });
      }
    },
    [setTab],
  );

  const value = useMemo(
    () => ({ tab, setTab, visited, airportCode, openAirport }),
    [tab, setTab, visited, airportCode, openAirport],
  );

  return (
    <PlannerContext.Provider value={value}>{children}</PlannerContext.Provider>
  );
}

export function usePlanner() {
  const ctx = useContext(PlannerContext);
  if (!ctx) throw new Error("usePlanner must be used within a PlannerProvider");
  return ctx;
}
