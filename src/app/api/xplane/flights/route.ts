import { createClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";
import { matchAircraft } from "@/lib/aircraft";
import { nearestAirport } from "@/lib/airports";
import { buildRecording } from "@/lib/recording";

// The X-Plane companion's endpoint (public/xplane-logger.mjs), with the
// user's connection token as a Bearer token (made on the Flight Log):
//   GET  → { ok: true } if the token is live (checked as it starts)
//   POST → logs a finished flight: { id, departure, arrival }
// The flight's airports are the ones nearest where it started and ended.

// No signed-in session here: the token is checked by the database
// functions, which run with their owner's rights.
function anonClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

function bearer(request: Request) {
  const match = request.headers
    .get("authorization")
    ?.match(/^Bearer\s+(fw_[A-Za-z0-9_-]{20,100})$/);
  return match?.[1] ?? null;
}

const fail = (status: number, error: string) =>
  Response.json({ error }, { status });

// PGRST202 (PostgREST) / 42883 (Postgres): no such function — the X-Plane
// and SimBrief migration not yet run.
const missingFunction = (code: string | undefined) =>
  code === "PGRST202" || code === "42883";
const NEEDS_MIGRATION =
  "Flight World's database needs the X-Plane update first (supabase/migrations/20261007_xplane_and_simbrief.sql).";
const BAD_TOKEN =
  "That connection token isn't recognised. Make a new one on the Flight Log page.";

export async function GET(request: Request) {
  const token = bearer(request);
  if (!token) return fail(401, BAD_TOKEN);
  const { data, error } = await anonClient().rpc("check_xplane_token", {
    p_token: token,
  });
  if (error) {
    return missingFunction(error.code)
      ? fail(503, NEEDS_MIGRATION)
      : fail(500, error.message);
  }
  return data === true ? Response.json({ ok: true }) : fail(401, BAD_TOKEN);
}

type Position = { lat: number; lon: number };

const isPosition = (value: unknown): value is Position => {
  const p = value as Position | null;
  return (
    typeof p?.lat === "number" &&
    typeof p?.lon === "number" &&
    Math.abs(p.lat) <= 90 &&
    Math.abs(p.lon) <= 180
  );
};
const clockTime = (value: unknown) =>
  typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value)
    ? value
    : null;
const finite = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

export async function POST(request: Request) {
  const token = bearer(request);
  if (!token) return fail(401, BAD_TOKEN);

  let body: Record<string, unknown>;
  try {
    const text = await request.text();
    if (text.length > 5_000_000) return fail(413, "That flight is too big.");
    body = JSON.parse(text);
  } catch {
    return fail(400, "Expected a JSON flight.");
  }

  const start = isPosition(body.start) ? body.start : null;
  const end = isPosition(body.end) ? body.end : null;
  if (!start || !end) return fail(400, "The flight needs a start and end.");
  const from = nearestAirport(start.lat, start.lon);
  const to = nearestAirport(end.lat, end.lon);
  if (!from || !to) return fail(400, "No airports found near the flight.");

  const flownOn =
    typeof body.flownOn === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.flownOn)
      ? body.flownOn
      : new Date().toISOString().slice(0, 10);
  const blockHours = finite(body.blockHours);
  if (blockHours === null || blockHours <= 0 || blockHours > 48) {
    return fail(400, "The flight needs its block time, in hours.");
  }
  const rate = finite(body.landingRateFpm);
  const icao =
    typeof body.aircraftIcao === "string"
      ? body.aircraftIcao.trim().toUpperCase().slice(0, 8)
      : "";
  // "B738" → "Boeing 737-800", when it's a type the app knows.
  const match = matchAircraft(icao)[0];
  const aircraft =
    (match?.exact ? match.name : null) || icao || "Unknown aircraft";
  const recording = buildRecording(body.track, "xplane", {
    fuelUsedKg: finite(body.fuelUsedKg),
  });
  // More than a few miles from the nearest airport with a code: say so,
  // since that's a guess (a private strip, a field, the sea).
  const far = [
    from.distanceNm > 3 && `departed ${Math.round(from.distanceNm)} nm from ${from.airport.code}`,
    to.distanceNm > 3 && `landed ${Math.round(to.distanceNm)} nm from ${to.airport.code}`,
  ].filter(Boolean);

  const { data, error } = await anonClient().rpc("log_xplane_flight", {
    p_token: token,
    p_flight: {
      flown_on: flownOn,
      aircraft,
      departure: from.airport.code,
      arrival: to.airport.code,
      hours: Math.max(0.1, Math.round(blockHours * 10) / 10),
      notes: `Logged automatically from X-Plane${far.length > 0 ? ` (${far.join("; ")})` : ""}.`,
      takeoff_time: clockTime(body.takeoffZulu),
      landing_time: clockTime(body.landingZulu),
      landing_rate_fpm:
        rate === null ? null : Math.min(5000, Math.round(Math.abs(rate))),
      recording,
    },
  });
  if (error) {
    return missingFunction(error.code)
      ? fail(503, NEEDS_MIGRATION)
      : fail(500, error.message);
  }
  if (!data) return fail(401, BAD_TOKEN);

  revalidatePath("/flights");
  revalidatePath("/log");
  revalidatePath("/plan");
  revalidatePath("/stats");
  return Response.json({
    id: data,
    departure: from.airport.code,
    arrival: to.airport.code,
    aircraft,
  });
}
