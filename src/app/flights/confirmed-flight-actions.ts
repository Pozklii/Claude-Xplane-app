"use server";

import { createClient } from "@/lib/supabase/server";
import type { ConfirmedFlight } from "./confirmed-flight-store";

/** The confirmed flight as saved with the account, or `undefined` where
 * the account can't hold one yet (the sharing and confirmed flights
 * database update not run). `null` means none was ever saved. */
export type SavedConfirmedFlight =
  | { flight: ConfirmedFlight | null; updatedAt: string }
  | null
  | undefined;

/** Saves the confirmed flight (or, with null, that there's none now) with
 * the signed-in user's account, as of `at`, so it follows them to their
 * other devices. Quietly does nothing when signed out or the database
 * can't hold it yet; this browser keeps its own copy either way. */
export async function saveConfirmedFlightToAccount(
  flight: ConfirmedFlight | null,
  at: string,
) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;
  const valid =
    flight === null ||
    (typeof flight === "object" &&
      typeof flight.from === "string" &&
      typeof flight.to === "string" &&
      JSON.stringify(flight).length < 4000);
  const when = new Date(at);
  if (!valid || Number.isNaN(when.getTime())) return;
  await supabase.from("confirmed_flights").upsert({
    user_id: user.id,
    flight,
    updated_at: when.toISOString(),
  });
}
