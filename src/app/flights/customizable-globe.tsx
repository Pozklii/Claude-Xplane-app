"use client";

import Link from "next/link";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { FlightGlobe, type GlobeArc, type GlobePoint } from "./flight-globe";
import type { TrackPoint } from "@/lib/recording";
import { usePlanner } from "./planner-context";
import { getFlightTrack } from "./recording-actions";
import { ROUTE_COLORS, useRouteColor } from "./route-color";
import { SelectedFlightCard, type FlightDetails } from "./selected-flight-card";
import { useSelection } from "./selection-context";

const VIEW_STORAGE_KEY = "flightworld:map-view";

type MapView = "globe" | "map";

function noopSubscribe() {
  return () => {};
}

function getPersistedView() {
  return window.localStorage.getItem(VIEW_STORAGE_KEY);
}

function getServerValue() {
  return null;
}

// The Flight Map page: the globe (or 2D map) filling the page, with its
// header and the selected flight's details card over it — all here
// because the card and the map share the user's chosen route colour.
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
  /** The signed-in owner (thumbnail editing); none on a shared map. */
  userId?: string;
  /** Start on the flat 2D map rather than the globe (?map=2d). */
  flat?: boolean;
}) {
  const [arcColor, handleChange] = useRouteColor();
  // Globe or flat 2D map (straight route lines), remembered likewise.
  const persistedView = useSyncExternalStore(
    noopSubscribe,
    getPersistedView,
    getServerValue,
  );
  const [viewThisSession, setViewThisSession] = useState<MapView | null>(null);
  const view: MapView =
    viewThisSession ??
    (flat ? "map" : persistedView === "map" ? "map" : "globe");
  const { airportCode, openAirport } = usePlanner();

  // The selected flight's flown route, fetched the first time it's
  // selected (the owner's own flights only; a shared map has none).
  const { selectedFlightId } = useSelection();
  const [tracks, setTracks] = useState<Record<string, TrackPoint[]>>({});
  const needsTrack =
    userId !== undefined &&
    selectedFlightId !== null &&
    !Object.hasOwn(tracks, selectedFlightId) &&
    arcs.some((arc) => arc.id === selectedFlightId && arc.hasTrack);
  useEffect(() => {
    if (!needsTrack || selectedFlightId === null) return;
    let cancelled = false;
    getFlightTrack(selectedFlightId)
      .catch(() => null)
      .then((points) => {
        if (cancelled) return;
        // Kept even when missing, so it isn't asked for again.
        setTracks((prev) => ({ ...prev, [selectedFlightId]: points ?? [] }));
      });
    return () => {
      cancelled = true;
    };
  }, [needsTrack, selectedFlightId]);

  // How far the header/card column reaches over the map (none once it
  // stacks above it, on narrow screens), so the globe centres beside it.
  const stageRef = useRef<HTMLDivElement>(null);
  const columnRef = useRef<HTMLDivElement>(null);
  const [insetLeft, setInsetLeft] = useState(0);
  useEffect(() => {
    const stage = stageRef.current;
    const column = columnRef.current;
    if (!stage || !column) return;
    const measure = () => {
      const s = stage.getBoundingClientRect();
      const c = column.getBoundingClientRect();
      const overlaps = c.top < s.bottom && c.bottom > s.top;
      setInsetLeft(overlaps ? Math.max(0, Math.round(c.right - s.left)) : 0);
    };
    // Also runs once straight away, on observing.
    const observer = new ResizeObserver(measure);
    observer.observe(stage);
    observer.observe(column);
    return () => observer.disconnect();
  }, []);

  const handleView = (next: MapView) => {
    setViewThisSession(next);
    window.localStorage.setItem(VIEW_STORAGE_KEY, next);
  };

  return (
    <div className="relative flex flex-1 flex-col lg:flex-row">
      {/* The map fills the whole page under the header, edge to edge, so
          zooming in never runs into a frame. On a wide screen the header
          and card sit over its left side (the globe centres in the space
          beside them); on a narrow one they stack above it. */}
      <div
        ref={stageRef}
        className="relative order-last h-[72svh] min-h-[420px] lg:absolute lg:inset-0 lg:h-auto lg:min-h-0"
      >
        <FlightGlobe
          // Remounted to switch: the map's projection is set up once.
          key={view}
          points={points}
          arcs={arcs}
          arcColor={arcColor}
          bare
          fill
          insetLeft={insetLeft}
          // The whole globe at the overview; selecting a flight zooms to
          // fit its route.
          wholeGlobe
          flat={view === "map"}
          onAirportClick={(code) => openAirport(code, { scroll: false })}
          tracks={tracks}
        />
      </div>

      {/* Fades the map out behind the text, so it stays readable when
          zoomed in; clicks between the panels reach the map. */}
      <div
        ref={columnRef}
        className="relative z-10 flex w-full flex-col gap-6 px-6 pb-6 pt-10 lg:pointer-events-none lg:w-[540px] lg:bg-[linear-gradient(to_right,rgb(2_3_4/0.92),rgb(2_3_4/0.78)_50%,transparent)] lg:pb-16 lg:pr-20"
      >
        {/* Own wrapper: see LandingShowcase. */}
        <div className="max-w-md lg:pointer-events-auto">{header}</div>
        <div className="max-w-md lg:pointer-events-auto">
          <SelectedFlightCard
            details={details}
            arcColor={arcColor}
            userId={userId}
            prominent
            emptyHint={`Select a route on the ${view === "map" ? "map" : "globe"} to see its details.`}
          />
        </div>
      </div>

      <div className="relative z-10 flex flex-wrap items-center justify-between gap-3 px-6 pb-3 lg:absolute lg:right-6 lg:top-6 lg:justify-end lg:p-0">
        {airportCode && userId && (
          <Link
            href={`/plan?airport=${encodeURIComponent(airportCode)}`}
            className="rounded-full border border-white/20 bg-black/40 px-3 py-1 text-xs text-white/80 backdrop-blur transition-colors hover:bg-white/10"
          >
            {airportCode}: airport info &amp; METAR &rarr;
          </Link>
        )}
        <div
          role="group"
          aria-label="Map style"
          className="flex rounded-full border border-white/15 bg-black/40 p-0.5 backdrop-blur"
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
          className="flex items-center gap-1.5 rounded-full bg-black/40 px-2 py-1 backdrop-blur"
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
    </div>
  );
}
