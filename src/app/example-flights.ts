import "server-only";
import { findAirport } from "@/lib/airports";
import {
  EXAMPLE_HISTORY_SIZE,
  generateExampleFlight,
  usableRoutes,
  type ExampleAirport,
  type ExampleFlight,
} from "@/lib/example-flights/generate";
import { EXAMPLE_ROUTES } from "@/lib/example-flights/routes";

// The airport dataset's city names can be long ("Paris (Roissy-en-France,
// Val-d'Oise)", "Honolulu, Oahu"); a short form reads better on the card.
const shortCity = (city: string) =>
  city.replace(/\s*\(.*\)$/, "").split(",")[0];

// Resolves every airport the example route table uses from the bundled
// OurAirports lookup (so coordinates are never hand-entered), then seeds
// the landing globe with a first batch of generated flights. The client
// carries on generating from the same airports indefinitely.
export function buildExampleShowcase() {
  const airports: Record<string, ExampleAirport> = {};
  for (const route of EXAMPLE_ROUTES) {
    for (const code of route.between) {
      const airport = findAirport(code);
      if (airport) {
        airports[code] = {
          code: airport.code,
          city: shortCity(airport.city),
          lat: airport.lat,
          lon: airport.lon,
        };
      }
    }
  }

  const routes = usableRoutes(airports);
  const initial: ExampleFlight[] = [];
  for (let i = 0; i < EXAMPLE_HISTORY_SIZE; i++) {
    initial.push(
      generateExampleFlight({
        id: `example-${i}`,
        airports,
        routes,
        recentRouteKeys: initial.map((flight) => flight.routeKey),
        recentNoteKeys: initial.flatMap((flight) => flight.noteKeys),
        // Re-dated against the viewer's own today on the client (see
        // LandingShowcase) — this page is prerendered, so the server's
        // today is whenever it was built.
        today: new Date().toISOString().slice(0, 10),
      }),
    );
  }

  return { airports, initial };
}
