import { AIRCRAFT, AIRCRAFT_CLASSES } from "./example-flights/routes";

// ICAO type designators and common shorthand for each aircraft in the
// route table, so "B738", "737-800" and "Zibo 737-800" all find the same
// type. The trailing family entry ("737", "A320") matches any variant.
const ALIASES: Record<keyof typeof AIRCRAFT, string[]> = {
  "Airbus A380-800": ["A388", "A380"],
  "Airbus A350-900": ["A359", "A350-900", "A350"],
  "Airbus A350-1000": ["A35K", "A350-1000", "A350"],
  "Airbus A330-200": ["A332", "A330-200", "A330"],
  "Airbus A330-300": ["A333", "A330-300", "A330"],
  "Airbus A330-900": ["A339", "A330-900", "A330neo", "A330"],
  "Boeing 747-8": ["B748", "747-8", "747"],
  "Boeing 777-200ER": ["B772", "777-200ER", "777-200", "777"],
  "Boeing 777-300ER": ["B77W", "777-300ER", "777-300", "777"],
  "Boeing 787-8": ["B788", "787-8", "787"],
  "Boeing 787-9": ["B789", "787-9", "787"],
  "Boeing 787-10": ["B78X", "787-10", "787"],
  "Boeing 757-200": ["B752", "757-200", "757"],
  "Airbus A319": ["A319"],
  "Airbus A320": ["A320"],
  "Airbus A320neo": ["A20N", "A320neo", "A320"],
  "Airbus A321": ["A321"],
  "Airbus A321neo": ["A21N", "A321neo", "A321"],
  "Airbus A220-100": ["BCS1", "A220-100", "CS100", "A220"],
  "Airbus A220-300": ["BCS3", "A220-300", "CS300", "A220"],
  "Boeing 717-200": ["B712", "717-200", "717"],
  "Boeing 737-700": ["B737", "737-700", "737"],
  "Boeing 737-800": ["B738", "737-800", "737"],
  "Boeing 737-900ER": ["B739", "737-900ER", "737-900", "737"],
  "Boeing 737 MAX 8": ["B38M", "737 MAX 8", "737 MAX", "737"],
  "Boeing 737 MAX 9": ["B39M", "737 MAX 9", "737 MAX", "737"],
  "Bombardier CRJ-700": ["CRJ7", "CRJ-700", "CRJ"],
  "Embraer E175": ["E175", "E170", "ERJ-175"],
  "Embraer E190": ["E190", "ERJ-190"],
  "Embraer E195": ["E195", "ERJ-195"],
  "Embraer E195-E2": ["E295", "E195-E2", "E195"],
  "ATR 72-600": ["AT76", "ATR 72-600", "ATR 72", "ATR"],
  "De Havilland Dash 8-400": ["DH8D", "Dash 8-400", "Q400", "Dash 8"],
  "DHC-6 Twin Otter": ["DHC6", "Twin Otter", "DHC-6"],
  "Pilatus PC-12": ["PC12", "PC-12"],
  "Cessna Citation CJ4": ["C25C", "CJ4", "Citation"],
  "Cirrus SR22": ["SR22"],
};

const MANUFACTURERS =
  /\b(airbus|boeing|embraer|bombardier|de havilland|dehavilland|cessna|cirrus|pilatus)\b/g;

const squash = (s: string) =>
  s
    .toLowerCase()
    .replace(MANUFACTURERS, "")
    .replace(/[^a-z0-9]/g, "");

type Term = { term: string; exact: boolean };

// Per aircraft: its exact terms (full model name, designator, model
// number) and its looser family terms (the last alias, e.g. "737").
const TERMS = Object.fromEntries(
  (Object.keys(ALIASES) as (keyof typeof AIRCRAFT)[]).map((name) => {
    const aliases = ALIASES[name];
    const family = aliases.length > 1 ? aliases[aliases.length - 1] : null;
    const terms: Term[] = [{ term: squash(name), exact: true }];
    for (const alias of aliases) {
      terms.push({ term: squash(alias), exact: alias !== family });
    }
    return [name, terms];
  }),
) as Record<keyof typeof AIRCRAFT, Term[]>;

export type AircraftMatch = {
  name: keyof typeof AIRCRAFT;
  /** True for the exact variant typed; false for the same family. */
  exact: boolean;
};

/**
 * Aircraft in the route table that a free-text type matches — exact
 * variants first, then the rest of the family. "B738" or "Zibo 737-800"
 * finds the 737-800 (then other 737s); "A320" finds the A320 and A320neo.
 */
export function matchAircraft(input: string | null | undefined) {
  const query = squash(input ?? "");
  if (query.length < 3) return [];

  // The typed text may carry extra words ("ToLiss A321") around a term, or
  // be a family prefix of one ("737"). The longest exact term found decides
  // which variant was meant, so "A320neo" doesn't also count as an exact
  // "A320".
  const scored: { name: keyof typeof AIRCRAFT; exactLength: number }[] = [];
  for (const [name, terms] of Object.entries(TERMS) as [
    keyof typeof AIRCRAFT,
    Term[],
  ][]) {
    let exactLength = 0;
    let family = false;
    for (const { term, exact } of terms) {
      if (term.length < 3) continue;
      if (query.includes(term)) {
        family = true;
        if (exact) exactLength = Math.max(exactLength, term.length);
      } else if (term.startsWith(query)) {
        family = true;
      }
    }
    if (family) scored.push({ name, exactLength });
  }

  const best = Math.max(0, ...scored.map((s) => s.exactLength));
  return scored
    .map(
      ({ name, exactLength }): AircraftMatch => ({
        name,
        exact: best > 0 && exactLength === best,
      }),
    )
    .sort((a, b) => Number(b.exact) - Number(a.exact));
}

/** Block time estimate: cruise time plus taxi/climb/descent, in hours. */
export function estimateHours(
  aircraft: keyof typeof AIRCRAFT,
  distanceNm: number,
) {
  const performance = AIRCRAFT_CLASSES[AIRCRAFT[aircraft]];
  return distanceNm / performance.cruiseKts + performance.overheadHours;
}

/** Every aircraft in the route table, for pickers. */
export const KNOWN_AIRCRAFT = Object.keys(
  AIRCRAFT,
) as (keyof typeof AIRCRAFT)[];
