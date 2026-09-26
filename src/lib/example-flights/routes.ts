// Source data for the landing page's generated example flights: real
// airlines on routes they're well known for, with aircraft types they
// typically fly there, plus a handful of private/general-aviation hops
// (no airline). The generator (./generate.ts) draws from this endlessly,
// randomizing direction, aircraft, date, notes and flight time, so the
// flights themselves are fictional even where the airline and route are
// real. Schedules and fleets change — this is illustrative, not a
// timetable.

export type AircraftClass =
  | "widebody"
  | "narrowbody"
  | "regional"
  | "turboprop"
  | "bizjet"
  | "piston";

// Typical cruise speed (knots true airspeed) and cruise altitude band, in
// hundreds of feet — used to estimate flight time and write notes.
export const AIRCRAFT_CLASSES: Record<
  AircraftClass,
  { cruiseKts: number; altitude: [number, number]; overheadHours: number }
> = {
  widebody: { cruiseKts: 488, altitude: [340, 410], overheadHours: 0.45 },
  narrowbody: { cruiseKts: 450, altitude: [320, 390], overheadHours: 0.4 },
  regional: { cruiseKts: 440, altitude: [300, 370], overheadHours: 0.35 },
  turboprop: { cruiseKts: 280, altitude: [180, 260], overheadHours: 0.3 },
  bizjet: { cruiseKts: 420, altitude: [390, 450], overheadHours: 0.3 },
  piston: { cruiseKts: 170, altitude: [60, 120], overheadHours: 0.2 },
};

export const AIRCRAFT: Record<string, AircraftClass> = {
  "Airbus A380-800": "widebody",
  "Airbus A350-900": "widebody",
  "Airbus A350-1000": "widebody",
  "Airbus A330-200": "widebody",
  "Airbus A330-300": "widebody",
  "Airbus A330-900": "widebody",
  "Boeing 747-8": "widebody",
  "Boeing 777-200ER": "widebody",
  "Boeing 777-300ER": "widebody",
  "Boeing 787-8": "widebody",
  "Boeing 787-9": "widebody",
  "Boeing 787-10": "widebody",
  "Boeing 757-200": "narrowbody",
  "Airbus A320": "narrowbody",
  "Airbus A320neo": "narrowbody",
  "Airbus A321": "narrowbody",
  "Airbus A321neo": "narrowbody",
  "Airbus A220-300": "narrowbody",
  "Boeing 717-200": "narrowbody",
  "Boeing 737-800": "narrowbody",
  "Boeing 737-900ER": "narrowbody",
  "Boeing 737 MAX 8": "narrowbody",
  "Boeing 737 MAX 9": "narrowbody",
  "Embraer E195": "regional",
  "Embraer E195-E2": "regional",
  "ATR 72-600": "turboprop",
  "Pilatus PC-12": "turboprop",
  "Cessna Citation CJ4": "bizjet",
  "Cirrus SR22": "piston",
};

export type ExampleRoute = {
  airline: string | null;
  /** IATA codes; the generator flies either direction. */
  between: [string, string];
  aircraft: (keyof typeof AIRCRAFT)[];
};

