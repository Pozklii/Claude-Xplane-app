"use client";

import { useEffect, useState } from "react";
import {
  describeWeather,
  runwayWinds,
  type FlightCategory,
  type Metar,
} from "@/lib/metar";
import { lookupAirport, type AirportLookup } from "./airport-actions";
import { Flag } from "./flag";
import { usePlanner } from "./planner-context";

const M_PER_FT = 0.3048;
const KM_PER_SM = 1.609344;

const formatFt = (ft: number) =>
  `${ft.toLocaleString("en-US")} ft (${Math.round(ft * M_PER_FT).toLocaleString("en-US")} m)`;

const CATEGORY_STYLES: Record<FlightCategory, string> = {
  VFR: "bg-emerald-600 text-white",
  MVFR: "bg-blue-600 text-white",
  IFR: "bg-red-600 text-white",
  LIFR: "bg-fuchsia-600 text-white",
};

const CATEGORY_HINTS: Record<FlightCategory, string> = {
  VFR: "Visual flight rules",
  MVFR: "Marginal VFR",
  IFR: "Instrument flight rules",
  LIFR: "Low IFR",
};

function formatWind(metar: Metar) {
  const wind = metar.wind;
  if (!wind) return "Not reported";
  if (wind.speedKt === 0) return "Calm";
  const direction =
    wind.directionDeg === null
      ? "Variable"
      : `${String(wind.directionDeg).padStart(3, "0")}°`;
  let text = `${direction} at ${wind.speedKt} kt`;
  if (wind.gustKt) text += `, gusting ${wind.gustKt} kt`;
  if (wind.varyingFromDeg !== null && wind.varyingToDeg !== null) {
    text += ` (varying ${wind.varyingFromDeg}°–${wind.varyingToDeg}°)`;
  }
  return text;
}

function formatVisibility(metar: Metar) {
  if (metar.cavok) return "CAVOK — 10 km or more, no significant cloud";
  const sm = metar.visibilitySm;
  if (sm === null) return "Not reported";
  if (sm >= 10) return "10 km or more";
  return `${sm < 1 ? sm.toFixed(2) : sm.toFixed(1)} SM (${(sm * KM_PER_SM).toFixed(1)} km)`;
}

function formatClouds(metar: Metar) {
  if (metar.clouds.length === 0) {
    return metar.clear ? "Clear" : "None reported";
  }
  const names = {
    FEW: "Few",
    SCT: "Scattered",
    BKN: "Broken",
    OVC: "Overcast",
    VV: "Sky obscured, vertical visibility",
  };
  return metar.clouds
    .map(
      (layer) =>
        `${names[layer.cover]} ${layer.baseFt !== null ? `${layer.baseFt.toLocaleString("en-US")} ft` : ""}${layer.convective ? ` (${layer.convective === "CB" ? "cumulonimbus" : "towering cumulus"})` : ""}`,
    )
    .join(", ");
}

function formatObserved(observed: string | null) {
  const m = observed?.match(/^(\d{2})(\d{2})(\d{2})Z$/);
  return m
    ? `${m[2]}:${m[3]} UTC on the ${Number(m[1])}${ordinal(Number(m[1]))}`
    : null;
}

function ordinal(n: number) {
  if (n % 100 >= 11 && n % 100 <= 13) return "th";
  return ["th", "st", "nd", "rd"][n % 10] ?? "th";
}

function Fact({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-[11px] font-medium uppercase tracking-wide text-zinc-500">
        {label}
      </dt>
      <dd className="text-sm text-black dark:text-zinc-100">{children}</dd>
    </div>
  );
}

type WeatherState =
  | { key: string; status: "ok"; metar: Metar }
  | { key: string; status: "none" | "error" };

