import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { HeaderLinks } from "./header-links";
import { signOut } from "./login/actions";

export async function SiteHeader() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <header className="flex items-center justify-between gap-4 border-b border-black/[.08] px-6 py-4 dark:border-white/[.145]">
      <Link
        href="/"
        className="text-sm font-semibold text-black dark:text-zinc-50"
      >
        Flight World
      </Link>
      <nav className="flex flex-wrap items-center justify-end gap-x-4 gap-y-1 text-sm">
        {user ? (
          <>
            <HeaderLinks />
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
        Flight World
      </span>
      <nav />
    </header>
  );
}
