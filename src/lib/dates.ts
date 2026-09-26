/** "2026-09-23" → "23/09/2026" (day/month/year). Splits the string rather
 * than going through Date, so a time-zone offset can't shift the day. */
export function formatDate(isoDate: string) {
  const [year, month, day] = isoDate.split("-");
  return day && month && year ? `${day}/${month}/${year}` : isoDate;
}

/** The calendar date `days` before `isoDate` (both "YYYY-MM-DD"). */
export function isoDaysBefore(isoDate: string, days: number) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day - days))
    .toISOString()
    .slice(0, 10);
}

/** Today's date in the viewer's own time zone, as "YYYY-MM-DD". */
export function localToday() {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}
