"use client";

import { useRouteColor } from "./route-color";
import { SelectedFlightCard, type FlightDetails } from "./selected-flight-card";

// The Flight Log page's summary of the flight picked in the list, under the
// page's heading: the same card as on the Flight Map page, in the user's
// route colour, with a link to the flight on the map. Choosing a flight
// further down the list scrolls back up to it.
export function LogSummary({
  details,
  userId,
}: {
  details: Record<string, FlightDetails>;
  userId: string;
}) {
  const [arcColor] = useRouteColor();
  return (
    <SelectedFlightCard
      details={details}
      arcColor={arcColor}
      userId={userId}
      prominent
      mapLink
      // Nothing until a flight is picked (the list says how).
      emptyHint={null}
    />
  );
}
