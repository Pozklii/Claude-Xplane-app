import data from "./data/airlines.json";

export type Airline = {
  name: string;
  alias?: string;
  iata: string;
  icao?: string;
  country?: string;
};

const airlines = data as Airline[];

// Words that vary between how people write an airline's name and how the
// OpenFlights dataset does ("Virgin Atlantic" vs "Virgin Atlantic Airways").
const FILLER_WORDS = new Set([
  "airline",
  "airlines",
  "airways",
  "international",
  "company",
  "limited",
  "ltd",
  "inc",
  "sa",
  "ag",
  "group",
  "system",
]);

function normalize(name: string) {
  const words = name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/air lines/g, "airlines")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(" ");
  return words.filter((word) => !FILLER_WORDS.has(word)).join(" ");
}

// Brand names that don't line up with the dataset's entry for the carrier
// (or carriers missing from it), keyed by normalized name → IATA code.
const BRAND_ALIASES: Record<string, string> = {
  klm: "KL",
  "klm royal dutch": "KL",
  sas: "SK",
  scandinavian: "SK",
  latam: "LA",
  tap: "TP",
  "tap air portugal": "TP",
  vueling: "VY",
  loganair: "LM",
  ita: "AZ",
  alitalia: "AZ",
  aeromexico: "AM",
  swiss: "LX",
  avianca: "AV",
  indigo: "6E",
  gol: "G3",
  jet2: "LS",
  "jet2 com": "LS",
  envoy: "MQ",
  "american eagle": "MQ",
  "united express": "UA",
  "delta connection": "DL",
  "air canada express": "QK",
  jazz: "QK",
  winair: "WM",
  drukair: "KB",
  "druk air": "KB",
  "tui airways": "BY",
  tui: "BY",
  airbaltic: "BT",
  "air baltic": "BT",
  norwegian: "DY",
  "ba cityflyer": "BA",
  "british cityflyer": "BA",
  "klm cityhopper": "KL",
  thy: "TK",
  ana: "NH",
  jal: "JL",
};

const byIata = new Map<string, Airline>();
const byIcao = new Map<string, Airline>();
const byName = new Map<string, Airline>();
for (const airline of airlines) {
  byIata.set(airline.iata, airline);
  if (airline.icao) byIcao.set(airline.icao, airline);
  for (const name of [airline.name, airline.alias]) {
    const key = name && normalize(name);
    if (key && !byName.has(key)) byName.set(key, airline);
  }
}

/**
 * Best-effort match from a free-text airline name (or its IATA/ICAO code)
 * to an airline and its codes, for showing its logo. Returns null rather
 * than guessing when the name is ambiguous, since a wrong logo is worse
 * than none.
 */
export function findAirline(input: string | null | undefined): Airline | null {
  const raw = input?.trim();
  if (!raw) return null;

  const upper = raw.toUpperCase();
  if (/^[A-Z0-9]{2}$/.test(upper) && byIata.has(upper)) {
    return byIata.get(upper)!;
  }
  if (/^[A-Z]{3}$/.test(upper) && byIcao.has(upper)) {
    return byIcao.get(upper)!;
  }

  const key = normalize(raw);
  if (!key) return null;
  // The dataset's own entry for an alias's code can be a defunct carrier
  // that once held it, so only the code is taken from the alias.
  const alias = BRAND_ALIASES[key];
  if (alias) return { name: raw, iata: alias };
  const exact = byName.get(key);
  if (exact) return exact;

  // "Lufthansa German" → "Lufthansa": a unique dataset name that the input
  // starts with (or that starts with the input), on a word boundary.
  if (key.length < 4) return null;
  const candidates = new Set<Airline>();
  for (const [name, airline] of byName) {
    if (key.startsWith(`${name} `) || name.startsWith(`${key} `)) {
      candidates.add(airline);
    }
  }
  return candidates.size === 1 ? [...candidates][0] : null;
}
