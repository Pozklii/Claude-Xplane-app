import styles from "../home.module.css";

// The top of the Flight Map and Flight Log pages: the page's title and the
// user's totals, plus whatever the page adds below them (links, notes).
export function FlightsHeader({
  title,
  count,
  totalHours,
  countries,
  averageRating,
  centered = false,
  children,
}: {
  title: string;
  count: number;
  totalHours: number;
  countries: number;
  averageRating: number | null;
  /** Centred on the page (the Flight Log) rather than to the left. */
  centered?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <div
      className={`flex flex-col gap-1 ${centered ? "items-center text-center" : ""}`}
    >
      <h1 className={`${styles.introHeading} text-3xl font-semibold`}>
        {title}
      </h1>
      <p className={`${styles.featureText} text-sm`}>
        {count} flight{count === 1 ? "" : "s"} logged &middot;{" "}
        {totalHours.toFixed(1)} total hours
        {countries > 0 &&
          ` · ${countries} ${countries === 1 ? "country" : "countries"}`}
        {averageRating !== null &&
          ` · average flight rating ${averageRating.toFixed(1)}/10`}
      </p>
      {children}
    </div>
  );
}
