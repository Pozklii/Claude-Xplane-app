import "server-only";
import data from "./data/airports.json";

export type Airport = {
  code: string;
  name: string;
  city: string;
  lat: number;
  lon: number;
  /** ISO 3166-1 alpha-2 country code. */
  country: string | null;
  /** OurAirports ident, the key into airport-details.json. */
  ident: string | null;
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

const entries = Object.entries(airports);

/** The airport nearest a position (e.g. where a flight took off or
 * landed), and how far away it is in nautical miles. Of an airport's two
 * codes, the ICAO one. */
export function nearestAirport(
  lat: number,
  lon: number,
): { airport: Airport; distanceNm: number } | null {
  const rad = Math.PI / 180;
  const cosLat = Math.cos(lat * rad);
  let bestKey: string | null = null;
  let best = Infinity;
  for (const [key, airport] of entries) {
    // Equirectangular: plenty accurate for picking the nearest.
    const dLat = airport.lat - lat;
    let dLon = Math.abs(airport.lon - lon);
    if (dLon > 180) dLon = 360 - dLon;
    const d = dLat * dLat + (dLon * cosLat) ** 2;
    if (
      d < best ||
      // The same airport under its other code: prefer the ICAO one.
      (d === best && key.length === 4 && bestKey?.length !== 4)
    ) {
      best = d;
      bestKey = key;
    }
  }
  if (bestKey === null) return null;
  return {
    airport: { ...airports[bestKey], code: bestKey },
    distanceNm: Math.sqrt(best) * 60,
  };
}
