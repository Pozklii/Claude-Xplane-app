import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { createClient } from "@/lib/supabase/server";
import { findAirline } from "@/lib/airlines";
import { findAirport } from "@/lib/airports";
import { distanceNm } from "@/lib/geo";
import { formatDate } from "@/lib/dates";
import {
  conditionsLabel,
  EXTRA_COLUMNS,
  NO_EXTRAS,
  timeMinutes,
  type FlightExtras,
} from "@/lib/flight-fields";
import type { GlobeArc, GlobePoint } from "./flight-globe";
import type { FlightDetails } from "./selected-flight-card";
import { thumbnailFolder } from "./thumbnail-path";
import type { MediaItem } from "./flight-media";

// Loading a signed-in user's flights, shared by the Flight Map (/flights)
// and Flight Log (/log) pages: the flights themselves, each one's uploaded
// media and chosen thumbnail, the summary card's details, and the globe's
// points and routes.

export type Flight = {
  id: string;
  flown_on: string;
  airline: string | null;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
  rating: number | null;
} & FlightExtras;

export type Preferences = {
  favourite_airline: string | null;
  favourite_aircraft: string | null;
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

export function buildFlightDetails(
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
      times:
        flight.takeoff_time || flight.landing_time
          ? {
              takeoff: timeMinutes(flight.takeoff_time) ?? undefined,
              landing: timeMinutes(flight.landing_time) ?? undefined,
            }
          : undefined,
      landingRateFpm: flight.landing_rate_fpm,
      conditions: conditionsLabel(flight.conditions),
      weather: flight.weather,
      thumbnailUrl: custom?.url ?? images[0]?.url ?? null,
      customThumbnailPath: custom?.path ?? null,
      images: images.map(({ path, name, url }) => ({ path, name, url })),
    };
  }
  return details;
}

export function buildGlobeData(flights: Flight[]) {
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

// 42703 (Postgres) / PGRST204 (PostgREST): no such column — a migration
// not yet run on this database.
const missingColumn = (code: string | undefined) =>
  code === "42703" || code === "PGRST204";

/** Loads the log, still working (without the extra details, and then
 * without ratings) on a database the newer migrations haven't been run on
 * yet. */
export async function loadFlights(
  supabase: Awaited<ReturnType<typeof createClient>>,
) {
  const query = (columns: string) =>
    supabase
      .from("flights")
      .select(columns)
      .order("flown_on", { ascending: false })
      .returns<Partial<Flight>[]>();
  let result = await query(`${FLIGHT_COLUMNS}, rating, ${EXTRA_COLUMNS}`);
  if (missingColumn(result.error?.code)) {
    result = await query(`${FLIGHT_COLUMNS}, rating`);
  }
  if (missingColumn(result.error?.code)) {
    result = await query(FLIGHT_COLUMNS);
  }
  return {
    data:
      result.data?.map(
        (flight) => ({ rating: null, ...NO_EXTRAS, ...flight }) as Flight,
      ) ?? null,
    error: result.error,
  };
}

/** The user's flights with everything the pages show about them. */
export async function loadFlightLog(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
) {
  const { data, error } = await loadFlights(supabase);
  const flights = data ?? [];
  const [media, thumbnails] = await Promise.all([
    Promise.all(
      flights.map(
        async (flight) =>
          [
            flight.id,
            await getFlightMedia(supabase, userId, flight.id),
          ] as const,
      ),
    ),
    Promise.all(
      flights.map(
        async (flight) =>
          [
            flight.id,
            await getFlightThumbnail(supabase, userId, flight.id),
          ] as const,
      ),
    ),
  ]);
  const mediaByFlight = new Map(media);
  return {
    flights,
    error,
    mediaByFlight,
    details: buildFlightDetails(flights, mediaByFlight, new Map(thumbnails)),
  };
}

/** Totals for the pages' headers. */
export function flightTotals(flights: Flight[]) {
  const rated = flights.filter((flight) => flight.rating !== null);
  return {
    count: flights.length,
    totalHours: flights.reduce((sum, flight) => sum + Number(flight.hours), 0),
    averageRating:
      rated.length > 0
        ? rated.reduce((sum, flight) => sum + (flight.rating ?? 0), 0) /
          rated.length
        : null,
  };
}
