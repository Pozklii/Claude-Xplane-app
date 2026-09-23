import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { findAirport } from "@/lib/airports";
import { deleteFlight } from "./actions";
import { NewFlightForm } from "./new-flight-form";
import { type GlobeArc, type GlobePoint } from "./flight-globe";
import { CustomizableGlobe } from "./customizable-globe";
import type { FlightDetails } from "./selected-flight-card";
import { thumbnailFolder } from "./thumbnail-path";
import { FlightMedia, type MediaItem } from "./flight-media";
import { FlightRow } from "./flight-row";
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

const EARTH_RADIUS_NM = 3440.065;

// Great-circle distance between two airports (haversine), in nautical miles.
function distanceNm(
  from: { lat: number; lon: number },
  to: { lat: number; lon: number },
) {
  const rad = Math.PI / 180;
  const dLat = (to.lat - from.lat) * rad;
  const dLon = (to.lon - from.lon) * rad;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(from.lat * rad) * Math.cos(to.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_NM * Math.asin(Math.min(1, Math.sqrt(a)));
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
      aircraft: flight.aircraft,
      from: { code: from.code, city: from.city },
      to: { code: to.code, city: to.city },
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
    .select("id, flown_on, airline, aircraft, departure, arrival, hours, notes")
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
                <h1 className={`${styles.introHeading} text-3xl font-semibold`}>
                  Your flights
                </h1>
                <p className={`${styles.featureText} text-sm`}>
                  {flights?.length ?? 0} flight
                  {flights?.length === 1 ? "" : "s"} logged &middot;{" "}
                  {totalHours.toFixed(1)} total hours
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
      </div>
    </SelectionProvider>
  );
}
