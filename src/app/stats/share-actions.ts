"use server";

import { randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type ShareState =
  | { error: string; saved?: never }
  | { saved: true; error?: never }
  | undefined;

// An unguessable id for a share link (24 URL-safe characters).
const newShareId = () => randomBytes(18).toString("base64url");

const cleanName = (value: FormDataEntryValue | null) =>
  String(value ?? "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 60) || null;

async function signedIn() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  return { supabase, user };
}

const NOT_SET_UP =
  "Sharing needs the database update in supabase/migrations/20261006_sharing_and_confirmed_flights.sql first.";
const missingTable = (code: string | undefined) =>
  code === "42P01" || code === "PGRST205";

/** Turns sharing on (with a new link) or saves the name shown on it. */
export async function saveShare(
  _prev: ShareState,
  formData: FormData,
): Promise<ShareState> {
  const { supabase, user } = await signedIn();
  const displayName = cleanName(formData.get("displayName"));
  const { data: existing, error: readError } = await supabase
    .from("flight_shares")
    .select("share_id")
    .maybeSingle();
  if (readError) {
    return {
      error: missingTable(readError.code) ? NOT_SET_UP : readError.message,
    };
  }
  const { error } = existing
    ? await supabase
        .from("flight_shares")
        .update({ display_name: displayName })
        .eq("user_id", user.id)
    : await supabase.from("flight_shares").insert({
        user_id: user.id,
        share_id: newShareId(),
        display_name: displayName,
      });
  if (error) return { error: error.message };
  revalidatePath("/stats");
  return { saved: true };
}

/** A new link in place of the old one, which stops working. */
export async function regenerateShareLink() {
  const { supabase, user } = await signedIn();
  await supabase
    .from("flight_shares")
    .update({ share_id: newShareId() })
    .eq("user_id", user.id);
  revalidatePath("/stats");
}

/** Turns sharing off: the link stops working. */
export async function stopSharing() {
  const { supabase, user } = await signedIn();
  await supabase.from("flight_shares").delete().eq("user_id", user.id);
  revalidatePath("/stats");
}
