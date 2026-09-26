import "server-only";
import { parseMetar, type Metar } from "./metar";

// NOAA's Aviation Weather Center data API: free, no key. Raw reports are
// decoded by ./metar rather than trusting a JSON schema that could drift.
const METAR_URL = "https://aviationweather.gov/api/data/metar";

/** Latest METAR per station, keyed by station ID. Cached for 5 minutes. */
export async function fetchMetars(stations: string[]) {
  const url = `${METAR_URL}?ids=${stations.map(encodeURIComponent).join(",")}&format=raw`;
  const res = await fetch(url, {
    headers: { "User-Agent": "FlightWorld/1.0 (flight logbook web app)" },
    next: { revalidate: 300 },
  });
  if (!res.ok) {
    throw new Error(`Aviation Weather Center returned ${res.status}`);
  }

  const metars: Record<string, Metar> = {};
  for (const line of (await res.text()).split("\n")) {
    const metar = line.trim() ? parseMetar(line) : null;
    // Newest first, so keep the first report seen for each station.
    if (metar && !metars[metar.station]) metars[metar.station] = metar;
  }
  return metars;
}