export const EXAMPLE_ROUTES: ExampleRoute[] = [
  // Europe
  {
    airline: "British Airways",
    between: ["LHR", "JFK"],
    aircraft: ["Boeing 777-300ER", "Airbus A350-1000", "Boeing 777-200ER"],
  },
  {
    airline: "British Airways",
    between: ["LHR", "SIN"],
    aircraft: ["Airbus A350-1000", "Boeing 777-300ER"],
  },
  {
    airline: "British Airways",
    between: ["LHR", "JNB"],
    aircraft: ["Airbus A350-1000"],
  },
  {
    airline: "British Airways",
    between: ["LHR", "BOS"],
    aircraft: ["Boeing 777-200ER", "Boeing 787-9"],
  },
  {
    airline: "British Airways",
    between: ["LHR", "EDI"],
    aircraft: ["Airbus A320neo", "Airbus A321neo"],
  },
  {
    airline: "British Airways",
    between: ["LHR", "LAX"],
    aircraft: ["Airbus A380-800"],
  },
  {
    airline: "Virgin Atlantic",
    between: ["LHR", "LAX"],
    aircraft: ["Airbus A350-1000", "Boeing 787-9"],
  },
  {
    airline: "Virgin Atlantic",
    between: ["LHR", "JFK"],
    aircraft: ["Airbus A330-900", "Airbus A350-1000"],
  },
  { airline: "Lufthansa", between: ["FRA", "JFK"], aircraft: ["Boeing 747-8"] },
  {
    airline: "Lufthansa",
    between: ["MUC", "LAX"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "Lufthansa",
    between: ["FRA", "SIN"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "Lufthansa",
    between: ["FRA", "BER"],
    aircraft: ["Airbus A320neo", "Airbus A321"],
  },
  {
    airline: "Air France",
    between: ["CDG", "JFK"],
    aircraft: ["Airbus A350-900", "Boeing 777-300ER"],
  },
  {
    airline: "Air France",
    between: ["CDG", "GRU"],
    aircraft: ["Boeing 777-300ER"],
  },
  {
    airline: "Air France",
    between: ["CDG", "HND"],
    aircraft: ["Boeing 777-300ER"],
  },
  {
    airline: "Air France",
    between: ["CDG", "NCE"],
    aircraft: ["Airbus A320", "Airbus A220-300"],
  },
  {
    airline: "KLM",
    between: ["AMS", "JFK"],
    aircraft: ["Boeing 777-200ER", "Boeing 787-10"],
  },
  { airline: "KLM", between: ["AMS", "ICN"], aircraft: ["Boeing 787-9"] },
  {
    airline: "KLM",
    between: ["AMS", "LHR"],
    aircraft: ["Embraer E195-E2", "Boeing 737-800"],
  },
  {
    airline: "Swiss",
    between: ["ZRH", "JFK"],
    aircraft: ["Airbus A330-300", "Boeing 777-300ER"],
  },
  {
    airline: "Austrian Airlines",
    between: ["VIE", "INN"],
    aircraft: ["Embraer E195"],
  },
  {
    airline: "Turkish Airlines",
    between: ["IST", "JFK"],
    aircraft: ["Boeing 777-300ER", "Airbus A350-900"],
  },
  {
    airline: "Turkish Airlines",
    between: ["IST", "LHR"],
    aircraft: ["Airbus A321neo", "Airbus A330-300"],
  },
  {
    airline: "TAP Air Portugal",
    between: ["LIS", "GRU"],
    aircraft: ["Airbus A330-900"],
  },
  { airline: "Iberia", between: ["MAD", "EZE"], aircraft: ["Airbus A350-900"] },
  {
    airline: "Aer Lingus",
    between: ["DUB", "JFK"],
    aircraft: ["Airbus A330-300", "Airbus A321neo"],
  },
  {
    airline: "Icelandair",
    between: ["KEF", "JFK"],
    aircraft: ["Boeing 757-200", "Boeing 737 MAX 8"],
  },
  {
    airline: "Finnair",
    between: ["HEL", "HND"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "SAS",
    between: ["CPH", "EWR"],
    aircraft: ["Airbus A330-300", "Airbus A350-900"],
  },
  { airline: "easyJet", between: ["LGW", "GVA"], aircraft: ["Airbus A320neo"] },
  { airline: "Ryanair", between: ["STN", "DUB"], aircraft: ["Boeing 737-800"] },

  // Middle East, Asia, Oceania
  {
    airline: "Emirates",
    between: ["DXB", "LHR"],
    aircraft: ["Airbus A380-800"],
  },
  {
    airline: "Emirates",
    between: ["DXB", "SYD"],
    aircraft: ["Airbus A380-800"],
  },
  {
    airline: "Emirates",
    between: ["DXB", "JFK"],
    aircraft: ["Airbus A380-800", "Boeing 777-300ER"],
  },
  {
    airline: "Qatar Airways",
    between: ["DOH", "LHR"],
    aircraft: ["Airbus A380-800", "Boeing 777-300ER", "Airbus A350-1000"],
  },
  {
    airline: "Qatar Airways",
    between: ["DOH", "MEL"],
    aircraft: ["Airbus A350-1000"],
  },
  {
    airline: "Etihad Airways",
    between: ["AUH", "LHR"],
    aircraft: ["Boeing 787-10", "Airbus A350-1000"],
  },
  {
    airline: "Singapore Airlines",
    between: ["SIN", "SYD"],
    aircraft: ["Airbus A380-800", "Airbus A350-900"],
  },
  {
    airline: "Singapore Airlines",
    between: ["SIN", "LHR"],
    aircraft: ["Airbus A380-800", "Boeing 777-300ER"],
  },
  {
    airline: "Singapore Airlines",
    between: ["SIN", "HND"],
    aircraft: ["Boeing 787-10", "Boeing 777-300ER"],
  },
  {
    airline: "Cathay Pacific",
    between: ["HKG", "LHR"],
    aircraft: ["Airbus A350-1000", "Boeing 777-300ER"],
  },
  {
    airline: "Cathay Pacific",
    between: ["HKG", "SYD"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "Japan Airlines",
    between: ["HND", "CTS"],
    aircraft: ["Airbus A350-900"],
  },
  { airline: "ANA", between: ["HND", "SIN"], aircraft: ["Boeing 787-9"] },
  {
    airline: "Korean Air",
    between: ["ICN", "CDG"],
    aircraft: ["Boeing 777-300ER"],
  },
  {
    airline: "Thai Airways",
    between: ["BKK", "LHR"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "Air India",
    between: ["DEL", "LHR"],
    aircraft: ["Boeing 787-8", "Boeing 777-300ER"],
  },
  {
    airline: "IndiGo",
    between: ["DEL", "BOM"],
    aircraft: ["Airbus A320neo", "Airbus A321neo"],
  },
  { airline: "Qantas", between: ["PER", "LHR"], aircraft: ["Boeing 787-9"] },
  { airline: "Qantas", between: ["SYD", "MEL"], aircraft: ["Boeing 737-800"] },
  {
    airline: "Qantas",
    between: ["SYD", "PER"],
    aircraft: ["Airbus A330-200", "Boeing 737-800"],
  },
  {
    airline: "Qantas",
    between: ["SYD", "SIN"],
    aircraft: ["Airbus A380-800", "Airbus A330-300"],
  },
  {
    airline: "Virgin Australia",
    between: ["BNE", "SYD"],
    aircraft: ["Boeing 737-800"],
  },
  {
    airline: "Air New Zealand",
    between: ["AKL", "SYD"],
    aircraft: ["Boeing 787-9", "Airbus A321neo"],
  },
  {
    airline: "Air New Zealand",
    between: ["AKL", "CHC"],
    aircraft: ["Airbus A320neo", "ATR 72-600"],
  },

  // Africa
  {
    airline: "Ethiopian Airlines",
    between: ["ADD", "IAD"],
    aircraft: ["Boeing 787-9", "Airbus A350-900"],
  },
  {
    airline: "Kenya Airways",
    between: ["NBO", "LHR"],
    aircraft: ["Boeing 787-8"],
  },
  {
    airline: "South African Airways",
    between: ["JNB", "CPT"],
    aircraft: ["Airbus A320"],
  },
  {
    airline: "Emirates",
    between: ["DXB", "JNB"],
    aircraft: ["Airbus A380-800"],
  },

  // Americas
  {
    airline: "American Airlines",
    between: ["JFK", "LAX"],
    aircraft: ["Airbus A321"],
  },
  {
    airline: "American Airlines",
    between: ["DFW", "LHR"],
    aircraft: ["Boeing 777-300ER"],
  },
  {
    airline: "American Airlines",
    between: ["MIA", "GRU"],
    aircraft: ["Boeing 777-200ER", "Boeing 787-9"],
  },
  {
    airline: "Delta Air Lines",
    between: ["ATL", "CDG"],
    aircraft: ["Airbus A350-900", "Airbus A330-900"],
  },
  {
    airline: "Delta Air Lines",
    between: ["ATL", "JNB"],
    aircraft: ["Airbus A350-900"],
  },
  {
    airline: "Delta Air Lines",
    between: ["MSP", "AMS"],
    aircraft: ["Airbus A330-300", "Airbus A330-900"],
  },
  {
    airline: "Delta Air Lines",
    between: ["ATL", "LAX"],
    aircraft: ["Boeing 737-900ER", "Airbus A321neo"],
  },
  {
    airline: "United Airlines",
    between: ["SFO", "HNL"],
    aircraft: ["Boeing 777-200ER", "Boeing 737 MAX 9"],
  },
  {
    airline: "United Airlines",
    between: ["EWR", "FRA"],
    aircraft: ["Boeing 787-10", "Boeing 777-200ER"],
  },
  {
    airline: "United Airlines",
    between: ["IAH", "LHR"],
    aircraft: ["Boeing 787-10"],
  },
  {
    airline: "United Airlines",
    between: ["ORD", "DEN"],
    aircraft: ["Boeing 737 MAX 9", "Airbus A321neo"],
  },
  {
    airline: "United Airlines",
    between: ["SFO", "EWR"],
    aircraft: ["Boeing 777-200ER", "Boeing 737 MAX 9"],
  },
  {
    airline: "Southwest Airlines",
    between: ["LAS", "DEN"],
    aircraft: ["Boeing 737-800", "Boeing 737 MAX 8"],
  },
  {
    airline: "Alaska Airlines",
    between: ["SEA", "ANC"],
    aircraft: ["Boeing 737-900ER", "Boeing 737-800"],
  },
  {
    airline: "Hawaiian Airlines",
    between: ["HNL", "OGG"],
    aircraft: ["Boeing 717-200"],
  },
  {
    airline: "Hawaiian Airlines",
    between: ["HNL", "LAX"],
    aircraft: ["Airbus A330-200", "Airbus A321neo"],
  },
  {
    airline: "Air Canada",
    between: ["YYZ", "LHR"],
    aircraft: ["Boeing 787-9", "Boeing 777-300ER"],
  },
  {
    airline: "Air Canada",
    between: ["YVR", "YYZ"],
    aircraft: ["Boeing 737 MAX 8", "Airbus A220-300", "Boeing 787-9"],
  },
  {
    airline: "Air Canada",
    between: ["YUL", "CDG"],
    aircraft: ["Airbus A330-300", "Boeing 787-9"],
  },
  { airline: "WestJet", between: ["YYC", "YVR"], aircraft: ["Boeing 737-800"] },
  {
    airline: "Aeromexico",
    between: ["MEX", "CDG"],
    aircraft: ["Boeing 787-9"],
  },
  {
    airline: "Aeromexico",
    between: ["MEX", "JFK"],
    aircraft: ["Boeing 737 MAX 8", "Boeing 787-8"],
  },
  {
    airline: "Copa Airlines",
    between: ["PTY", "MIA"],
    aircraft: ["Boeing 737 MAX 9"],
  },
  { airline: "Avianca", between: ["BOG", "MAD"], aircraft: ["Boeing 787-8"] },
  {
    airline: "LATAM",
    between: ["GRU", "SCL"],
    aircraft: ["Airbus A320neo", "Boeing 787-9"],
  },

  // Private and general aviation
  { airline: null, between: ["ZRH", "INN"], aircraft: ["Pilatus PC-12"] },
  { airline: null, between: ["TEB", "PBI"], aircraft: ["Cessna Citation CJ4"] },
  { airline: null, between: ["DEN", "ASE"], aircraft: ["Pilatus PC-12"] },
  { airline: null, between: ["PAO", "MRY"], aircraft: ["Cirrus SR22"] },
];
