"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from "react";

export type PlannerTab = "airport" | "suggestions" | "challenges";

/** The flight being planned in the route panel (route-planner.tsx). */
export type RoutePlan = {
  from: string;
  to: string;
  airline: string;
  aircraft: string;
};

type PlannerContextValue = {
  tab: PlannerTab;
  setTab: (tab: PlannerTab) => void;
  /** Tabs opened at least once. */
  visited: ReadonlySet<PlannerTab>;
  /** The airport shown in the airport panel (ICAO/IATA code). */
  airportCode: string | null;
  /** Shows an airport in the airport panel; `scroll` brings it into view. */
  openAirport: (code: string, options?: { scroll?: boolean }) => void;
  plan: RoutePlan;
  /** Changes some of the plan (as its fields are edited). */
  updatePlan: (changes: Partial<RoutePlan>) => void;
  /** Loads a whole flight into the plan (a suggested route, a challenge)
   * and brings the route panel into view. */
  loadPlan: (plan: RoutePlan) => void;
  /** Bumped by every loadPlan, so the panel can mark the change. */
  planLoads: number;
};

const PlannerContext = createContext<PlannerContextValue | null>(null);

export const PLANNER_ID = "flight-planner";
export const ROUTE_PLAN_ID = "route-plan";

// Shared by the planner's tabs and its suggestion/challenge lists (clicking
// an airport code), so any of them can bring up an airport's details and
// METAR, or load a flight into the route panel's plan, and by the flights page's globe, where clicking an airport offers
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

  const [plan, setPlan] = useState<RoutePlan>({
    from: initialAirport ? initialAirport.toUpperCase() : "",
    to: "",
    airline: "",
    aircraft: "",
  });
  const [planLoads, setPlanLoads] = useState(0);
  const updatePlan = useCallback(
    (changes: Partial<RoutePlan>) =>
      setPlan((prev) => ({ ...prev, ...changes })),
    [],
  );
  const loadPlan = useCallback((next: RoutePlan) => {
    setPlan(next);
    setPlanLoads((n) => n + 1);
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    document.getElementById(ROUTE_PLAN_ID)?.scrollIntoView({
      behavior: reduce ? "auto" : "smooth",
      block: "start",
    });
  }, []);

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
    () => ({
      tab,
      setTab,
      visited,
      airportCode,
      openAirport,
      plan,
      updatePlan,
      loadPlan,
      planLoads,
    }),
    [
      tab,
      setTab,
      visited,
      airportCode,
      openAirport,
      plan,
      updatePlan,
      loadPlan,
      planLoads,
    ],
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
