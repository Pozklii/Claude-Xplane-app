-- Flight ratings and favourite airline/aircraft. Safe to run more than
-- once; run it in the Supabase SQL editor on a project that already has
-- the tables from ../schema.sql.

alter table public.flights
  add column if not exists rating smallint
  check (rating between 1 and 10);

create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  favourite_airline text,
  favourite_aircraft text,
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

drop policy if exists "Users can view their own preferences"
  on public.user_preferences;
create policy "Users can view their own preferences"
  on public.user_preferences for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own preferences"
  on public.user_preferences;
create policy "Users can insert their own preferences"
  on public.user_preferences for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own preferences"
  on public.user_preferences;
create policy "Users can update their own preferences"
  on public.user_preferences for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
