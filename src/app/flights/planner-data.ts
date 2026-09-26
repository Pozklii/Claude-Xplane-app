import "server-only";
import { estimateHours } from "@/lib/aircraft";
import { findAirline } from "@/lib/airlines";
import { getAirportFacts } from "@/lib/airport-details";
import { findAirport, type Airport } from "@/lib/airports";
import {
  CHALLENGING_AIRPORTS,
  type ChallengeKind,
} from "@/lib/challenging-airports";
import { AIRCRAFT, EXAMPLE_ROUTES } from "@/lib/example-flights/routes";
import { distanceNm } from "@/lib/geo";

export type PlannerAirport = {
  code: string;
  city: string;
  country: string | null;
};

export type SuggestionRoute = {
  /** "airline:AAA-BBB", as the example-flight generator keys routes. */
  key: string;
  /** The airport pair, direction-free — see routePairKey. */
  pairKey: string;
  airline: string | null;
  airlineIata: string | null;
  from: PlannerAirport;
  to: PlannerAirport;
  aircraft: string[];
  distanceNm: number;
  /** Either end is on the challenging-airports list. */
  challenging: boolean;
};

export type ChallengeCardData = {
  icao: string;
  iata: string;
  name: string;
  city: string;
  country: string | null;
  kinds: ChallengeKind[];
  difficulty: number;
  why: string;
  elevationFt: number | null;
  longestRunwayFt: number | null;
  route: {
    from: PlannerAirport;
    airline: string | null;
    airlineIata: string | null;
    aircraft: string;
    distanceNm: number;
    hours: number;
  } | null;
};

// The dataset's long city names ("Paris (Roissy-en-France, Val-d'Oise)")
// read better short, as on the landing page.
const shortCity = (city: string) =>
  city.replace(/\s*\(.*\)$/, "").split(",")[0];

const plannerAirport = (airport: Airport): PlannerAirport => ({
  code: airport.code,
  city: shortCity(airport.city),
  country: airport.country,
});

/** A direction-free key for an airport pair, the same whether each end was
 * given by ICAO or IATA code (both resolve to one OurAirports ident). */
export function routePairKey(a: Airport, b: Airport) {
  return [a.ident ?? a.code, b.ident ?? b.code].sort().join("-");
}

const challengingCodes = new Set(
  CHALLENGING_AIRPORTS.flatMap((airport) => [airport.icao, airport.iata]),
);

/** Every real-world route in the route table, resolved for display. */
export function buildSuggestionRoutes(): SuggestionRoute[] {
  const routes: SuggestionRoute[] = [];
  for (const route of EXAMPLE_ROUTES) {
    const from = findAirport(route.between[0]);
    const to = findAirport(route.between[1]);
    if (!from || !to) continue;
    routes.push({
      key: `${route.airline}:${route.between.join("-")}`,
      pairKey: routePairKey(from, to),
      airline: route.airline,
      airlineIata: findAirline(route.airline)?.iata ?? null,
      from: plannerAirport(from),
      to: plannerAirport(to),
      aircraft: route.aircraft,
      distanceNm: Math.round(distanceNm(from, to)),
      challenging:
        challengingCodes.has(from.code) || challengingCodes.has(to.code),
    });
  }
  return routes;
}

/** The challenging airports, with their facts and a route in to try. */
export function buildChallenges(): ChallengeCardData[] {
  return CHALLENGING_AIRPORTS.flatMap((challenge) => {
    const facts = getAirportFacts(challenge.icao);
    if (!facts) return [];
    const origin = findAirport(challenge.route.from);
    const aircraft = challenge.route.aircraft as keyof typeof AIRCRAFT;
    const distance = origin ? distanceNm(origin, facts) : null;
    return [
      {
        icao: challenge.icao,
        iata: challenge.iata,
        name: facts.name,
        city: shortCity(facts.city),
        country: facts.country?.code ?? null,
        kinds: challenge.kinds,
        difficulty: challenge.difficulty,
        why: challenge.why,
        elevationFt: facts.elevationFt,
        longestRunwayFt: facts.runways[0]?.lengthFt ?? null,
        route:
          origin && distance !== null && aircraft in AIRCRAFT
            ? {
                from: plannerAirport(origin),
                airline: challenge.route.airline,
                airlineIata: findAirline(challenge.route.airline)?.iata ?? null,
                aircraft,
                distanceNm: Math.round(distance),
                hours: estimateHours(aircraft, distance),
              }
            : null,
      },
    ];
  }).sort((a, b) => b.difficulty - a.difficulty);
}
