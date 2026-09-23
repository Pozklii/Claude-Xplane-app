// Logbook-style notes for generated example flights. Each note is two
// sentences from two different phases of flight (in flight order), drawn
// from a pool of templates — each with its own key, so the generator can
// steer away from phrasings the flights already on screen have used.

type Rng = () => number;

export type NoteContext = {
  from: string;
  to: string;
  /** Cruise altitude, in hundreds of feet. */
  altitude: number;
  hours: number;
  /** The route reaches far enough north or south for aurora sightings. */
  highLatitude: boolean;
  /** Piston/turboprop types flying well below the jet flight levels. */
  lowAndSlow: boolean;
  /** An airline service, as opposed to a private/GA flight. */
  airliner: boolean;
  rng: Rng;
};

type Template = {
  key: string;
  when?: (c: NoteContext) => boolean;
  text: (c: NoteContext) => string;
};

const pick = <T>(items: readonly T[], rng: Rng) =>
  items[Math.floor(rng() * items.length)];
const int = (min: number, max: number, rng: Rng) =>
  Math.round(min + (max - min) * rng());
const flightLevel = (altitude: number) => `FL${Math.round(altitude / 10) * 10}`;
const feet = (altitude: number) =>
  `${(Math.round(altitude / 5) * 500).toLocaleString("en-US")} ft`;
const cruiseLevel = (c: NoteContext) =>
  c.lowAndSlow && c.altitude < 180 ? feet(c.altitude) : flightLevel(c.altitude);
const isLong = (c: NoteContext) => c.hours >= 5;
const isJet = (c: NoteContext) => !c.lowAndSlow;
const isAirlineJet = (c: NoteContext) => c.airliner && isJet(c);
const isPrivate = (c: NoteContext) => !c.airliner;

