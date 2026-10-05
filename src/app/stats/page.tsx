import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { flightStats } from "@/lib/flight-stats";
import { FlightsHeader } from "../flights/flights-header";
import { flightTotals, loadFlights } from "../flights/flights-data";
import styles from "../home.module.css";
import { ShareSettings } from "./share-settings";
import { StatsView } from "./stats-view";

export const metadata = { title: "Flight Stats · Flight World" };

/** Today's date, UTC, "YYYY-MM-DD" (ending the months chart). */
const todayUtc = () => new Date().toISOString().slice(0, 10);

// Flight Stats: the user's headline figures, hours per month, most-flown
// aircraft and airports, longest flights and achievements.
export default async function StatsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [{ data, error }, share] = await Promise.all([
    loadFlights(supabase),
    supabase
      .from("flight_shares")
      .select("share_id, display_name")
      .maybeSingle<{ share_id: string; display_name: string | null }>(),
  ]);
  // 42P01 / PGRST205: no such table — the sharing update not run yet.
  const sharingAvailable =
    share.error?.code !== "42P01" && share.error?.code !== "PGRST205";
  const flights = data ?? [];
  const stats = flightStats(flights, todayUtc());
  const totals = flightTotals(flights);

  return (
    <>
      <section className={styles.page}>
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-6 py-12">
          <FlightsHeader
            title="Flight Stats"
            count={totals.count}
            totalHours={totals.totalHours}
            countries={stats.totals.countries}
            averageRating={totals.averageRating}
          />
        </div>
      </section>

      <div className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-10 px-6 py-12">
        {error && (
          <p className="text-sm text-red-600 dark:text-red-400">
            Could not load flights: {error.message}
          </p>
        )}
        <ShareSettings
          share={share.data ?? null}
          available={sharingAvailable}
        />
        <StatsView stats={stats} />
      </div>
    </>
  );
}
