"use client";

import { useActionState, useState, useSyncExternalStore } from "react";
import {
  regenerateShareLink,
  saveShare,
  stopSharing,
  type ShareState,
} from "./share-actions";

const fieldClass =
  "w-full min-w-0 rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";
const primaryButton =
  "rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]";
const secondaryButton =
  "rounded-full border border-black/[.08] px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-300 dark:hover:bg-[#1a1a1a]";

const noopSubscribe = () => () => {};

// The Flight Stats page's sharing: an optional public link to the user's
// flight map and stats (without notes or photos), with a name shown on
// it; the link can be copied, replaced with a new one, or switched off.
export function ShareSettings({
  share,
  available,
}: {
  share: { share_id: string; display_name: string | null } | null;
  /** False until the sharing database update has been run. */
  available: boolean;
}) {
  const origin = useSyncExternalStore(
    noopSubscribe,
    () => window.location.origin,
    () => "",
  );
  const [state, action, pending] = useActionState<ShareState, FormData>(
    saveShare,
    undefined,
  );
  const [copied, setCopied] = useState(false);
  const [confirmingNew, setConfirmingNew] = useState(false);
  const link = share ? `${origin}/share/${share.share_id}` : null;

  return (
    <section
      aria-labelledby="share-heading"
      className="flex flex-col gap-3 rounded-2xl border border-black/[.08] p-4 dark:border-white/[.145]"
    >
      <div className="flex flex-col gap-1">
        <h2
          id="share-heading"
          className="text-lg font-semibold text-black dark:text-zinc-50"
        >
          Share your flight map
        </h2>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          A public link to your globe, routes and these stats, to show friends
          or post online. Anyone with the link can see it; your notes and photos
          are never included.
        </p>
      </div>

      {!available ? (
        <p className="text-sm text-amber-700 dark:text-amber-400">
          Sharing needs a database update first
          (supabase/migrations/20261006_sharing_and_confirmed_flights.sql).
        </p>
      ) : (
        <>
          {link && (
            <div className="flex flex-col gap-2 sm:flex-row">
              <input
                readOnly
                value={link}
                aria-label="Your share link"
                onFocus={(event) => event.currentTarget.select()}
                className={`${fieldClass} font-mono text-xs`}
              />
              <div className="flex shrink-0 gap-2">
                <button
                  type="button"
                  onClick={async () => {
                    try {
                      await navigator.clipboard.writeText(link);
                      setCopied(true);
                      window.setTimeout(() => setCopied(false), 2000);
                    } catch {
                      // Clipboard blocked: the field can still be copied.
                    }
                  }}
                  className={primaryButton}
                >
                  {copied ? "Copied" : "Copy link"}
                </button>
                <a
                  href={link}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={secondaryButton}
                >
                  Open
                </a>
              </div>
            </div>
          )}

          <form
            action={action}
            className="flex flex-col gap-2 sm:flex-row sm:items-end"
          >
            <div className="flex min-w-0 flex-1 flex-col gap-1.5">
              <label
                htmlFor="share-name"
                className="text-xs font-medium uppercase tracking-wide text-zinc-500"
              >
                Name shown on it
              </label>
              <input
                id="share-name"
                name="displayName"
                maxLength={60}
                defaultValue={share?.display_name ?? ""}
                placeholder="e.g. Alex's sim flights (or leave blank)"
                className={fieldClass}
              />
            </div>
            <button
              type="submit"
              disabled={pending}
              className={share ? secondaryButton : primaryButton}
            >
              {pending ? "Saving…" : share ? "Save name" : "Create share link"}
            </button>
          </form>
          {state?.error && (
            <p className="text-sm text-red-600 dark:text-red-400">
              {state.error}
            </p>
          )}

          {share &&
            (confirmingNew ? (
              <div className="flex flex-wrap items-center gap-2 text-sm text-zinc-700 dark:text-zinc-300">
                <span>The current link will stop working.</span>
                <button
                  type="button"
                  onClick={async () => {
                    await regenerateShareLink();
                    setConfirmingNew(false);
                  }}
                  className={secondaryButton}
                >
                  Make a new link
                </button>
                <button
                  type="button"
                  onClick={() => setConfirmingNew(false)}
                  className={secondaryButton}
                >
                  Keep this one
                </button>
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => setConfirmingNew(true)}
                  className={secondaryButton}
                >
                  New link
                </button>
                <button
                  type="button"
                  onClick={() => stopSharing()}
                  className={secondaryButton}
                >
                  Stop sharing
                </button>
              </div>
            ))}
        </>
      )}
    </section>
  );
}
