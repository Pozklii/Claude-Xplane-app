import type { NextRequest } from "next/server";
import { fetchMetars } from "@/lib/metar-source";

const MAX_STATIONS = 10;

// GET /api/metar?ids=EGLL,KSFO → { metars: { EGLL: Metar, ... } }
export async function GET(request: NextRequest) {
  const ids = (request.nextUrl.searchParams.get("ids") ?? "")
    .toUpperCase()
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);

  if (
    ids.length === 0 ||
    ids.length > MAX_STATIONS ||
    !ids.every((id) => /^[A-Z0-9]{3,4}$/.test(id))
  ) {
    return Response.json(
      { error: `Pass 1–${MAX_STATIONS} ICAO codes as ?ids=EGLL,KSFO` },
      { status: 400 },
    );
  }

  try {
    return Response.json({ metars: await fetchMetars(ids) });
  } catch {
    return Response.json(
      { error: "The weather service is unavailable right now." },
      { status: 502 },
    );
  }
}
