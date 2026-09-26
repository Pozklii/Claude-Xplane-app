"use client";

import { useOptimistic, useState, useTransition } from "react";
import { rateFlight } from "./actions";

const SCALE = Array.from({ length: 10 }, (_, i) => i + 1);

/** A 1–10 rating as ten segments; clicking one saves it, clicking the
 * current rating again clears it. */
export function RatingControl({
  flightId,
  rating,
}: {
  flightId: string;
  rating: number | null;
}) {
  const [optimistic, setOptimistic] = useOptimistic(rating);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const rate = (value: number) => {
    const next = value === optimistic ? null : value;
    setError(null);
    startTransition(async () => {
      setOptimistic(next);
      const result = await rateFlight(flightId, next);
      if (result?.error) setError(result.error);
    });
  };

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <div
          role="radiogroup"
          aria-label="Rate this flight out of 10"
          className={`flex gap-0.5 ${pending ? "opacity-70" : ""}`}
        >
          {SCALE.map((value) => {
            const filled = optimistic !== null && value <= optimistic;
            return (
              <button
                key={value}
                type="button"
                role="radio"
                aria-checked={optimistic === value}
                aria-label={`${value} out of 10`}
                title={`${value}/10`}
                onClick={() => rate(value)}
                className={`h-3.5 w-3 rounded-sm transition-colors ${
                  filled
                    ? "bg-amber-400 hover:bg-amber-500"
                    : "bg-zinc-200 hover:bg-amber-200 dark:bg-zinc-800 dark:hover:bg-amber-900"
                }`}
              />
            );
          })}
        </div>
        <span className="text-xs font-medium tabular-nums text-zinc-600 dark:text-zinc-400">
          {optimistic !== null ? `${optimistic}/10` : "Not rated"}
        </span>
      </div>
      {error && (
        <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
      )}
    </div>
  );
}
