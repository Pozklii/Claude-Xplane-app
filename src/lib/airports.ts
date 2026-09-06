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
 * Looks up an airport by ICAO or IATA code. The bundled dataset (derived
 * from OpenFlights via the `airport-data` npm package, Unlicense) is keyed
 * by both, uppercased.
 */
export function findAirport(code: string): Airport | null {
  const key = code.trim().toUpperCase();
  const airport = airports[key];
  return airport ? { ...airport, code: key } : null;
}
