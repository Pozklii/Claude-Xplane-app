import "server-only";
import { findAirline } from "@/lib/airlines";
import { findAirport } from "@/lib/airports";
import { countryName } from "@/lib/countries";
import { routePairKey } from "./planner-data";

// What summarizeFlying needs from each logged flight.
type LoggedFlight = {
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
};

// How often each value occurs, most frequent first.
function rankByCount(values: string[]) {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

// The user's airlines (with logo codes and flight counts), the countries
// their flights touched, the airports they use most and the routes they've
// flown — for the flights page's profile strip and the flight planner.
export function summarizeFlying(flights: LoggedFlight[]) {
  const airlines = rankByCount(
    flights.flatMap((flight) => (flight.airline ? [flight.airline] : [])),
  ).map(([name, count]) => ({
    name,
    count,
    iata: findAirline(name)?.iata ?? null,
  }));

  const countries = new Map<string, number>();
  const airportCodes: string[] = [];
  const flownPairs = new Set<string>();
  for (const flight of flights) {
    const from = findAirport(flight.departure);
    const to = findAirport(flight.arrival);
    for (const airport of [from, to]) {
      if (!airport) continue;
      airportCodes.push(airport.code);
      if (airport.country) {
        countries.set(
          airport.country,
          (countries.get(airport.country) ?? 0) + 1,
        );
      }
    }
    if (from && to) flownPairs.add(routePairKey(from, to));
  }

  return {
    airlines,
    countries: [...countries.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([code]) => ({ code, name: countryName(code) ?? code })),
    topAirports: rankByCount(airportCodes)
      .slice(0, 6)
      .map(([code]) => code),
    topAircraft: rankByCount(flights.map((flight) => flight.aircraft))[0]?.[0],
    flownPairs: [...flownPairs],
  };
}
