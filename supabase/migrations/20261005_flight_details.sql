-- Extra, optional details for each logged flight: runway times, landing
-- rate, fuel, light conditions and the weather. Safe to run more than
-- once; run it in the Supabase SQL editor on a project that already has
-- the tables from ../schema.sql (the app works without it, just without
-- these details).

alter table public.flights
  add column if not exists takeoff_time time,
  add column if not exists landing_time time,
  add column if not exists landing_rate_fpm smallint
    check (landing_rate_fpm between 0 and 5000),
  add column if not exists fuel_used numeric(8, 1)
    check (fuel_used >= 0),
  add column if not exists fuel_unit text
    check (fuel_unit in ('kg', 'lb')),
  add column if not exists conditions text
    check (conditions in ('day', 'night', 'twilight')),
  add column if not exists weather text;
