"use client";

import { usePathname, useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";
import {
  LOG_SORTS,
  type LogFilterOptions,
  type LogQuery,
} from "@/lib/log-query";

const controlClass =
  "min-w-0 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";

// The Flight Log's search, filters and sort, kept in the page's address
// (?q=…&aircraft=…&sort=…) so a filtered view can be reloaded, bookmarked
// or shared; the page filters the list on the server.
export function LogFilters({
  query,
  options,
  shown,
  total,
}: {
  query: LogQuery;
  options: LogFilterOptions;
  shown: number;
  total: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  const [search, setSearch] = useState(query.q);
  const typing = useRef<number>(0);

  const apply = (changes: Partial<LogQuery>) => {
    const next = { ...query, q: search, ...changes };
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(next)) {
      if (value && !(key === "sort" && value === "newest")) {
        params.set(key, value);
      }
    }
    const qs = params.toString();
    startTransition(() => {
      router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    });
  };

  const filtered =
    query.q || query.aircraft || query.airline || query.airport || query.year;

  const select = (
    key: "aircraft" | "airline" | "airport" | "year",
    label: string,
    values: string[],
  ) =>
    values.length > 0 && (
      <select
        aria-label={label}
        value={query[key]}
        onChange={(event) => apply({ [key]: event.target.value })}
        className={controlClass}
      >
        <option value="">Any {label.toLowerCase()}</option>
        {values.map((value) => (
          <option key={value} value={value}>
            {value}
          </option>
        ))}
      </select>
    );

  return (
    <section
      aria-label="Search and filter flights"
      className="flex flex-col gap-3 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]"
    >
      <div className="flex flex-col gap-2 sm:flex-row">
        <input
          type="search"
          value={search}
          onChange={(event) => {
            const value = event.target.value;
            setSearch(value);
            // Searches once typing pauses.
            window.clearTimeout(typing.current);
            typing.current = window.setTimeout(() => apply({ q: value }), 350);
          }}
          placeholder="Search airports, cities, aircraft, airlines, notes…"
          aria-label="Search flights"
          className={`${controlClass} flex-1`}
        />
        <select
          aria-label="Sort by"
          value={query.sort}
          onChange={(event) =>
            apply({ sort: event.target.value as LogQuery["sort"] })
          }
          className={controlClass}
        >
          {LOG_SORTS.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {select("aircraft", "Aircraft", options.aircraft)}
        {select("airline", "Airline", options.airlines)}
        {select("airport", "Airport", options.airports)}
        {select("year", "Year", options.years)}
      </div>
      <p
        className="flex flex-wrap items-center gap-2 text-xs text-zinc-500"
        aria-live="polite"
      >
        <span className="tabular-nums">
          {pending
            ? "Updating…"
            : filtered
              ? `Showing ${shown} of ${total} flight${total === 1 ? "" : "s"}`
              : `${total} flight${total === 1 ? "" : "s"}`}
        </span>
        {filtered && (
          <button
            type="button"
            onClick={() => {
              setSearch("");
              window.clearTimeout(typing.current);
              apply({
                q: "",
                aircraft: "",
                airline: "",
                airport: "",
                year: "",
              });
            }}
            className="font-medium text-zinc-700 underline-offset-4 hover:underline dark:text-zinc-300"
          >
            Clear filters
          </button>
        )}
      </p>
    </section>
  );
}
