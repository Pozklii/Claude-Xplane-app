"use server";

import { matchAircraft } from "@/lib/aircraft";
import { findAirline } from "@/lib/airlines";
import { createClient } from "@/lib/supabase/server";
import { parseSimbriefOfp, type SimbriefPlan } from "@/lib/simbrief";

const FETCHER = "https://www.simbrief.com/api/xml.fetcher.php";

export type SimbriefImport = {
  plan: SimbriefPlan;
  /** The plan's airline and aircraft as the planner names them. */
  airline: string;
  aircraft: string;
};

/** Fetches a pilot's latest SimBrief flight plan, by their SimBrief
 * username or numeric Pilot ID (signed-in users only). */
export async function importSimbriefPlan(
  pilot: string,
): Promise<SimbriefImport | { error: string }> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "Sign in to import a SimBrief plan." };

  const value = pilot.trim();
  if (!/^[A-Za-z0-9_.-]{1,40}$/.test(value)) {
    return { error: "Enter your SimBrief username or Pilot ID." };
  }
  const params = new URLSearchParams({ json: "1" });
  params.set(/^\d+$/.test(value) ? "userid" : "username", value);

  let json: unknown;
  try {
    const response = await fetch(`${FETCHER}?${params}`, {
      cache: "no-store",
      signal: AbortSignal.timeout(15000),
    });
    json = await response.json().catch(() => null);
    // SimBrief answers 400 with a reason ("Error: Unknown UserID") when
    // there's no such pilot or plan.
    const status = (json as { fetch?: { status?: unknown } } | null)?.fetch
      ?.status;
    if (!response.ok || (typeof status === "string" && status !== "Success")) {
      const reason =
        typeof status === "string" ? status.replace(/^Error:\s*/i, "") : null;
      return {
        error: reason
          ? `SimBrief says: ${reason}.`
          : "SimBrief didn't return a plan. Check the username or Pilot ID.",
      };
    }
  } catch {
    return { error: "Couldn't reach SimBrief right now. Try again shortly." };
  }

  const plan = parseSimbriefOfp(json);
  if (!plan) {
    return { error: "That SimBrief plan has no departure and arrival yet." };
  }
  // "BAW" → "British Airways"; "A20N" → "Airbus A320neo" (else SimBrief's
  // own name for the type).
  const match = matchAircraft(plan.aircraftIcao)[0];
  return {
    plan,
    airline: plan.airlineIcao
      ? (findAirline(plan.airlineIcao)?.name ?? plan.airlineIcao)
      : "",
    aircraft:
      (match?.exact ? match.name : null) ??
      plan.aircraftName ??
      plan.aircraftIcao ??
      "",
  };
}
