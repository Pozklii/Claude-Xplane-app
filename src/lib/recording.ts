import { distanceNm } from "./geo";

// A flight's recorded route — the path actually flown — from the X-Plane
// companion (public/xplane-logger.mjs) or an uploaded GPX, KML or CSV
// file, stored in flights.recording (see supabase/migrations/
// 20261007_xplane_and_simbrief.sql). Shared by the server, which stores
// it, and the browser, which reads uploaded files and draws it.

/** [longitude, latitude, altitude in feet (MSL), or null if unknown]. */
export type TrackPoint = [number, number, number | null];

export type RecordingSummary = {
  source: "xplane" | "file";
  /** Points kept (after thinning). */
  points: number;
  /** Length of the flown path. */
  distanceNm: number;
  maxAltitudeFt: number | null;
  /** Fuel burned from blocks off to blocks on (X-Plane only). */
  fuelUsedKg?: number | null;
};

export type Recording = { summary: RecordingSummary; points: TrackPoint[] };

/** The most points kept per flight: plenty to show holds and go-arounds,
 * while keeping a flight's row small. */
export const MAX_TRACK_POINTS = 1500;

const round = (value: number, places: number) => {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
};

/** Valid points only, rounded (~1 m; whole feet). */
export function cleanTrack(raw: unknown): TrackPoint[] {
  if (!Array.isArray(raw)) return [];
  const points: TrackPoint[] = [];
  for (const entry of raw) {
    if (!Array.isArray(entry)) continue;
    const [lon, lat, alt] = entry;
    if (
      typeof lon !== "number" ||
      typeof lat !== "number" ||
      !Number.isFinite(lon) ||
      !Number.isFinite(lat) ||
      Math.abs(lat) > 90 ||
      Math.abs(lon) > 180
    ) {
      continue;
    }
    // Null Island: a sim (or file) with no position yet.
    if (lat === 0 && lon === 0) continue;
    const altitude =
      typeof alt === "number" && Number.isFinite(alt) && Math.abs(alt) < 100000
        ? Math.round(alt)
        : null;
    points.push([round(lon, 5), round(lat, 5), altitude]);
  }
  return points;
}

/** Thins a track to at most `max` points, evenly spaced, always keeping
 * the first and last. */
export function thinTrack(points: TrackPoint[], max = MAX_TRACK_POINTS) {
  if (points.length <= max) return points;
  const step = (points.length - 1) / (max - 1);
  return Array.from(
    { length: max },
    (_, i) => points[Math.round(i * step)],
  );
}

/** Length of a path, in nautical miles. */
export function trackDistanceNm(points: TrackPoint[]) {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += distanceNm(
      { lon: points[i - 1][0], lat: points[i - 1][1] },
      { lon: points[i][0], lat: points[i][1] },
    );
  }
  return total;
}

/** A recording ready to store: cleaned, thinned and summarised, or null
 * if there's no usable path (fewer than two points). */
export function buildRecording(
  raw: unknown,
  source: RecordingSummary["source"],
  extra: { fuelUsedKg?: number | null } = {},
): Recording | null {
  const cleaned = cleanTrack(raw);
  if (cleaned.length < 2) return null;
  // Measured on the full track, before thinning cuts corners.
  const distance = trackDistanceNm(cleaned);
  const points = thinTrack(cleaned);
  const altitudes = cleaned.flatMap(([, , alt]) => (alt === null ? [] : [alt]));
  const fuel = extra.fuelUsedKg;
  return {
    summary: {
      source,
      points: points.length,
      distanceNm: Math.round(distance),
      maxAltitudeFt: altitudes.length > 0 ? Math.max(...altitudes) : null,
      ...(typeof fuel === "number" && Number.isFinite(fuel) && fuel >= 0
        ? { fuelUsedKg: Math.round(fuel) }
        : {}),
    },
    points,
  };
}

const M_TO_FT = 3.28084;

/** Reads a track from a GPX, KML or CSV file's text (the browser's
 * DOMParser for the XML formats). GPX and KML altitudes are metres; a CSV
 * needs latitude and longitude columns, and may have an altitude column
 * in feet ("alt", "altitude", "alt_ft") or metres ("alt_m",
 * "elevation"). */
export function parseTrackFile(name: string, text: string): TrackPoint[] {
  const ext = name.split(".").pop()?.toLowerCase();
  if (ext === "csv" || ext === "txt") return parseCsvTrack(text);

  const doc = new DOMParser().parseFromString(text, "application/xml");
  if (doc.getElementsByTagName("parsererror").length > 0) return [];
  const points: TrackPoint[] = [];

  // GPX: track points, else route points, else waypoints.
  for (const tag of ["trkpt", "rtept", "wpt"]) {
    const nodes = doc.getElementsByTagName(tag);
    if (nodes.length === 0) continue;
    for (const node of Array.from(nodes)) {
      const ele = node.getElementsByTagName("ele")[0]?.textContent;
      points.push([
        Number(node.getAttribute("lon")),
        Number(node.getAttribute("lat")),
        ele ? Number(ele) * M_TO_FT : null,
      ]);
    }
    return cleanTrack(points);
  }

  // KML: gx:Track's "lon lat alt" coords, else LineString coordinates
  // ("lon,lat[,alt]" separated by spaces).
  const coords = doc.getElementsByTagNameNS("*", "coord");
  if (coords.length > 0) {
    for (const node of Array.from(coords)) {
      const [lon, lat, alt] = (node.textContent ?? "")
        .trim()
        .split(/\s+/)
        .map(Number);
      points.push([lon, lat, alt === undefined ? null : alt * M_TO_FT]);
    }
    return cleanTrack(points);
  }
  for (const node of Array.from(doc.getElementsByTagName("coordinates"))) {
    for (const tuple of (node.textContent ?? "").trim().split(/\s+/)) {
      const [lon, lat, alt] = tuple.split(",").map(Number);
      points.push([lon, lat, alt === undefined ? null : alt * M_TO_FT]);
    }
  }
  return cleanTrack(points);
}

function parseCsvTrack(text: string): TrackPoint[] {
  const lines = text.split(/\r?\n/).filter((line) => line.trim());
  if (lines.length < 2) return [];
  const delimiter = lines[0].includes(";") && !lines[0].includes(",") ? ";" : ",";
  const header = lines[0]
    .split(delimiter)
    .map((cell) => cell.trim().toLowerCase().replace(/["']/g, ""));
  const find = (...names: string[]) =>
    header.findIndex((cell) => names.includes(cell));
  const latCol = find("lat", "latitude");
  const lonCol = find("lon", "lng", "long", "longitude");
  const ftCol = find("alt", "altitude", "alt_ft", "altitude_ft", "altitude (ft)");
  const mCol = find("alt_m", "altitude_m", "ele", "elevation", "altitude (m)");
  if (latCol < 0 || lonCol < 0) return [];
  const points: TrackPoint[] = [];
  for (const line of lines.slice(1)) {
    const cells = line.split(delimiter).map((cell) => cell.trim());
    // (An empty cell is no altitude, not 0.)
    const number = (col: number) =>
      col >= 0 && cells[col] ? Number(cells[col]) : NaN;
    const ft = number(ftCol);
    const m = number(mCol);
    points.push([
      Number(cells[lonCol]),
      Number(cells[latCol]),
      Number.isFinite(ft) ? ft : Number.isFinite(m) ? m * M_TO_FT : null,
    ]);
  }
  return cleanTrack(points);
}
