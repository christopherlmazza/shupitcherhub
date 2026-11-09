-- SHUpitcherhub — throwing-program tables for the team's existing Supabase project.
-- Run once: Supabase dashboard → SQL Editor → New query → paste this whole file → Run.
-- Before running, replace COACH_EMAIL_HERE (bottom of file) with the coach's sign-in email.
-- Safe to re-run: every statement checks before creating.

create table if not exists public.staff (
  email text primary key
);

create table if not exists public.athletes (
  id          text primary key,
  name        text not null,
  nickname    text,
  role        text,                 -- SP / RP / blank
  targets     jsonb default '{}',   -- {"ip":5,"pitches":75}
  role_note   text,
  email       text,                 -- the athlete's sign-in email (set by the coach)
  profile     jsonb default '{}',   -- goals, warm-up, program cards, return-to-throw, Drive links, velo log
  archive     jsonb default '{}',   -- every cell of the original Google Sheet, kept as a backup
  updated_at  timestamptz default now()
);

create table if not exists public.programs (
  id          uuid primary key default gen_random_uuid(),
  athlete_id  text references public.athletes(id) on delete cascade,
  title       text not null,
  start_date  date not null,
  end_date    date not null,
  days        jsonb not null default '{}',  -- {"2026-11-09":{"type":"Hybrid B","throws":60,"intensity":70,"notes":""}}
  source      text default 'app',
  created_at  timestamptz default now()
);

create table if not exists public.logs (
  id          uuid primary key default gen_random_uuid(),
  athlete_id  text references public.athletes(id) on delete cascade,
  date        date not null,
  type        text,          -- what was actually done (Recovery, Hybrid B, ...)
  checkin     int,           -- 0 = fresh, 10 = awful pain
  throws      int,
  intensity   int,           -- % effort
  innings     numeric,
  pitches     int,
  bullpen     text,
  notes       text,
  source      text default 'app',
  updated_at  timestamptz default now(),
  unique (athlete_id, date)
);

create table if not exists public.templates (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  weeks       jsonb not null,  -- [[{"type":"Rest","throws":null,"intensity":null}, ...7], ...]
  created_at  timestamptz default now()
);

create table if not exists public.settings (
  key   text primary key,
  value jsonb
);

-- Who is who -------------------------------------------------------------
create or replace function public.is_coach() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

create or replace function public.my_athlete_id() returns text
language sql stable security definer set search_path = public as $$
  select id from public.athletes where lower(email) = lower(auth.jwt() ->> 'email') limit 1;
$$;

alter table public.staff     enable row level security;
alter table public.athletes  enable row level security;
alter table public.programs  enable row level security;
alter table public.logs      enable row level security;
alter table public.templates enable row level security;
alter table public.settings  enable row level security;

drop policy if exists staff_read  on public.staff;
drop policy if exists staff_write on public.staff;
create policy staff_read  on public.staff for select to authenticated using (public.is_coach() or lower(email) = lower(auth.jwt() ->> 'email'));
create policy staff_write on public.staff for all    to authenticated using (public.is_coach()) with check (public.is_coach());

drop policy if exists athletes_read  on public.athletes;
drop policy if exists athletes_write on public.athletes;
create policy athletes_read  on public.athletes for select to authenticated using (public.is_coach() or id = public.my_athlete_id());
create policy athletes_write on public.athletes for all    to authenticated using (public.is_coach()) with check (public.is_coach());

drop policy if exists programs_read  on public.programs;
drop policy if exists programs_write on public.programs;
create policy programs_read  on public.programs for select to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id());
create policy programs_write on public.programs for all    to authenticated using (public.is_coach()) with check (public.is_coach());

drop policy if exists logs_read   on public.logs;
drop policy if exists logs_insert on public.logs;
drop policy if exists logs_update on public.logs;
drop policy if exists logs_delete on public.logs;
create policy logs_read   on public.logs for select to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id());
create policy logs_insert on public.logs for insert to authenticated with check (public.is_coach() or athlete_id = public.my_athlete_id());
create policy logs_update on public.logs for update to authenticated using (public.is_coach() or athlete_id = public.my_athlete_id()) with check (public.is_coach() or athlete_id = public.my_athlete_id());
create policy logs_delete on public.logs for delete to authenticated using (public.is_coach());

drop policy if exists templates_read  on public.templates;
drop policy if exists templates_write on public.templates;
create policy templates_read  on public.templates for select to authenticated using (true);
create policy templates_write on public.templates for all    to authenticated using (public.is_coach()) with check (public.is_coach());

drop policy if exists settings_read  on public.settings;
drop policy if exists settings_write on public.settings;
create policy settings_read  on public.settings for select to authenticated using (true);
create policy settings_write on public.settings for all    to authenticated using (public.is_coach()) with check (public.is_coach());

-- The coach account ------------------------------------------------------
insert into public.staff (email) values ('COACH_EMAIL_HERE') on conflict do nothing;
