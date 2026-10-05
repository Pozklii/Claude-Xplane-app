import "server-only";
import { countries, type TCountryCode } from "countries-list";
import { findAirport } from "@/lib/airports";
import { CHALLENGING_AIRPORTS } from "@/lib/challenging-airports";
import { countryName } from "@/lib/countries";
import { distanceNm } from "@/lib/geo";

// The Flight Stats page's (and a shared flight map's) figures, charts and
// achievements, worked out from a user's logged flights.

/** What the stats need from each logged flight. */
export type StatsFlight = {
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  landing_rate_fpm?: number | null;
  conditions?: string | null;
};

export type Achievement = {
  id: string;
  title: string;
  description: string;
  earned: boolean;
  /** How far along an unearned one is, e.g. "4 of 6". */
  progress?: string;
};

// The six inhabited continents, by countries-list's codes.
const CONTINENTS: [string, string][] = [
  ["AF", "Africa"],
  ["AS", "Asia"],
  ["EU", "Europe"],
  ["NA", "North America"],
  ["SA", "South America"],
  ["OC", "Oceania"],
];
const LUKLA = new Set(["VNLK", "LUA"]);
// Earth's circumference at the equator, in nautical miles.
const AROUND_THE_WORLD_NM = 21_639;

const MONTHS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ");

function count<T>(values: T[]) {
  const counts = new Map<T, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return counts;
}

/** Every figure the stats pages show. `today` ("YYYY-MM-DD") ends the
 * months chart. */
