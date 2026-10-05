import { createClient } from "@/lib/supabase/server";
import { conditionsLabel, shortTime } from "@/lib/flight-fields";
import { loadFlights } from "../../flights/flights-data";

// A spreadsheet-safe CSV cell: quoted when it holds a comma, quote or line
// break, and with a leading = + - @ neutralised so a spreadsheet doesn't
// run it as a formula.
function cell(value: string | number | null | undefined) {
  if (value === null || value === undefined) return "";
  let text = String(value);
  if (/^[=+\-@\t\r]/.test(text) && typeof value === "string") text = `'${text}`;
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

const COLUMNS = [
  "Date",
  "From",
  "To",
  "Airline",
  "Aircraft",
  "Hours",
  "Takeoff",
  "Landing",
  "Landing rate (fpm)",
  "Conditions",
  "Weather",
  "Flight rating",
  "Notes",
];

// GET /log/export: the signed-in user's whole Flight Log as a CSV file,
// oldest flight first.
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return new Response("Sign in to download your Flight Log.", {
      status: 401,
    });
  }

  const { data, error } = await loadFlights(supabase);
  if (error) {
    return new Response(`Could not load flights: ${error.message}`, {
      status: 500,
    });
  }

  const rows = [...(data ?? [])]
    .sort((a, b) => a.flown_on.localeCompare(b.flown_on))
    .map((f) =>
      [
        f.flown_on,
        f.departure,
        f.arrival,
        f.airline,
        f.aircraft,
        Number(f.hours).toFixed(1),
        shortTime(f.takeoff_time),
        shortTime(f.landing_time),
        f.landing_rate_fpm,
        conditionsLabel(f.conditions),
        f.weather,
        f.rating,
        f.notes,
      ]
        .map(cell)
        .join(","),
    );
  // A byte-order mark so Excel reads it as UTF-8 (accents, the arrow…).
  const csv = "﻿" + [COLUMNS.join(","), ...rows].join("\r\n") + "\r\n";
  const date = new Date().toISOString().slice(0, 10);

  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="flight-log-${date}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
