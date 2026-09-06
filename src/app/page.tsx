import Link from "next/link";

const features = [
  {
    title: "Log every flight",
    description:
      "Capture aircraft, route, times, and notes for each flight as soon as you land.",
  },
  {
    title: "See your history",
    description:
      "Browse past flights, filter by aircraft or route, and track hours over time.",
  },
  {
    title: "Your data, backed up",
    description:
      "Flights are stored in Supabase and tied to your account, accessible from anywhere.",
  },
];

export default function Home() {
  return (
    <div className="flex flex-1 flex-col bg-zinc-50 font-sans dark:bg-black">
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col items-center justify-center gap-12 px-6 py-24 text-center">
        <div className="flex flex-col items-center gap-4">
          <span className="rounded-full border border-black/[.08] px-3 py-1 text-sm font-medium text-zinc-600 dark:border-white/[.145] dark:text-zinc-400">
            Flight Tracker
          </span>
          <h1 className="text-4xl font-semibold tracking-tight text-black sm:text-5xl dark:text-zinc-50">
            Track your flights, effortlessly.
          </h1>
          <p className="max-w-xl text-lg leading-8 text-zinc-600 dark:text-zinc-400">
            A simple place to log flights, review your history, and keep
            track of the hours you&apos;ve flown.
          </p>
          <Link
            href="/login"
            className="rounded-full bg-foreground px-5 py-2 text-sm font-medium text-background transition-colors hover:bg-[#383838] dark:hover:bg-[#ccc]"
          >
            Get started
          </Link>
        </div>

        <div className="grid w-full grid-cols-1 gap-6 text-left sm:grid-cols-3">
          {features.map((feature) => (
            <div
              key={feature.title}
              className="flex flex-col gap-2 rounded-2xl border border-black/[.08] p-6 dark:border-white/[.145]"
            >
              <h2 className="font-semibold text-black dark:text-zinc-50">
                {feature.title}
              </h2>
              <p className="text-sm leading-6 text-zinc-600 dark:text-zinc-400">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
