"use client";

import { useSyncExternalStore } from "react";
import type { SimbriefPlan } from "@/lib/simbrief";
import { saveConfirmedFlightToAccount } from "./confirmed-flight-actions";

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
  /** The SimBrief plan it was confirmed with, if any; logged with the
   * flight, to compare planned against actual. */
  plan?: SimbriefPlan;
  /** When it was confirmed (ISO timestamp). */
  confirmedAt: string;
};

const KEY = "flight-world:confirmed-flight";
// When this browser's copy last changed (confirmed, logged or cancelled),
// to tell which is newer: it or the one saved with the account.
const CHANGED_KEY = "flight-world:confirmed-flight-changed";
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
    return value && typeof value.from === "string" && value.to ? value : null;
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
  // (CHANGED_KEY changes alongside KEY.)
  window.addEventListener("storage", onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", onStorage);
  };
}

let memoryChanged: string | null = null;

/** When this browser's confirmed flight last changed (ISO), if known. */
export function confirmedFlightChangedAt() {
  try {
    return window.localStorage.getItem(CHANGED_KEY);
  } catch {
    return memoryChanged;
  }
}

/** Confirms a flight (replacing any already confirmed), or with null clears
 * it. Kept in this browser, so it survives reloads and going off to fly,
 * and saved with the account so it follows the user to other devices
 * (unless `fromAccount`: it came from there). */
export function setConfirmedFlight(
  flight: ConfirmedFlight | null,
  { at = new Date().toISOString(), fromAccount = false } = {},
) {
  const raw = flight ? JSON.stringify(flight) : null;
  memory = raw;
  memoryChanged = at;
  try {
    if (raw) window.localStorage.setItem(KEY, raw);
    else window.localStorage.removeItem(KEY);
    window.localStorage.setItem(CHANGED_KEY, at);
  } catch {
    // Kept in memory only.
  }
  for (const listener of listeners) listener();
  if (!fromAccount) {
    saveConfirmedFlightToAccount(flight, at).catch(() => {
      // Offline or signed out: this browser's copy still stands.
    });
  }
}

/** Brings this browser and the account into step when the planner opens:
 * whichever changed more recently wins. */
export function syncConfirmedFlight(
  saved: {
    flight: ConfirmedFlight | null;
    updatedAt: string;
  } | null,
) {
  const local = getSnapshot();
  const localAt = confirmedFlightChangedAt();
  // Compared as times: the database writes "+00:00" where browsers write
  // "Z", and keeps microseconds.
  const savedTime = saved ? Date.parse(saved.updatedAt) : NaN;
  const localTime = localAt ? Date.parse(localAt) : NaN;
  if (saved && !(localTime > savedTime + 1)) {
    if (JSON.stringify(saved.flight) !== JSON.stringify(local)) {
      setConfirmedFlight(saved.flight, {
        at: saved.updatedAt,
        fromAccount: true,
      });
    }
  } else if (local || saved) {
    // This browser's is newer (or the account has none yet): save it.
    saveConfirmedFlightToAccount(
      local,
      localAt ?? new Date().toISOString(),
    ).catch(() => {});
  }
}

/** The confirmed flight, if any (null while rendering on the server). */
export function useConfirmedFlight() {
  return useSyncExternalStore(subscribe, getSnapshot, () => null);
}
