import { distanceNm } from "@/lib/geo";
import type { GlobeArc, GlobePoint } from "@/app/flights/flight-globe";
import type { FlightDetails } from "@/app/flights/selected-flight-card";
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

function randomDate(rng: Rng, now: number) {
  // Some time in the last ~18 months.
  const daysAgo = Math.floor(between(1, 540, rng));
  return new Date(now - daysAgo * 86_400_000).toISOString().slice(0, 10);
}

function writeNotes(
  from: ExampleAirport,
  to: ExampleAirport,
  altitude: number,
  isShort: boolean,
  rng: Rng,
) {
  const cruise =
    altitude >= 180
      ? `Cruised at FL${Math.round(altitude / 10) * 10} with a ${Math.round(between(10, 130, rng))} kt ${pick(["headwind", "tailwind", "crosswind"], rng)}.`
      : `Cruised at ${(Math.round(altitude / 5) * 500).toLocaleString("en-US")} ft, ${pick(["smooth air below the cloud base", "a few bumps over the hills", "clear views of the coast"], rng)}.`;
  const departure = pick(
    [
      `Early-morning departure out of ${from.city}.`,
      `Night departure out of ${from.city}.`,
      `Short taxi and an on-time push in ${from.city}.`,
      `Held for ${Math.round(between(5, 25, rng))} minutes at the gate in ${from.city}.`,
      `De-iced in ${from.city} before departure.`,
    ],
    rng,
  );
  const enroute = isShort
    ? pick(["Light chop on the climb.", "Smooth ride the whole way."], rng)
    : pick(
        [
          "Light chop for the first hour, smooth after that.",
          "Smooth ride the whole way.",
          "Some turbulence crossing a line of storms.",
          `Stepped up to FL${Math.round(altitude / 10) * 10 + 20} as fuel burned off.`,
        ],
        rng,
      );
  const arrival = `${pick(["ILS", "RNAV", "Visual"], rng)} approach into ${to.city} ${pick(
    [
      "in clear skies",
      "through low cloud",
      "in light rain",
      "with a gusty crosswind",
      "at dusk",
      "after a short hold",
    ],
    rng,
  )}.`;
  // Two sentences: always the arrival, plus one of the others.
  return `${pick([departure, cruise, enroute], rng)} ${arrival}`;
}

/**
 * One random example flight: a route from the table (in either direction),
 * one of the aircraft that airline flies on it, a recent date, a flight
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
  rng = Math.random,
  now = Date.now(),
}: {
  id: string;
  airports: Record<string, ExampleAirport>;
  routes: ExampleRoute[];
  recentRouteKeys?: string[];
  rng?: Rng;
  now?: number;
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
  const date = randomDate(rng, now);

  return {
    id,
    routeKey,
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
      notes: writeNotes(from, to, altitude, hours < 2, rng),
      thumbnailUrl: null,
      customThumbnailPath: null,
      images: [],
    },
  };
}
