# Flight World

A web app for logging and reviewing flights, built with Next.js, Supabase, and deployed on Vercel.

## Stack

- [Next.js](https://nextjs.org) (App Router, TypeScript, Tailwind CSS)
- [Supabase](https://supabase.com) for auth and data storage
- [Vercel](https://vercel.com) for hosting, deployed from this GitHub repo

## Getting started

1. Install dependencies:

   ```bash
   npm install
   ```

2. Create a Supabase project at [supabase.com](https://supabase.com), then copy `.env.local.example` to `.env.local` and fill in your project's URL and anon key (Project Settings → API):

   ```bash
   cp .env.local.example .env.local
   ```

3. Create the `flights` table and its row-level security policies by running [`supabase/schema.sql`](./supabase/schema.sql) in your project's SQL editor (Supabase dashboard → SQL Editor → New query).

4. In the Supabase dashboard, under Authentication → URL Configuration, set the **Site URL** to `http://localhost:3000` for local development (and add your Vercel domain once deployed). Email/password sign-up is enabled by default and requires confirming a link sent by email before a user can sign in.

5. Run the dev server:

   ```bash
   npm run dev
   ```

   Open [http://localhost:3000](http://localhost:3000).

## Deploying

Import this repository in [Vercel](https://vercel.com/new), add the same two environment variables from `.env.local` in the project's settings, and deploy. Every push to `main` will trigger a new deployment.

After deploying, add your Vercel URL (and any preview URLs) to Supabase's Authentication → URL Configuration → Redirect URLs so email confirmation links work in production.

## Features

- A landing page (`/`) with an animated day/night sky (sun and drifting clouds in light mode, a moon and twinkling stars in dark mode — pure CSS, driven by `prefers-color-scheme`) and a live example globe using the same `FlightGlobe` component as the flights page, seeded with a sample JFK → LHR → CDG route
- Email/password sign-up and sign-in via Supabase Auth (`/login`)
- A protected `/flights` page for logging and reviewing your flights (date, airline, aircraft, route, hours, notes), backed by a `flights` table scoped to each user via row-level security
- A rotatable 3D globe on the flights page, rendered with [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/) over free, no-API-key [OpenStreetMap](https://www.openstreetmap.org/copyright) vector tiles from [OpenFreeMap](https://openfreemap.org/) (swap `STYLE_URL` in `flight-globe.tsx` for a MapTiler/Mapbox satellite style if you have a key). Flight routes and airport markers are drawn with [deck.gl](https://deck.gl/)'s `ArcLayer` and `ScatterplotLayer`, composited into the MapLibre render pass via `@deck.gl/mapbox`'s `MapboxOverlay` (`interleaved: true`), styled as glowing cyan-to-violet plasma arcs and satellite-like markers (a wide, low-opacity layer under a thin, bright one approximates the glow, since deck.gl has no native bloom). Clicking a route highlights it on the globe (with its two airports' city/code labels) and highlights the matching entry in the flight log below, and vice versa. Airport coordinates come from a bundled ICAO/IATA lookup — no coordinates to enter manually.
  - **Pinned to `maplibre-gl@5`, not the current v6** — v6 changed how it bundles its background Web Worker (used to process map data off the main thread), and that pattern doesn't get picked up correctly by Next.js's Turbopack: no worker is ever created, so every GeoJSON layer (the flight routes and airport markers) silently renders nothing, with no error. v5 doesn't hit this. Worth re-testing after a Turbopack or MapLibre update in case it's since been fixed upstream, but don't bump the major version without confirming flights actually render on the globe first.
  - deck.gl's `ArcLayer` needs `parameters: { cullMode: "none" }` under the globe projection — `GlobeView` back-face-culls by default, which otherwise hides most of an arc's tube geometry depending on viewing angle.
  - Click-to-select on the arcs is driven by MapLibre's own `click` event calling `overlay.pickObject()` directly, rather than the `ArcLayer`'s own `onClick` prop — in `interleaved: true` mode, MapLibre owns input handling and only forwards a subset of events to deck.gl, so a layer's `onClick` doesn't reliably fire from real clicks even though picking itself works.
- Screenshots/videos per flight, uploaded to a private Supabase Storage bucket (`flight-media`) scoped to each user

## Roadmap

- [x] Landing page
- [x] Supabase auth (sign up / log in)
- [x] Flight log CRUD (create, view, delete flights)
- [x] Flight route globe
- [x] Per-flight media (screenshots/videos)
- [ ] Editing existing flights
- [ ] Flight history / stats view
