-- =============================================================================
-- eআরণ্যক — Tutorials Automated Pipeline & Monthly Rotation Migration
-- =============================================================================

-- 1. Ensure tutorials table has source tracking columns
ALTER TABLE public.tutorials
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_name text,
  ADD COLUMN IF NOT EXISTS source_article_id text;

-- 2. Unique index on source_url for duplicate protection
CREATE UNIQUE INDEX IF NOT EXISTS tutorials_source_url_uidx
  ON public.tutorials (source_url)
  WHERE source_url is not null and source_url <> '';

-- 3. Enable RLS on tutorials if not already enabled
ALTER TABLE public.tutorials ENABLE ROW LEVEL SECURITY;

-- 4. Schedule monthly tutorial rotation via pg_cron (1st of every month at 2:30 AM)
do $$
begin
  if exists (select 1 from cron.job where jobname = 'refresh-tutorials-monthly') then
    perform cron.unschedule('refresh-tutorials-monthly');
  end if;
end $$;

select cron.schedule(
  'refresh-tutorials-monthly',
  '30 2 1 * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/refresh-tutorials',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-tutorial-refresh-secret',
      coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'tutorial_refresh_secret'),
        (select decrypted_secret from vault.decrypted_secrets where name = 'news_refresh_secret')
      )
    ),
    body := '{}'::jsonb
  ) as request_id;
  $$
);
