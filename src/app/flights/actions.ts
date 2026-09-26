"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type FlightFormState = { error: string } | undefined;

/** A whole number 1–10, or undefined if the input isn't one. */
function parseRating(value: unknown) {
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 10
    ? rating
    : undefined;
}

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
    return { error: "Fill in date, aircraft, route, and hours." };
  }

  const hours = Number(hoursRaw);
  if (!Number.isFinite(hours) || hours <= 0) {
    return { error: "Hours must be a positive number." };
  }

  const rating = ratingRaw ? parseRating(ratingRaw) : null;
  if (rating === undefined) {
    return { error: "Rating must be a whole number from 1 to 10." };
  }

  const { error } = await supabase.from("flights").insert({
    user_id: user.id,
    flown_on: flownOn,
    airline: airline || null,
    aircraft,
    departure,
    arrival,
    hours,
    notes: notes || null,
    ...(rating !== null ? { rating } : {}),
  });

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/flights");
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
  revalidatePath("/flights");
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

  revalidatePath("/flights");
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

  revalidatePath("/flights");
  return { saved: true };
}
