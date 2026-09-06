"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type FlightFormState = { error: string } | undefined;

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

  if (!flownOn || !aircraft || !departure || !arrival || !hoursRaw) {
    return { error: "Fill in date, aircraft, route, and hours." };
  }

  const hours = Number(hoursRaw);
  if (!Number.isFinite(hours) || hours <= 0) {
    return { error: "Hours must be a positive number." };
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
