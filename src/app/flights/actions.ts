"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { parseExtras, type FlightExtras } from "@/lib/flight-fields";
import { createClient } from "@/lib/supabase/server";

export type FlightFormState =
  | { error: string; saved?: never; notice?: never }
  | { saved?: true; notice?: string; error?: never }
  | undefined;

/** A whole number 1–10, or undefined if the input isn't one. */
function parseRating(value: unknown) {
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 10
    ? rating
    : undefined;
}

// Every page showing the user's flights or favourites: the Flight Map, the
// Flight Log and the Flight Plan (its suggestions use both).
function revalidateFlightPages() {
  revalidatePath("/flights");
  revalidatePath("/log");
  revalidatePath("/plan");
}

/** Reads a logged flight's fields from the add/edit forms. */
function parseFlight(formData: FormData) {
  const flownOn = String(formData.get("flownOn") ?? "");
  const airline = String(formData.get("airline") ?? "").trim();
  const aircraft = String(formData.get("aircraft") ?? "").trim();
  const departure = String(formData.get("departure") ?? "")
    .trim()
    .toUpperCase();
  const arrival = String(formData.get("arrival") ?? "")
    .trim()
    .toUpperCase();
  const hoursRaw = String(formData.get("hours") ?? "");
  const notes = String(formData.get("notes") ?? "").trim();
  const ratingRaw = String(formData.get("rating") ?? "");

  if (!flownOn || !aircraft || !departure || !arrival || !hoursRaw) {
    return { error: "Fill in date, aircraft, route, and hours." } as const;
  }

  const hours = Number(hoursRaw);
  if (!Number.isFinite(hours) || hours <= 0) {
    return { error: "Hours must be a positive number." } as const;
  }

  const rating = ratingRaw ? parseRating(ratingRaw) : null;
  if (rating === undefined) {
    return { error: "Rating must be a whole number from 1 to 10." } as const;
  }

  const parsedExtras = parseExtras(formData);
  if ("error" in parsedExtras) return { error: parsedExtras.error } as const;

  return {
    row: {
      flown_on: flownOn,
      airline: airline || null,
      aircraft,
      departure,
      arrival,
      hours,
      notes: notes || null,
      ...(rating !== null ? { rating } : {}),
    },
    extras: parsedExtras.extras,
  } as const;
}

// 42703 (Postgres) / PGRST204 (PostgREST): no such column — the flight
// details migration not yet run on this database.
const missingColumn = (code: string | undefined) =>
  code === "42703" || code === "PGRST204";
const hasExtras = (extras: FlightExtras) =>
  Object.values(extras).some((value) => value !== null);
const EXTRAS_NOT_SAVED =
  "Saved, but without the extra details (times, landing rate, fuel, conditions, weather): the database needs the flight details migration first (supabase/migrations/20261005_flight_details.sql).";

export async function addFlight(
  _prevState: FlightFormState,
  formData: FormData,
): Promise<FlightFormState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const parsed = parseFlight(formData);
  if ("error" in parsed) return { error: parsed.error };

  const insert = (withExtras: boolean) =>
    supabase.from("flights").insert({
      user_id: user.id,
      ...parsed.row,
      ...(withExtras ? parsed.extras : {}),
    });
  let { error } = await insert(true);
  let notice: string | undefined;
  if (missingColumn(error?.code)) {
    ({ error } = await insert(false));
    if (!error && hasExtras(parsed.extras)) notice = EXTRAS_NOT_SAVED;
  }

  if (error) {
    return { error: error.message };
  }

  revalidateFlightPages();
  return notice ? { notice } : undefined;
}

/** Saves changes to one of the user's logged flights (the edit form). */
export async function updateFlight(
  id: string,
  _prevState: FlightFormState,
  formData: FormData,
): Promise<FlightFormState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const parsed = parseFlight(formData);
  if ("error" in parsed) return { error: parsed.error };

  const update = (withExtras: boolean) =>
    supabase
      .from("flights")
      .update({
        ...parsed.row,
        // Cleared on the form: cleared in the log too.
        rating: "rating" in parsed.row ? parsed.row.rating : null,
        ...(withExtras ? parsed.extras : {}),
      })
      .eq("id", id)
      .eq("user_id", user.id);
  let { error } = await update(true);
  let notice: string | undefined;
  if (missingColumn(error?.code)) {
    ({ error } = await update(false));
    if (!error && hasExtras(parsed.extras)) notice = EXTRAS_NOT_SAVED;
  }

  if (error) {
    return { error: error.message };
  }

  revalidateFlightPages();
  return { saved: true, notice };
}

export async function deleteFlight(id: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const folder = `${user.id}/${id}`;
  const { data: files } = await supabase.storage
    .from("flight-media")
    .list(folder);

  if (files && files.length > 0) {
    await supabase.storage
      .from("flight-media")
      .remove(files.map((file) => `${folder}/${file.name}`));
  }

  await supabase.from("flights").delete().eq("id", id);
  revalidateFlightPages();
}

/** Sets (or, with null, clears) a flight's 1–10 rating. */
export async function rateFlight(id: string, rating: number | null) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const value = rating === null ? null : parseRating(rating);
  if (value === undefined) {
    return { error: "Rating must be a whole number from 1 to 10." };
  }

  const { error } = await supabase
    .from("flights")
    .update({ rating: value })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) {
    return { error: error.message };
  }

  revalidateFlightPages();
}

export type PreferencesFormState =
  | { error: string; saved?: never }
  | { saved: true; error?: never }
  | undefined;

export async function savePreferences(
  _prevState: PreferencesFormState,
  formData: FormData,
): Promise<PreferencesFormState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const favouriteAirline = String(formData.get("favouriteAirline") ?? "")
    .trim()
    .slice(0, 80);
  const favouriteAircraft = String(formData.get("favouriteAircraft") ?? "")
    .trim()
    .slice(0, 80);

  const { error } = await supabase.from("user_preferences").upsert({
    user_id: user.id,
    favourite_airline: favouriteAirline || null,
    favourite_aircraft: favouriteAircraft || null,
    updated_at: new Date().toISOString(),
  });

  if (error) {
    return { error: error.message };
  }

  revalidateFlightPages();
  return { saved: true };
}
