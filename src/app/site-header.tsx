import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./login/actions";

export async function SiteHeader() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <header className="flex items-center justify-between border-b border-black/[.08] px-6 py-4 dark:border-white/[.145]">
      <Link
        href="/"
        className="text-sm font-semibold text-black dark:text-zinc-50"
      >
        Flight Tracker
      </Link>
      <nav className="flex items-center gap-4 text-sm">
        {user ? (
          <>
            <Link
              href="/flights"
              className="text-zinc-600 hover:text-black dark:text-zinc-400 dark:hover:text-zinc-50"
            >
              Flights
            </Link>
            <form action={signOut}>
              <button
                type="submit"
                className="text-zinc-600 hover:text-black dark:text-zinc-400 dark:hover:text-zinc-50"
              >
                Sign out
              </button>
            </form>
          </>
        ) : (
          <Link
            href="/login"
            className="text-zinc-600 hover:text-black dark:text-zinc-400 dark:hover:text-zinc-50"
          >
            Sign in
          </Link>
        )}
      </nav>
    </header>
  );
}

export function SiteHeaderFallback() {
  return (
    <header className="flex items-center justify-between border-b border-black/[.08] px-6 py-4 dark:border-white/[.145]">
      <span className="text-sm font-semibold text-black dark:text-zinc-50">
        Flight Tracker
      </span>
      <nav />
    </header>
  );
}
