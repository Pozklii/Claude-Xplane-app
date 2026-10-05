// The Flight Log's search, filters and sort (see log-filters.tsx), read
// from the page's address and applied to the user's flights on the server.

export const LOG_SORTS = [
  ["newest", "Newest first"],
  ["oldest", "Oldest first"],
  ["longest", "Longest first"],
  ["shortest", "Shortest first"],
  ["rating", "Highest rated"],
  ["landing", "Softest landing"],
] as const;
export type LogSort = (typeof LOG_SORTS)[number][0];

export type LogQuery = {
  q: string;
  aircraft: string;
  airline: string;
  airport: string;
  year: string;
  sort: LogSort;
};

export type LogFilterOptions = {
  aircraft: string[];
  airlines: string[];
  airports: string[];
  years: string[];
};

/** The parts of a logged flight the log's filters look at. */
type LogFlight = {
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
  rating: number | null;
  landing_rate_fpm: number | null;
};

const one = (value: string | string[] | undefined) =>
  (Array.isArray(value) ? value[0] : value)?.trim() ?? "";

export function parseLogQuery(
  params: Record<string, string | string[] | undefined>,
): LogQuery {
  const sort = one(params.sort);
  return {
    q: one(params.q).slice(0, 100),
    aircraft: one(params.aircraft),
    airline: one(params.airline),
    airport: one(params.airport).toUpperCase(),
    year: /^\d{4}$/.test(one(params.year)) ? one(params.year) : "",
    sort: LOG_SORTS.some(([id]) => id === sort) ? (sort as LogSort) : "newest",
  };
}

const sorted = (values: Iterable<string>) =>
  [...new Set(values)].sort((a, b) => a.localeCompare(b));

/** The choices each filter offers: whatever appears in the log. */
export function logFilterOptions(flights: LogFlight[]): LogFilterOptions {
  return {
    aircraft: sorted(flights.map((f) => f.aircraft)),
    airlines: sorted(flights.flatMap((f) => (f.airline ? [f.airline] : []))),
    airports: sorted(flights.flatMap((f) => [f.departure, f.arrival])),
    years: sorted(flights.map((f) => f.flown_on.slice(0, 4))).reverse(),
  };
}

/** The flights matching a query, in its order. `places` gives any other
 * words a flight should be found by (its airports' cities and names). */
export function applyLogQuery<F extends LogFlight>(
  flights: F[],
  query: LogQuery,
  places: (flight: F) => string[] = () => [],
): F[] {
  const words = query.q.toLowerCase().split(/\s+/).filter(Boolean);
  const matching = flights.filter((flight) => {
    if (query.aircraft && flight.aircraft !== query.aircraft) return false;
    if (query.airline && flight.airline !== query.airline) return false;
    if (
      query.airport &&
      flight.departure !== query.airport &&
      flight.arrival !== query.airport
    ) {
      return false;
    }
    if (query.year && !flight.flown_on.startsWith(query.year)) return false;
    if (words.length === 0) return true;
    const haystack = [
      flight.departure,
      flight.arrival,
      flight.aircraft,
      flight.airline ?? "",
      flight.notes ?? "",
      ...places(flight),
    ]
      .join(" ")
      .toLowerCase();
    return words.every((word) => haystack.includes(word));
  });

  const byDate = (a: F, b: F) => b.flown_on.localeCompare(a.flown_on);
  const compare: Record<LogSort, (a: F, b: F) => number> = {
    newest: byDate,
    oldest: (a, b) => -byDate(a, b),
    longest: (a, b) => Number(b.hours) - Number(a.hours) || byDate(a, b),
    shortest: (a, b) => Number(a.hours) - Number(b.hours) || byDate(a, b),
    // Unrated (and, for landings, unrecorded) flights last.
    rating: (a, b) => (b.rating ?? -1) - (a.rating ?? -1) || byDate(a, b),
    landing: (a, b) =>
      (a.landing_rate_fpm ?? Infinity) - (b.landing_rate_fpm ?? Infinity) ||
      byDate(a, b),
  };
  return matching.sort(compare[query.sort]);
}
