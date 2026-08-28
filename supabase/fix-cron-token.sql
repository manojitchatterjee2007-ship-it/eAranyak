-- =============================================================
-- eআরণ্যক — CRON + NEWS PIPELINE REPAIR (run ONCE in SQL Editor)
-- Fixes three problems on the live project:
--  1. The scheduled cron jobs contained a corrupted Authorization
--     token (stray ';bGci...' fragment) → every run failed.
--  2. The news cron pointed at fetch-news-article, which is a
--     single-article reader requiring a 'url' param → always 400.
--     It now points at refresh-wildlife-news, which actually
--     populates the wildlife_news table (deploy that function first!).
--  3. The empty wildlife_news table is normalized so inserts from
--     the refresher always succeed (safe: table had 0 rows).
-- Safe to re-run.
-- =============================================================

-- -------------------------------------------------------------
-- 0. Normalize the wildlife_news table (idempotent)
-- -------------------------------------------------------------
create table if not exists public.wildlife_news (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  snippet text not null default '',
  content text not null default '',
  source text not null default '',
  source_url text,
  image_url text,
  category text not null default 'forest',
  date_str text not null default '',
  img_tags text not null default 'wildlife,nature,watercolor',
  created_at timestamptz not null default now()
);

alter table public.wildlife_news add column if not exists title text not null default '';
alter table public.wildlife_news add column if not exists snippet text not null default '';
alter table public.wildlife_news add column if not exists content text not null default '';
alter table public.wildlife_news add column if not exists source text not null default '';
alter table public.wildlife_news add column if not exists source_url text;
alter table public.wildlife_news add column if not exists image_url text;
alter table public.wildlife_news add column if not exists category text not null default 'forest';
alter table public.wildlife_news add column if not exists date_str text not null default '';
alter table public.wildlife_news add column if not exists img_tags text not null default 'wildlife,nature,watercolor';
alter table public.wildlife_news add column if not exists created_at timestamptz not null default now();

create unique index if not exists wildlife_news_source_url_key
  on public.wildlife_news (source_url);

alter table public.wildlife_news enable row level security;

drop policy if exists "anyone read wildlife news" on public.wildlife_news;
create policy "anyone read wildlife news"
  on public.wildlife_news
  for select
  to anon, authenticated
  using (true);

-- -------------------------------------------------------------
-- 1. Drop any existing (broken) schedules
-- -------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fetch-news-every-30min') then
    perform cron.unschedule('fetch-news-every-30min');
  end if;
  if exists (select 1 from cron.job where jobname = 'rotate-weekly-games-monday') then
    perform cron.unschedule('rotate-weekly-games-monday');
  end if;
end $$;

-- -------------------------------------------------------------
-- 2a. Refresh wildlife news every 30 minutes
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 2b. Rotate weekly game challenges every Monday 03:00 UTC
-- -------------------------------------------------------------
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

-- Confirm ------------------------------------------------------
select jobname, schedule, active from cron.job;

-- 3b. Rotate weekly game challenges every Monday 03:00 UTC ----
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

-- Confirm ------------------------------------------------------
select jobname, schedule, active from cron.job;