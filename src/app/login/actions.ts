"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import {
  isAuthRetryableFetchError,
  type AuthError,
} from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

export type AuthState = { error: string } | undefined;

// A network-level failure (Supabase unreachable — most often a paused
// free-tier project, or a wrong NEXT_PUBLIC_SUPABASE_URL) otherwise
// surfaces as a bare "fetch failed", which says nothing about the cause.
function describeAuthError(error: AuthError) {
  if (isAuthRetryableFetchError(error)) {
    return "Can't reach the sign-in service right now. Please try again in a moment.";
  }
  return error.message;
}

function readCredentials(formData: FormData) {
  return {
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
  };
}

export async function login(
  _prevState: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const { email, password } = readCredentials(formData);
  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    return { error: describeAuthError(error) };
  }

  revalidatePath("/", "layout");
  redirect("/flights");
}

export async function signup(
  _prevState: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const { email, password } = readCredentials(formData);
  const supabase = await createClient();

  const { error } = await supabase.auth.signUp({ email, password });

  if (error) {
    return { error: describeAuthError(error) };
  }

  revalidatePath("/", "layout");
  redirect("/login?checkEmail=1");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/");
}
