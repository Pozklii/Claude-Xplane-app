"use client";

import { useState, useTransition } from "react";
import { createXplaneToken, revokeXplaneToken } from "./xplane-actions";

/** The user's X-Plane connection, as the Flight Log loads it: undefined
 * where the database can't hold one yet (migration not run). */
export type XplaneConnection =
  | { createdAt: string; lastUsedAt: string | null }
  | null
  | undefined;

const primaryButton =
  "rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]";
const secondaryButton =
  "rounded-full border border-black/[.08] px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

const when = (iso: string) =>
  new Date(iso).toLocaleString(undefined, {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });

// The Flight Log's X-Plane section: making a connection token for the
// companion program (public/xplane-logger.mjs), which watches X-Plane and
// logs each flight here when it's done — airports, aircraft, times,
// landing rate and the route flown.
export function XplaneConnect({
  connection,
}: {
  connection: XplaneConnection;
}) {
  const [token, setToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [pending, startTransition] = useTransition();

  const connect = () =>
    startTransition(async () => {
      const result = await createXplaneToken();
      if ("error" in result) {
        setError(result.error);
      } else {
        setError(null);
        setToken(result.token);
        setCopied(false);
      }
    });
  const disconnect = () =>
    startTransition(async () => {
      await revokeXplaneToken();
      setToken(null);
    });

  const site = typeof window === "undefined" ? "" : window.location.origin;
  const command = token
    ? `node xplane-logger.mjs --site ${site} --token ${token}`
    : null;

  return (
    <section className="flex flex-col gap-4 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]">
      <div className="flex flex-col gap-1">
        <h2 className="text-lg font-semibold text-black dark:text-zinc-50">
          Log flights automatically from X-Plane
        </h2>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          A small companion program runs alongside X-Plane 11 or 12 and logs
          each flight here once you&apos;re parked: the airports, aircraft,
          takeoff and landing times, landing rate, fuel and the route you
          actually flew. If it matches your confirmed flight, its SimBrief
          plan comes along too.
        </p>
      </div>

      {connection === undefined ? (
        <p className="text-sm text-amber-700 dark:text-amber-400">
          This needs the database update first
          (supabase/migrations/20261007_xplane_and_simbrief.sql).
        </p>
      ) : (
        <>
          <ol className="flex list-decimal flex-col gap-2 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
            <li>
              Install{" "}
              <a
                href="https://nodejs.org/"
                target="_blank"
                rel="noreferrer"
                className="underline underline-offset-4"
              >
                Node.js
              </a>{" "}
              (version 18 or later) on the computer that runs X-Plane.
            </li>
            <li>
              <a
                href="/xplane-logger.mjs"
                download
                className="underline underline-offset-4"
              >
                Download the companion (xplane-logger.mjs)
              </a>
              .
            </li>
            <li>
              {connection || token
                ? "Run it with your connection token, from the folder you saved it in:"
                : "Connect, then run it with the command shown, from the folder you saved it in."}
            </li>
            <li>
              Fly as usual. Leave it running; each flight is logged a minute
              after you park, and shows on the Flight Map with its route.
            </li>
          </ol>

          {command && (
            <div className="flex flex-col gap-2 rounded-lg bg-zinc-50 p-3 dark:bg-zinc-900/60">
              <p className="text-xs text-zinc-600 dark:text-zinc-400">
                Your connection token is in this command. It&apos;s shown only
                now, so copy it somewhere safe; anyone with it can add flights
                to your log.
              </p>
              <code className="break-all rounded bg-white p-2 font-mono text-xs text-black dark:bg-zinc-950 dark:text-zinc-50">
                {command}
              </code>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard
                    ?.writeText(command)
                    .then(() => setCopied(true))
                    .catch(() => {});
                }}
                className={`${secondaryButton} self-start`}
              >
                {copied ? "Copied" : "Copy command"}
              </button>
            </div>
          )}

          {connection && !token && (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Connected {when(connection.createdAt)}
              {connection.lastUsedAt
                ? ` · last flight logged ${when(connection.lastUsedAt)}`
                : " · no flights logged with it yet"}
              . Lost the command? Make a new token (the old one stops
              working).
            </p>
          )}

          {error && (
            <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
          )}

          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={connect}
              disabled={pending}
              className={primaryButton}
            >
              {connection || token ? "Make a new token" : "Connect X-Plane"}
            </button>
            {(connection || token) && (
              <button
                type="button"
                onClick={disconnect}
                disabled={pending}
                className={secondaryButton}
              >
                Disconnect
              </button>
            )}
          </div>
        </>
      )}
    </section>
  );
}
