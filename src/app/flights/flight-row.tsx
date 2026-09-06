"use client";

import { useSelection } from "./selection-context";

export function FlightRow({
  id,
  children,
}: {
  id: string;
  children: React.ReactNode;
}) {
  const { selectedFlightId, setSelectedFlightId } = useSelection();
  const selected = selectedFlightId === id;

  return (
    <div
      onClick={() => setSelectedFlightId(selected ? null : id)}
      className={`flex cursor-pointer flex-col gap-3 rounded-2xl border p-4 transition-colors ${
        selected
          ? "border-blue-400 bg-blue-50 dark:border-blue-500/60 dark:bg-blue-950/30"
          : "border-black/[.08] dark:border-white/[.145]"
      }`}
    >
      {children}
    </div>
  );
}
