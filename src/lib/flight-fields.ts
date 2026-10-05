// The optional extra details a logged flight can carry beyond its date,
// route, aircraft and hours (see supabase/migrations/
// 20261005_flight_details.sql): shared by the forms that log and edit
// flights, the server actions that save them and the pages that show them.
// (The migration's fuel columns are no longer used.)

export const CONDITIONS = [
  ["day", "Day"],
  ["night", "Night"],
  ["twilight", "Dawn / dusk"],
] as const;
export type Conditions = (typeof CONDITIONS)[number][0];

/** The weather to choose from (stored as the label). */
export const WEATHER_OPTIONS = [
  "Clear skies",
  "Few clouds",
  "Scattered clouds",
  "Overcast",
  "Low cloud (IMC)",
  "Fog or mist",
  "Light rain",
  "Heavy rain",
  "Thunderstorms",
  "Snow",
  "Freezing conditions",
  "Gusty winds",
  "Strong crosswind",
] as const;

export type FlightExtras = {
  /** "HH:MM" or "HH:MM:SS" (as Postgres returns a time). */
  takeoff_time: string | null;
  landing_time: string | null;
  /** Touchdown rate, in feet per minute (as a positive number). */
  landing_rate_fpm: number | null;
  conditions: Conditions | null;
  /** One of WEATHER_OPTIONS (or, on older entries, any text). */
  weather: string | null;
};

export const EXTRA_COLUMNS =
  "takeoff_time, landing_time, landing_rate_fpm, conditions, weather";

export const NO_EXTRAS: FlightExtras = {
  takeoff_time: null,
  landing_time: null,
  landing_rate_fpm: null,
  conditions: null,
  weather: null,
};

/** "14:05:00" → "14:05"; null stays null. */
export const shortTime = (time: string | null) => time?.slice(0, 5) ?? null;

/** Minutes after midnight for "HH:MM[:SS]", or null. */
export function timeMinutes(time: string | null) {
  const match = time?.match(/^(\d{2}):(\d{2})/);
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

/** Hours from takeoff to landing (past midnight if landing is earlier). */
export function airborneHours(takeoff: string | null, landing: string | null) {
  const a = timeMinutes(takeoff);
  const b = timeMinutes(landing);
  if (a === null || b === null) return null;
  const minutes = (b - a + 1440) % 1440;
  return minutes > 0 ? minutes / 60 : null;
}

export const conditionsLabel = (conditions: Conditions | null) =>
  CONDITIONS.find(([id]) => id === conditions)?.[1] ?? null;

/** Reads the extra details from a submitted form, or an error message. */
export function parseExtras(
  formData: FormData,
): { extras: FlightExtras } | { error: string } {
  const text = (name: string) => String(formData.get(name) ?? "").trim();
  const time = (name: string) => {
    const value = text(name);
    if (!value) return null;
    return /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(value)
      ? value
      : undefined;
  };
  const takeoff = time("takeoffTime");
  const landing = time("landingTime");
  if (takeoff === undefined || landing === undefined) {
    return { error: "Times must be 24-hour, like 14:05." };
  }

  const rateText = text("landingRate").replace(/^-/, "");
  const rate = rateText ? Number(rateText) : null;
  if (rate !== null && !(Number.isInteger(rate) && rate >= 0 && rate <= 5000)) {
    return { error: "Landing rate must be a whole number of fpm, 0–5000." };
  }

  const conditionsText = text("conditions");
  const conditions = CONDITIONS.some(([id]) => id === conditionsText)
    ? (conditionsText as Conditions)
    : null;

  const weather = text("weather").slice(0, 100);

  return {
    extras: {
      takeoff_time: takeoff,
      landing_time: landing,
      landing_rate_fpm: rate,
      conditions,
      weather: weather || null,
    },
  };
}
