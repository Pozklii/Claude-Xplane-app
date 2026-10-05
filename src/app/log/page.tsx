import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { KNOWN_AIRCRAFT } from "@/lib/aircraft";
import { findAirline } from "@/lib/airlines";
import { findAirport } from "@/lib/airports";
import { countryName } from "@/lib/countries";
import { formatDate } from "@/lib/dates";
import { EXAMPLE_ROUTES } from "@/lib/example-flights/routes";
import { conditionsLabel, shortTime } from "@/lib/flight-fields";
import {
  applyLogQuery,
  logFilterOptions,
  parseLogQuery,
} from "@/lib/log-query";
import { deleteFlight } from "../flights/actions";
import { AirlineLogo } from "../flights/airline-logo";
import { FavouritesForm } from "../flights/favourites-form";
import { Flag } from "../flights/flag";
import { EditableFlight } from "../flights/editable-flight";
import { FlightMedia } from "../flights/flight-media";
import { FlightRow } from "../flights/flight-row";
import { FlightsHeader } from "../flights/flights-header";
import {
  flightTotals,
  loadFlightLog,
  type Preferences,
} from "../flights/flights-data";
import { summarizeFlying } from "../flights/flying-summary";
import { LogFilters } from "../flights/log-filters";
import { LogSummary } from "../flights/log-summary";
import { NewFlightForm } from "../flights/new-flight-form";
import { RatingControl } from "../flights/rating-control";
import { SelectionProvider } from "../flights/selection-context";
import { StopPropagation } from "../flights/stop-propagation";
import styles from "../home.module.css";

export const metadata = { title: "Flight Log · Flight World" };