// Phases, in the order they're written when two are combined.
const PHASES: Template[][] = [
  // Ground and departure
  [
    {
      key: "push-late",
      when: (c) => c.airliner,
      text: (c) =>
        `Pushed back ${int(10, 40, c.rng)} minutes late out of ${c.from}.`,
    },
    {
      key: "long-taxi",
      text: (c) => `Long taxi out to the runway in ${c.from}.`,
    },
    {
      key: "deice",
      text: (c) => `De-icing in ${c.from} added ${int(15, 35, c.rng)} minutes.`,
    },
    { key: "on-time", text: (c) => `On-time departure from ${c.from}.` },
    {
      key: "heavy-takeoff",
      when: (c) => isLong(c) && isAirlineJet(c),
      text: (c) => `Heavy takeoff out of ${c.from}, using most of the runway.`,
    },
    {
      key: "crosswind-takeoff",
      text: (c) =>
        `Took off from ${c.from} with a ${int(12, 25, c.rng)} kt crosswind.`,
    },
    {
      key: "night-dep",
      text: (c) => `Night departure over the lights of ${c.from}.`,
    },
    {
      key: "dawn-dep",
      text: (c) => `Wheels up from ${c.from} just after sunrise.`,
    },
    {
      key: "preflight",
      when: isPrivate,
      text: (c) => `Thorough preflight and a quick fuel top-up in ${c.from}.`,
    },
  ],
  // Climb
  [
    {
      key: "bumpy-climb",
      text: () => "Bumpy climb through a layer of cumulus.",
    },
    {
      key: "direct-climb",
      when: isJet,
      text: (c) => `Cleared straight up to ${flightLevel(c.altitude)}.`,
    },
    {
      key: "shortcut",
      text: () => "ATC gave us a shortcut soon after departure.",
    },
    {
      key: "level-off",
      when: isJet,
      text: () => "Held low for crossing traffic before continuing the climb.",
    },
    {
      key: "vfr-climb",
      when: (c) => c.lowAndSlow,
      text: () => "Climbed out VFR under a broken cloud deck.",
    },
  ],
  // Cruise
  [
    {
      key: "wind",
      text: (c) =>
        `Cruised at ${cruiseLevel(c)} with a ${int(15, 130, c.rng)} kt ${pick(["headwind", "tailwind"], c.rng)}.`,
    },
    {
      key: "early",
      when: (c) => isJet(c) && c.hours >= 2,
      text: (c) =>
        `A strong tailwind put us ${int(10, Math.min(45, c.hours * 5), c.rng)} minutes ahead of schedule.`,
    },
    {
      key: "step-climb",
      when: (c) => isLong(c) && isJet(c),
      text: (c) =>
        `Step-climbed to ${flightLevel(c.altitude + 20)} as the fuel burned off.`,
    },
    {
      key: "oat",
      when: isJet,
      text: (c) =>
        `Outside air temperature dropped to −${int(48, 62, c.rng)}°C at ${flightLevel(c.altitude)}.`,
    },
    {
      key: "autopilot-off",
      text: () => "Hand-flew the whole cruise with the autopilot off.",
    },
    {
      key: "fuel",
      when: isLong,
      text: () => "Fuel burn came in a little under plan.",
    },
  ],
  // En route
  [
    { key: "storms", text: () => "Deviated around a line of thunderstorms." },
    {
      key: "chop",
      text: (c) =>
        `Light chop for about ${int(10, 40, c.rng)} minutes, then smooth.`,
    },
    { key: "moonlit", text: () => "Moonlit cloud tops most of the way." },
    {
      key: "views",
      text: (c) =>
        `Clear skies, with ${pick(["the coastline", "snow-capped mountains", "open ocean", "farmland", "a sea of cloud"], c.rng)} below.`,
    },
    {
      key: "aurora",
      when: (c) => c.highLatitude,
      text: () => "Aurora on the left side for a good half hour.",
    },
    { key: "smooth", text: () => "Smooth ride from start to finish." },
    {
      key: "sunrise",
      when: isLong,
      text: () => "Watched the sun come up over the horizon.",
    },
  ],
  // Approach
  [
    {
      key: "approach",
      text: (c) =>
        `${pick(["ILS", "RNAV", "RNP"], c.rng)} approach into ${c.to} ${pick(["through low cloud", "in light rain", "at dusk", "in clear skies"], c.rng)}.`,
    },
    {
      key: "vectors",
      text: (c) => `Vectored onto a long straight-in to ${c.to}.`,
    },
    {
      key: "hold",
      text: (c) =>
        `Held for ${int(8, 25, c.rng)} minutes before starting the approach into ${c.to}.`,
    },
    {
      key: "hand-flown",
      text: (c) =>
        `Hand-flew the last ${int(3, 10, c.rng)},000 ft into ${c.to}.`,
    },
    {
      key: "autoland",
      when: isAirlineJet,
      text: (c) =>
        `Autoland into ${c.to} in fog, with visibility under ${pick(["300", "400", "550"], c.rng)} m.`,
    },
    {
      key: "visual",
      text: (c) =>
        `Visual approach into ${c.to} with the city spread out below.`,
    },
    {
      key: "circling",
      text: (c) =>
        `Circling approach at ${c.to}, as the wind favoured the other runway.`,
    },
  ],
  // Landing and arrival
  [
    {
      key: "firm",
      text: (c) => `Firm landing in ${c.to} in a gusty crosswind.`,
    },
    { key: "greaser", text: (c) => `Greased the landing in ${c.to}.` },
    {
      key: "early-arrival",
      text: (c) =>
        `Arrived in ${c.to} ${int(5, Math.min(30, c.hours * 5 + 5), c.rng)} minutes early.`,
    },
    {
      key: "weather-arrival",
      text: (c) =>
        `Landed in ${c.to} to ${pick(["light rain", "sunshine and 24°C", "low cloud and drizzle", "a strong breeze", "a cold, clear evening"], c.rng)}.`,
    },
    {
      key: "go-around",
      text: (c) =>
        `Went around in ${c.to} for traffic on the runway and landed on the second try.`,
    },
    {
      key: "fbo",
      when: isPrivate,
      text: (c) => `Taxied straight to the FBO in ${c.to} and shut down.`,
    },
    {
      key: "remote-stand",
      when: isAirlineJet,
      text: (c) =>
        `Parked on a remote stand in ${c.to} and bussed to the terminal.`,
    },
  ],
];

const APPROACH = 4;
const LANDING = 5;

/**
 * Writes a note for one flight and returns it with the keys of the
 * templates it used. Templates listed in `avoidKeys` are skipped where
 * there's any alternative.
 */
export function writeNotes(
  c: NoteContext,
  avoidKeys: string[] = [],
): { text: string; keys: string[] } {
  // Two different phases, kept in flight order — but not approach and
  // landing together, which would both name the destination.
  const first = Math.floor(c.rng() * PHASES.length);
  let second = Math.floor(c.rng() * (PHASES.length - 1));
  if (second >= first) second++;
  if (
    Math.min(first, second) === APPROACH &&
    Math.max(first, second) === LANDING
  ) {
    second = Math.floor(c.rng() * APPROACH);
  }
  const phases = [first, second].sort((a, b) => a - b);

  const chosen = phases.map((phase) => {
    const eligible = PHASES[phase].filter((t) => !t.when || t.when(c));
    const fresh = eligible.filter((t) => !avoidKeys.includes(t.key));
    return pick(fresh.length > 0 ? fresh : eligible, c.rng);
  });

  return {
    text: chosen.map((t) => t.text(c)).join(" "),
    keys: chosen.map((t) => t.key),
  };
}
