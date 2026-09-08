"use client";

import { useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { login, signup } from "./actions";

export function LoginForm() {
  const searchParams = useSearchParams();
  const checkEmail = searchParams.get("checkEmail") === "1";

  const [loginState, loginAction, loginPending] = useActionState(
    login,
    undefined,
  );
  const [signupState, signupAction, signupPending] = useActionState(
    signup,
    undefined,
  );

  return (
    <div className="flex flex-1 items-center justify-center bg-zinc-50 px-6 py-24 font-sans dark:bg-black">
      <div className="flex w-full max-w-sm flex-col gap-10">
        <div className="flex flex-col gap-1 text-center">
          <h1 className="text-2xl font-semibold text-black dark:text-zinc-50">
            Flight World
          </h1>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Sign in or create an account to log your flights.
          </p>
        </div>

        {checkEmail && (
          <p className="rounded-xl border border-black/[.08] bg-white p-3 text-center text-sm text-zinc-700 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-300">
            Check your email to confirm your account, then sign in below.
          </p>
        )}

        <form action={loginAction} className="flex flex-col gap-3">
          <input
            name="email"
            type="email"
            placeholder="Email"
            required
            autoComplete="email"
            className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
          />
          <input
            name="password"
            type="password"
            placeholder="Password"
            required
            autoComplete="current-password"
            className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
          />
          {loginState?.error && (
            <p className="text-sm text-red-600 dark:text-red-400">
              {loginState.error}
            </p>
          )}
          <button
            type="submit"
            disabled={loginPending}
            className="rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] disabled:opacity-60 dark:hover:bg-[#ccc]"
          >
            {loginPending ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <div className="flex items-center gap-3 text-xs text-zinc-400">
          <div className="h-px flex-1 bg-black/[.08] dark:bg-white/[.145]" />
          or
          <div className="h-px flex-1 bg-black/[.08] dark:bg-white/[.145]" />
        </div>

        <form action={signupAction} className="flex flex-col gap-3">
          <input
            name="email"
            type="email"
            placeholder="Email"
            required
            autoComplete="email"
            className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
          />
          <input
            name="password"
            type="password"
            placeholder="Password (min. 6 characters)"
            required
            minLength={6}
            autoComplete="new-password"
            className="rounded-lg border border-black/[.08] bg-white px-3 py-2 text-sm text-black outline-none focus:border-black/30 dark:border-white/[.145] dark:bg-zinc-950 dark:text-zinc-50"
          />
          {signupState?.error && (
            <p className="text-sm text-red-600 dark:text-red-400">
              {signupState.error}
            </p>
          )}
          <button
            type="submit"
            disabled={signupPending}
            className="rounded-full border border-black/[.08] px-5 py-2 text-sm font-medium text-black transition-colors hover:bg-black/[.04] disabled:opacity-60 dark:border-white/[.145] dark:text-zinc-50 dark:hover:bg-[#1a1a1a]"
          >
            {signupPending ? "Creating account…" : "Create account"}
          </button>
        </form>
      </div>
    </div>
  );
}