function WeatherPanel({ airport }: { airport: AirportLookup }) {
  const station = airport.icao ?? airport.code;
  const [refreshCount, setRefreshCount] = useState(0);
  const [weather, setWeather] = useState<WeatherState | null>(null);
  const key = `${station}:${refreshCount}`;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(
          `/api/metar?ids=${encodeURIComponent(station)}`,
        );
        const body = (await res.json()) as { metars?: Record<string, Metar> };
        if (cancelled) return;
        const metar = body.metars?.[station];
        setWeather(
          !res.ok
            ? { key, status: "error" }
            : metar
              ? { key, status: "ok", metar }
              : { key, status: "none" },
        );
      } catch {
        if (!cancelled) setWeather({ key, status: "error" });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [key, station]);

  const current = weather?.key === key ? weather : null;
  const bestRunway =
    current?.status === "ok"
      ? runwayWinds(
          current.metar.wind,
          airport.runways.map((runway) => runway.name),
        )[0]
      : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-xl border border-black/[.08] p-4 dark:border-white/[.145]">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
          Live METAR &middot; {station}
        </h3>
        <button
          type="button"
          onClick={() => setRefreshCount((n) => n + 1)}
          disabled={!current}
          className="rounded-full border border-black/[.08] px-3 py-1 text-xs text-zinc-600 transition-colors hover:bg-black/[.04] disabled:opacity-50 dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
        >
          Refresh
        </button>
      </div>

      {!current && (
        <p className="text-sm text-zinc-500">Fetching the latest report…</p>
      )}
      {current?.status === "error" && (
        <p className="text-sm text-zinc-500">
          Live weather is unavailable right now. Try refreshing in a minute.
        </p>
      )}
      {current?.status === "none" && (
        <p className="text-sm text-zinc-500">
          No recent METAR for {station} — many smaller airfields don&apos;t
          report one.
        </p>
      )}
      {current?.status === "ok" && (
        <>
          <div className="flex flex-wrap items-center gap-2">
            {current.metar.category && (
              <span
                title={CATEGORY_HINTS[current.metar.category]}
                className={`rounded px-2 py-0.5 text-xs font-bold ${CATEGORY_STYLES[current.metar.category]}`}
              >
                {current.metar.category}
              </span>
            )}
            {formatObserved(current.metar.observed) && (
              <span className="text-xs text-zinc-500">
                Observed {formatObserved(current.metar.observed)}
              </span>
            )}
          </div>
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Fact label="Wind">{formatWind(current.metar)}</Fact>
            <Fact label="Visibility">{formatVisibility(current.metar)}</Fact>
            <Fact label="Cloud">{formatClouds(current.metar)}</Fact>
            <Fact label="Weather">
              {current.metar.weather.length > 0
                ? current.metar.weather.map(describeWeather).join(", ")
                : "Nothing significant"}
            </Fact>
            <Fact label="Temperature / dewpoint">
              {current.metar.temperatureC !== null
                ? `${current.metar.temperatureC}°C / ${current.metar.dewpointC ?? "—"}°C`
                : "Not reported"}
            </Fact>
            <Fact label="Pressure (QNH)">
              {current.metar.altimeterHpa !== null
                ? `${current.metar.altimeterHpa} hPa (${current.metar.altimeterInHg?.toFixed(2)} inHg)`
                : "Not reported"}
            </Fact>
            {bestRunway && (
              <Fact label="Best-aligned runway">
                {bestRunway.runwayEnd}: {Math.max(0, bestRunway.headwindKt)} kt
                headwind, {bestRunway.crosswindKt} kt crosswind
                {current.metar.wind?.gustKt ? " (in the gusts)" : ""}
              </Fact>
            )}
          </dl>
          <code className="block overflow-x-auto rounded-lg bg-zinc-100 px-3 py-2 text-xs text-zinc-700 dark:bg-zinc-900 dark:text-zinc-300">
            {current.metar.raw}
          </code>
        </>
      )}
      <p className="text-[11px] text-zinc-500">
        From NOAA&apos;s Aviation Weather Center. For flight simulation only —
        not for real-world flight planning.
      </p>
    </section>
  );
}

