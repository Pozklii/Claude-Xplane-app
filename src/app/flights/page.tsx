import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { findAirport } from "@/lib/airports";
import { deleteFlight } from "./actions";
import { NewFlightForm } from "./new-flight-form";
import { FlightGlobe, type GlobeArc, type GlobePoint } from "./flight-globe";
import { FlightMedia, type MediaItem } from "./flight-media";
import { FlightRow } from "./flight-row";
import { SelectionProvider } from "./selection-context";
import { StopPropagation } from "./stop-propagation";

type Flight = {
  id: string;
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
};

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
        label: `${flight.aircraft} · ${from.code} → ${to.code} · ${flight.flown_on}`,
      });
    }
  }

  return {
    points: Array.from(pointsByCode.values()),
    arcs,
    unresolvedCodes: Array.from(unresolvedCodes),
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

  const { data: flights, error } = await supabase
    .from("flights")
    .select(
      "id, flown_on, airline, aircraft, departure, arrival, hours, notes",
    )
    .order("flown_on", { ascending: false })
    .returns<Flight[]>();

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

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-16">
      <div className="flex flex-col gap-1">
        <h1 className="text-3xl font-semibold text-black dark:text-zinc-50">
          Your flights
        </h1>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {flights?.length ?? 0} flight{flights?.length === 1 ? "" : "s"}{" "}
          logged &middot; {totalHours.toFixed(1)} total hours
        </p>
      </div>

      <SelectionProvider>
        <div className="flex flex-col gap-2">
          <FlightGlobe points={points} arcs={arcs} />
          {unresolvedCodes.length > 0 && (
            <p className="text-xs text-zinc-500 dark:text-zinc-500">
              Not shown on the globe (unrecognized airport code):{" "}
              {unresolvedCodes.join(", ")}
            </p>
          )}
        </div>

        <NewFlightForm />

        {error && (
          <p className="text-sm text-red-600 dark:text-red-400">
            Could not load flights: {error.message}
          </p>
        )}

        <div className="flex flex-col gap-3">
          {flights?.length === 0 && (
            <p className="text-sm text-zinc-500 dark:text-zinc-500">
              No flights logged yet. Add your first one above.
            </p>
          )}

          {flights?.map((flight) => (
            <FlightRow key={flight.id} id={flight.id}>
              <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                <div className="flex flex-col gap-1">
                  <div className="flex flex-wrap items-center gap-2 text-sm font-medium text-black dark:text-zinc-50">
                    <span>{flight.flown_on}</span>
                    <span className="text-zinc-400">&middot;</span>
                    {flight.airline && (
                      <>
                        <span>{flight.airline}</span>
                        <span className="text-zinc-400">&middot;</span>
                      </>
                    )}
                    <span>{flight.aircraft}</span>
                    <span className="text-zinc-400">&middot;</span>
                    <span>
                      {flight.departure} &rarr; {flight.arrival}
                    </span>
                    <span className="text-zinc-400">&middot;</span>
                    <span>{Number(flight.hours).toFixed(1)}h</span>
                  </div>
                  {flight.notes && (
                    <p className="text-sm text-zinc-600 dark:text-zinc-400">
                      {flight.notes}
                    </p>
                  )}
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
          ))}
        </div>
      </SelectionProvider>
    </div>
  );
}
