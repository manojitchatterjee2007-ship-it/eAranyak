﻿-- =============================================================
-- eআরণ্যক — one-time database setup
-- Run this ONCE in: Supabase Dashboard → SQL Editor → New query
-- =============================================================

-- -------------------------------------------------------------
-- 1. DEVICE TOKENS (for FCM push)
-- -------------------------------------------------------------
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

drop policy if exists "clients manage own token" on public.device_tokens;
create policy "clients manage own token"
  on public.device_tokens
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- -------------------------------------------------------------
-- 2. WEEKLY GAME CHALLENGES
--    (4 rows per week: photo / audio / hint / scramble;
--     old weeks are deleted by the rotate-weekly-games function)
-- -------------------------------------------------------------
create table if not exists public.weekly_challenges (
  id uuid not null default gen_random_uuid() primary key,
  week_start date not null,
  category text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (week_start, category)
);

alter table public.weekly_challenges enable row level security;

drop policy if exists "anyone read weekly challenges" on public.weekly_challenges;
create policy "anyone read weekly challenges"
  on public.weekly_challenges
  for select
  to anon, authenticated
  using (true);

-- -------------------------------------------------------------
-- 3. CRON SCHEDULES (pg_cron + pg_net)
-- -------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 3a. Refresh wildlife news every 30 minutes (server-side fetch from
--     Mongabay India RSS + Sanctuary Nature Foundation into wildlife_news,
--     so background Workmanager notifications have fresh content
--     even when no user has the app open).
--     NOTE: cron.schedule() with an existing jobname raises a duplicate
--     error, so we drop any pre-existing (possibly corrupt) schedule first
--     — this makes the script safely re-runnable.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fetch-news-every-30min') then
    perform cron.unschedule('fetch-news-every-30min');
  end if;
end $$;

select cron.schedule(
  'fetch-news-every-30min',
  '*/30 * * * *',
  $$
  select net.http_post(
    url := 'https://btbcojfuipogpsarjcdw.supabase.co/functions/v1/refresh-wildlife-news',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- 3b. Rotate weekly game challenges every Monday 03:00 UTC
--     (new challenges in, old challenges deleted, users notified).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'rotate-weekly-games-monday') then
    perform cron.unschedule('rotate-weekly-games-monday');
  end if;
end $$;

select cron.schedule(
  'rotate-weekly-games-monday',
  '0 3 * * 1',
  $$
  select net.http_post(
    url := 'https://btbcojfuipogpsarjcdw.supabase.co/functions/v1/rotate-weekly-games',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Verify schedules with:
--   select jobname, schedule, active from cron.job;
-- Check recent run results with:
--   select status, return_message, start_time
--   from cron.job_run_details
--   order by start_time desc limit 10;

