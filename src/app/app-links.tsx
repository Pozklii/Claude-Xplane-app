import Link from "next/link";
import styles from "./home.module.css";

// The app's three sections, which need an account: the flight map (the
// globe) and the flight log share the flights page, the log below the map;
// the flight planner has its own page.
export const APP_LINKS = [
  { href: "/flights#log", label: "Flight Log", icon: "log" },
  { href: "/flights", label: "Flight Map", icon: "map" },
  { href: "/plan", label: "Flight Plan", icon: "plan" },
] as const;

type IconName = (typeof APP_LINKS)[number]["icon"] | "lock";

function Icon({ name }: { name: IconName }) {
  const paths: Record<IconName, React.ReactNode> = {
    // A logbook: a bound book with ruled lines.
    log: (
      <>
        <path d="M4 4.5A1.5 1.5 0 0 1 5.5 3H12v10H5.5A1.5 1.5 0 0 0 4 14.5z" />
        <path d="M4 14.5A1.5 1.5 0 0 0 5.5 16H12v-3" />
        <path d="M6.5 6h3M6.5 8.5h3" />
      </>
    ),
    // A globe.
    map: (
      <>
        <circle cx="8" cy="9" r="6" />
        <path d="M2 9h12M8 3c-2.2 2.4-2.2 9.6 0 12M8 3c2.2 2.4 2.2 9.6 0 12" />
      </>
    ),
    // A route between two waypoints.
    plan: (
      <>
        <circle cx="3.8" cy="13.2" r="1.6" />
        <circle cx="12.2" cy="4.8" r="1.6" />
        <path d="M5.3 12.3c3.2-.6 1.6-4.3 5.3-6.6" strokeDasharray="1.6 1.6" />
      </>
    ),
    lock: (
      <>
        <rect x="3.5" y="7.5" width="9" height="7" rx="1.5" />
        <path d="M5.5 7.5V5.5a2.5 2.5 0 0 1 5 0v2" />
      </>
    ),
  };
  return (
    <svg
      viewBox="0 0 16 18"
      width="15"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

// On the landing page: working buttons once signed in; before that, the same
// buttons greyed out behind a lock, so visitors can see what an account gets
// them.
export function AppButtons({ signedIn }: { signedIn: boolean }) {
  if (signedIn) {
    return (
      <nav aria-label="Your flights" className={styles.appLinks}>
        {APP_LINKS.map((link) => (
          <Link key={link.href} href={link.href} className={styles.appLink}>
            <Icon name={link.icon} />
            {link.label}
          </Link>
        ))}
      </nav>
    );
  }
  return (
    <div className={styles.appButtons}>
      <div className={styles.appLinks}>
        {APP_LINKS.map((link) => (
          <span
            key={link.href}
            className={`${styles.appLink} ${styles.appLinkLocked}`}
            aria-disabled="true"
            title={`Sign in to use ${link.label}`}
          >
            <Icon name="lock" />
            {link.label}
          </span>
        ))}
      </div>
      <p className={styles.appLinksHint}>Sign in to use these.</p>
    </div>
  );
}
