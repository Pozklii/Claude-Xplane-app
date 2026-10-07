"use server";

import { revalidatePath } from "next/cache";
import { buildRecording, type TrackPoint } from "@/lib/recording";
import { createClient } from "@/lib/supabase/server";

// 42703 (Postgres) / PGRST204 (PostgREST): no such column — the X-Plane
// and SimBrief migration not yet run on this database.
const missingColumn = (code: string | undefined) =>
  code === "42703" || code === "PGRST204";
const NEEDS_MIGRATION =
  "Flown routes need the X-Plane and SimBrief database update first (supabase/migrations/20261007_xplane_and_simbrief.sql).";

/** The points of one of the signed-in user's flown routes, or null. */
export async function getFlightTrack(
  flightId: string,
): Promise<TrackPoint[] | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  const { data } = await supabase
    .from("flights")
    .select("points:recording->points")
    .eq("id", flightId)
    .eq("user_id", user.id)
    .maybeSingle<{ points: TrackPoint[] | null }>();
  return Array.isArray(data?.points) ? data.points : null;
}

/** Saves a flown route read from an uploaded file to one of the user's
 * flights (replacing any it had), or with null removes it. */
export async function saveFlightTrack(
  flightId: string,
  points: TrackPoint[] | null,
): Promise<{ error: string } | undefined> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Sign in to change this flight." };

  let recording = null;
  if (points !== null) {
    // Thinned in the browser already; this is a backstop on size.
    if (!Array.isArray(points) || points.length > 50000) {
      return { error: "That route has too many points." };
    }
    recording = buildRecording(points, "file");
    if (!recording) {
      return { error: "That file has no route in it (two points at least)." };
    }
  }

  const { error } = await supabase
    .from("flights")
    .update({ recording })
    .eq("id", flightId)
    .eq("user_id", user.id);
  if (error) {
    return { error: missingColumn(error.code) ? NEEDS_MIGRATION : error.message };
  }
  revalidatePath("/flights");
  revalidatePath("/log");
}