function AirportDetails({ airport }: { airport: AirportLookup }) {
  const country = airport.country;
  const longest = airport.runways[0];
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-start gap-3">
        <Flag
          country={country?.code}
          label={country?.name}
          className="mt-1 text-2xl"
        />
        <div className="flex flex-col gap-0.5">
          <h3 className="text-lg font-semibold text-black dark:text-zinc-50">
            {airport.name}
          </h3>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            {airport.city}
            {country ? `, ${country.name}` : ""} &middot;{" "}
            {[airport.icao, airport.iata].filter(Boolean).join(" / ")}
          </p>
        </div>
      </div>

      {airport.challenge && (
        <p className="rounded-lg border border-amber-300/60 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-500/30 dark:bg-amber-950/30 dark:text-amber-200">
          <strong>Challenging airport:</strong> {airport.challenge}
        </p>
      )}

      <WeatherPanel key={airport.code} airport={airport} />

      <section className="flex flex-col gap-3">
        <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
          Airport facts
        </h3>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {airport.typeLabel && <Fact label="Type">{airport.typeLabel}</Fact>}
          {airport.elevationFt !== null && (
            <Fact label="Elevation">{formatFt(airport.elevationFt)}</Fact>
          )}
          <Fact label="Scheduled flights">
            {airport.scheduledService ? "Yes" : "No"}
          </Fact>
          <Fact label="Runways">{airport.runways.length || "None listed"}</Fact>
          {longest?.lengthFt && (
            <Fact label="Longest runway">
              {longest.name} &middot; {formatFt(longest.lengthFt)}
            </Fact>
          )}
          <Fact label="Position">
            {airport.lat.toFixed(4)}, {airport.lon.toFixed(4)}
          </Fact>
        </dl>
        {airport.runways.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-[11px] uppercase tracking-wide text-zinc-500">
                <tr>
                  <th className="py-1 pr-4 font-medium">Runway</th>
                  <th className="py-1 pr-4 font-medium">Length</th>
                  <th className="py-1 pr-4 font-medium">Width</th>
                  <th className="py-1 pr-4 font-medium">Surface</th>
                  <th className="py-1 font-medium">Lit</th>
                </tr>
              </thead>
              <tbody className="text-black dark:text-zinc-200">
                {airport.runways.map((runway, i) => (
                  <tr
                    key={`${runway.name}-${i}`}
                    className="border-t border-black/[.06] dark:border-white/[.08]"
                  >
                    <td className="py-1 pr-4 font-medium">{runway.name}</td>
                    <td className="py-1 pr-4 tabular-nums">
                      {runway.lengthFt ? formatFt(runway.lengthFt) : "—"}
                    </td>
                    <td className="py-1 pr-4 tabular-nums">
                      {runway.widthFt ? `${runway.widthFt} ft` : "—"}
                    </td>
                    <td className="py-1 pr-4">{runway.surfaceLabel ?? "—"}</td>
                    <td className="py-1">{runway.lighted ? "Yes" : "No"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {airport.wikipedia && (
          <a
            href={airport.wikipedia}
            target="_blank"
            rel="noopener noreferrer"
            className="self-start text-sm text-blue-600 underline dark:text-blue-400"
          >
            Read about {airport.name} on Wikipedia
          </a>
        )}
      </section>

      {country && (
        <section className="flex flex-col gap-3">
          <h3 className="text-sm font-semibold text-black dark:text-zinc-50">
            About {country.name}
          </h3>
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {country.nativeName !== country.name && (
              <Fact label="Local name">{country.nativeName}</Fact>
            )}
            {country.capital && <Fact label="Capital">{country.capital}</Fact>}
            <Fact label="Continent">{country.continent}</Fact>
            <Fact
              label={country.currencies.length > 1 ? "Currencies" : "Currency"}
            >
              {country.currencies.join(", ")}
            </Fact>
            <Fact
              label={country.languages.length > 1 ? "Languages" : "Language"}
            >
              {country.languages.join(", ")}
            </Fact>
            <Fact label="Calling code">{country.callingCodes.join(", ")}</Fact>
            {airport.countryAirportCount > 0 && (
              <Fact label="Coded airports">
                {airport.countryAirportCount.toLocaleString("en-US")} with an
                ICAO or IATA code
              </Fact>
            )}
          </dl>
        </section>
      )}
    </div>
  );
}

/** Look up any airport by code (or click one on the globe / in a list):
 * live METAR, airport facts and country facts. */
export function AirportExplorer({ quickCodes }: { quickCodes: string[] }) {
  const { airportCode, openAirport } = usePlanner();
  const [query, setQuery] = useState("");
  const [lookup, setLookup] = useState<{
    code: string;
    airport: AirportLookup | null;
  } | null>(null);

  useEffect(() => {
    if (!airportCode) return;
    let cancelled = false;
    lookupAirport(airportCode).then((airport) => {
      if (!cancelled) setLookup({ code: airportCode, airport });
    });
    return () => {
      cancelled = true;
    };
  }, [airportCode]);

  const current = lookup?.code === airportCode ? lookup : null;

  return (
    <div className="flex flex-col gap-4">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (query.trim()) openAirport(query.trim(), { scroll: false });
        }}
        className="flex flex-wrap items-center gap-2"
      >
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="ICAO or IATA code, e.g. EGLL or LHR"
          maxLength={4}
          aria-label="Airport code"
          className="w-64 max-w-full rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm uppercase text-black outline-none placeholder:normal-case focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
        />
        <button
          type="submit"
          className="rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] dark:hover:bg-[#ccc]"
        >
          Look up
        </button>
        {quickCodes.map((code) => (
          <button
            key={code}
            type="button"
            onClick={() => openAirport(code, { scroll: false })}
            className="rounded-full border border-black/[.08] px-2.5 py-1 text-xs text-zinc-600 transition-colors hover:bg-black/[.04] dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]"
          >
            {code}
          </button>
        ))}
      </form>

      {!airportCode && (
        <p className="text-sm text-zinc-500">
          Search for an airport, click one on the globe, or pick one of yours
          above to see its live weather, runways and country facts.
        </p>
      )}
      {airportCode && !current && (
        <p className="text-sm text-zinc-500">Looking up {airportCode}…</p>
      )}
      {current && !current.airport && (
        <p className="text-sm text-zinc-500">
          No airport found for &ldquo;{current.code}&rdquo;. Try its 4-letter
          ICAO or 3-letter IATA code.
        </p>
      )}
      {current?.airport && <AirportDetails airport={current.airport} />}
    </div>
  );
}
