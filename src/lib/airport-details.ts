import "server-only";
import data from "./data/airport-details.json";
import { findAirport } from "./airports";
import { countryFacts, type CountryFacts } from "./countries";

export type Runway = {
  name: string;
  lengthFt: number | null;
  widthFt: number | null;
  surface: string | null;
  lighted: boolean;
};

type Details = {
  type: string;
  country: string | null;
  elevationFt: number | null;
  continent: string | null;
  region: string | null;
  icao: string | null;
  iata: string | null;
  scheduledService: boolean;
  wikipedia: string | null;
  runways: Runway[];
};

const details = data as Record<string, Details>;

const TYPE_LABELS: Record<string, string> = {
  large_airport: "Large airport",
  medium_airport: "Medium airport",
  small_airport: "Small airport",
  heliport: "Heliport",
  seaplane_base: "Seaplane base",
  balloonport: "Balloon port",
  closed: "Closed",
};

// OurAirports surface codes are free text, mostly abbreviations.
const SURFACES: [RegExp, string][] = [
  [/^(ASP|ASPH|BIT|PEM)/i, "Asphalt"],
  [/^CON/i, "Concrete"],
  [/^(GRS|GRASS|TURF)/i, "Grass"],
  [/^(GRE|GRV|GRAVEL)/i, "Gravel"],
  [/^(DIRT|CLA|SAND|SAN)/i, "Dirt/sand"],
  [/^(WATER|WAT)/i, "Water"],
  [/^(SNOW|ICE)/i, "Snow/ice"],
];

function surfaceLabel(surface: string | null) {
  if (!surface) return null;
  const match = SURFACES.find(([pattern]) => pattern.test(surface));
  return match ? match[1] : surface;
}

export type AirportFacts = {
  code: string;
  name: string;
  city: string;
  lat: number;
  lon: number;
  icao: string | null;
  iata: string | null;
  typeLabel: string | null;
  elevationFt: number | null;
  scheduledService: boolean;
  wikipedia: string | null;
  runways: (Runway & { surfaceLabel: string | null })[];
  country: CountryFacts | null;
  /** How many airports with a usable ICAO/IATA code the country has. */
  countryAirportCount: number;
};

let airportsPerCountry: Map<string, number> | null = null;
function countAirports(country: string) {
  if (!airportsPerCountry) {
    airportsPerCountry = new Map();
    for (const entry of Object.values(details)) {
      if (!entry.country || entry.type === "heliport") continue;
      airportsPerCountry.set(
        entry.country,
        (airportsPerCountry.get(entry.country) ?? 0) + 1,
      );
    }
  }
  return airportsPerCountry.get(country) ?? 0;
}

/** Everything the airport panel shows about an airport, by ICAO/IATA code. */
export function getAirportFacts(code: string): AirportFacts | null {
  const airport = findAirport(code);
  if (!airport) return null;
  const extra = airport.ident ? details[airport.ident] : undefined;
  return {
    code: airport.code,
    name: airport.name,
    city: airport.city,
    lat: airport.lat,
    lon: airport.lon,
    icao: extra?.icao ?? (airport.code.length === 4 ? airport.code : null),
    iata: extra?.iata ?? (airport.code.length === 3 ? airport.code : null),
    typeLabel: extra ? (TYPE_LABELS[extra.type] ?? extra.type) : null,
    elevationFt: extra?.elevationFt ?? null,
    scheduledService: extra?.scheduledService ?? false,
    wikipedia: extra?.wikipedia ?? null,
    runways: (extra?.runways ?? []).map((runway) => ({
      ...runway,
      surfaceLabel: surfaceLabel(runway.surface),
    })),
    country: countryFacts(airport.country),
    countryAirportCount: airport.country ? countAirports(airport.country) : 0,
  };
}

/** Runway names only, e.g. ["09L/27R", "09R/27L"], for crosswind maths. */
export function runwayNames(code: string) {
  const airport = findAirport(code);
  const extra = airport?.ident ? details[airport.ident] : undefined;
  return (extra?.runways ?? []).map((runway) => runway.name);
}
