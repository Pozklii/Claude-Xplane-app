"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from "react";

type SelectionContextValue = {
  selectedFlightId: string | null;
  setSelectedFlightId: (id: string | null) => void;
  /** Bumped on every selection change, so each opening of a flight can be
   * told apart from the last (e.g. to pick a different fact). */
  selectionCount: number;
};

const SelectionContext = createContext<SelectionContextValue | null>(null);

export function SelectionProvider({
  children,
  initialSelectedId = null,
}: {
  children: React.ReactNode;
  /** A flight to start with selected (e.g. one linked to from the log). */
  initialSelectedId?: string | null;
}) {
  const [selection, setSelection] = useState<{
    id: string | null;
    count: number;
  }>({ id: initialSelectedId, count: 0 });
  const setSelectedFlightId = useCallback(
    (id: string | null) =>
      setSelection((prev) => ({ id, count: prev.count + 1 })),
    [],
  );
  const value = useMemo(
    () => ({
      selectedFlightId: selection.id,
      setSelectedFlightId,
      selectionCount: selection.count,
    }),
    [selection, setSelectedFlightId],
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
