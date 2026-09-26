"use client";

import { useActionState } from "react";
import { savePreferences } from "./actions";

const inputClass =
  "rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50";

export function FavouritesForm({
  favouriteAirline,
  favouriteAircraft,
  airlineOptions,
  aircraftOptions,
}: {
  favouriteAirline: string | null;
  favouriteAircraft: string | null;
  airlineOptions: string[];
  aircraftOptions: string[];
}) {
  const [state, action, pending] = useActionState(savePreferences, undefined);

  return (
    <form action={action} className="flex flex-col gap-2">
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_1fr_auto]">
        <input
          name="favouriteAirline"
          defaultValue={favouriteAirline ?? ""}
          placeholder="Favourite airline"
          aria-label="Favourite airline"
          list="favourite-airline-options"
          maxLength={80}
          className={inputClass}
        />
        <input
          name="favouriteAircraft"
          defaultValue={favouriteAircraft ?? ""}
          placeholder="Favourite aircraft"
          aria-label="Favourite aircraft"
          list="favourite-aircraft-options"
          maxLength={80}
          className={inputClass}
        />
        <button
          type="submit"
          disabled={pending}
          className="rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]"
        >
          {pending ? "Saving…" : "Save favourites"}
        </button>
      </div>
      <datalist id="favourite-airline-options">
        {airlineOptions.map((name) => (
          <option key={name} value={name} />
        ))}
      </datalist>
      <datalist id="favourite-aircraft-options">
        {aircraftOptions.map((name) => (
          <option key={name} value={name} />
        ))}
      </datalist>
      {state?.error && (
        <p className="text-sm text-red-600 dark:text-red-400">
          Couldn&apos;t save: {state.error}
        </p>
      )}
      {state?.saved && !pending && (
        <p className="text-sm text-emerald-700 dark:text-emerald-400">
          Favourites saved.
        </p>
      )}
    </form>
  );
}
