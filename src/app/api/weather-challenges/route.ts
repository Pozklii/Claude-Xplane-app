import { findAirport } from "@/lib/airports";
import { runwayNames } from "@/lib/airport-details";
import {
  CHALLENGING_AIRPORTS,
  WEATHER_WATCHLIST,
  type WeatherChallengeEntry,
} from "@/lib/challenging-airports";
import { weatherChallenge } from "@/lib/metar";
import { fetchMetars } from "@/lib/metar-source";

const MAX_RESULTS = 6;

// GET /api/weather-challenges → the airports whose current weather makes
// for the most demanding arrivals right now, scored from their METARs and
// runway layouts.
export async function GET() {
  const stations = [
    ...new Set([
      ...CHALLENGING_AIRPORTS.map((airport) => airport.icao),
      ...WEATHER_WATCHLIST,
    ]),
  ];

  let metars;
  try {
    metars = await fetchMetars(stations);
  } catch {
    return Response.json(
      { error: "The weather service is unavailable right now." },
      { status: 502 },
    );
  }

  const entries: WeatherChallengeEntry[] = [];
  for (const metar of Object.values(metars)) {
    const airport = findAirport(metar.station);
    if (!airport) continue;
    const { score, reasons } = weatherChallenge(
      metar,
      runwayNames(metar.station),
    );
    if (score < 2) continue;
    entries.push({
      icao: metar.station,
      name: airport.name,
      city: airport.city,
      country: airport.country,
      score,
      reasons,
      raw: metar.raw,
      category: metar.category,
    });
  }

  entries.sort((a, b) => b.score - a.score);
  return Response.json({ entries: entries.slice(0, MAX_RESULTS) });
}
