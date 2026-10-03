"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { APP_LINKS } from "./app-links";

// The header's links to the app's three pages, once signed in, with the
// page you're on marked.
export function HeaderLinks() {
  const pathname = usePathname();
  return APP_LINKS.map((link) => {
    const current =
      pathname === link.href || pathname.startsWith(`${link.href}/`);
    return (
      <Link
        key={link.href}
        href={link.href}
        aria-current={current ? "page" : undefined}
        className={
          current
            ? "font-medium text-black dark:text-zinc-50"
            : "text-zinc-600 hover:text-black dark:text-zinc-400 dark:hover:text-zinc-50"
        }
      >
        {/* "Flight Map" etc., shortened to "Map" on phones. */}
        <span className="hidden sm:inline">Flight </span>
        {link.label.replace(/^Flight /, "")}
      </Link>
    );
  });
}
