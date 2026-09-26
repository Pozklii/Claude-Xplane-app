"use server";

import { getAirportFacts } from "@/lib/airport-details";
import { CHALLENGING_AIRPORTS } from "@/lib/challenging-airports";

/** Facts for the airport panel, by ICAO or IATA code (public data). */
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
  return { ...facts, challenge: challenge?.why ?? null };
}

export type AirportLookup = NonNullable<
  Awaited<ReturnType<typeof lookupAirport>>
>;
