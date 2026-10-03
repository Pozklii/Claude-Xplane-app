"use client";

import { useSyncExternalStore } from "react";

/** A flight confirmed on the Flight Plan page, waiting to be flown and
 * then logged ("Flight completed"). */
export type ConfirmedFlight = {
  /** Airport codes as looked up (ICAO, or IATA where there's no ICAO). */
  from: string;
  to: string;
  fromName: string;
  toName: string;
  fromCountry: string | null;
  toCountry: string | null;
  airline: string;
  airlineIata: string | null;
  aircraft: string;
  nm: number;
  /** The planned flight time. */
  hours: number;
  /** When it was confirmed (ISO timestamp). */
  confirmedAt: string;
};

const KEY = "flight-world:confirmed-flight";
const listeners = new Set<() => void>();
// Stands in for storage where it's unavailable (private windows, blocked
// site data), so confirming still works for the visit.
let memory: string | null = null;
let cachedRaw: string | null = null;
let cached: ConfirmedFlight | null = null;

function readRaw() {
  try {
    return window.localStorage.getItem(KEY);
  } catch {
    return memory;
  }
}

function parse(raw: string | null): ConfirmedFlight | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as ConfirmedFlight;
    return value && typeof value.from === "string" && value.to
      ? value
      : null;
  } catch {
    return null;
  }
}

// The same object for the same stored text, as useSyncExternalStore needs.
function getSnapshot() {
  const raw = readRaw();
  if (raw !== cachedRaw) {
    cachedRaw = raw;
    cached = parse(raw);
  }
  return cached;
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  // Another tab confirming or logging a flight.
  const onStorage = (event: StorageEvent) => {
    if (event.key === KEY) listener();
  };
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

/** Confirms a flight (replacing any already confirmed), or with null clears
 * it. Kept in this browser, so it survives reloads and going off to fly. */
export function setConfirmedFlight(flight: ConfirmedFlight | null) {
  const raw = flight ? JSON.stringify(flight) : null;
  memory = raw;
  try {
    if (raw) window.localStorage.setItem(KEY, raw);
    else window.localStorage.removeItem(KEY);
  } catch {
    // Kept in memory only.
  }
  for (const listener of listeners) listener();
}

/** The confirmed flight, if any (null while rendering on the server). */
export function useConfirmedFlight() {
  return useSyncExternalStore(subscribe, getSnapshot, () => null);
}
