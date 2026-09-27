import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { findAirline } from "@/lib/airlines";
import { FlightPlanner } from "../flights/flight-planner";
import { summarizeFlying } from "../flights/flying-summary";
import { PlannerProvider } from "../flights/planner-context";
import { buildChallenges, buildSuggestionRoutes } from "../flights/planner-data";
import styles from "../home.module.css";

export const metadata: Metadata = { title: "Flight Plan · Flight World" };

type LoggedFlight = {
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
};

// The flight planner, on its own page: look up any airport (details and
// live METAR), browse real-world routes to fly next, or take on a
// challenging one. It's personalised from the flight log — your most-used
// airports as quick picks, your favourite (or most-flown) aircraft, and
// which routes you've already flown. `?airport=CODE` opens with that
// airport shown (the flights page's globe links here).
export default async function PlanPage(props: PageProps<"/plan">) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [{ data: flights }, { data: preferences }, searchParams] =
    await Promise.all([
      supabase
        .from("flights")
        .select("airline, aircraft, departure, arrival")
        .returns<LoggedFlight[]>(),
      // Errors (e.g. the table not created yet) just mean no favourites.
      supabase
        .from("user_preferences")
        .select("favourite_airline, favourite_aircraft")
        .maybeSingle<{
          favourite_airline: string | null;
          favourite_aircraft: string | null;
        }>(),
      props.searchParams,
    ]);

  const flying = summarizeFlying(flights ?? []);
  const favouriteAirline = preferences?.favourite_airline ?? null;
  const favouriteAircraft = preferences?.favourite_aircraft ?? null;
  const airportParam = searchParams.airport;
  const initialAirport =
    typeof airportParam === "string" && /^[A-Za-z0-9]{3,4}$/.test(airportParam)
      ? airportParam
      : null;

  return (
    <PlannerProvider initialAirport={initialAirport}>
      <section className={styles.page}>
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-1 px-6 py-12">
          <h1 className={`${styles.introHeading} text-3xl font-semibold`}>
            Flight Plan
          </h1>
          <p className={`${styles.featureText} text-sm`}>
            Look up an airport and its live weather, find a real-world route
            to fly next, or take on a challenging one.
          </p>
        </div>
      </section>

      <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-12">
        <FlightPlanner
          quickCodes={flying.topAirports}
          routes={buildSuggestionRoutes()}
          challenges={buildChallenges()}
          defaultAircraft={favouriteAircraft ?? flying.topAircraft ?? "A320"}
          favouriteAirline={
            favouriteAirline
              ? {
                  name: favouriteAirline,
                  iata: findAirline(favouriteAirline)?.iata ?? null,
                }
              : null
          }
          flownRouteKeys={flying.flownPairs}
        />
      </div>
    </PlannerProvider>
  );
}
