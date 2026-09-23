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

Free-tier Supabase projects are paused after a period of inactivity. While paused, the auth API is unreachable and sign-in/sign-up fail with a "can't reach the sign-in service" message — restore the project from the Supabase dashboard (it takes a few minutes to come back up).

## Features

- A landing page (`/`) with a dark aviation/instrument-panel look — brushed-metal panel seams, HUD-style corner brackets, converging livery lines feeding into a generatively-drawn turbofan engine (spinning blades via CSS animation) — and a live example globe using the same `FlightGlobe` component as the flights page. The globe tours an endless stream of generated example flights: every 7 seconds it generates a new one and flies onto it, keeping the last six drawn. They're built from a table of real airlines on routes they're known for, with aircraft types they typically fly there, plus a few private/GA hops (`src/lib/example-flights/routes.ts`); the generator (`src/lib/example-flights/generate.ts`) randomizes direction, aircraft, date and notes, and estimates flight time from the real great-circle distance and the aircraft's cruise speed. Airport coordinates come from the bundled OurAirports lookup, and routes crossing the antimeridian are skipped. A summary card (the same one as the flights page, minus thumbnail and close) shows its route, distance, flight time, date, aircraft, airline and notes. The tour can be paused, and a visitor's own click on the globe holds for 20 seconds before it carries on. The artwork hero fills the top three quarters of the viewport and a plain black band with the feature blurbs the bottom quarter (a 3:1 flex split). All of the decorative SVG chrome is computed once at module load in `page.tsx` (deterministic, no client JS needed), and it's a deliberately single dark theme rather than adapting to light/dark preference.
- Email/password sign-up and sign-in via Supabase Auth (`/login`)
- A protected `/flights` page for logging and reviewing your flights (date, airline, aircraft, route, hours, notes), backed by a `flights` table scoped to each user via row-level security
- A rotatable, self-rotating 3D globe on the flights page — the same frameless, circular globe as the landing page, on the same dark ground (bare mode leaves the land transparent so that ground shows through) — rendered with [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/) over free, no-API-key [OpenStreetMap](https://www.openstreetmap.org/copyright) vector tiles from [OpenFreeMap](https://openfreemap.org/) (swap `STYLE_URL` in `flight-globe.tsx` for a MapTiler/Mapbox satellite style if you have a key). Idle at the overview zoom, it spins slowly on its own (nudging the center longitude every frame, not the bearing, so it reads as the Earth turning rather than the camera orbiting) — paused for the duration of any drag/rotate/pitch gesture or programmatic camera move, and skipped entirely under `prefers-reduced-motion`. Flight routes are drawn with [deck.gl](https://deck.gl/)'s `ArcLayer`, composited into the MapLibre render pass via `@deck.gl/mapbox`'s `MapboxOverlay` (`interleaved: true`), styled as glowing arcs in one flat color end to end (a wide, low-opacity layer under a thin, bright one approximates the glow, since deck.gl has no native bloom) — airports have no visible marker (a flat disc on the globe's surface z-fights with it and flickers), but a fully transparent `ScatterplotLayer` keeps them clickable, since deck.gl picks by its own picking colors rather than fill alpha. The selected route is drawn as its own pair of layers with constant colors/widths rather than per-arc accessor functions — deck.gl only re-runs accessor functions when the data or an `updateTriggers` entry changes, so a function would keep drawing the old color/selection. Clicking a route highlights it on the globe (with its two airports' city/code labels), highlights the matching entry in the flight log below, and vice versa, and flies the camera in on the two airports with a 55° pitch; deselecting eases back out to the full overview. Clicking an individual airport marker flies in further still (zoom 15, 60° pitch) — close enough for MapLibre's native 3D buildings to render, showing that airport's actual OpenStreetMap building footprints in 3D rather than a generic marker. Airport coordinates come from a bundled ICAO/IATA lookup, derived from [OurAirports](https://ourairports.com/data/) (public domain) — no coordinates to enter manually. On the flights page, a color swatch above the globe lets you pick the color used for every route in place of the default cyan, applied immediately without moving the camera. Selecting a flight (on the globe or in the log) pulses its route's glow while the camera flies in, and animates a details card into the globe band: a thumbnail, the route's city names, great-circle distance (haversine, in nm and km), logged flight time, date, aircraft, airline and the flight's notes — the numbers count up from zero. An always-visible **Add/Change thumbnail** button on the card opens a picker to choose one of the flight's uploaded images or upload a new one; the choice is stored as its own copy at `{user id}/thumbnails/{flight id}/…` in the `flight-media` bucket (already covered by its per-user storage policies, so no schema change), replacing the previous one. Without a chosen thumbnail the card falls back to the flight's first uploaded image, then to a drawn route graphic. All of it is skipped under `prefers-reduced-motion` — remembered in `localStorage`, so it's per-browser rather than synced to your account.
  - The globe's basemap is stripped down to just airports on load: every style layer is hidden (`setLayoutProperty(id, "visibility", "none")`) except water (so it still reads as a globe), the widened `fill-extrusion` buildings above, and anything on the OpenMapTiles `aeroway` / `aerodrome_label` source-layers — an airport's physical layout (runways, taxiways, aprons/stands) and name label. Everything else (place/road/POI labels, landcover/landuse texture, roads, boundaries, hillshading) is otherwise just clutter at globe scale.
  - **Pinned to `maplibre-gl@5`, not the current v6** — v6 changed how it bundles its background Web Worker (used to process map data off the main thread), and that pattern doesn't get picked up correctly by Next.js's Turbopack: no worker is ever created, so every GeoJSON layer (the flight routes and airport markers) silently renders nothing, with no error. v5 doesn't hit this. Worth re-testing after a Turbopack or MapLibre update in case it's since been fixed upstream, but don't bump the major version without confirming flights actually render on the globe first.
  - deck.gl's `ArcLayer` needs `parameters: { cullMode: "none" }` under the globe projection — `GlobeView` back-face-culls by default, which otherwise hides most of an arc's tube geometry depending on viewing angle.
  - Click-to-select is driven by MapLibre's own `click` event calling `overlay.pickObject()` directly, rather than a layer's own `onClick` prop — in `interleaved: true` mode, MapLibre owns input handling and only forwards a subset of events to deck.gl, so a layer's `onClick` doesn't reliably fire from real clicks even though picking itself works.
  - The fly-to camera uses MapLibre's `cameraForBounds()` to fit the two selected airports (falling back to a simple midpoint if it returns nothing, e.g. for antipodal-ish points), rather than hand-computing zoom from the coordinate spread.
  - The style's `fill-extrusion` building layer(s) have their zoom range explicitly widened on load (`map.setLayerZoomRange(id, 0, 24)`) so they're not gated behind whatever minzoom the upstream style tuned for street-level browsing — the actual level of detail still depends on how well OpenStreetMap has mapped that specific airport's buildings; some are well-mapped with individual terminal footprints and heights, others may show little more than the runway/tarmac outline.
- Screenshots/videos per flight, uploaded to a private Supabase Storage bucket (`flight-media`) scoped to each user

## Roadmap

- [x] Landing page
- [x] Supabase auth (sign up / log in)
- [x] Flight log CRUD (create, view, delete flights)
- [x] Flight route globe
- [x] Per-flight media (screenshots/videos)
- [ ] Editing existing flights
- [ ] Flight history / stats view
