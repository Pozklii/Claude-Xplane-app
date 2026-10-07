// A SimBrief flight plan (OFP), as imported on the Flight Plan page and
// kept with the confirmed flight, then the logged one (flights.plan), to
// compare planned against actual. Fetched by importSimbriefPlan.

export type SimbriefPlan = {
  source: "simbrief";
  /** ICAO codes. */
  origin: string;
  destination: string;
  /** e.g. "BAW", and the flight number, e.g. "123". */
  airlineIcao: string | null;
  flightNumber: string | null;
  /** ICAO type designator (e.g. "A20N") and SimBrief's name for it. */
  aircraftIcao: string | null;
  aircraftName: string | null;
  /** The ATC route string, e.g. "DET L6 DVR UL9 KONAN". */
  route: string | null;
  cruiseAltitudeFt: number | null;
  distanceNm: number | null;
  /** Ramp (block) fuel and planned burn, in fuelUnit. */
  fuelRamp: number | null;
  fuelBurn: number | null;
  fuelUnit: "kg" | "lb";
  /** Planned time en route (takeoff to landing) and block time. */
  eteMinutes: number | null;
  blockMinutes: number | null;
  /** Scheduled off-blocks time (ISO), if SimBrief has one. */
  scheduledOut: string | null;
};

const text = (value: unknown) =>
  typeof value === "string" && value.trim() ? value.trim() : null;

const number = (value: unknown) => {
  const n = typeof value === "number" ? value : Number(text(value));
  return Number.isFinite(n) ? n : null;
};

const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" ? (value as Record<string, unknown>) : {};

/** The plan from SimBrief's OFP JSON (xml.fetcher.php?json=1), or null if
 * it has no origin and destination. */
export function parseSimbriefOfp(json: unknown): SimbriefPlan | null {
  const ofp = record(json);
  const general = record(ofp.general);
  const origin = text(record(ofp.origin).icao_code)?.toUpperCase();
  const destination = text(record(ofp.destination).icao_code)?.toUpperCase();
  if (!origin || !destination) return null;
  const aircraft = record(ofp.aircraft);
  const fuel = record(ofp.fuel);
  const times = record(ofp.times);
  const units = text(record(ofp.params).units)?.toLowerCase() ?? "kgs";
  const minutes = (seconds: unknown) => {
    const n = number(seconds);
    return n === null ? null : Math.round(n / 60);
  };
  const scheduledOut = number(times.sched_out);
  return {
    source: "simbrief",
    origin,
    destination,
    airlineIcao: text(general.icao_airline)?.toUpperCase() ?? null,
    flightNumber: text(general.flight_number),
    aircraftIcao: text(aircraft.icaocode)?.toUpperCase() ?? null,
    aircraftName: text(aircraft.name),
    route: text(general.route)?.slice(0, 1000) ?? null,
    cruiseAltitudeFt: number(general.initial_altitude),
    distanceNm: number(general.route_distance) ?? number(general.air_distance),
    fuelRamp: number(fuel.plan_ramp),
    fuelBurn: number(fuel.enroute_burn),
    fuelUnit: units.startsWith("lb") ? "lb" : "kg",
    eteMinutes: minutes(times.est_time_enroute),
    blockMinutes: minutes(times.est_block),
    scheduledOut:
      scheduledOut && scheduledOut > 0
        ? new Date(scheduledOut * 1000).toISOString()
        : null,
  };
}

/** A stored plan read back (from the database or browser storage): the
 * same shape, or null if it isn't one. */
export function asSimbriefPlan(value: unknown): SimbriefPlan | null {
  const plan = record(value);
  return plan.source === "simbrief" &&
    typeof plan.origin === "string" &&
    typeof plan.destination === "string"
    ? (plan as SimbriefPlan)
    : null;
}

/** e.g. 35000 → "FL350"; 8000 → "8,000 ft". */
export function formatAltitude(feet: number) {
  return feet >= 18000
    ? `FL${String(Math.round(feet / 100)).padStart(3, "0")}`
    : `${Math.round(feet).toLocaleString("en-US")} ft`;
}
