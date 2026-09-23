"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { sanitizeFilename } from "./flight-media";
import { thumbnailFolder } from "./thumbnail-path";
import styles from "./selected-flight.module.css";

export type ThumbnailChoice = { path: string; name: string; url: string };


function newThumbnailPath(userId: string, flightId: string, name: string) {
  return `${thumbnailFolder(userId, flightId)}/${Date.now()}-${sanitizeFilename(name)}`;
}

// Lets the user pick one of the flight's uploaded images as its thumbnail,
// or upload a new one just for this. The choice is stored as its own copy
// under the flight's thumbnail folder (so it survives the original being
// removed from the flight's media), replacing whatever was there before.
export function ThumbnailPicker({
  userId,
  flightId,
  images,
  currentThumbnailPath,
  onDone,
}: {
  userId: string;
  flightId: string;
  images: ThumbnailChoice[];
  /** The custom thumbnail's own path, or null if the default is showing. */
  currentThumbnailPath: string | null;
  onDone: () => void;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Only once the new thumbnail is safely in place is the old one removed,
  // so a failed upload/copy leaves the previous choice untouched.
  async function replaceWith(write: () => Promise<{ error: Error | null }>) {
    setBusy(true);
    setError(null);
    const { error: writeError } = await write();
    if (writeError) {
      setError(writeError.message);
      setBusy(false);
      return;
    }
    if (currentThumbnailPath) {
      await createClient()
        .storage.from("flight-media")
        .remove([currentThumbnailPath]);
    }
    setBusy(false);
    onDone();
    router.refresh();
  }

  const chooseExisting = (image: ThumbnailChoice) =>
    replaceWith(() =>
      createClient()
        .storage.from("flight-media")
        .copy(image.path, newThumbnailPath(userId, flightId, image.name)),
    );

  const uploadNew = (file: File) =>
    replaceWith(() =>
      createClient()
        .storage.from("flight-media")
        .upload(newThumbnailPath(userId, flightId, file.name), file),
    );

  async function resetToDefault() {
    if (!currentThumbnailPath) return;
    setBusy(true);
    setError(null);
    const { error: removeError } = await createClient()
      .storage.from("flight-media")
      .remove([currentThumbnailPath]);
    setBusy(false);
    if (removeError) {
      setError(removeError.message);
      return;
    }
    onDone();
    router.refresh();
  }

  // The copy's name ends with the original's, so that's how the current
  // choice is recognized among the flight's images.
  const isCurrent = (image: ThumbnailChoice) =>
    currentThumbnailPath?.endsWith(`-${image.name}`) ?? false;

  return (
    <div className={`${styles.picker} flex flex-col gap-3`}>
      <div className="flex items-center justify-between gap-2">
        <p className={styles.label}>Choose a thumbnail</p>
        <button
          type="button"
          onClick={onDone}
          className={`${styles.textButton} text-xs`}
        >
          Cancel
        </button>
      </div>

      <div className="grid grid-cols-4 gap-2">
        {images.map((image) => (
          <button
            key={image.path}
            type="button"
            disabled={busy}
            onClick={() => chooseExisting(image)}
            className={`${styles.pickerTile} ${isCurrent(image) ? styles.pickerTileCurrent : ""}`}
            aria-label={`Use ${image.name} as thumbnail`}
            aria-pressed={isCurrent(image)}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={image.url} alt="" />
          </button>
        ))}
        <button
          type="button"
          disabled={busy}
          onClick={() => inputRef.current?.click()}
          className={`${styles.pickerTile} ${styles.pickerUpload}`}
        >
          <span aria-hidden="true" className="text-lg leading-none">
            +
          </span>
          <span className="text-[10px]">Upload</span>
        </button>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = "";
            if (file) uploadNew(file);
          }}
        />
      </div>

      {images.length === 0 && (
        <p className={`${styles.soft} text-xs`}>
          Upload an image to use as this flight&apos;s thumbnail.
        </p>
      )}

      <div className="flex items-center justify-between gap-2">
        {busy ? (
          <span className={`${styles.soft} text-xs`}>Saving…</span>
        ) : error ? (
          <span className="text-xs text-red-400">{error}</span>
        ) : (
          <span />
        )}
        {currentThumbnailPath && (
          <button
            type="button"
            disabled={busy}
            onClick={resetToDefault}
            className={`${styles.textButton} text-xs`}
          >
            Remove thumbnail
          </button>
        )}
      </div>
    </div>
  );
}
