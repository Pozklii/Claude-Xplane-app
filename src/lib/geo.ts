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
