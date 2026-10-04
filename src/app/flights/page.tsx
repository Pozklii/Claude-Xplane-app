import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CustomizableGlobe } from "./customizable-globe";
import { FlightsHeader } from "./flights-header";
import { buildGlobeData, flightTotals, loadFlightLog } from "./flights-data";
import { summarizeFlying } from "./flying-summary";
import { PlannerProvider } from "./planner-context";
import { SelectionProvider } from "./selection-context";
import styles from "../home.module.css";

export const metadata = { title: "Flight Map · Flight World" };

// The Flight Map: the user's flights on the globe (or a flat 2D map), with
// the selected flight's summary card beside it. Logging and the list of
// flights are on the Flight Log page (/log), which links here with
// ?flight=<id> to open a flight on the map.
export default async function FlightsPage(props: PageProps<"/flights">) {
  // ?map=2d starts on the flat map instead of the globe.
  const { map, flight } = await props.searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { flights, details } = await loadFlightLog(supabase, user.id);
  const totals = flightTotals(flights);
  const flying = summarizeFlying(flights);
  const { points, arcs, unresolvedCodes } = buildGlobeData(flights);
  const initialFlight =
    typeof flight === "string" && Object.hasOwn(details, flight)
      ? flight
      : null;

  return (
    <SelectionProvider initialSelectedId={initialFlight}>
      <PlannerProvider>
        {/* The page's dark ground (the landing page's tokens), which the
            bare globe's clear land shows; the map fills the rest of the
            page. */}
        <section className={`${styles.page} flex flex-1 flex-col`}>
          <CustomizableGlobe
            points={points}
            arcs={arcs}
            details={details}
            userId={user.id}
            flat={map === "2d"}
            header={
              <FlightsHeader
                title="Flight Map"
                count={totals.count}
                totalHours={totals.totalHours}
                countries={flying.countries.length}
                averageRating={totals.averageRating}
              >
                {flights.length === 0 && (
                  <p className={`${styles.featureText} mt-3 text-sm`}>
                    No flights yet: log your first one in the Flight Log.
                  </p>
                )}
                {unresolvedCodes.length > 0 && (
                  <p className={`${styles.featureText} mt-3 text-xs`}>
                    Not shown on the map (unrecognized airport code):{" "}
                    {unresolvedCodes.join(", ")}
                  </p>
                )}
                <Link
                  href="/log"
                  className={`${styles.featureText} mt-3 text-sm underline-offset-4 hover:underline`}
                >
                  Log a flight, or browse them all, in the Flight Log &rarr;
                </Link>
              </FlightsHeader>
            }
          />
        </section>
      </PlannerProvider>
    </SelectionProvider>
  );
}
