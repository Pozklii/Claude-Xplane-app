// Shared by the server (flights page, which reads the chosen thumbnail)
// and the client (ThumbnailPicker, which writes it) — so it must live
// outside any "use client" module: calling a function exported from one
// of those on the server throws at runtime.

/** Storage folder holding a flight's chosen thumbnail (at most one file). */
export function thumbnailFolder(userId: string, flightId: string) {
  return `${userId}/thumbnails/${flightId}`;
}
