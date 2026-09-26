"use client";

import { useState, useSyncExternalStore } from "react";
import {
  DEFAULT_ARC_COLOR,
  FlightGlobe,
  type GlobeArc,
  type GlobePoint,
} from "./flight-globe";
import { SelectedFlightCard, type FlightDetails } from "./selected-flight-card";

const STORAGE_KEY = "flightworld:arc-color";

function noopSubscribe() {
  return () => {};
}

function getPersistedArcColor() {
  return window.localStorage.getItem(STORAGE_KEY);
}

function getServerArcColor() {
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
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
  details: Record<string, FlightDetails>;
  header: React.ReactNode;
  userId: string;
}) {
  // Reads localStorage without a server/client hydration mismatch: this
  // resolves to null during SSR and the client's first render, then
  // (harmlessly, since nothing else writes this key from outside this
  // component) settles on the stored value right after.
  const persisted = useSyncExternalStore(
    noopSubscribe,
    getPersistedArcColor,
    getServerArcColor,
  );
  // A color picked THIS session, which takes priority once set — a plain
  // setState from the input's own onChange, not an effect, so it applies
  // immediately rather than waiting for the next external-store read.
  const [pickedThisSession, setPickedThisSession] = useState<string | null>(
    null,
  );
  const arcColor = pickedThisSession ?? persisted ?? DEFAULT_ARC_COLOR;

  const handleChange = (color: string) => {
    setPickedThisSession(color);
    window.localStorage.setItem(STORAGE_KEY, color);
  };

  return (
    <div className="flex flex-col gap-8 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex w-full max-w-sm flex-col gap-6">
        {/* Own wrapper: see LandingShowcase. */}
        <div>{header}</div>
        <SelectedFlightCard
          details={details}
          arcColor={arcColor}
          userId={userId}
        />
      </div>
      {/* Same bare, circular globe (and container width) as the landing page,
        so it looks the same in both places — it needs to sit on the same
        dark ground too, since bare mode leaves the globe's land
        transparent. */}
      <div className="flex w-[380px] max-w-full flex-col gap-2 self-center">
        <div className="flex items-center justify-end gap-2">
          <label htmlFor="arc-color" className="text-xs text-white/60">
            Route color
          </label>
          <input
            id="arc-color"
            type="color"
            value={arcColor}
            onChange={(e) => handleChange(e.target.value)}
            className="h-6 w-10 cursor-pointer rounded border border-white/20 bg-transparent p-0"
          />
        </div>
        <FlightGlobe points={points} arcs={arcs} arcColor={arcColor} bare />
      </div>
    </div>
  );
}
