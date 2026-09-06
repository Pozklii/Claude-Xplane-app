"use client";

import { createContext, useContext, useMemo, useState } from "react";

type SelectionContextValue = {
  selectedFlightId: string | null;
  setSelectedFlightId: (id: string | null) => void;
};

const SelectionContext = createContext<SelectionContextValue | null>(null);

export function SelectionProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [selectedFlightId, setSelectedFlightId] = useState<string | null>(
    null,
  );
  const value = useMemo(
    () => ({ selectedFlightId, setSelectedFlightId }),
    [selectedFlightId],
  );

  return (
    <SelectionContext.Provider value={value}>
      {children}
    </SelectionContext.Provider>
  );
}

export function useSelection() {
  const ctx = useContext(SelectionContext);
  if (!ctx) {
    throw new Error("useSelection must be used within a SelectionProvider");
  }
  return ctx;
}
