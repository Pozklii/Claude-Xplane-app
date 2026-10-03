import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { fetchLiveTraffic, LIVE_RADIUS_NM } from "@/lib/live-traffic";

// Snapping the query point to a half-degree grid lets nearby views share
// one cached upstream request (and keeps this from being an open proxy for
// arbitrary coordinates).
const snap = (value: number) => Math.round(value * 2) / 2;

// GET /api/live-traffic?lat=51.5&lon=-0.5 → airborne airline traffic within
// 250 nm of that point, from adsb.lol. Signed-in users only.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return Response.json({ error: "Sign in to see live traffic." }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const lat = Number(params.get("lat"));
  const lon = Number(params.get("lon"));
  if (
    !params.has("lat") ||
    !params.has("lon") ||
    !Number.isFinite(lat) ||
    !Number.isFinite(lon) ||
    Math.abs(lat) > 90 ||
    Math.abs(lon) > 180
  ) {
    return Response.json({ error: "lat and lon must be valid coordinates." }, { status: 400 });
  }

  const centre = { lat: snap(lat), lon: snap(lon) };
  try {
    const { aircraft, generatedAt } = await fetchLiveTraffic(centre.lat, centre.lon);
    return Response.json({ aircraft, generatedAt, centre, radiusNm: LIVE_RADIUS_NM });
  } catch {
    return Response.json(
      { error: "The live traffic feed is unavailable right now." },
      { status: 502 },
    );
  }
}
