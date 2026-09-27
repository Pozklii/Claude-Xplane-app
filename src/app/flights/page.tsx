import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { KNOWN_AIRCRAFT } from "@/lib/aircraft";
import { findAirline } from "@/lib/airlines";
import { findAirport } from "@/lib/airports";
import { countryName } from "@/lib/countries";
import { distanceNm } from "@/lib/geo";
import { formatDate } from "@/lib/dates";
import { EXAMPLE_ROUTES } from "@/lib/example-flights/routes";
import { deleteFlight } from "./actions";
import { AirlineLogo } from "./airline-logo";
import { FavouritesForm } from "./favourites-form";
import { Flag } from "./flag";
import { FlightPlanner } from "./flight-planner";
import { NewFlightForm } from "./new-flight-form";
import { type GlobeArc, type GlobePoint } from "./flight-globe";
import { CustomizableGlobe } from "./customizable-globe";
import type { FlightDetails } from "./selected-flight-card";
import { thumbnailFolder } from "./thumbnail-path";
import { FlightMedia, type MediaItem } from "./flight-media";
import { FlightRow } from "./flight-row";
import { PlannerProvider } from "./planner-context";
import {
  buildChallenges,
  buildSuggestionRoutes,
  routePairKey,
} from "./planner-data";
import { RatingControl } from "./rating-control";
import { SelectionProvider } from "./selection-context";
import { StopPropagation } from "./stop-propagation";
import styles from "../home.module.css";

type Flight = {
  id: string;
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
  rating: number | null;
};

type Preferences = {
  favourite_airline: string | null;
  favourite_aircraft: string | null;
};

// How often each value occurs, most frequent first.
function rankByCount(values: string[]) {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

// The user's airlines (with logo codes and flight counts), the countries
// their flights touched, the airports they use most and the routes they've
// flown — for the profile strip and the planner.
function summarizeFlying(flights: Flight[]) {
  const airlines = rankByCount(
    flights.flatMap((flight) => (flight.airline ? [flight.airline] : [])),
  ).map(([name, count]) => ({
    name,
    count,
    iata: findAirline(name)?.iata ?? null,
  }));

  const countries = new Map<string, number>();
  const airportCodes: string[] = [];
  const flownPairs = new Set<string>();
  for (const flight of flights) {
    const from = findAirport(flight.departure);
    const to = findAirport(flight.arrival);
    for (const airport of [from, to]) {
      if (!airport) continue;
      airportCodes.push(airport.code);
      if (airport.country) {
        countries.set(
          airport.country,
          (countries.get(airport.country) ?? 0) + 1,
        );
      }
    }
    if (from && to) flownPairs.add(routePairKey(from, to));
  }

  return {
    airlines,
    countries: [...countries.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([code]) => ({ code, name: countryName(code) ?? code })),
    topAirports: rankByCount(airportCodes)
      .slice(0, 6)
      .map(([code]) => code),
    topAircraft: rankByCount(flights.map((flight) => flight.aircraft))[0]?.[0],
    flownPairs: [...flownPairs],
  };
}

const VIDEO_EXTENSIONS = new Set(["mp4", "mov", "webm", "m4v"]);
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "gif", "webp", "heic"]);

function kindForFilename(name: string): MediaItem["kind"] {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (IMAGE_EXTENSIONS.has(ext)) return "image";
  if (VIDEO_EXTENSIONS.has(ext)) return "video";
  return "other";
}

async function getFlightMedia(
  supabase: SupabaseClient,
  userId: string,
  flightId: string,
): Promise<MediaItem[]> {
  const folder = `${userId}/${flightId}`;
  const { data: files } = await supabase.storage
    .from("flight-media")
    .list(folder);

  if (!files || files.length === 0) return [];

  const paths = files.map((file) => `${folder}/${file.name}`);
  const { data: signed } = await supabase.storage
    .from("flight-media")
    .createSignedUrls(paths, 3600);

  return (signed ?? []).flatMap((entry, i) =>
    entry.signedUrl
      ? [
          {
            path: paths[i],
            name: files[i].name,
            url: entry.signedUrl,
            kind: kindForFilename(files[i].name),
          },
        ]
      : [],
  );
}

type Thumbnail = { path: string; url: string };

// The user's chosen thumbnail for a flight, if any (see ThumbnailPicker) —
// the newest file in its thumbnail folder, in case a replace was
// interrupted before the old one was removed.
async function getFlightThumbnail(
  supabase: SupabaseClient,
  userId: string,
  flightId: string,
): Promise<Thumbnail | null> {
  const folder = thumbnailFolder(userId, flightId);
  const { data: files } = await supabase.storage
    .from("flight-media")
    .list(folder, { sortBy: { column: "name", order: "desc" }, limit: 1 });
  const file = files?.[0];
  if (!file) return null;

  const path = `${folder}/${file.name}`;
  const { data: signed } = await supabase.storage
    .from("flight-media")
    .createSignedUrl(path, 3600);
  return signed?.signedUrl ? { path, url: signed.signedUrl } : null;
}