export function flightStats(flights: StatsFlight[], today: string) {
  const resolved = flights.map((flight) => {
    const from = findAirport(flight.departure);
    const to = findAirport(flight.arrival);
    return {
      flight,
      from,
      to,
      nm: from && to ? distanceNm(from, to) : null,
    };
  });

  const totalHours = flights.reduce((sum, f) => sum + Number(f.hours), 0);
  const totalNm = resolved.reduce((sum, r) => sum + (r.nm ?? 0), 0);

  // Countries and continents touched, by either end of a flight.
  const countryCodes = new Set<string>();
  for (const { from, to } of resolved) {
    for (const airport of [from, to]) {
      if (airport?.country) countryCodes.add(airport.country);
    }
  }
  const continentCodes = new Set(
    [...countryCodes].flatMap((code) => {
      const continent = countries[code as TCountryCode]?.continent;
      return continent ? [continent] : [];
    }),
  );
  const continents = CONTINENTS.filter(([code]) =>
    (continentCodes as Set<string>).has(code),
  );

  // Hours per month, the last 12 months (this one included).
  const [year, month] = today.split("-").map(Number);
  const monthly = Array.from({ length: 12 }, (_, i) => {
    const date = new Date(Date.UTC(year, month - 12 + i, 1));
    const key = date.toISOString().slice(0, 7);
    return {
      key,
      label: MONTHS[date.getUTCMonth()],
      year: date.getUTCFullYear(),
      hours: 0,
      flights: 0,
    };
  });
  const byMonth = new Map(monthly.map((m) => [m.key, m]));
  for (const flight of flights) {
    const bucket = byMonth.get(flight.flown_on.slice(0, 7));
    if (bucket) {
      bucket.hours += Number(flight.hours);
      bucket.flights += 1;
    }
  }

  // Most-flown aircraft (by hours) and most-visited airports.
  const aircraft = new Map<string, { flights: number; hours: number }>();
  for (const flight of flights) {
    const entry = aircraft.get(flight.aircraft) ?? { flights: 0, hours: 0 };
    entry.flights += 1;
    entry.hours += Number(flight.hours);
    aircraft.set(flight.aircraft, entry);
  }
  const topAircraft = [...aircraft.entries()]
    .map(([name, entry]) => ({ name, ...entry }))
    .sort((a, b) => b.hours - a.hours || b.flights - a.flights)
    .slice(0, 5);
  const visits = count(
    resolved.flatMap(({ flight, from, to }) => [
      from?.code ?? flight.departure,
      to?.code ?? flight.arrival,
    ]),
  );
  const topAirports = [...visits.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([code, n]) => {
      const airport = findAirport(code);
      return {
        code,
        city: airport?.city ?? null,
        country: airport?.country ?? null,
        visits: n,
      };
    });

  // The longest flights, by distance and by time.
  const describe = (r: (typeof resolved)[number]) => ({
    date: r.flight.flown_on,
    from: r.from?.code ?? r.flight.departure,
    to: r.to?.code ?? r.flight.arrival,
    fromCity: r.from?.city ?? null,
    toCity: r.to?.city ?? null,
    aircraft: r.flight.aircraft,
    hours: Number(r.flight.hours),
    nm: r.nm,
  });
  const farthest = [...resolved]
    .filter((r) => r.nm !== null)
    .sort((a, b) => (b.nm ?? 0) - (a.nm ?? 0))[0];
  const longestTime = [...resolved].sort(
    (a, b) => Number(b.flight.hours) - Number(a.flight.hours),
  )[0];

  // Achievements.
  const challenging = new Set(
    resolved.flatMap(({ flight }) => {
      const code = flight.arrival.toUpperCase();
      const match = CHALLENGING_AIRPORTS.find(
        (airport) => airport.icao === code || airport.iata === code,
      );
      return match ? [match.icao] : [];
    }),
  );
  const bestType = topAircraft[0];
  const nightFlights = flights.filter((f) => f.conditions === "night").length;
  const twilightFlights = flights.filter(
    (f) => f.conditions === "twilight",
  ).length;
  const softest = Math.min(
    ...flights.flatMap((f) =>
      f.landing_rate_fpm != null ? [f.landing_rate_fpm] : [],
    ),
  );
  const longestNm = farthest?.nm ?? 0;
  const of = (have: number, need: number) =>
    `${Math.min(have, need).toLocaleString("en-US")} of ${need.toLocaleString("en-US")}`;
  const achievements: Achievement[] = [
    {
      id: "first",
      title: "First flight",
      description: "Log your first flight.",
      earned: flights.length >= 1,
    },
    {
      id: "ten",
      title: "Regular",
      description: "Log 10 flights.",
      earned: flights.length >= 10,
      progress: of(flights.length, 10),
    },
    {
      id: "fifty",
      title: "Frequent flyer",
      description: "Log 50 flights.",
      earned: flights.length >= 50,
      progress: of(flights.length, 50),
    },
    {
      id: "hundred",
      title: "Centurion",
      description: "Log 100 flights.",
      earned: flights.length >= 100,
      progress: of(flights.length, 100),
    },
    {
      id: "hundred-hours",
      title: "100 hours",
      description: "Fly 100 hours in all.",
      earned: totalHours >= 100,
      progress: `${Math.floor(Math.min(totalHours, 100))} of 100 h`,
    },
    {
      id: "hundred-in-type",
      title: "100 hours in type",
      description: "Fly 100 hours in one aircraft type.",
      earned: (bestType?.hours ?? 0) >= 100,
      progress: bestType
        ? `${Math.floor(Math.min(bestType.hours, 100))} of 100 h in the ${bestType.name}`
        : undefined,
    },
    {
      id: "continents",
      title: "All six continents",
      description:
        "Fly to or from Africa, Asia, Europe, North and South America, and Oceania.",
      earned: continents.length === 6,
      progress: of(continents.length, 6),
    },
    {
      id: "countries",
      title: "Globetrotter",
      description: "Fly to or from 10 countries.",
      earned: countryCodes.size >= 10,
      progress: of(countryCodes.size, 10),
    },
    {
      id: "lukla",
      title: "Lukla landed",
      description:
        "Land at Tenzing-Hillary, Lukla (VNLK): the steep, short runway high in the Himalaya.",
      earned: flights.some((f) => LUKLA.has(f.arrival.toUpperCase())),
    },
    {
      id: "challenging",
      title: "Daredevil",
      description: "Land at 5 of the famously challenging airports.",
      earned: challenging.size >= 5,
      progress: of(challenging.size, 5),
    },
    {
      id: "long-haul",
      title: "Long haul",
      description: "Fly a single flight of 5,000 nm or more.",
      earned: longestNm >= 5000,
      progress: `Longest so far ${Math.round(longestNm).toLocaleString("en-US")} nm`,
    },
    {
      id: "around-the-world",
      title: "Around the world",
      description: "Fly the Earth's circumference, 21,639 nm, in all.",
      earned: totalNm >= AROUND_THE_WORLD_NM,
      progress: of(Math.round(totalNm), AROUND_THE_WORLD_NM) + " nm",
    },
    {
      id: "night",
      title: "Night owl",
      description: "Log 5 flights flown at night.",
      earned: nightFlights >= 5,
      progress: of(nightFlights, 5),
    },
    {
      id: "twilight",
      title: "Dawn patrol",
      description: "Log a flight flown at dawn or dusk.",
      earned: twilightFlights >= 1,
    },
    {
      id: "butter",
      title: "Butter",
      description: "Touch down at 60 fpm or less.",
      earned: softest <= 60,
      progress: Number.isFinite(softest)
        ? `Softest so far ${softest} fpm`
        : "Log a landing rate to qualify",
    },
  ];

  return {
    totals: {
      flights: flights.length,
      hours: totalHours,
      nm: totalNm,
      countries: countryCodes.size,
      continents: continents.map(([, name]) => name),
    },
    countryNames: [...countryCodes]
      .map((code) => countryName(code) ?? code)
      .sort((a, b) => a.localeCompare(b)),
    monthly,
    topAircraft,
    topAirports,
    farthest: farthest ? describe(farthest) : null,
    longestTime: longestTime ? describe(longestTime) : null,
    achievements,
  };
}

export type FlightStats = ReturnType<typeof flightStats>;
