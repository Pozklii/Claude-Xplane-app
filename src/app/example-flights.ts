import "server-only";
import { findAirport } from "@/lib/airports";
import { distanceNm } from "@/lib/geo";
import type { GlobeArc, GlobePoint } from "./flights/flight-globe";
import type { FlightDetails } from "./flights/selected-flight-card";

// Made-up logbook entries (real airports, fictional flights and airlines)
// that the landing page's globe cycles through. None of these cross the
// antimeridian: the selection camera fits a plain min/max bounding box,
// which would otherwise wrap the long way around the globe.
const EXAMPLE_FLIGHTS: {
  from: string;
  to: string;
  date: string;
  aircraft: string;
  airline: string | null;
  hours: number;
  notes: string;
}[] = [
  {
    from: "LHR",
    to: "JFK",
    date: "2026-08-14",
    aircraft: "Boeing 777-300ER",
    airline: "Northwind Airways",
    hours: 7.9,
    notes: "Westbound into a 120 kt jet stream on NAT track B at FL360.",
  },
  {
    from: "DXB",
    to: "SIN",
    date: "2026-08-02",
    aircraft: "Airbus A380-800",
    airline: "Meridian Air",
    hours: 6.9,
    notes: "Night departure, smooth ride across the Bay of Bengal.",
  },
  {
    from: "SFO",
    to: "HNL",
    date: "2026-07-21",
    aircraft: "Boeing 737 MAX 8",
    airline: "Bluecrest",
    hours: 5.6,
    notes: "ETOPS dispatch, steady trade winds landing on 8L.",
  },
  {
    from: "CDG",
    to: "NRT",
    date: "2026-07-09",
    aircraft: "Boeing 787-9",
    airline: "Altair Express",
    hours: 12.3,
    notes: "Great-circle over Siberia with aurora visible near 60°N.",
  },
  {
    from: "GRU",
    to: "LIS",
    date: "2026-06-28",
    aircraft: "Airbus A330-900",
    airline: "Solara",
    hours: 9.4,
    notes: "Crossed the ITCZ with some light chop around 5°N.",
  },
  {
    from: "SYD",
    to: "AKL",
    date: "2026-06-11",
    aircraft: "Airbus A321neo",
    airline: "Polaris Air",
    hours: 3.1,
    notes: "Gusty crosswind landing on runway 23L.",
  },
  {
    from: "ZRH",
    to: "INN",
    date: "2026-05-30",
    aircraft: "De Havilland Dash 8-400",
    airline: null,
    hours: 0.8,
    notes: "Visual approach down the Inn valley between the peaks.",
  },
  {
    from: "YVR",
    to: "ANC",
    date: "2026-05-17",
    aircraft: "Boeing 737-800",
    airline: "Northwind Airways",
    hours: 3.4,
    notes: "Clear skies up the coast with glaciers all the way.",
  },
  {
    from: "JNB",
    to: "CPT",
    date: "2026-04-25",
    aircraft: "Airbus A320neo",
    airline: "Meridian Air",
    hours: 2.1,
    notes: "Table Mountain in view on the final approach to 01.",
  },
];

// The airport dataset's city names can be long ("Paris (Roissy-en-France,
// Val-d'Oise)", "Honolulu, Oahu"); a short form reads better on the card.
const shortCity = (city: string) =>
  city.replace(/\s*\(.*\)$/, "").split(",")[0];

export function buildExampleShowcase() {
  const pointsByCode = new Map<string, GlobePoint>();
  const arcs: GlobeArc[] = [];
  const details: Record<string, FlightDetails> = {};

  EXAMPLE_FLIGHTS.forEach((flight, index) => {
    const from = findAirport(flight.from);
    const to = findAirport(flight.to);
    if (!from || !to) return;
    const id = `example-${index}`;

    for (const airport of [from, to]) {
      pointsByCode.set(airport.code, {
        code: airport.code,
        name: airport.name,
        city: shortCity(airport.city),
        lat: airport.lat,
        lng: airport.lon,
      });
    }
    arcs.push({
      id,
      startLat: from.lat,
      startLng: from.lon,
      endLat: to.lat,
      endLng: to.lon,
      fromCode: from.code,
      toCode: to.code,
      label: `${flight.aircraft} · ${from.code} → ${to.code} · ${flight.date}`,
    });
    details[id] = {
      date: flight.date,
      airline: flight.airline,
      aircraft: flight.aircraft,
      from: { code: from.code, city: shortCity(from.city) },
      to: { code: to.code, city: shortCity(to.city) },
      hours: flight.hours,
      distanceNm: distanceNm(from, to),
      notes: flight.notes,
      thumbnailUrl: null,
      customThumbnailPath: null,
      images: [],
    };
  });

  return { points: Array.from(pointsByCode.values()), arcs, details };
}
