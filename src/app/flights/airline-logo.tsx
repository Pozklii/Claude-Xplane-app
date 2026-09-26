"use client";

import { useState } from "react";

// Public airline-logo CDNs keyed by IATA code, tried in order; if both
// fail (or there's no code) a monogram badge stands in.
const LOGO_SOURCES = [
  (iata: string) => `https://pics.avs.io/120/40/${iata}.png`,
  (iata: string) => `https://images.kiwi.com/airlines/64/${iata}.png`,
];

function monogram(name: string) {
  const words = name
    .replace(/[^A-Za-z0-9 ]/g, " ")
    .split(/\s+/)
    .filter(Boolean);
  return (
    words.length > 1 ? words[0][0] + words[1][0] : (words[0] ?? "?").slice(0, 2)
  ).toUpperCase();
}

export function AirlineLogo({
  name,
  iata,
  size = "sm",
}: {
  name: string;
  iata: string | null;
  size?: "sm" | "md";
}) {
  const [sourceIndex, setSourceIndex] = useState(0);
  const box = size === "md" ? "h-8 w-16" : "h-5 w-10";

  if (!iata || sourceIndex >= LOGO_SOURCES.length) {
    return (
      <span
        title={name}
        aria-label={name}
        role="img"
        className={`${box} inline-flex shrink-0 items-center justify-center rounded bg-zinc-200 text-[10px] font-semibold tracking-wide text-zinc-600 dark:bg-zinc-800 dark:text-zinc-300`}
      >
        {monogram(name)}
      </span>
    );
  }

  return (
    // Third-party CDN images of arbitrary size; next/image would need each
    // host configured and adds nothing for tiny logos.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      key={sourceIndex}
      src={LOGO_SOURCES[sourceIndex](iata)}
      alt={name}
      title={name}
      loading="lazy"
      // A server-rendered image can fail before hydration attaches
      // onError, so also check whether it had already failed on attach.
      ref={(img) => {
        if (img?.complete && img.naturalWidth === 0) {
          setSourceIndex((i) => i + 1);
        }
      }}
      onError={() => setSourceIndex((i) => i + 1)}
      className={`${box} shrink-0 rounded bg-white object-contain p-0.5`}
    />
  );
}
