-- eআরণ্যক news pipeline cleanup
-- Run after creating the Edge Function secrets described in README.md.

-- 1. Ensure the news tables have the columns required by the pipeline.
alter table public.wildlife_news
  add column if not exists source_url text;
alter table public.wildlife_news
  add column if not exists image_url text;
alter table public.wildlife_news
  add column if not exists category text not null default 'forest';
alter table public.wildlife_news
  add column if not exists date_str text not null default '';
alter table public.wildlife_news
  add column if not exists img_tags text not null default 'wildlife,nature,watercolor';
alter table public.wildlife_news
  add column if not exists created_at timestamptz not null default now();

-- Duplicate URLs must be removed before this index can be created.
-- If this reports duplicates, run the diagnostic query in README.md first.
create unique index if not exists wildlife_news_source_url_uidx
  on public.wildlife_news (source_url)
  where source_url is not null and source_url <> '';

create table if not exists public.wildlife_news_translations (
  source_url text primary key,
  headline text not null,
  dek text,
  body text,
  created_at timestamptz not null default now()
);

alter table public.wildlife_news_translations enable row level security;

drop policy if exists "translations readable by everyone"
  on public.wildlife_news_translations;
create policy "translations readable by everyone"
  on public.wildlife_news_translations
  for select using (true);

-- Writes are performed by the service-role Edge Function only.
drop policy if exists "anyone can insert translations"
  on public.wildlife_news_translations;
drop policy if exists "anyone can update translations"
  on public.wildlife_news_translations;

-- Foreign key: translations must belong to a news row.
alter table public.wildlife_news_translations
  drop constraint if exists fk_wildlife_news;

alter table public.wildlife_news_translations
  add constraint fk_wildlife_news
  foreign key (source_url)
  references public.wildlife_news(source_url)
  on delete cascade;

-- 2. Remove the old/duplicated news cron and recreate exactly one job.
do $$
begin
  perform cron.unschedule('fetch-news-every-30min');
exception when others then
  null;
end $$;

-- The cron job reads project_url and news_refresh_secret from Supabase Vault.
-- Create those two Vault secrets before enabling this job (see README.md).
select cron.schedule(
  'fetch-news-every-30min',
  '*/30 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/refresh-wildlife-news',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-news-refresh-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'news_refresh_secret')
    ),
    body := '{}'::jsonb
  ) as request_id;
  $$
);

-- 3. Optional diagnostic queries:
-- select jobid, jobname, schedule, active from cron.job order by jobname;
-- select source_url, count(*) from public.wildlife_news
--   where source_url is not null and source_url <> ''
--   group by source_url having count(*) > 1;
