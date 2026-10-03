"use client";

import { useEffect, useRef, useState } from "react";

// Mirrors LiveAircraft in src/lib/live-traffic.ts (server-only, so it can't
// be imported here).
export type LiveAircraft = {
  hex: string;
  callsign: string;
  registration: string | null;
  type: string | null;
  lat: number;
  lon: number;
  altitudeFt: number;
  groundSpeedKt: number;
  trackDeg: number;
  verticalRateFpm: number | null;
  positionAgeSec: number;
};

export type LiveFeed = {
  aircraft: LiveAircraft[];
  centre: { lat: number; lon: number };
  radiusNm: number;
  /** When this browser received the feed (ms since epoch). */
  receivedAt: number;
};

type LiveRoute = {
  codes: string[];
  airports: { code: string; name: string; city: string }[];
  plausible: boolean;
};

const POLL_MS = 20_000;
// Dead reckoning stops after this long without a fresh report, rather than
// sending an aircraft that's dropped out of coverage across the map.
const MAX_EXTRAPOLATION_SEC = 90;
const EARTH_RADIUS_M = 6_371_000;

/**
 * Polls /api/live-traffic around whatever point `getCentre` returns (the
 * map's centre) while `enabled`. `refresh` re-queries straight away, e.g.
 * after the map has been moved somewhere else.
 */
export function useLiveTraffic(
  enabled: boolean,
  getCentre: () => { lat: number; lon: number } | null,
) {
  const [feed, setFeed] = useState<LiveFeed | null>(null);
  const [error, setError] = useState<string | null>(null);
  const getCentreRef = useRef(getCentre);
  const refreshRef = useRef<() => void>(() => {});
  useEffect(() => {
    getCentreRef.current = getCentre;
  });

  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    let timer = 0;
    let controller: AbortController | null = null;

    const load = async () => {
      window.clearTimeout(timer);
      const centre = getCentreRef.current();
      if (!centre) {
        timer = window.setTimeout(load, 1000);
        return;
      }
      controller?.abort();
      controller = new AbortController();
      try {
        const res = await fetch(
          `/api/live-traffic?lat=${centre.lat.toFixed(3)}&lon=${centre.lon.toFixed(3)}`,
          { signal: controller.signal, cache: "no-store" },
        );
        const body = await res.json();
        if (cancelled) return;
        if (res.ok) {
          setError(null);
          setFeed({ ...body, receivedAt: Date.now() });
        } else {
          setError(body.error ?? "Live traffic is unavailable right now.");
        }
      } catch (err) {
        if (cancelled || (err as Error).name === "AbortError") return;
        setError("Couldn’t reach the live traffic feed.");
      }
      if (!cancelled) timer = window.setTimeout(load, POLL_MS);
    };

    refreshRef.current = load;
    load();
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      controller?.abort();
      refreshRef.current = () => {};
    };
  }, [enabled]);

  return {
    feed: enabled ? feed : null,
    error: enabled ? error : null,
    refresh: () => refreshRef.current(),
  };
}

/**
 * Where an aircraft is now, moved on from its last report along its track at
 * its ground speed (great-circle dead reckoning).
 */
export function deadReckon(
  aircraft: LiveAircraft,
  receivedAt: number,
  now: number,
): [number, number] {
  const seconds = Math.min(
    MAX_EXTRAPOLATION_SEC,
    Math.max(0, (now - receivedAt) / 1000 + aircraft.positionAgeSec),
  );
  const distance = (aircraft.groundSpeedKt * 1852 * seconds) / 3600;
  const delta = distance / EARTH_RADIUS_M;
  const theta = (aircraft.trackDeg * Math.PI) / 180;
  const phi1 = (aircraft.lat * Math.PI) / 180;
  const lambda1 = (aircraft.lon * Math.PI) / 180;
  const phi2 = Math.asin(
    Math.sin(phi1) * Math.cos(delta) +
      Math.cos(phi1) * Math.sin(delta) * Math.cos(theta),
  );
  const lambda2 =
    lambda1 +
    Math.atan2(
      Math.sin(theta) * Math.sin(delta) * Math.cos(phi1),
      Math.cos(delta) - Math.sin(phi1) * Math.sin(phi2),
    );
  return [
    ((((lambda2 * 180) / Math.PI + 540) % 360) - 180),
    (phi2 * 180) / Math.PI,
  ];
}

