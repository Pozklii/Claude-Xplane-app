"use client";

import { Flag } from "./flag";
import { usePlanner } from "./planner-context";

/** An airport code (with its country's flag) that opens the airport panel. */
export function AirportLink({
  airport,
}: {
  airport: { code: string; city: string; country: string | null };
}) {
  const { openAirport } = usePlanner();
  return (
    <button
      type="button"
      onClick={() => openAirport(airport.code)}
      title={`${airport.city}: live METAR and airport facts`}
      className="inline-flex items-center gap-1 rounded font-semibold text-black underline-offset-2 hover:underline dark:text-zinc-50"
    >
      <Flag country={airport.country} />
      {airport.code}
    </button>
  );
}
