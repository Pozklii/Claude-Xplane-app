import "server-only";
import { getAirportFacts, type AirportFacts } from "./airport-details";
import { CHALLENGING_AIRPORTS } from "./challenging-airports";

/** One "did you know?" fact about an airport or its country. */
export type Trivia = {
  /** What it's about, e.g. "London Heathrow Airport" or "United Kingdom". */
  subject: string;
  text: string;
  /** Country code, for a flag beside the fact. */
  country: string | null;
};

const M_PER_FT = 0.3048;
const ARCTIC_CIRCLE = 66.56;

const ft = (value: number) =>
  `${Math.round(value).toLocaleString("en-US")} ft (${Math.round(value * M_PER_FT).toLocaleString("en-US")} m)`;

const list = (items: string[]) =>
  items.length <= 1
    ? (items[0] ?? "")
    : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;

// Country names that read with "the": the United Kingdom, the Netherlands,
// the Faroe Islands, the Czech Republic...
const TAKES_THE =
  /^(United |Czech |Dominican |Central African )|(Islands|Republic|Emirates|Kingdom)$|^(Netherlands|Philippines|Bahamas|Maldives|Gambia|Seychelles|Comoros|Vatican City)$/;
const the = (name: string) => (TAKES_THE.test(name) ? `the ${name}` : name);
const capitalize = (text: string) => text[0].toUpperCase() + text.slice(1);

const currencyNames = new Intl.DisplayNames(["en"], { type: "currency" });
function currencyName(code: string) {
  try {
    return currencyNames.of(code) ?? code;
  } catch {
    return code;
  }
}

function airportTrivia(airport: AirportFacts): Trivia[] {
  const country = airport.country?.code ?? null;
  const about = (text: string): Trivia => ({
    subject: airport.name,
    text,
    country,
  });
  const facts: Trivia[] = [];
  const name = airport.name;

  const challenge = CHALLENGING_AIRPORTS.find(
    (entry) => entry.icao === airport.icao || entry.iata === airport.iata,
  );
  if (challenge) {
    const why = challenge.why[0].toLowerCase() + challenge.why.slice(1);
    facts.push(about(`${name} is famously challenging: ${why}`));
  }

  if (airport.elevationFt !== null) {
    if (airport.elevationFt < 0) {
      facts.push(
        about(`${name} lies ${ft(-airport.elevationFt)} below sea level.`),
      );
    } else if (airport.elevationFt >= 5000) {
      facts.push(
        about(
          `${name} sits ${ft(airport.elevationFt)} above sea level — high enough that thin air noticeably lengthens take-off rolls.`,
        ),
      );
    } else {
      facts.push(
        about(`${name} sits ${ft(airport.elevationFt)} above sea level.`),
      );
    }
  }

  // Helipads ("H1", "01H/19H") are listed as runways too; skip them.
  const runways = airport.runways.filter((runway) => !/H/.test(runway.name));
  const [longest, ...others] = runways;
  if (longest?.lengthFt) {
    facts.push(
      about(
        others.length === 0
          ? `${name} has a single runway, ${longest.name}, ${ft(longest.lengthFt)} long.`
          : `${name}'s longest runway, ${longest.name}, is ${ft(longest.lengthFt)} long.`,
      ),
    );
  }
  if (others.length >= 2) {
    facts.push(about(`${name} has ${runways.length} runways.`));
  }
  const unpaved = runways.find(
    (runway) =>
      runway.surfaceLabel &&
      !["Asphalt", "Concrete"].includes(runway.surfaceLabel),
  );
  if (unpaved) {
    facts.push(
      about(
        `Runway ${unpaved.name} at ${name} is ${unpaved.surfaceLabel!.toLowerCase()}, not asphalt or concrete.`,
      ),
    );
  }

  if (airport.icao && airport.iata) {
    facts.push(
      about(
        `${name} goes by ${airport.icao} to pilots and air traffic control (its ICAO code), and ${airport.iata} on tickets and baggage tags (its IATA code).`,
      ),
    );
  }
  if (!airport.scheduledService) {
    facts.push(about(`${name} has no scheduled airline service.`));
  }
  if (Math.abs(airport.lat) >= ARCTIC_CIRCLE) {
    facts.push(
      about(
        `${name} is inside the ${airport.lat > 0 ? "Arctic" : "Antarctic"} Circle, so it sees midnight sun in summer and polar night in winter.`,
      ),
    );
  } else if (airport.lat < 0) {
    facts.push(about(`${name} is in the southern hemisphere.`));
  }
  return facts;
}

function countryTrivia(airport: AirportFacts): Trivia[] {
  const country = airport.country;
  if (!country) return [];
  const about = (text: string): Trivia => ({
    subject: country.name,
    text,
    country: country.code,
  });
  const facts: Trivia[] = [];
  const name = the(country.name);
  const Name = capitalize(name);

  if (country.capital) {
    const stop = country.capital.endsWith(".") ? "" : ".";
    facts.push(about(`The capital of ${name} is ${country.capital}${stop}`));
  }
  if (country.nativeName !== country.name) {
    facts.push(about(`Locally, ${name} is called ${country.nativeName}.`));
  }
  // Only the first listed currency: later ones are often units like the
  // Swiss "WIR Franc" or the US "next day" dollar.
  if (country.currencies.length > 0) {
    facts.push(
      about(`${Name} uses the ${currencyName(country.currencies[0])}.`),
    );
  }
  if (country.languages.length === 1) {
    facts.push(
      about(`The main language of ${name} is ${country.languages[0]}.`),
    );
  } else if (country.languages.length > 1) {
    facts.push(
      about(`Languages of ${name} include ${list(country.languages)}.`),
    );
  }
  if (country.callingCodes.length > 0) {
    facts.push(
      about(
        `To phone ${name} from abroad, dial ${list(country.callingCodes)}.`,
      ),
    );
  }
  if (airport.countryAirportCount > 1) {
    facts.push(
      about(
        `${Name} has ${airport.countryAirportCount.toLocaleString("en-US")} airports with an ICAO or IATA code.`,
      ),
    );
  }
  facts.push(about(`${Name} is in ${country.continent}.`));
  return facts;
}

/**
 * A pool of facts about the given airports and their countries (each
 * country once), for picking from at random.
 */
export function triviaFor(codes: string[]): Trivia[] {
  const facts: Trivia[] = [];
  const countriesDone = new Set<string>();
  for (const code of codes) {
    const airport = getAirportFacts(code);
    if (!airport) continue;
    facts.push(...airportTrivia(airport));
    const countryCode = airport.country?.code;
    if (countryCode && !countriesDone.has(countryCode)) {
      countriesDone.add(countryCode);
      facts.push(...countryTrivia(airport));
    }
  }
  return facts;
}
