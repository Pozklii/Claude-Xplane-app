"use client";

import Link from "next/link";
import { useState, useSyncExternalStore } from "react";
import {
  DEFAULT_ARC_COLOR,
  FlightGlobe,
  type GlobeArc,
  type GlobePoint,
} from "./flight-globe";
import { usePlanner } from "./planner-context";
import { SelectedFlightCard, type FlightDetails } from "./selected-flight-card";

const STORAGE_KEY = "flightworld:arc-color";
const VIEW_STORAGE_KEY = "flightworld:map-view";

// The route colours to choose from.
const ROUTE_COLORS = [
  { name: "Sky", hex: DEFAULT_ARC_COLOR },
  { name: "Gold", hex: "#f5c451" },
  { name: "Coral", hex: "#ff7a6b" },
  { name: "Rose", hex: "#ff6fb5" },
  { name: "Violet", hex: "#a78bfa" },
  { name: "Lime", hex: "#9be15d" },
  { name: "White", hex: "#e8eef5" },
];

type MapView = "globe" | "map";

function noopSubscribe() {
  return () => {};
}

function getPersistedArcColor() {
  return window.localStorage.getItem(STORAGE_KEY);
}

function getPersistedView() {
  return window.localStorage.getItem(VIEW_STORAGE_KEY);
}

function getServerValue() {
  return null;
}

// The flights page's globe band: the page header, the selected flight's
// details card and the globe itself — all here because the card and the
// globe share the user's chosen route color.
export function CustomizableGlobe({
  points,
  arcs,
  details,
  header,
  userId,
  flat = false,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  details: Record<string, FlightDetails>;
  header: React.ReactNode;
  userId: string;
  /** Start on the flat 2D map rather than the globe (?map=2d). */
  flat?: boolean;
}) {
  // Reads localStorage without a server/client hydration mismatch: this
  // resolves to null during SSR and the client's first render, then
  // (harmlessly, since nothing else writes this key from outside this
  // component) settles on the stored value right after.
  const persisted = useSyncExternalStore(
    noopSubscribe,
    getPersistedArcColor,
    getServerValue,
  );
  const persistedView = useSyncExternalStore(
    noopSubscribe,
    getPersistedView,
    getServerValue,
  );
  // A color picked THIS session, which takes priority once set — a plain
  // setState from the input's own onChange, not an effect, so it applies
  // immediately rather than waiting for the next external-store read.
  const [pickedThisSession, setPickedThisSession] = useState<string | null>(
    null,
  );
  const arcColor = pickedThisSession ?? persisted ?? DEFAULT_ARC_COLOR;
  // Globe or flat 2D map (straight route lines), likewise remembered.
  const [viewThisSession, setViewThisSession] = useState<MapView | null>(null);
  const view: MapView =
    viewThisSession ??
    (flat ? "map" : persistedView === "map" ? "map" : "globe");
  const { airportCode, openAirport } = usePlanner();

  const handleChange = (color: string) => {
    setPickedThisSession(color);
    window.localStorage.setItem(STORAGE_KEY, color);
  };
  const handleView = (next: MapView) => {
    setViewThisSession(next);
    window.localStorage.setItem(VIEW_STORAGE_KEY, next);
  };

  return (
    <div className="flex flex-col gap-8 lg:flex-row lg:items-center lg:justify-between">
      <div className="flex w-full max-w-md flex-col gap-6">
        {/* Own wrapper: see LandingShowcase. */}
        <div>{header}</div>
        <SelectedFlightCard
          details={details}
          arcColor={arcColor}
          userId={userId}
          prominent
          emptyHint={`Select a route on the ${view === "map" ? "map" : "globe"}, or a flight below, to see its details.`}
        />
      </div>
      {/* Same bare, circular globe (and container width) as the landing page,
        so it looks the same in both places — it needs to sit on the same
        dark ground too, since bare mode leaves the globe's land
        transparent. */}
      <div
        className={`flex ${view === "map" ? "w-[560px]" : "w-[380px]"} max-w-full flex-col gap-3 self-center`}
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div
            role="group"
            aria-label="Map style"
            className="flex rounded-full border border-white/15 p-0.5"
          >
            {(
              [
                ["globe", "Globe"],
                ["map", "2D map"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                aria-pressed={view === id}
                onClick={() => handleView(id)}
                className={`rounded-full px-3 py-1 text-xs transition-colors ${
                  view === id
                    ? "bg-white/15 text-white"
                    : "text-white/60 hover:text-white"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
          <div
            role="group"
            aria-label="Route colour"
            className="flex items-center gap-1.5"
          >
            {ROUTE_COLORS.map(({ name, hex }) => {
              const chosen = arcColor.toLowerCase() === hex.toLowerCase();
              return (
                <button
                  key={hex}
                  type="button"
                  title={name}
                  aria-label={`${name} routes`}
                  aria-pressed={chosen}
                  onClick={() => handleChange(hex)}
                  className={`h-5 w-5 rounded-full border transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white ${
                    chosen
                      ? "border-white ring-2 ring-white/40"
                      : "border-white/25"
                  }`}
                  style={{ background: hex }}
                />
              );
            })}
          </div>
        </div>
        <FlightGlobe
          // Remounted to switch: the map's projection is set up once.
          key={view}
          points={points}
          arcs={arcs}
          arcColor={arcColor}
          bare
          flat={view === "map"}
          onAirportClick={(code) => openAirport(code, { scroll: false })}
        />
        {airportCode && (
          <Link
            href={`/plan?airport=${encodeURIComponent(airportCode)}`}
            className="self-center rounded-full border border-white/20 px-3 py-1 text-xs text-white/80 transition-colors hover:bg-white/10"
          >
            {airportCode}: airport info &amp; METAR &rarr;
          </Link>
        )}
      </div>
    </div>
  );
}
