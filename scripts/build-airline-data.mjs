// Builds src/lib/data/airlines.json — active airlines with their IATA and
// ICAO codes, used to match a logged airline name to its logo — from
// OpenFlights' airlines.dat (https://openflights.org/data, Open Database
// License; attribution in the README).
//
// Usage: node scripts/build-airline-data.mjs <path to airlines.dat>

import fs from "node:fs";
import path from "node:path";

const source = process.argv[2];
if (!source) {
  console.error("Usage: node scripts/build-airline-data.mjs <airlines.dat>");
  process.exit(1);
}

// airlines.dat is CSV with \N for nulls: id, name, alias, IATA, ICAO,
// callsign, country, active.
function parseLine(line) {
  const out = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") {
      out.push(field);
      field = "";
    } else field += c;
  }
  out.push(field);
  return out.map((v) => (v === "\\N" ? "" : v.trim()));
}

const airlines = [];
const seenIata = new Set();
for (const line of fs.readFileSync(source, "utf8").split(/\r?\n/)) {
  if (!line) continue;
  const [, name, alias, iata, icao, , country, active] = parseLine(line);
  if (active !== "Y" || !/^[A-Z0-9]{2}$/.test(iata) || seenIata.has(iata)) {
    continue;
  }
  seenIata.add(iata);
  airlines.push({
    name,
    ...(alias && alias !== name ? { alias } : {}),
    iata,
    ...(/^[A-Z]{3}$/.test(icao) ? { icao } : {}),
    ...(country ? { country } : {}),
  });
}

const out = path.join(
  import.meta.dirname,
  "..",
  "src",
  "lib",
  "data",
  "airlines.json",
);
fs.writeFileSync(out, JSON.stringify(airlines));
console.log(`${airlines.length} airlines`);
