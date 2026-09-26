import "flag-icons/css/flag-icons.min.css";

/** A country's flag (SVG, from the MIT-licensed flag-icons package) by ISO
 * 3166-1 alpha-2 code. Renders nothing for an unknown/missing code. */
export function Flag({
  country,
  label,
  className = "",
}: {
  country: string | null | undefined;
  /** Accessible name, e.g. the country's name; defaults to the code. */
  label?: string | null;
  className?: string;
}) {
  if (!country || !/^[A-Za-z]{2}$/.test(country)) return null;
  return (
    <span
      role="img"
      aria-label={label ?? country}
      title={label ?? country}
      className={`fi fi-${country.toLowerCase()} shrink-0 rounded-[2px] shadow-[0_0_0_1px_rgba(0,0,0,0.12)] ${className}`}
    />
  );
}
