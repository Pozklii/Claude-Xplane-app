import { formatDate, formatDuration } from "@/lib/dates";
import type { FlightStats } from "@/lib/flight-stats";
import { Flag } from "../flights/flag";

const fmt = (n: number) => Math.round(n).toLocaleString("en-US");
const hoursText = (h: number) =>
  `${h.toLocaleString("en-US", { maximumFractionDigits: 1 })} h`;

const card =
  "flex flex-col gap-4 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]";
const heading = "text-lg font-semibold text-black dark:text-zinc-50";
const muted = "text-zinc-500 dark:text-zinc-400";

// The Flight Stats page's body (also on a shared flight map): headline
// figures, hours per month, most-flown aircraft and airports, the longest
// flights, and achievements. Server-rendered; the chart's tooltips are its
// marks' titles.
export function StatsView({
  stats,
  owner = "you",
}: {
  stats: FlightStats;
  /** Who the stats are about, for the wording ("you", or a name). */
  owner?: string;
}) {
  const { totals } = stats;
  if (totals.flights === 0) {
    return (
      <p className={`text-sm ${muted}`}>
        No flights logged yet: stats and achievements appear here once{" "}
        {owner === "you" ? "you log your first flight" : "flights are logged"}.
      </p>
    );
  }
  const earned = stats.achievements.filter((a) => a.earned).length;

  return (
    <div className="flex flex-col gap-8">
      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        {(
          [
            ["Flights", fmt(totals.flights)],
            ["Hours", hoursText(totals.hours)],
            ["Distance", `${fmt(totals.nm)} nm`],
            ["Countries", fmt(totals.countries)],
            ["Continents", `${totals.continents.length} of 6`],
          ] as const
        ).map(([label, value]) => (
          <div
            key={label}
            className="flex flex-col gap-1 rounded-xl bg-zinc-50 px-4 py-3 dark:bg-zinc-900/60"
          >
            <dt
              className={`text-xs font-medium uppercase tracking-wide ${muted}`}
            >
              {label}
            </dt>
            <dd className="text-2xl font-semibold tabular-nums text-black dark:text-zinc-50">
              {value}
            </dd>
          </div>
        ))}
      </dl>

      <section className={card} aria-labelledby="stats-monthly">
        <h2 id="stats-monthly" className={heading}>
          Hours per month
        </h2>
        <MonthlyChart months={stats.monthly} />
      </section>

      <div className="grid gap-4 md:grid-cols-2">
        <section className={card} aria-labelledby="stats-aircraft">
          <h2 id="stats-aircraft" className={heading}>
            Most-flown aircraft
          </h2>
          <BarList
            items={stats.topAircraft.map((a) => ({
              key: a.name,
              label: a.name,
              value: a.hours,
              text: `${hoursText(a.hours)} · ${a.flights} flight${a.flights === 1 ? "" : "s"}`,
            }))}
          />
        </section>
        <section className={card} aria-labelledby="stats-airports">
          <h2 id="stats-airports" className={heading}>
            Most-visited airports
          </h2>
          <BarList
            items={stats.topAirports.map((a) => ({
              key: a.code,
              label: (
                <span className="inline-flex items-center gap-1.5">
                  <Flag country={a.country} />
                  {a.code}
                  {a.city && <span className={muted}>{a.city}</span>}
                </span>
              ),
              value: a.visits,
              text: `${a.visits} visit${a.visits === 1 ? "" : "s"}`,
            }))}
          />
        </section>
      </div>

      <section className={card} aria-labelledby="stats-records">
        <h2 id="stats-records" className={heading}>
          Longest flights
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {(
            [
              ["Farthest", stats.farthest, "nm"],
              ["Longest in the air", stats.longestTime, "hours"],
            ] as const
          ).map(([label, flight, measure]) =>
            flight ? (
              <div
                key={label}
                className="flex flex-col gap-1 rounded-xl bg-zinc-50 px-4 py-3 dark:bg-zinc-900/60"
              >
                <p
                  className={`text-xs font-medium uppercase tracking-wide ${muted}`}
                >
                  {label}
                </p>
                <p className="text-xl font-semibold tabular-nums text-black dark:text-zinc-50">
                  {measure === "nm" && flight.nm !== null
                    ? `${fmt(flight.nm)} nm`
                    : formatDuration(flight.hours)}
                </p>
                <p className="text-sm text-zinc-700 dark:text-zinc-300">
                  {flight.from} &rarr; {flight.to}
                  {flight.fromCity && flight.toCity && (
                    <span className={muted}>
                      {" "}
                      ({flight.fromCity} to {flight.toCity})
                    </span>
                  )}
                </p>
                <p className={`text-xs ${muted}`}>
                  {formatDate(flight.date)} · {flight.aircraft}
                </p>
              </div>
            ) : null,
          )}
        </div>
      </section>

      <section className={card} aria-labelledby="stats-achievements">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="stats-achievements" className={heading}>
            Achievements
          </h2>
          <p className={`text-sm tabular-nums ${muted}`}>
            {earned} of {stats.achievements.length} earned
          </p>
        </div>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {stats.achievements.map((a) => (
            <li
              key={a.id}
              className={`flex gap-3 rounded-xl border p-3 ${
                a.earned
                  ? "border-amber-400/60 bg-amber-50 dark:border-amber-400/40 dark:bg-amber-950/30"
                  : "border-black/[.06] dark:border-white/[.08]"
              }`}
            >
              <span
                aria-hidden="true"
                className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full ${
                  a.earned
                    ? "bg-amber-400 text-amber-950"
                    : "bg-zinc-100 text-zinc-400 dark:bg-zinc-800 dark:text-zinc-500"
                }`}
              >
                <svg
                  viewBox="0 0 16 16"
                  width="16"
                  height="16"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.6"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  {a.earned ? (
                    <path d="M3.5 8.5l3 3 6-7" />
                  ) : (
                    <>
                      <rect x="3.5" y="7" width="9" height="6.5" rx="1.5" />
                      <path d="M5.5 7V5.2a2.5 2.5 0 0 1 5 0V7" />
                    </>
                  )}
                </svg>
              </span>
              <div className="flex min-w-0 flex-col gap-0.5">
                <p className="text-sm font-semibold text-black dark:text-zinc-50">
                  {a.title}
                  <span className="sr-only">
                    {a.earned ? " (earned)" : " (not yet earned)"}
                  </span>
                </p>
                <p className="text-xs text-zinc-600 dark:text-zinc-400">
                  {a.description}
                </p>
                {!a.earned && a.progress && (
                  <p className={`text-xs tabular-nums ${muted}`}>
                    {a.progress}
                  </p>
                )}
              </div>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

// Columns of hours, one per month, from a single baseline: thin columns
// (at most 24 px) with rounded tops, a recessive grid, the busiest month
// labelled, every column's figures on hover, and the same data as a table.
function MonthlyChart({ months }: { months: FlightStats["monthly"] }) {
  const W = 640;
  const H = 210;
  const left = 34;
  const right = 8;
  const top = 18;
  const bottom = 26;
  const plotW = W - left - right;
  const plotH = H - top - bottom;
  const max = Math.max(...months.map((m) => m.hours), 0);
  // A round top for the scale: 1, 2, 5, 10, 20, 50… hours.
  const step =
    max <= 0
      ? 1
      : ([1, 2, 5]
          .flatMap((m) => [0, 1, 2, 3].map((e) => m * 10 ** e))
          .sort((a, b) => a - b)
          .find((s) => s * 4 >= max) ?? 1000);
  const scaleMax = step * 4;
  const y = (hours: number) => top + plotH - (hours / scaleMax) * plotH;
  const band = plotW / months.length;
  const barW = Math.min(24, band * 0.6);
  const busiest = months.reduce((best, m) => (m.hours > best.hours ? m : best));

  return (
    <div className="flex flex-col gap-2">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-auto w-full"
        role="img"
        aria-label={`Hours flown each month over the last 12 months; the busiest was ${busiest.label} ${busiest.year} with ${hoursText(busiest.hours)}.`}
      >
        {[0, 1, 2, 3, 4].map((i) => {
          const value = step * i;
          const gy = y(value);
          return (
            <g key={i}>
              <line
                x1={left}
                x2={W - right}
                y1={gy}
                y2={gy}
                className={
                  i === 0
                    ? "stroke-zinc-300 dark:stroke-zinc-700"
                    : "stroke-zinc-200 dark:stroke-zinc-800"
                }
                strokeWidth={1}
              />
              <text
                x={left - 6}
                y={gy}
                dy="0.32em"
                textAnchor="end"
                className="fill-zinc-500 text-[10px] tabular-nums dark:fill-zinc-400"
              >
                {value}
              </text>
            </g>
          );
        })}
        {months.map((m, i) => {
          const cx = left + band * i + band / 2;
          const h = Math.max(0, top + plotH - y(m.hours));
          const x = cx - barW / 2;
          const yTop = top + plotH - h;
          const r = Math.min(4, h, barW / 2);
          const tip = `${m.label} ${m.year}: ${hoursText(m.hours)}, ${m.flights} flight${m.flights === 1 ? "" : "s"}`;
          return (
            <g key={m.key} className="group">
              <title>{tip}</title>
              {/* A hit target the whole band's height. */}
              <rect
                x={left + band * i}
                y={top}
                width={band}
                height={plotH}
                fill="transparent"
              />
              {h > 0 && (
                <path
                  d={`M${x},${top + plotH} V${yTop + r} Q${x},${yTop} ${x + r},${yTop} H${x + barW - r} Q${x + barW},${yTop} ${x + barW},${yTop + r} V${top + plotH} Z`}
                  className="fill-[#2a78d6] transition-opacity group-hover:opacity-80 dark:fill-[#3987e5]"
                />
              )}
              <text
                x={cx}
                y={H - 8}
                textAnchor="middle"
                className="fill-zinc-500 text-[10px] dark:fill-zinc-400"
              >
                {m.label}
              </text>
              {m === busiest && m.hours > 0 && (
                <text
                  x={cx}
                  y={yTop - 6}
                  textAnchor="middle"
                  className="fill-zinc-800 text-[10px] font-semibold tabular-nums dark:fill-zinc-200"
                >
                  {hoursText(m.hours)}
                </text>
              )}
            </g>
          );
        })}
      </svg>
      <details className="text-xs text-zinc-600 dark:text-zinc-400">
        <summary className="cursor-pointer select-none">
          Show as a table
        </summary>
        <table className="mt-2 w-full max-w-sm tabular-nums">
          <thead>
            <tr className="text-left">
              <th className="py-1 font-medium">Month</th>
              <th className="py-1 text-right font-medium">Hours</th>
              <th className="py-1 text-right font-medium">Flights</th>
            </tr>
          </thead>
          <tbody>
            {months.map((m) => (
              <tr
                key={m.key}
                className="border-t border-black/[.06] dark:border-white/[.08]"
              >
                <td className="py-1">
                  {m.label} {m.year}
                </td>
                <td className="py-1 text-right">{hoursText(m.hours)}</td>
                <td className="py-1 text-right">{m.flights}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </div>
  );
}

// A ranked list with a bar for each value (thin, rounded at its end), the
// figures in text beside it.
function BarList({
  items,
}: {
  items: {
    key: string;
    label: React.ReactNode;
    value: number;
    text: string;
  }[];
}) {
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <ol className="flex flex-col gap-3">
      {items.map((item) => (
        <li key={item.key} className="flex flex-col gap-1">
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="min-w-0 truncate font-medium text-black dark:text-zinc-50">
              {item.label}
            </span>
            <span className="shrink-0 text-xs tabular-nums text-zinc-600 dark:text-zinc-400">
              {item.text}
            </span>
          </div>
          <div className="h-2.5 w-full rounded-r bg-zinc-100 dark:bg-zinc-800/60">
            <div
              className="h-full rounded-r-[4px] bg-[#2a78d6] dark:bg-[#3987e5]"
              style={{ width: `${Math.max(2, (item.value / max) * 100)}%` }}
            />
          </div>
        </li>
      ))}
    </ol>
  );
}
