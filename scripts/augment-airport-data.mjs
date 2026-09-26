// Adds country and OurAirports ident to every entry in
// src/lib/data/airports.json (without changing its keys, names or
// coordinates, so existing flights keep resolving), and writes
// src/lib/data/airport-details.json: elevation, type, codes, Wikipedia
// link and runways per airport, keyed by ident.
//
// Usage: download OurAirports' airports.csv and runways.csv
// (https://github.com/davidmegginson/ourairports-data, public domain) into
// a directory, then run:
//   node scripts/augment-airport-data.mjs <that directory>

import fs from "node:fs";
import path from "node:path";

const sourceDir = process.argv[2];
if (!sourceDir) {
  console.error("Usage: node scripts/augment-airport-data.mjs <csv dir>");
  process.exit(1);
}

const dataDir = path.join(import.meta.dirname, "..", "src", "lib", "data");
const airportsPath = path.join(dataDir, "airports.json");
const detailsPath = path.join(dataDir, "airport-details.json");

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (c !== "\r") field += c;
  }
  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }
  const [header, ...rest] = rows;
  return rest.map((r) =>
    Object.fromEntries(header.map((key, i) => [key, r[i] ?? ""])),
  );
}

const read = (name) =>
  parseCsv(fs.readFileSync(path.join(sourceDir, name), "utf8"));

const airports = JSON.parse(fs.readFileSync(airportsPath, "utf8"));
const sourceAirports = read("airports.csv");
const runwayRows = read("runways.csv");

// Codes to OurAirports rows, most-specific field first, open airports
// preferred over closed ones.
const byCode = new Map();
const fields = ["icao_code", "iata_code", "ident", "gps_code", "local_code"];
for (const field of fields) {
  for (const closedPass of [false, true]) {
    for (const row of sourceAirports) {
      if ((row.type === "closed") !== closedPass) continue;
      const code = row[field].trim().toUpperCase();
      if (code && !byCode.has(code)) byCode.set(code, row);
    }
  }
}

function nearest(lat, lon) {
  let best = null;
  let bestDist = Infinity;
  for (const row of sourceAirports) {
    const d =
      (Number(row.latitude_deg) - lat) ** 2 +
      (Number(row.longitude_deg) - lon) ** 2;
    if (d < bestDist) {
      bestDist = d;
      best = row;
    }
  }
  // ~0.05° ≈ 5 km: close enough to be the same field.
  return bestDist < 0.05 ** 2 ? best : null;
}

const runwaysByIdent = new Map();
for (const runway of runwayRows) {
  if (runway.closed === "1") continue;
  const list = runwaysByIdent.get(runway.airport_ident) ?? [];
  const name = [runway.le_ident, runway.he_ident].filter(Boolean).join("/");
  list.push({
    name: name || "—",
    lengthFt: Number(runway.length_ft) || null,
    widthFt: Number(runway.width_ft) || null,
    surface: runway.surface || null,
    lighted: runway.lighted === "1",
  });
  runwaysByIdent.set(runway.airport_ident, list);
}

const details = {};
let unmatched = 0;
for (const [key, airport] of Object.entries(airports)) {
  const row = byCode.get(key) ?? nearest(airport.lat, airport.lon);
  if (!row) {
    unmatched++;
    continue;
  }
  airport.country = row.iso_country || null;
  airport.ident = row.ident;
  if (details[row.ident]) continue;
  details[row.ident] = {
    type: row.type,
    country: row.iso_country || null,
    elevationFt: row.elevation_ft === "" ? null : Number(row.elevation_ft),
    continent: row.continent || null,
    region: row.iso_region || null,
    icao: row.icao_code || row.gps_code || null,
    iata: row.iata_code || null,
    scheduledService: row.scheduled_service === "yes",
    wikipedia: row.wikipedia_link || null,
    runways: (runwaysByIdent.get(row.ident) ?? []).sort(
      (a, b) => (b.lengthFt ?? 0) - (a.lengthFt ?? 0),
    ),
  };
}

fs.writeFileSync(airportsPath, JSON.stringify(airports));
fs.writeFileSync(detailsPath, JSON.stringify(details));
console.log(
  `${Object.keys(airports).length} lookup keys, ${Object.keys(details).length} airports with details, ${unmatched} unmatched`,
);
