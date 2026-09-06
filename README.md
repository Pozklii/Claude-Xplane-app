# Flight Tracker

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

- Email/password sign-up and sign-in via Supabase Auth (`/login`)
- A protected `/flights` page for logging and reviewing your flights, backed by a `flights` table scoped to each user via row-level security

## Roadmap

- [x] Landing page
- [x] Supabase auth (sign up / log in)
- [x] Flight log CRUD (create, view, delete flights)
- [ ] Editing existing flights
- [ ] Flight history / stats view
