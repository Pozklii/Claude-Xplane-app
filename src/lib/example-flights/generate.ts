import { distanceNm } from "@/lib/geo";
import type { GlobeArc, GlobePoint } from "@/app/flights/flight-globe";
import type { FlightDetails } from "@/app/flights/selected-flight-card";
import { isoDaysBefore } from "@/lib/dates";
import { writeNotes } from "./notes";
import {
  AIRCRAFT,
  AIRCRAFT_CLASSES,
  EXAMPLE_ROUTES,
  type ExampleRoute,
} from "./routes";

export type ExampleAirport = {
  code: string;
  city: string;
  lat: number;
  lon: number;
};

export type ExampleFlight = {
  id: string;
  routeKey: string;
  /** Days before "today" this flight is dated — kept so the client can
   * re-date flights seeded on the server against the viewer's own today. */
  daysAgo: number;
  /** Note templates used (see ./notes), so later flights can avoid them. */
  noteKeys: string[];
  arc: GlobeArc;
  points: [GlobePoint, GlobePoint];
  details: FlightDetails;
};

/** How many recent example flights stay drawn on the landing globe. */
export const EXAMPLE_HISTORY_SIZE = 6;

type Rng = () => number;

const pick = <T>(items: readonly T[], rng: Rng) =>
  items[Math.floor(rng() * items.length)];
const between = (min: number, max: number, rng: Rng) =>
  min + (max - min) * rng();

/** Routes whose airports are all known, and that don't cross the
 * antimeridian (the selection camera fits a plain min/max bounding box,
 * which would otherwise wrap the long way around the globe). */
export function usableRoutes(airports: Record<string, ExampleAirport>) {
  return EXAMPLE_ROUTES.filter(({ between: [a, b] }) => {
    const from = airports[a];
    const to = airports[b];
    return from && to && Math.abs(from.lon - to.lon) < 180;
  });
}

// How far back generated flights go: anywhere from today to ~18 months ago.
const MAX_DAYS_AGO = 540;

/**
 * One random example flight: a route from the table (in either direction),
 * one of the aircraft that airline flies on it, a date in the last ~18
 * months (possibly `today` itself), a flight
 * time estimated from the real great-circle distance and the aircraft's
 * cruise speed, and a couple of generated notes. Endless — call it as
 * often as needed. Avoids repeating any route listed in `recentRouteKeys`
 * where it can.
 */
export function generateExampleFlight({
  id,
  airports,
  routes,
  recentRouteKeys = [],
  recentNoteKeys = [],
  today,
  rng = Math.random,
}: {
  id: string;
  airports: Record<string, ExampleAirport>;
  routes: ExampleRoute[];
  recentRouteKeys?: string[];
  /** Note templates the flights already on screen used. */
  recentNoteKeys?: string[];
  /** "YYYY-MM-DD" the dates count back from (0 days ago = this day). */
  today: string;
  rng?: Rng;
}): ExampleFlight {
  let route = pick(routes, rng);
  for (let tries = 0; tries < 10; tries++) {
    const key = `${route.airline}:${route.between.join("-")}`;
    if (!recentRouteKeys.includes(key)) break;
    route = pick(routes, rng);
  }
  const routeKey = `${route.airline}:${route.between.join("-")}`;
  const [a, b] = rng() < 0.5 ? route.between : [...route.between].reverse();
  const from = airports[a];
  const to = airports[b];

  const aircraft = pick(route.aircraft, rng);
  const performance = AIRCRAFT_CLASSES[AIRCRAFT[aircraft]];
  const distance = distanceNm(from, to);
  // Cruise time plus taxi/climb/descent, give or take ~6% for winds.
  const hours =
    Math.round(
      (distance / performance.cruiseKts + performance.overheadHours) *
        between(0.94, 1.06, rng) *
        10,
    ) / 10;
  const altitude = Math.round(
    between(performance.altitude[0], performance.altitude[1], rng),
  );

  const point = (airport: ExampleAirport): GlobePoint => ({
    code: airport.code,
    name: airport.code,
    city: airport.city,
    lat: airport.lat,
    lng: airport.lon,
  });
  const daysAgo = Math.floor(rng() * (MAX_DAYS_AGO + 1));
  const date = isoDaysBefore(today, daysAgo);
  const notes = writeNotes(
    {
      from: from.city,
      to: to.city,
      altitude,
      hours,
      highLatitude: Math.max(Math.abs(from.lat), Math.abs(to.lat)) > 55,
      lowAndSlow: ["turboprop", "piston"].includes(AIRCRAFT[aircraft]),
      airliner: route.airline !== null,
      rng,
    },
    recentNoteKeys,
  );

  return {
    id,
    routeKey,
    daysAgo,
    noteKeys: notes.keys,
    points: [point(from), point(to)],
    arc: {
      id,
      startLat: from.lat,
      startLng: from.lon,
      endLat: to.lat,
      endLng: to.lon,
      fromCode: from.code,
      toCode: to.code,
      label: `${aircraft} · ${from.code} → ${to.code} · ${date}`,
    },
    details: {
      date,
      airline: route.airline,
      aircraft,
      from: { code: from.code, city: from.city },
      to: { code: to.code, city: to.city },
      hours,
      distanceNm: distance,
      notes: notes.text,
      thumbnailUrl: null,
      customThumbnailPath: null,
      images: [],
    },
  };
}
