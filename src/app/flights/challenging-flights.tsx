"use client";

import { useEffect, useState } from "react";
import type { WeatherChallengeEntry } from "@/lib/challenging-airports";
import { AirlineLogo } from "./airline-logo";
import { AirportLink } from "./airport-link";
import { Flag } from "./flag";
import type { ChallengeCardData } from "./planner-data";
import { usePlanner } from "./planner-context";

const M_PER_FT = 0.3048;

function formatHours(hours: number) {
  const minutes = Math.round(hours * 60);
  return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, "0")}m`;
}

function Difficulty({ value }: { value: number }) {
  return (
    <span
      className="inline-flex gap-0.5"
      role="img"
      aria-label={`Difficulty ${value} of 5`}
      title={`Difficulty ${value}/5`}
    >
      {[1, 2, 3, 4, 5].map((n) => (
        <span
          key={n}
          className={`h-2 w-2 rounded-full ${n <= value ? "bg-red-500" : "bg-zinc-300 dark:bg-zinc-700"}`}
        />
      ))}
    </span>
  );
}

type LiveState =
  | { status: "loading" }
  | { status: "error" }
  | { status: "ok"; entries: WeatherChallengeEntry[] };

function ChallengingNow() {
  const { openAirport } = usePlanner();
  const [live, setLive] = useState<LiveState>({ status: "loading" });

  useEffect(() => {
    let cancelled = false;
    fetch("/api/weather-challenges")
      .then(async (res) => {
        const body = (await res.json()) as {
          entries?: WeatherChallengeEntry[];
        };
        if (cancelled) return;
        setLive(
          res.ok && body.entries
            ? { status: "ok", entries: body.entries }
            : { status: "error" },
        );
      })
      .catch(() => {
        if (!cancelled) setLive({ status: "error" });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
        Challenging right now
      </h3>
      <p className="text-xs text-zinc-500">
        Airports where the latest METAR means strong or gusty winds, big
        crosswinds on the best runway, low cloud or visibility, or hazardous
        weather — load it into your sim and fly it in live weather.
      </p>
      {live.status === "loading" && (
        <p className="text-sm text-zinc-500">Checking live weather…</p>
      )}
      {live.status === "error" && (
        <p className="text-sm text-zinc-500">
          Live weather is unavailable right now.
        </p>
      )}
      {live.status === "ok" && live.entries.length === 0 && (
        <p className="text-sm text-zinc-500">
          Nothing notable right now — calm weather across the watchlist.
        </p>
      )}
      {live.status === "ok" && live.entries.length > 0 && (
        <ul className="flex flex-col gap-2">
          {live.entries.map((entry) => (
            <li key={entry.icao}>
              <button
                type="button"
                onClick={() => openAirport(entry.icao)}
                className="flex w-full flex-col gap-1 rounded-xl border border-black/[.08] p-3 text-left transition-colors hover:bg-black/[.02] dark:border-white/[.145] dark:hover:bg-white/[.03]"
              >
                <span className="flex flex-wrap items-center gap-2 text-sm">
                  <Flag country={entry.country} />
                  <span className="font-semibold text-black dark:text-zinc-50">
                    {entry.icao}
                  </span>
                  <span className="text-zinc-600 dark:text-zinc-400">
                    {entry.name}
                  </span>
                  {entry.category && (
                    <span className="rounded bg-zinc-200 px-1.5 text-[11px] font-bold text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                      {entry.category}
                    </span>
                  )}
                </span>
                <span className="flex flex-wrap gap-1">
                  {entry.reasons.map((reason) => (
                    <span
                      key={reason}
                      className="rounded-full bg-red-100 px-2 py-0.5 text-xs text-red-800 dark:bg-red-950/50 dark:text-red-300"
                    >
                      {reason}
                    </span>
                  ))}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** Live weather challenges plus airports known for terrain, runways and
 * approaches that test a pilot, each with a real route in to try. */
export function ChallengingFlights({
  challenges,
}: {
  challenges: ChallengeCardData[];
}) {
  return (
    <div className="flex flex-col gap-6">
      <ChallengingNow />

      <section className="flex flex-col gap-2">
        <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
          Famous challenging approaches
        </h3>
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {challenges.map((challenge) => (
            <li
              key={challenge.icao}
              className="flex flex-col gap-2 rounded-xl border border-black/[.08] p-3 dark:border-white/[.145]"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex flex-col gap-0.5">
                  <span className="flex items-center gap-1.5 text-sm">
                    <AirportLink
                      airport={{
                        code: challenge.icao,
                        city: challenge.city,
                        country: challenge.country,
                      }}
                    />
                    <span className="text-zinc-600 dark:text-zinc-400">
                      {challenge.city}
                    </span>
                  </span>
                  <span className="text-xs text-zinc-500">
                    {challenge.name}
                  </span>
                </div>
                <Difficulty value={challenge.difficulty} />
              </div>
              <div className="flex flex-wrap gap-1">
                {challenge.kinds.map((kind) => (
                  <span
                    key={kind}
                    className="rounded-full bg-zinc-100 px-2 py-0.5 text-[11px] text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
                  >
                    {kind}
                  </span>
                ))}
              </div>
              <p className="text-sm text-zinc-700 dark:text-zinc-300">
                {challenge.why}
              </p>
              <p className="text-xs text-zinc-500">
                {challenge.elevationFt !== null &&
                  `Elevation ${challenge.elevationFt.toLocaleString("en-US")} ft (${Math.round(challenge.elevationFt * M_PER_FT).toLocaleString("en-US")} m)`}
                {challenge.elevationFt !== null && challenge.longestRunwayFt
                  ? " · "
                  : ""}
                {challenge.longestRunwayFt &&
                  `Longest runway ${challenge.longestRunwayFt.toLocaleString("en-US")} ft (${Math.round(challenge.longestRunwayFt * M_PER_FT).toLocaleString("en-US")} m)`}
              </p>
              {challenge.route && (
                <div className="mt-auto flex items-center gap-2 border-t border-black/[.06] pt-2 text-xs text-zinc-600 dark:border-white/[.08] dark:text-zinc-400">
                  <AirlineLogo
                    name={challenge.route.airline ?? "Private"}
                    iata={challenge.route.airlineIata}
                  />
                  <span className="flex flex-wrap items-center gap-1">
                    Try it:
                    <AirportLink airport={challenge.route.from} />
                    &rarr; {challenge.iata} &middot;{" "}
                    {challenge.route.airline ?? "Private"} &middot;{" "}
                    {challenge.route.aircraft} &middot;{" "}
                    {challenge.route.distanceNm.toLocaleString("en-US")} nm, ~
                    {formatHours(challenge.route.hours)}
                  </span>
                </div>
              )}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
