"use server";

import { getAirportFacts } from "@/lib/airport-details";
import { CHALLENGING_AIRPORTS } from "@/lib/challenging-airports";

/** An airport for the airport panel, by ICAO or IATA code (public data):
 * its name and codes, and whether it's a famously challenging airport. */
export async function lookupAirport(code: string) {
  const query = String(code ?? "")
    .trim()
    .toUpperCase();
  if (!/^[A-Z0-9]{3,4}$/.test(query)) return null;

  const facts = getAirportFacts(query);
  if (!facts) return null;

  const challenge = CHALLENGING_AIRPORTS.find(
    (airport) => airport.icao === facts.icao || airport.iata === facts.iata,
  );
  return {
    code: facts.code,
    name: facts.name,
    city: facts.city,
    icao: facts.icao,
    iata: facts.iata,
    country: facts.country
      ? { code: facts.country.code, name: facts.country.name }
      : null,
    runwayNames: facts.runways.map((runway) => runway.name),
    lat: facts.lat,
    lon: facts.lon,
    challenge: challenge?.why ?? null,
  };
}

export type AirportLookup = NonNullable<
  Awaited<ReturnType<typeof lookupAirport>>
>;
