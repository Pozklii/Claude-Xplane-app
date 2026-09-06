-- Run this in the Supabase SQL editor (or via the Supabase CLI) for your project.

create table if not exists public.flights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  flown_on date not null,
  aircraft text not null,
  departure text not null,
  arrival text not null,
  hours numeric(5, 1) not null check (hours > 0),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists flights_user_id_flown_on_idx
  on public.flights (user_id, flown_on desc);

alter table public.flights enable row level security;

create policy "Users can view their own flights"
  on public.flights for select
  using (auth.uid() = user_id);

create policy "Users can insert their own flights"
  on public.flights for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own flights"
  on public.flights for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their own flights"
  on public.flights for delete
  using (auth.uid() = user_id);
