-- Automatic logging from X-Plane, the route actually flown, and SimBrief
-- plans. Safe to run more than once; run it in the Supabase SQL editor on
-- a project that already has ../schema.sql and the earlier migrations.
-- Until it's run the app still works, just without these.

-- The flown route (from X-Plane, or an uploaded GPX/KML/CSV file):
-- { "summary": { "source", "points", "distanceNm", "maxAltitudeFt",
-- "fuelUsedKg"? }, "points": [[lon, lat, altitudeFt], ...] }. And the
-- SimBrief plan the flight was flown to, if any (see src/lib/simbrief.ts).
alter table public.flights
  add column if not exists recording jsonb
    check (recording is null or pg_column_size(recording) < 400000),
  add column if not exists plan jsonb
    check (plan is null or pg_column_size(plan) < 20000);

-- A user's X-Plane connection: the companion program sends finished
-- flights with this token. Only its SHA-256 is kept (the token itself is
-- shown once, when made); one per user, replaced by making a new one.
create table if not exists public.xplane_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

alter table public.xplane_tokens enable row level security;

drop policy if exists "Users can view their own X-Plane token"
  on public.xplane_tokens;
create policy "Users can view their own X-Plane token"
  on public.xplane_tokens for select
  using (auth.uid() = user_id);

drop policy if exists "Users can create their own X-Plane token"
  on public.xplane_tokens;
create policy "Users can create their own X-Plane token"
  on public.xplane_tokens for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can replace their own X-Plane token"
  on public.xplane_tokens;
create policy "Users can replace their own X-Plane token"
  on public.xplane_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own X-Plane token"
  on public.xplane_tokens;
create policy "Users can delete their own X-Plane token"
  on public.xplane_tokens for delete
  using (auth.uid() = user_id);

-- Logs a flight sent by the X-Plane companion (through /api/xplane/flights,
-- which works out the airports): adds it to the token owner's log and
-- returns its id, or null for an unknown token. Runs with its owner's
-- rights, since the companion has no signed-in session. If the owner has a
-- confirmed flight on the same route, it's taken as flown: its SimBrief
-- plan (if any) goes with the logged flight and the confirmed flight is
-- cleared.
create or replace function public.log_xplane_flight(
  p_token text,
  p_flight jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_id uuid;
  v_plan jsonb;
begin
  select t.user_id into v_user
  from public.xplane_tokens t
  where t.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  if v_user is null then
    return null;
  end if;

  update public.xplane_tokens
  set last_used_at = now()
  where user_id = v_user;

  select c.flight -> 'plan' into v_plan
  from public.confirmed_flights c
  where c.user_id = v_user
    and c.flight ->> 'from' = p_flight ->> 'departure'
    and c.flight ->> 'to' = p_flight ->> 'arrival';
  if found then
    update public.confirmed_flights
    set flight = null, updated_at = now()
    where user_id = v_user;
  end if;

  insert into public.flights (
    user_id, flown_on, aircraft, departure, arrival, hours, notes,
    takeoff_time, landing_time, landing_rate_fpm, recording, plan
  )
  values (
    v_user,
    (p_flight ->> 'flown_on')::date,
    left(p_flight ->> 'aircraft', 80),
    left(upper(p_flight ->> 'departure'), 8),
    left(upper(p_flight ->> 'arrival'), 8),
    (p_flight ->> 'hours')::numeric(5, 1),
    left(p_flight ->> 'notes', 500),
    (p_flight ->> 'takeoff_time')::time,
    (p_flight ->> 'landing_time')::time,
    (p_flight ->> 'landing_rate_fpm')::smallint,
    case when jsonb_typeof(p_flight -> 'recording') = 'object'
      then p_flight -> 'recording' end,
    case when jsonb_typeof(v_plan) = 'object' then v_plan end
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.log_xplane_flight(text, jsonb) from public;
grant execute on function public.log_xplane_flight(text, jsonb)
  to anon, authenticated;

-- Whether a token is a live X-Plane connection (the companion checks its
-- token when it starts, before any flight).
create or replace function public.check_xplane_token(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.xplane_tokens t
    where t.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
  );
$$;

revoke all on function public.check_xplane_token(text) from public;
grant execute on function public.check_xplane_token(text)
  to anon, authenticated;
