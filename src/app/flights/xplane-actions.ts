"use server";

import { createHash, randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// 42P01 (Postgres) / PGRST205 (PostgREST): no such table — the X-Plane and
// SimBrief migration not yet run on this database.
const missingTable = (code: string | undefined) =>
  code === "42P01" || code === "PGRST205";
const NEEDS_MIGRATION =
  "Connecting X-Plane needs the database update first (supabase/migrations/20261007_xplane_and_simbrief.sql).";

/** Makes the signed-in user a new X-Plane connection token, replacing any
 * they had (which stops working). The token is returned this once; only
 * its hash is kept. */
export async function createXplaneToken(): Promise<
  { token: string } | { error: string }
> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Sign in to connect X-Plane." };

  const token = `fw_${randomBytes(32).toString("base64url")}`;
  const { error } = await supabase.from("xplane_tokens").upsert({
    user_id: user.id,
    token_hash: createHash("sha256").update(token).digest("hex"),
    created_at: new Date().toISOString(),
    last_used_at: null,
  });
  if (error) {
    return { error: missingTable(error.code) ? NEEDS_MIGRATION : error.message };
  }
  revalidatePath("/log");
  return { token };
}

/** Disconnects X-Plane: the user's token stops working. */
export async function revokeXplaneToken() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;
  await supabase.from("xplane_tokens").delete().eq("user_id", user.id);
  revalidatePath("/log");
}
