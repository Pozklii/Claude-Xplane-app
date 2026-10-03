import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { fetchRoute } from "@/lib/live-traffic";

const CALLSIGN = /^[A-Z0-9]{2,8}$/;

// GET /api/flight-route?callsign=BAW117&lat=51.2&lon=-20.4 → the route that
// callsign is scheduled to fly ({ route: null } when it isn't known). The
// aircraft's position helps adsb.lol pick between same-numbered flights.
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return Response.json({ error: "Sign in to look up routes." }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const callsign = (params.get("callsign") ?? "").trim().toUpperCase();
  const lat = Number(params.get("lat"));
  const lon = Number(params.get("lon"));
  if (!CALLSIGN.test(callsign) || !Number.isFinite(lat) || !Number.isFinite(lon)) {
    return Response.json({ error: "A callsign and position are required." }, { status: 400 });
  }

  try {
    return Response.json({ route: await fetchRoute(callsign, lat, lon) });
  } catch {
    return Response.json(
      { error: "The route lookup is unavailable right now." },
      { status: 502 },
    );
  }
}
