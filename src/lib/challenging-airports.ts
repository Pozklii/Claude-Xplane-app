// Airports known for demanding arrivals — terrain, short or sloping
// runways, unusual approaches or notorious weather — each with a real
// scheduled (or typical private) route in to try it, drawn from the route
// table in ./example-flights/routes.ts.

export type ChallengeKind = "Terrain" | "Runway" | "Approach" | "Weather";

export type ChallengingAirport = {
  /** ICAO code, for METARs. */
  icao: string;
  /** IATA code, matching the route table. */
  iata: string;
  kinds: ChallengeKind[];
  /** 1 (tricky) to 5 (among the hardest anywhere). */
  difficulty: 1 | 2 | 3 | 4 | 5;
  why: string;
  route: { from: string; airline: string | null; aircraft: string };
};

export const CHALLENGING_AIRPORTS: ChallengingAirport[] = [
  {
    icao: "VNLK",
    iata: "LUA",
    kinds: ["Terrain", "Runway"],
    difficulty: 5,
    why: "A short runway on a steep upslope high in the Himalaya, with a mountainside at one end and a drop into the valley at the other — once committed there is no go-around.",
    route: { from: "KTM", airline: "Tara Air", aircraft: "DHC-6 Twin Otter" },
  },
  {
    icao: "VQPR",
    iata: "PBH",
    kinds: ["Terrain", "Approach"],
    difficulty: 5,
    why: "A visual approach winding through a narrow valley between Himalayan ridges, flown only in daylight and only by a small number of specially certified pilots.",
    route: { from: "KTM", airline: "Drukair", aircraft: "Airbus A319" },
  },
  {
    icao: "TNCS",
    iata: "SAB",
    kinds: ["Runway"],
    difficulty: 5,
    why: "One of the shortest commercial runways in the world, on a cliff-edged plateau with the sea at both ends.",
    route: { from: "SXM", airline: "Winair", aircraft: "DHC-6 Twin Otter" },
  },
  {
    icao: "LFLJ",
    iata: "CVF",
    kinds: ["Runway", "Terrain"],
    difficulty: 5,
    why: "An Alpine altiport runway with a gradient of around 18% — land uphill, take off downhill, no go-around — requiring a special site qualification.",
    route: { from: "GVA", airline: null, aircraft: "Pilatus PC-12" },
  },
  {
    icao: "TFFJ",
    iata: "SBH",
    kinds: ["Approach", "Runway"],
    difficulty: 4,
    why: "A steep descent over a hilltop road straight onto a short runway that ends at a beach; pilots need a local qualification.",
    route: { from: "SXM", airline: "Winair", aircraft: "DHC-6 Twin Otter" },
  },
  {
    icao: "LPMA",
    iata: "FNC",
    kinds: ["Weather", "Terrain"],
    difficulty: 4,
    why: "A runway extended out over the sea on columns along the cliffs, with gusts and wind shear rolling off the mountains; crews need specific training.",
    route: {
      from: "LIS",
      airline: "TAP Air Portugal",
      aircraft: "Airbus A320neo",
    },
  },
  {
    icao: "LXGB",
    iata: "GIB",
    kinds: ["Weather", "Approach"],
    difficulty: 4,
    why: "A short runway on a narrow isthmus beside the Rock, which throws off turbulence and wind shear when the easterly Levanter blows.",
    route: { from: "LHR", airline: "British Airways", aircraft: "Airbus A320" },
  },
  {
    icao: "NZQN",
    iata: "ZQN",
    kinds: ["Terrain", "Approach"],
    difficulty: 4,
    why: "Approaches thread the Southern Alps' valleys, typically on RNP procedures, with mountains close on every side and strong, gusty winds.",
    route: {
      from: "AKL",
      airline: "Air New Zealand",
      aircraft: "Airbus A320neo",
    },
  },
  {
    icao: "LOWI",
    iata: "INN",
    kinds: ["Terrain", "Weather"],
    difficulty: 4,
    why: "A narrow Alpine valley with high peaks either side, offset approaches, and foehn winds that bring severe turbulence.",
    route: { from: "LGW", airline: "easyJet", aircraft: "Airbus A320" },
  },
  {
    icao: "KASE",
    iata: "ASE",
    kinds: ["Terrain", "Runway"],
    difficulty: 4,
    why: "A high-elevation mountain valley with rising terrain, effectively one-way operations and demanding climb performance on departure.",
    route: {
      from: "DEN",
      airline: "United Airlines",
      aircraft: "Bombardier CRJ-700",
    },
  },
  {
    icao: "EKVG",
    iata: "FAE",
    kinds: ["Weather", "Terrain"],
    difficulty: 4,
    why: "A short runway between fjords and mountains in the North Atlantic, with frequent fog, low cloud and turbulent crosswinds.",
    route: {
      from: "CPH",
      airline: "Atlantic Airways",
      aircraft: "Airbus A320neo",
    },
  },
  {
    icao: "EGPR",
    iata: "BRR",
    kinds: ["Runway"],
    difficulty: 4,
    why: "Scheduled flights land on a tidal beach — the runways are under the sea at high tide, so the timetable follows the tides.",
    route: { from: "GLA", airline: "Loganair", aircraft: "DHC-6 Twin Otter" },
  },
  {
    icao: "VNKT",
    iata: "KTM",
    kinds: ["Terrain", "Weather"],
    difficulty: 3,
    why: "A bowl surrounded by high terrain, with steep approach paths, busy traffic and frequent haze and afternoon cloud.",
    route: { from: "PBH", airline: "Drukair", aircraft: "Airbus A319" },
  },
  {
    icao: "SPZO",
    iata: "CUZ",
    kinds: ["Terrain"],
    difficulty: 3,
    why: "Over 10,000 ft up in an Andean valley: thin air, terrain on all sides and afternoon winds that push most flights to the morning.",
    route: { from: "LIM", airline: "LATAM", aircraft: "Airbus A319" },
  },
  {
    icao: "PAJN",
    iata: "JNU",
    kinds: ["Terrain", "Weather"],
    difficulty: 3,
    why: "Approaches along a mountain-lined channel, flown on RNP procedures through frequent low cloud, rain and turbulence.",
    route: {
      from: "SEA",
      airline: "Alaska Airlines",
      aircraft: "Boeing 737-800",
    },
  },
  {
    icao: "ENSB",
    iata: "LYR",
    kinds: ["Weather"],
    difficulty: 3,
    why: "The northernmost airport with scheduled flights: polar night, icy runways and strong crosswinds.",
    route: { from: "OSL", airline: "Norwegian", aircraft: "Boeing 737-800" },
  },
  {
    icao: "EGLC",
    iata: "LCY",
    kinds: ["Approach", "Runway"],
    difficulty: 3,
    why: "A steep 5.5° glidepath between Docklands towers onto a short runway; aircraft need special certification to operate here.",
    route: { from: "ZRH", airline: "Swiss", aircraft: "Airbus A220-100" },
  },
  {
    icao: "SBRJ",
    iata: "SDU",
    kinds: ["Runway", "Approach"],
    difficulty: 3,
    why: "A short runway on the edge of Guanabara Bay beside Sugarloaf Mountain, with water at both ends.",
    route: { from: "CGH", airline: "GOL", aircraft: "Boeing 737-800" },
  },
  {
    icao: "LGSK",
    iata: "JSI",
    kinds: ["Runway", "Approach"],
    difficulty: 3,
    why: "A short island runway with a very low final approach over a beach road, and a hill beyond the far end.",
    route: { from: "LGW", airline: "easyJet", aircraft: "Airbus A320" },
  },
];

/** One row of the live "challenging right now" list. */
export type WeatherChallengeEntry = {
  icao: string;
  name: string;
  city: string;
  country: string | null;
  score: number;
  reasons: string[];
  raw: string;
  category: string | null;
};

// Big airports worldwide that often see rough weather, checked alongside
// the challenging airports above for the live "challenging right now" list.
export const WEATHER_WATCHLIST = [
  "EGLL",
  "EGKK",
  "EGPH",
  "EGAA",
  "EHAM",
  "EDDF",
  "LFPG",
  "LEMD",
  "LIRF",
  "LSZH",
  "LOWW",
  "EKCH",
  "ENGM",
  "ENBR",
  "BIKF",
  "KJFK",
  "KBOS",
  "KORD",
  "KDEN",
  "KSFO",
  "KSEA",
  "KATL",
  "KDFW",
  "CYYZ",
  "CYVR",
  "CYYT",
  "PANC",
  "PHNL",
  "MMMX",
  "SBGR",
  "SCEL",
  "SAEZ",
  "FAOR",
  "FACT",
  "OMDB",
  "VIDP",
  "VHHH",
  "RJTT",
  "RKSI",
  "WSSS",
  "YSSY",
  "YMML",
  "NZAA",
  "NZWN",
];
