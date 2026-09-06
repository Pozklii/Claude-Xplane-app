"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export type MediaItem = {
  path: string;
  name: string;
  url: string;
  kind: "image" | "video" | "other";
};

function sanitizeFilename(name: string) {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_");
}

export function FlightMedia({
  flightId,
  userId,
  items,
}: {
  flightId: string;
  userId: string;
  items: MediaItem[];
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFiles(fileList: FileList | null) {
    if (!fileList || fileList.length === 0) return;
    setBusy(true);
    setError(null);
    const supabase = createClient();

    for (const file of Array.from(fileList)) {
      const path = `${userId}/${flightId}/${Date.now()}-${sanitizeFilename(file.name)}`;
      const { error: uploadError } = await supabase.storage
        .from("flight-media")
        .upload(path, file);

      if (uploadError) {
        setError(uploadError.message);
        break;
      }
    }

    setBusy(false);
    if (inputRef.current) inputRef.current.value = "";
    router.refresh();
  }

  async function handleDelete(path: string) {
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error: deleteError } = await supabase.storage
      .from("flight-media")
      .remove([path]);

    setBusy(false);
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    router.refresh();
  }

  return (
    <div className="flex flex-col gap-2">
      {items.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {items.map((item) => (
            <div
              key={item.path}
              className="group relative h-20 w-20 overflow-hidden rounded-lg border border-black/[.08] bg-zinc-100 dark:border-white/[.145] dark:bg-zinc-900"
            >
              {item.kind === "image" ? (
                <a href={item.url} target="_blank" rel="noopener noreferrer">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={item.url}
                    alt={item.name}
                    className="h-full w-full object-cover"
                  />
                </a>
              ) : item.kind === "video" ? (
                <video
                  src={item.url}
                  controls
                  className="h-full w-full object-cover"
                />
              ) : (
                <a
                  href={item.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex h-full w-full items-center justify-center p-1 text-center text-[10px] text-zinc-600 dark:text-zinc-400"
                >
                  {item.name}
                </a>
              )}
              <button
                type="button"
                onClick={() => handleDelete(item.path)}
                disabled={busy}
                aria-label={`Remove ${item.name}`}
                className="absolute right-0.5 top-0.5 hidden h-5 w-5 items-center justify-center rounded-full bg-black/70 text-xs text-white group-hover:flex disabled:opacity-60"
              >
                &times;
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="flex items-center gap-2">
        <input
          ref={inputRef}
          type="file"
          accept="image/*,video/*"
          multiple
          disabled={busy}
          onChange={(e) => handleFiles(e.target.files)}
          className="text-xs text-zinc-600 file:mr-2 file:rounded-full file:border file:border-black/[.08] file:bg-white file:px-2 file:py-1 file:text-xs file:font-medium file:text-black dark:text-zinc-400 dark:file:border-white/[.145] dark:file:bg-zinc-950 dark:file:text-zinc-50"
        />
        {busy && (
          <span className="text-xs text-zinc-500 dark:text-zinc-500">
            Uploading…
          </span>
        )}
      </div>
      {error && (
        <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
      )}
    </div>
  );
}
