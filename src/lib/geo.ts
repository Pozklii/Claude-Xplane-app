const EARTH_RADIUS_NM = 3440.065;

/** Great-circle distance between two points (haversine), in nautical miles. */
export function distanceNm(
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

/** Initial true course from one point towards another along the great
 * circle, in degrees (0-360). */
export function initialCourse(
  from: { lat: number; lon: number },
  to: { lat: number; lon: number },
) {
  const rad = Math.PI / 180;
  const f1 = from.lat * rad;
  const f2 = to.lat * rad;
  const dLon = (to.lon - from.lon) * rad;
  const y = Math.sin(dLon) * Math.cos(f2);
  const x =
    Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dLon);
  return (Math.atan2(y, x) / rad + 360) % 360;
}