function buildFlightDetails(
  flights: Flight[],
  mediaByFlight: Map<string, MediaItem[]>,
  thumbnailByFlight: Map<string, Thumbnail | null>,
) {
  const details: Record<string, FlightDetails> = {};
  for (const flight of flights) {
    const from = findAirport(flight.departure);
    const to = findAirport(flight.arrival);
    // Only flights drawn on the globe can be selected there.
    if (!from || !to) continue;
    const images = (mediaByFlight.get(flight.id) ?? []).filter(
      (item) => item.kind === "image",
    );
    const custom = thumbnailByFlight.get(flight.id) ?? null;
    details[flight.id] = {
      date: flight.flown_on,
      airline: flight.airline,
      airlineIata: findAirline(flight.airline)?.iata ?? null,
      aircraft: flight.aircraft,
      from: { code: from.code, city: from.city, country: from.country },
      to: { code: to.code, city: to.city, country: to.country },
      rating: flight.rating,
      hours: Number(flight.hours),
      distanceNm: distanceNm(from, to),
      notes: flight.notes,
      thumbnailUrl: custom?.url ?? images[0]?.url ?? null,
      customThumbnailPath: custom?.path ?? null,
      images: images.map(({ path, name, url }) => ({ path, name, url })),
    };
  }
  return details;
}

function buildGlobeData(flights: Flight[]) {
  const pointsByCode = new Map<string, GlobePoint>();
  const arcs: GlobeArc[] = [];
  const unresolvedCodes = new Set<string>();

  for (const flight of flights) {
    const from = findAirport(flight.departure);
    const to = findAirport(flight.arrival);

    if (from) {
      pointsByCode.set(from.code, {
        code: from.code,
        name: from.name,
        city: from.city,
        lat: from.lat,
        lng: from.lon,
      });
    } else {
      unresolvedCodes.add(flight.departure);
    }

    if (to) {
      pointsByCode.set(to.code, {
        code: to.code,
        name: to.name,
        city: to.city,
        lat: to.lat,
        lng: to.lon,
      });
    } else {
      unresolvedCodes.add(flight.arrival);
    }

    if (from && to) {
      arcs.push({
        id: flight.id,
        startLat: from.lat,
        startLng: from.lon,
        endLat: to.lat,
        endLng: to.lon,
        fromCode: from.code,
        toCode: to.code,
        label: `${flight.aircraft} · ${from.code} → ${to.code} · ${formatDate(flight.flown_on)}`,
      });
    }
  }

  return {
    points: Array.from(pointsByCode.values()),
    arcs,
    unresolvedCodes: Array.from(unresolvedCodes),
  };
}

const FLIGHT_COLUMNS =
  "id, flown_on, airline, aircraft, departure, arrival, hours, notes";

/** Loads the log, still working (without ratings) if the ratings migration
 * hasn't been run on this database yet. */
async function loadFlights(supabase: Awaited<ReturnType<typeof createClient>>) {
  const result = await supabase
    .from("flights")
    .select(`${FLIGHT_COLUMNS}, rating`)
    .order("flown_on", { ascending: false })
    .returns<Flight[]>();
  // 42703 (Postgres) / PGRST204 (PostgREST): no such column.
  if (result.error?.code !== "42703" && result.error?.code !== "PGRST204") {
    return result;
  }
  const fallback = await supabase
    .from("flights")
    .select(FLIGHT_COLUMNS)
    .order("flown_on", { ascending: false })
    .returns<Omit<Flight, "rating">[]>();
  return {
    data: fallback.data?.map((flight) => ({ ...flight, rating: null })) ?? null,
    error: fallback.error,
  };
}