// The Flight Log: logging new flights, the user's favourites and flying
// summary, and the list of flights logged, with the picked flight's summary
// card at the top (and a link to it on the Flight Map, which has the globe).
export default async function LogPage(props: PageProps<"/log">) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [
    { flights, error, mediaByFlight, details: flightDetails },
    { data: preferences },
    searchParams,
  ] = await Promise.all([
    loadFlightLog(supabase, user.id),
    // Errors (e.g. the table not created yet) just mean no favourites.
    supabase
      .from("user_preferences")
      .select("favourite_airline, favourite_aircraft")
      .maybeSingle<Preferences>(),
    props.searchParams,
  ]);

  // The search, filters and sort (see LogFilters), from the address.
  const query = parseLogQuery(searchParams);
  const shownFlights = applyLogQuery(flights, query, (flight) =>
    [flight.departure, flight.arrival].flatMap((code) => {
      const airport = findAirport(code);
      return airport ? [airport.city, airport.name] : [];
    }),
  );

  const flying = summarizeFlying(flights);
  const totals = flightTotals(flights);
  const favouriteAirline = preferences?.favourite_airline ?? null;
  const favouriteAircraft = preferences?.favourite_aircraft ?? null;
  const favouriteAirlineIata = findAirline(favouriteAirline)?.iata ?? null;
  const routeAirlines = [
    ...new Set(
      EXAMPLE_ROUTES.flatMap((route) => (route.airline ? [route.airline] : [])),
    ),
  ];

  return (
    <SelectionProvider>
      <section className={styles.page}>
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-6 py-12 lg:flex-row lg:items-start lg:justify-between">
          <FlightsHeader
            title="Flight Log"
            count={totals.count}
            totalHours={totals.totalHours}
            countries={flying.countries.length}
            averageRating={totals.averageRating}
          >
            <Link
              href="/flights"
              className={`${styles.featureText} mt-3 text-sm underline-offset-4 hover:underline`}
            >
              See your flights on the Flight Map &rarr;
            </Link>
          </FlightsHeader>
          <div className="w-full max-w-md">
            <LogSummary details={flightDetails} userId={user.id} />
          </div>
        </div>
      </section>

      <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-12">
        <NewFlightForm />

        <section className="flex flex-col gap-4 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]">
          <h2 className="text-lg font-semibold text-black dark:text-zinc-50">
            Your flying
          </h2>
          <div className="flex flex-col gap-2">
            <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
              Favourites
            </h3>
            {(favouriteAirline || favouriteAircraft) && (
              <p className="flex flex-wrap items-center gap-2 text-sm text-zinc-700 dark:text-zinc-300">
                {favouriteAirline && (
                  <>
                    <AirlineLogo
                      name={favouriteAirline}
                      iata={favouriteAirlineIata}
                      size="md"
                    />
                    <span>{favouriteAirline}</span>
                  </>
                )}
                {favouriteAirline && favouriteAircraft && (
                  <span className="text-zinc-400">&middot;</span>
                )}
                {favouriteAircraft && <span>{favouriteAircraft}</span>}
              </p>
            )}
            <FavouritesForm
              favouriteAirline={favouriteAirline}
              favouriteAircraft={favouriteAircraft}
              airlineOptions={[
                ...new Set([
                  ...flying.airlines.map((airline) => airline.name),
                  ...routeAirlines,
                ]),
              ]}
              aircraftOptions={[
                ...new Set([
                  ...flights.map((flight) => flight.aircraft),
                  ...KNOWN_AIRCRAFT,
                ]),
              ]}
            />
          </div>

          {flying.airlines.length > 0 && (
            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
                Airlines you fly
              </h3>
              <ul className="flex flex-wrap gap-2">
                {flying.airlines.map((airline) => (
                  <li
                    key={airline.name}
                    className="flex items-center gap-2 rounded-full border border-black/[.08] py-1 pl-1 pr-3 text-xs text-zinc-700 dark:border-white/[.145] dark:text-zinc-300"
                  >
                    <AirlineLogo name={airline.name} iata={airline.iata} />
                    {airline.name}
                    <span className="tabular-nums text-zinc-500">
                      &times;{airline.count}
                    </span>
                    {favouriteAirline &&
                      (airline.iata
                        ? airline.iata === favouriteAirlineIata
                        : airline.name === favouriteAirline) && (
                        <span className="text-amber-500" title="Favourite">
                          &#9733;
                        </span>
                      )}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {flying.countries.length > 0 && (
            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
                Countries you&apos;ve flown to or from
              </h3>
              <ul className="flex flex-wrap gap-2">
                {flying.countries.map((country) => (
                  <li
                    key={country.code}
                    className="flex items-center gap-1.5 rounded-full border border-black/[.08] px-2.5 py-1 text-xs text-zinc-700 dark:border-white/[.145] dark:text-zinc-300"
                  >
                    <Flag country={country.code} label={country.name} />
                    {country.name}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>

        {error && (
          <p className="text-sm text-red-600 dark:text-red-400">
            Could not load flights: {error.message}
          </p>
        )}

        <div className="flex flex-col gap-3">
          {flights.length === 0 && (
            <p className="text-sm text-zinc-500 dark:text-zinc-500">
              No flights logged yet. Add your first one above.
            </p>
          )}

          {flights.length > 0 && (
            <LogFilters
              query={query}
              options={logFilterOptions(flights)}
              shown={shownFlights.length}
              total={flights.length}
            />
          )}
          {flights.length > 0 && shownFlights.length === 0 && (
            <p className="text-sm text-zinc-500 dark:text-zinc-500">
              No flights match these filters.
            </p>
          )}

          {shownFlights.map((flight) => {
            const details = flightDetails[flight.id];
            const fromCountry =
              details?.from.country ?? findAirport(flight.departure)?.country;
            const toCountry =
              details?.to.country ?? findAirport(flight.arrival)?.country;
            const extras = [
              flight.takeoff_time &&
                `Takeoff ${shortTime(flight.takeoff_time)}`,
              flight.landing_time &&
                `Landing ${shortTime(flight.landing_time)}`,
              flight.landing_rate_fpm != null &&
                `${flight.landing_rate_fpm.toLocaleString("en-US")} fpm`,
              flight.fuel_used != null &&
                `${Number(flight.fuel_used).toLocaleString("en-US")} ${flight.fuel_unit ?? "kg"} fuel`,
              conditionsLabel(flight.conditions),
            ].filter(Boolean) as string[];
            return (
              <FlightRow key={flight.id} id={flight.id}>
                <EditableFlight
                  flight={flight}
                  actions={
                    <form action={deleteFlight.bind(null, flight.id)}>
                      <button
                        type="submit"
                        className="rounded-full border border-black/[.08] px-3 py-1 text-xs font-medium text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
                      >
                        Delete
                      </button>
                    </form>
                  }
                >
                  <div className="flex min-w-0 flex-col gap-1">
                    <div className="flex flex-wrap items-center gap-2 text-sm font-medium text-black dark:text-zinc-50">
                      <span>{formatDate(flight.flown_on)}</span>
                      <span className="text-zinc-400">&middot;</span>
                      {flight.airline && (
                        <>
                          <AirlineLogo
                            name={flight.airline}
                            iata={findAirline(flight.airline)?.iata ?? null}
                          />
                          <span>{flight.airline}</span>
                          <span className="text-zinc-400">&middot;</span>
                        </>
                      )}
                      <span>{flight.aircraft}</span>
                      <span className="text-zinc-400">&middot;</span>
                      <span className="inline-flex items-center gap-1.5">
                        <Flag
                          country={fromCountry}
                          label={countryName(fromCountry)}
                        />
                        {flight.departure} &rarr;
                        <Flag
                          country={toCountry}
                          label={countryName(toCountry)}
                        />
                        {flight.arrival}
                      </span>
                      <span className="text-zinc-400">&middot;</span>
                      <span>{Number(flight.hours).toFixed(1)}h</span>
                    </div>
                    {extras.length > 0 && (
                      <p className="flex flex-wrap gap-x-3 gap-y-0.5 text-xs tabular-nums text-zinc-600 dark:text-zinc-400">
                        {extras.map((item) => (
                          <span key={item}>{item}</span>
                        ))}
                      </p>
                    )}
                    {flight.notes && (
                      <p className="text-sm text-zinc-600 dark:text-zinc-400">
                        {flight.notes}
                      </p>
                    )}
                    {flight.weather && (
                      <p className="break-words font-mono text-[11px] text-zinc-500">
                        {flight.weather}
                      </p>
                    )}
                    <StopPropagation>
                      <RatingControl
                        flightId={flight.id}
                        rating={flight.rating}
                      />
                    </StopPropagation>
                  </div>
                </EditableFlight>

                <StopPropagation>
                  <FlightMedia
                    flightId={flight.id}
                    userId={user.id}
                    items={mediaByFlight.get(flight.id) ?? []}
                  />
                </StopPropagation>
              </FlightRow>
            );
          })}
        </div>
      </div>
    </SelectionProvider>
  );
}
