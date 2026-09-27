import { useState, useSyncExternalStore } from "react";

// The colour the user draws their routes in, chosen on the Flight Map page
// and shared with the summary card there and on the Flight Log page.
// Remembered per browser. Kept apart from flight-globe.tsx so the log page
// doesn't load the map library just for this.

export const DEFAULT_ARC_COLOR = "#38d9ff";

// The route colours to choose from.
export const ROUTE_COLORS = [
  { name: "Sky", hex: DEFAULT_ARC_COLOR },
  { name: "Gold", hex: "#f5c451" },
  { name: "Coral", hex: "#ff7a6b" },
  { name: "Rose", hex: "#ff6fb5" },
  { name: "Violet", hex: "#a78bfa" },
  { name: "Lime", hex: "#9be15d" },
  { name: "White", hex: "#e8eef5" },
];

const STORAGE_KEY = "flightworld:arc-color";

const noopSubscribe = () => () => {};
const getPersisted = () => window.localStorage.getItem(STORAGE_KEY);
const getServerValue = () => null;

/** The chosen route colour, and a setter that also remembers it. */
export function useRouteColor(): [string, (hex: string) => void] {
  // Reads localStorage without a server/client hydration mismatch: this
  // resolves to null during SSR and the client's first render, then settles
  // on the stored value right after.
  const persisted = useSyncExternalStore(
    noopSubscribe,
    getPersisted,
    getServerValue,
  );
  // A colour picked this session takes priority once set, applying at once
  // rather than waiting for the next external-store read.
  const [picked, setPicked] = useState<string | null>(null);
  const choose = (hex: string) => {
    setPicked(hex);
    window.localStorage.setItem(STORAGE_KEY, hex);
  };
  return [picked ?? persisted ?? DEFAULT_ARC_COLOR, choose];
}
