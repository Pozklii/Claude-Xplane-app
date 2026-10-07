"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  parseTrackFile,
  thinTrack,
  type RecordingSummary,
} from "@/lib/recording";
import { saveFlightTrack } from "./recording-actions";

const smallButton =
  "rounded-full border border-black/[.08] px-3 py-1 text-xs font-medium text-zinc-600 transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-400 dark:hover:bg-[#1a1a1a]";

// A logged flight's flown route on the Flight Log: what was recorded (from
// X-Plane or a file), with a way to add one from a GPX, KML or CSV file
// (e.g. exported from Little Navmap or Volanta), replace it or remove it.
// The Flight Map draws it when the flight is selected.
export function TrackUpload({
  flightId,
  summary,
}: {
  flightId: string;
  summary: RecordingSummary | null;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const save = (points: Parameters<typeof saveFlightTrack>[1]) =>
    startTransition(async () => {
      const result = await saveFlightTrack(flightId, points);
      setError(result?.error ?? null);
      if (!result) router.refresh();
    });

  const onFile = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    if (file.size > 20 * 1024 * 1024) {
      setError("That file is too big (20 MB at most).");
      return;
    }
    const points = parseTrackFile(file.name, await file.text());
    if (points.length < 2) {
      setError(
        "No route found in that file. Use a GPX or KML track, or a CSV with latitude and longitude columns.",
      );
      return;
    }
    save(thinTrack(points));
  };

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex flex-wrap items-center gap-2 text-xs text-zinc-600 dark:text-zinc-400">
        {summary ? (
          <span>
            Flown route{" "}
            {summary.source === "xplane" ? "recorded in X-Plane" : "from a file"}
            : {summary.distanceNm.toLocaleString("en-US")} nm flown
          </span>
        ) : (
          <span>No flown route yet.</span>
        )}
        <button
          type="button"
          disabled={pending}
          onClick={() => inputRef.current?.click()}
          className={smallButton}
        >
          {pending
            ? "Saving…"
            : summary
              ? "Replace from file"
              : "Add flown route (GPX, KML or CSV)"}
        </button>
        {summary && (
          <button
            type="button"
            disabled={pending}
            onClick={() => save(null)}
            className={smallButton}
          >
            Remove route
          </button>
        )}
        <input
          ref={inputRef}
          type="file"
          accept=".gpx,.kml,.csv,.txt,application/gpx+xml,application/vnd.google-earth.kml+xml,text/csv"
          onChange={onFile}
          className="hidden"
        />
      </div>
      {error && (
        <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
      )}
    </div>
  );
}