export default async function FlightsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [{ data: flights, error }, { data: preferences }] = await Promise.all([
    loadFlights(supabase),
    // Errors (e.g. the table not created yet) just mean no favourites.
    supabase
      .from("user_preferences")
      .select("favourite_airline, favourite_aircraft")
      .maybeSingle<Preferences>(),
  ]);

  const flying = summarizeFlying(flights ?? []);
  const favouriteAirline = preferences?.favourite_airline ?? null;
  const favouriteAircraft = preferences?.favourite_aircraft ?? null;
  const favouriteAirlineIata = findAirline(favouriteAirline)?.iata ?? null;
  const routeAirlines = [
    ...new Set(
      EXAMPLE_ROUTES.flatMap((route) => (route.airline ? [route.airline] : [])),
    ),
  ];
  const ratedFlights = (flights ?? []).filter(
    (flight) => flight.rating !== null,
  );
  const averageRating =
    ratedFlights.length > 0
      ? ratedFlights.reduce((sum, flight) => sum + (flight.rating ?? 0), 0) /
        ratedFlights.length
      : null;

  const totalHours =
    flights?.reduce((sum, flight) => sum + Number(flight.hours), 0) ?? 0;

  const { points, arcs, unresolvedCodes } = buildGlobeData(flights ?? []);

  const mediaByFlight = new Map(
    await Promise.all(
      (flights ?? []).map(
        async (flight) =>
          [
            flight.id,
            await getFlightMedia(supabase, user.id, flight.id),
          ] as const,
      ),
    ),
  );

  const thumbnailByFlight = new Map(
    await Promise.all(
      (flights ?? []).map(
        async (flight) =>
          [
            flight.id,
            await getFlightThumbnail(supabase, user.id, flight.id),
          ] as const,
      ),
    ),
  );

  const flightDetails = buildFlightDetails(
    flights ?? [],
    mediaByFlight,
    thumbnailByFlight,
  );

  return (
    <SelectionProvider>
      <PlannerProvider>
        {/* The landing page's dark ground (same tokens), which the bare globe
          needs behind it to look the same as it does there. */}
        <section className={styles.page}>
          <div className="mx-auto w-full max-w-3xl px-6 py-12">
            <CustomizableGlobe
              points={points}
              arcs={arcs}
              details={flightDetails}
              userId={user.id}
              header={
                <div className="flex flex-col gap-1">
                  <h1
                    className={`${styles.introHeading} text-3xl font-semibold`}
                  >
                    Your flights
                  </h1>
                  <p className={`${styles.featureText} text-sm`}>
                    {flights?.length ?? 0} flight
                    {flights?.length === 1 ? "" : "s"} logged &middot;{" "}
                    {totalHours.toFixed(1)} total hours
                    {flying.countries.length > 0 &&
                      ` · ${flying.countries.length} ${flying.countries.length === 1 ? "country" : "countries"}`}
                    {averageRating !== null &&
                      ` · average rating ${averageRating.toFixed(1)}/10`}
                  </p>
                  {unresolvedCodes.length > 0 && (
                    <p className={`${styles.featureText} mt-3 text-xs`}>
                      Not shown on the globe (unrecognized airport code):{" "}
                      {unresolvedCodes.join(", ")}
                    </p>
                  )}
                </div>
              }
            />
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
                    ...(flights ?? []).map((flight) => flight.aircraft),
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

          <FlightPlanner
            quickCodes={flying.topAirports}
            routes={buildSuggestionRoutes()}
            challenges={buildChallenges()}
            defaultAircraft={favouriteAircraft ?? flying.topAircraft ?? "A320"}
            favouriteAirline={
              favouriteAirline
                ? { name: favouriteAirline, iata: favouriteAirlineIata }
                : null
            }
            flownRouteKeys={flying.flownPairs}
          />

          {error && (
            <p className="text-sm text-red-600 dark:text-red-400">
              Could not load flights: {error.message}
            </p>
          )}

          <div id="log" className="flex scroll-mt-6 flex-col gap-3">
            {flights?.length === 0 && (
              <p className="text-sm text-zinc-500 dark:text-zinc-500">
                No flights logged yet. Add your first one above.
              </p>
            )}

            {flights?.map((flight) => {
              const details = flightDetails[flight.id];
              const fromCountry =
                details?.from.country ?? findAirport(flight.departure)?.country;
              const toCountry =
                details?.to.country ?? findAirport(flight.arrival)?.country;
              return (
                <FlightRow key={flight.id} id={flight.id}>
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                    <div className="flex flex-col gap-1">
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
                      {flight.notes && (
                        <p className="text-sm text-zinc-600 dark:text-zinc-400">
                          {flight.notes}
                        </p>
                      )}
                      <StopPropagation>
                        <RatingControl
                          flightId={flight.id}
                          rating={flight.rating}
                        />
                      </StopPropagation>
                    </div>
                    <StopPropagation>
                      <form action={deleteFlight.bind(null, flight.id)}>
                        <button
                          type="submit"
                          className="self-start rounded-full border border-black/[.08] px-3 py-1 text-xs font-medium text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
                        >
                          Delete
                        </button>
                      </form>
                    </StopPropagation>
                  </div>

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
      </PlannerProvider>
    </SelectionProvider>
  );
}
