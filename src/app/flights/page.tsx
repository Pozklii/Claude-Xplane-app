import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { deleteFlight } from "./actions";
import { NewFlightForm } from "./new-flight-form";

type Flight = {
  id: string;
  flown_on: string;
  aircraft: string;
  departure: string;
  arrival: string;
  hours: number;
  notes: string | null;
};

export default async function FlightsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: flights, error } = await supabase
    .from("flights")
    .select("id, flown_on, aircraft, departure, arrival, hours, notes")
    .order("flown_on", { ascending: false })
    .returns<Flight[]>();

  const totalHours =
    flights?.reduce((sum, flight) => sum + Number(flight.hours), 0) ?? 0;

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-16">
      <div className="flex flex-col gap-1">
        <h1 className="text-3xl font-semibold text-black dark:text-zinc-50">
          Your flights
        </h1>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          {flights?.length ?? 0} flight{flights?.length === 1 ? "" : "s"}{" "}
          logged &middot; {totalHours.toFixed(1)} total hours
        </p>
      </div>

      <NewFlightForm />

      {error && (
        <p className="text-sm text-red-600 dark:text-red-400">
          Could not load flights: {error.message}
        </p>
      )}

      <div className="flex flex-col gap-3">
        {flights?.length === 0 && (
          <p className="text-sm text-zinc-500 dark:text-zinc-500">
            No flights logged yet. Add your first one above.
          </p>
        )}

        {flights?.map((flight) => (
          <div
            key={flight.id}
            className="flex flex-col gap-2 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145] sm:flex-row sm:items-center sm:justify-between"
          >
            <div className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-sm font-medium text-black dark:text-zinc-50">
                <span>{flight.flown_on}</span>
                <span className="text-zinc-400">&middot;</span>
                <span>{flight.aircraft}</span>
                <span className="text-zinc-400">&middot;</span>
                <span>
                  {flight.departure} &rarr; {flight.arrival}
                </span>
                <span className="text-zinc-400">&middot;</span>
                <span>{Number(flight.hours).toFixed(1)}h</span>
              </div>
              {flight.notes && (
                <p className="text-sm text-zinc-600 dark:text-zinc-400">
                  {flight.notes}
                </p>
              )}
            </div>
            <form action={deleteFlight.bind(null, flight.id)}>
              <button
                type="submit"
                className="self-start rounded-full border border-black/[.08] px-3 py-1 text-xs font-medium text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
              >
                Delete
              </button>
            </form>
          </div>
        ))}
      </div>
    </div>
  );
}
