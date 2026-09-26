"use server";

import { getAirportFacts } from "@/lib/airport-details";
import { triviaFor } from "@/lib/airport-trivia";
import { CHALLENGING_AIRPORTS } from "@/lib/challenging-airports";

/** An airport for the airport panel, by ICAO or IATA code (public data):
 * its name and codes, whether it's a famously challenging airport, and a
 * pool of facts about it and its country to show one of at random. */
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
    challenge: challenge?.why ?? null,
    // The challenge is shown separately, so leave it out of the facts.
    trivia: triviaFor([query]).filter(
      (fact) => !challenge || !fact.text.includes("famously challenging"),
    ),
  };
}

export type AirportLookup = NonNullable<
  Awaited<ReturnType<typeof lookupAirport>>
>;
