"use client";

export function StopPropagation({ children }: { children: React.ReactNode }) {
  return <div onClick={(e) => e.stopPropagation()}>{children}</div>;
}
