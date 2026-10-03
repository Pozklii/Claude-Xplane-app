import "server-only";
import { findAirport } from "./airports";

// adsb.lol: a community ADS-B network with a free, keyless API. Its data is
// open under the ODbL, which requires crediting adsb.lol wherever it's
// shown. Aircraft come back in the readsb / ADS-B Exchange v2 format.
const POINT_URL = "https://api.adsb.lol/v2/point";
const ROUTESET_URL = "https://api.adsb.lol/api/0/routeset";
const USER_AGENT = "FlightWorld/1.0 (flight logbook web app)";

/** The point query's maximum radius, in nautical miles. */
export const LIVE_RADIUS_NM = 250;

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
  /** Seconds between the position fix and the response being generated. */
  positionAgeSec: number;
};

export type LiveRoute = {
  codes: string[];
  airports: { code: string; name: string; city: string; lat: number; lon: number }[];
  plausible: boolean;
};

// Airline flights use the operator's ICAO code plus a flight number
// (BAW117, DLH4AB); private and military callsigns usually don't.
const AIRLINE_CALLSIGN = /^[A-Z]{3}\d[A-Z0-9]{0,3}$/;

const num = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : null;
const str = (value: unknown) =>
  typeof value === "string" && value.trim() ? value.trim() : null;

/** Airborne airline traffic within LIVE_RADIUS_NM of a point. Cached for 15 s. */
export async function fetchLiveTraffic(lat: number, lon: number) {
  const res = await fetch(`${POINT_URL}/${lat}/${lon}/${LIVE_RADIUS_NM}`, {
    headers: { "User-Agent": USER_AGENT },
    next: { revalidate: 15 },
  });
  if (!res.ok) throw new Error(`adsb.lol returned ${res.status}`);

  const body = (await res.json()) as { ac?: unknown; now?: unknown };
  if (!Array.isArray(body.ac)) throw new Error("adsb.lol sent no aircraft list");

  const aircraft: LiveAircraft[] = [];
  for (const raw of body.ac as Record<string, unknown>[]) {
    const callsign = str(raw.flight)?.toUpperCase();
    const hex = str(raw.hex);
    const lat = num(raw.lat);
    const lon = num(raw.lon);
    // alt_baro is the string "ground" for aircraft on the ground, which
    // num() turns into null, dropping them along with incomplete reports.
    const altitudeFt = num(raw.alt_baro) ?? num(raw.alt_geom);
    const groundSpeedKt = num(raw.gs);
    const trackDeg = num(raw.track) ?? num(raw.true_heading);
    if (
      !callsign ||
      !AIRLINE_CALLSIGN.test(callsign) ||
      !hex ||
      lat === null ||
      lon === null ||
      altitudeFt === null ||
      groundSpeedKt === null ||
      trackDeg === null
    ) {
      continue;
    }
    aircraft.push({
      hex,
      callsign,
      registration: str(raw.r),
      type: str(raw.t),
      lat,
      lon,
      altitudeFt,
      groundSpeedKt,
      trackDeg,
      verticalRateFpm: num(raw.baro_rate) ?? num(raw.geom_rate),
      positionAgeSec: num(raw.seen_pos) ?? num(raw.seen) ?? 0,
    });
  }
  return { aircraft, generatedAt: num(body.now) ?? Date.now() };
}

/**
 * The scheduled route a callsign is flying, from adsb.lol's crowd-sourced
 * route database. Null when it isn't known. Airports are resolved against
 * the app's own OurAirports dataset rather than adsb.lol's copy.
 */
export async function fetchRoute(
  callsign: string,
  lat: number,
  lon: number,
): Promise<LiveRoute | null> {
  const res = await fetch(ROUTESET_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "User-Agent": USER_AGENT },
    body: JSON.stringify({ planes: [{ callsign, lat, lng: lon }] }),
  });
  if (!res.ok) throw new Error(`adsb.lol returned ${res.status}`);

  const body: unknown = await res.json();
  const entry = (Array.isArray(body) ? body[0] : null) as Record<
    string,
    unknown
  > | null;
  const codesText =
    str(entry?._airport_codes_iata) ?? str(entry?.airport_codes);
  if (!entry || !codesText || codesText.toLowerCase() === "unknown") return null;

  const codes = codesText.split("-").map((code) => code.trim().toUpperCase());
  const airports = codes.flatMap((code) => {
    const airport = findAirport(code);
    return airport
      ? [
          {
            code,
            name: airport.name,
            city: airport.city,
            lat: airport.lat,
            lon: airport.lon,
          },
        ]
      : [];
  });
  return { codes, airports, plausible: entry.plausible !== 0 && entry.plausible !== false };
}
