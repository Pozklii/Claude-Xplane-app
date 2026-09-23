"use client";

import { useState, useSyncExternalStore } from "react";
import {
  DEFAULT_ARC_COLOR,
  FlightGlobe,
  type GlobeArc,
  type GlobePoint,
} from "./flight-globe";

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

export function CustomizableGlobe({
  points,
  arcs,
}: {
  points: GlobePoint[];
  arcs: GlobeArc[];
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
    // Same bare, circular globe (and container width) as the landing page,
    // so it looks the same in both places — it needs to sit on the same
    // dark ground too, since bare mode leaves the globe's land transparent.
    <div className="flex w-[380px] max-w-full flex-col gap-2">
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
  );
}