const formatAltitude = (feet: number) =>
  feet >= 18_000
    ? `FL${String(Math.round(feet / 100)).padStart(3, "0")}`
    : `${Math.round(feet / 100) * 100} ft`;

function verticalTrend(rate: number | null) {
  if (rate === null || Math.abs(rate) < 300) return "Level";
  return `${rate > 0 ? "Climbing" : "Descending"} ${Math.abs(Math.round(rate / 100) * 100)} ft/min`;
}

/** Status of the live feed, and the selected aircraft's details. */
export function LiveTrafficPanel({
  feed,
  error,
  selectedHex,
  onClose,
}: {
  feed: LiveFeed | null;
  error: string | null;
  selectedHex: string | null;
  onClose: () => void;
}) {
  const selected =
    (selectedHex && feed?.aircraft.find((a) => a.hex === selectedHex)) || null;
  return (
    <div className="flex flex-col gap-2 px-1 text-xs text-white/70">
      <p role="status">
        {error
          ? error
          : feed
            ? `${feed.aircraft.length} airliners in the air within ${feed.radiusNm} nm of the centre of the view · updated ${new Date(feed.receivedAt).toLocaleTimeString()}. Click one for details.`
            : "Loading live traffic…"}
      </p>
      {selected && (
        <LiveAircraftCard key={selected.hex} aircraft={selected} onClose={onClose} />
      )}
    </div>
  );
}

function LiveAircraftCard({
  aircraft,
  onClose,
}: {
  aircraft: LiveAircraft;
  onClose: () => void;
}) {
  const [route, setRoute] = useState<LiveRoute | null | undefined>(undefined);
  // Looked up once per selected aircraft (the card is keyed by it).
  const lookup = useRef({
    callsign: aircraft.callsign,
    lat: aircraft.lat,
    lon: aircraft.lon,
  });
  useEffect(() => {
    const controller = new AbortController();
    const { callsign, lat, lon } = lookup.current;
    fetch(
      `/api/flight-route?callsign=${encodeURIComponent(callsign)}&lat=${lat.toFixed(3)}&lon=${lon.toFixed(3)}`,
      { signal: controller.signal },
    )
      .then((res) => (res.ok ? res.json() : { route: null }))
      .then((body: { route: LiveRoute | null }) => setRoute(body.route))
      .catch((err: Error) => {
        if (err.name !== "AbortError") setRoute(null);
      });
    return () => controller.abort();
  }, []);

  const routeText =
    route === undefined
      ? "Looking up route…"
      : route && route.codes.length >= 2
        ? `${route.codes.join(" → ")}${
            route.airports.length === route.codes.length
              ? ` · ${route.airports.map((a) => a.city).join(" to ")}`
              : ""
          }${route.plausible ? "" : " (unconfirmed)"}`
        : "Route not known";

  return (
    <div className="rounded-xl border border-white/15 bg-white/[.04] p-3 text-white/80">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-base font-semibold tracking-wide text-white">
            {aircraft.callsign}
          </p>
          <p>
            {[aircraft.type, aircraft.registration].filter(Boolean).join(" · ") ||
              "Aircraft type not reported"}
          </p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="rounded-full border border-white/20 px-2.5 py-0.5 text-white/70 hover:bg-white/10"
        >
          Close
        </button>
      </div>
      <p className="mt-2 text-white">{routeText}</p>
      <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 tabular-nums">
        <dt className="text-white/50">Altitude</dt>
        <dd>{formatAltitude(aircraft.altitudeFt)}</dd>
        <dt className="text-white/50">Speed</dt>
        <dd>{Math.round(aircraft.groundSpeedKt)} kt ground speed</dd>
        <dt className="text-white/50">Track</dt>
        <dd>{String(Math.round(aircraft.trackDeg) % 360).padStart(3, "0")}°</dd>
        <dt className="text-white/50">Vertical</dt>
        <dd>{verticalTrend(aircraft.verticalRateFpm)}</dd>
      </dl>
    </div>
  );
}
