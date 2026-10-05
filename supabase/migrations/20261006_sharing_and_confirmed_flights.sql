-- Confirmed flights kept with the account (not just one browser), and
-- optional public share links for a user's flight map and stats. Safe to
-- run more than once; run it in the Supabase SQL editor on a project that
-- already has ../schema.sql and the earlier migrations.

-- The flight a user has confirmed on the Flight Plan page and not yet
-- logged (at most one each). Null once it's logged or cancelled, with the
-- time of that change, so a browser still holding the old one knows it's
-- out of date rather than putting it back.
create table if not exists public.confirmed_flights (
  user_id uuid primary key references auth.users (id) on delete cascade,
  flight jsonb,
  updated_at timestamptz not null default now()
);

alter table public.confirmed_flights enable row level security;

drop policy if exists "Users can view their own confirmed flight"
  on public.confirmed_flights;
create policy "Users can view their own confirmed flight"
  on public.confirmed_flights for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own confirmed flight"
  on public.confirmed_flights;
create policy "Users can insert their own confirmed flight"
  on public.confirmed_flights for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own confirmed flight"
  on public.confirmed_flights;
create policy "Users can update their own confirmed flight"
  on public.confirmed_flights for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own confirmed flight"
  on public.confirmed_flights;
create policy "Users can delete their own confirmed flight"
  on public.confirmed_flights for delete
  using (auth.uid() = user_id);

-- A user's public share link: an unguessable id, and the name shown on
-- the shared page. No row (or a deleted one) means not shared.
create table if not exists public.flight_shares (
  user_id uuid primary key references auth.users (id) on delete cascade,
  share_id text not null unique check (share_id ~ '^[A-Za-z0-9_-]{16,64}$'),
  display_name text check (char_length(display_name) <= 60),
  created_at timestamptz not null default now()
);

alter table public.flight_shares enable row level security;

drop policy if exists "Users can view their own share link"
  on public.flight_shares;
create policy "Users can view their own share link"
  on public.flight_shares for select
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own share link"
  on public.flight_shares;
create policy "Users can create their own share link"
  on public.flight_shares for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own share link"
  on public.flight_shares;
create policy "Users can update their own share link"
  on public.flight_shares for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own share link"
  on public.flight_shares;
create policy "Users can delete their own share link"
  on public.flight_shares for delete
  using (auth.uid() = user_id);

-- What a share link shows, to anyone with it: the display name and each
-- flight's date, route, airline, aircraft, hours and flight details.
-- Notes, photos and the owner's account are never included. Runs with
-- its owner's rights (so visitors need no access to the tables), and only
-- for a share id that exists.
create or replace function public.shared_flight_map(p_share_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'display_name', s.display_name,
    'flights', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', md5(f.id::text),
            'flown_on', f.flown_on,
            'airline', f.airline,
            'aircraft', f.aircraft,
            'departure', f.departure,
            'arrival', f.arrival,
            'hours', f.hours,
            'rating', f.rating,
            'takeoff_time', f.takeoff_time,
            'landing_time', f.landing_time,
            'landing_rate_fpm', f.landing_rate_fpm,
            'conditions', f.conditions,
            'weather', f.weather
          )
          order by f.flown_on desc
        )
        from public.flights f
        where f.user_id = s.user_id
      ),
      '[]'::jsonb
    )
  )
  from public.flight_shares s
  where s.share_id = p_share_id;
$$;

revoke all on function public.shared_flight_map(text) from public;
grant execute on function public.shared_flight_map(text) to anon, authenticated;
