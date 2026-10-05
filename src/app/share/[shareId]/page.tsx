import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { NO_EXTRAS } from "@/lib/flight-fields";
import { flightStats } from "@/lib/flight-stats";
import { CustomizableGlobe } from "../../flights/customizable-globe";
import { FlightsHeader } from "../../flights/flights-header";
import {
  buildFlightDetails,
  buildGlobeData,
  flightTotals,
  type Flight,
} from "../../flights/flights-data";
import { PlannerProvider } from "../../flights/planner-context";
import { SelectionProvider } from "../../flights/selection-context";
import styles from "../../home.module.css";
import { StatsView } from "../../stats/stats-view";

type SharedMap = {
  display_name: string | null;
  flights: Omit<Flight, "notes">[];
};

/** Today's date, UTC, "YYYY-MM-DD" (ending the months chart). */
const todayUtc = () => new Date().toISOString().slice(0, 10);

// One lookup per request, shared by the page and its metadata.
const loadShare = cache(async (shareId: string) => {
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(shareId)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("shared_flight_map", {
    p_share_id: shareId,
  });
  if (error || !data) return null;
  return data as SharedMap;
});

const titleFor = (share: SharedMap) =>
  share.display_name ? `${share.display_name}'s Flight Map` : "Flight Map";

export async function generateMetadata(
  props: PageProps<"/share/[shareId]">,
): Promise<Metadata> {
  const { shareId } = await props.params;
  const share = await loadShare(shareId);
  return {
    title: share ? `${titleFor(share)} · Flight World` : "Flight World",
    // Shared by link, not for search engines.
    robots: { index: false, follow: false },
  };
}

// A user's flight map and stats, shared by a public link (see the Flight
// Stats page): their globe, routes and achievements, without notes,
// photos or any account details. Read through the shared_flight_map
// database function, so visitors need no access to the flights table.
export default async function SharedMapPage(
  props: PageProps<"/share/[shareId]">,
) {
  const { shareId } = await props.params;
  const share = await loadShare(shareId);
  if (!share) notFound();

  const flights: Flight[] = share.flights.map((flight) => ({
    ...NO_EXTRAS,
    ...flight,
    hours: Number(flight.hours),
    notes: null,
  }));
  const { points, arcs } = buildGlobeData(flights);
  const details = buildFlightDetails(flights, new Map(), new Map());
  const totals = flightTotals(flights);
  const stats = flightStats(flights, todayUtc());
  const owner = share.display_name ?? "This pilot";

  return (
    <SelectionProvider>
      <PlannerProvider>
        <section className={`${styles.page} flex min-h-[85vh] flex-1 flex-col`}>
          <CustomizableGlobe
            points={points}
            arcs={arcs}
            details={details}
            header={
              <FlightsHeader
                title={titleFor(share)}
                count={totals.count}
                totalHours={totals.totalHours}
                countries={stats.totals.countries}
                averageRating={totals.averageRating}
              >
                <p className={`${styles.featureText} mt-3 text-sm`}>
                  Shared from Flight World. Scroll down for{" "}
                  {owner === "This pilot" ? "their" : `${owner}'s`} stats and
                  achievements.
                </p>
              </FlightsHeader>
            }
          />
        </section>
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-10 px-6 py-12">
          <StatsView stats={stats} owner={owner} />
        </div>
      </PlannerProvider>
    </SelectionProvider>
  );
}
