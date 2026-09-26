"use client";

import { useEffect, useState } from "react";
import type { Trivia } from "@/lib/airport-trivia";
import { Flag } from "./flag";
import { useSelection } from "./selection-context";
import styles from "./fact-toast.module.css";

const AUTO_HIDE_MS = 15_000;

function hash(text: string) {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  }
  return h >>> 0;
}

/**
 * Whenever a flight is opened (on the globe or in the log), a random fact
 * about one of its airports or their countries rises from the bottom of
 * the screen, hiding itself after a while. The pick is seeded by which
 * flight and how many times anything has been opened, so it's different
 * each time without randomness during render.
 */
export function FactToast({
  factsByFlight,
}: {
  factsByFlight: Record<string, Trivia[]>;
}) {
  const { selectedFlightId, selectionCount } = useSelection();
  const [shuffle, setShuffle] = useState(0);
  const [hiddenKey, setHiddenKey] = useState<string | null>(null);

  const facts = selectedFlightId ? factsByFlight[selectedFlightId] : undefined;
  const key = `${selectionCount}:${shuffle}`;
  const visible = Boolean(facts?.length) && hiddenKey !== key;

  useEffect(() => {
    if (!visible) return;
    const timer = setTimeout(() => setHiddenKey(key), AUTO_HIDE_MS);
    return () => clearTimeout(timer);
  }, [visible, key]);

  if (!visible || !facts || !selectedFlightId) return null;
  // "Another fact" steps on from the opening pick, so it never repeats
  // until the whole pool has been seen.
  const start = hash(`${selectedFlightId}:${selectionCount}`);
  const fact = facts[(start + shuffle) % facts.length];

  return (
    <aside
      key={selectionCount}
      className={styles.toast}
      role="status"
      aria-live="polite"
    >
      <Flag country={fact.country} className="mt-0.5 text-lg" />
      <div className="flex min-w-0 flex-col gap-1">
        <p className={`${styles.label} flex flex-wrap gap-x-1.5`}>
          Did you know? <span className={styles.subject}>{fact.subject}</span>
        </p>
        <p key={shuffle} className={`${styles.text} text-sm`}>
          {fact.text}
        </p>
        {facts.length > 1 && (
          <button
            type="button"
            onClick={() => setShuffle((n) => n + 1)}
            className={`${styles.button} mt-1 self-start`}
          >
            Another fact
          </button>
        )}
      </div>
      <button
        type="button"
        onClick={() => setHiddenKey(key)}
        className={styles.close}
        aria-label="Dismiss fact"
      >
        &times;
      </button>
    </aside>
  );
}
