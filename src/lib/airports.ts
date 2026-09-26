import "server-only";
import data from "./data/airports.json";

export type Airport = {
  code: string;
  name: string;
  city: string;
  lat: number;
  lon: number;
};

const airports = data as Record<
  string,
  Omit<Airport, "code">
>;

/**
 * Looks up an airport by ICAO or IATA code. The bundled dataset is derived
 * from OurAirports (ourairports.com/data, public domain) — ~19k airports
 * with a usable ICAO and/or IATA code, closed airports excluded — keyed by
 * both codes, uppercased.
 */
export function findAirport(code: string): Airport | null {
  const key = code.trim().toUpperCase();
  const airport = airports[key];
  return airport ? { ...airport, code: key } : null;
}
