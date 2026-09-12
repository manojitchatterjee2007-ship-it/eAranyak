-- Server-driven Bengali wildlife-news publication and FCM delivery ledger.
-- Apply once in the Supabase SQL editor after deploying notify-news-published.

alter table public.wildlife_news
  add column if not exists source_title text,
  add column if not exists original_article_url text,
  add column if not exists source_name text,
  add column if not exists bengali_headline text,
  add column if not exists bengali_dek text,
  add column if not exists bengali_body text,
  add column if not exists content_hash text,
  add column if not exists fetched_at timestamptz,
  add column if not exists processed_at timestamptz,
  add column if not exists published_at timestamptz,
  add column if not exists notification_ready_at timestamptz,
  add column if not exists processing_status text not null default 'pending';

-- Existing source_url uniqueness remains the primary de-duplication rule.
create unique index if not exists wildlife_news_content_hash_uidx
  on public.wildlife_news (content_hash)
  where content_hash is not null and content_hash <> '';

create index if not exists wildlife_news_processing_status_idx
  on public.wildlife_news (processing_status, created_at desc);

create table if not exists public.news_notification_events (
  id uuid primary key default gen_random_uuid(),
  news_id uuid not null references public.wildlife_news(id) on delete cascade,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer not null default 0,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text,
  unique (news_id)
);

create index if not exists news_notification_events_pending_idx
  on public.news_notification_events (status, created_at)
  where status in ('pending', 'failed');

create table if not exists public.news_notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.news_notification_events(id) on delete cascade,
  token text not null,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'invalid', 'failed')),
  attempted_at timestamptz,
  delivered_at timestamptz,
  fcm_message_id text,
  last_error text,
  unique (event_id, token)
);

create index if not exists news_notification_deliveries_event_idx
  on public.news_notification_deliveries (event_id, status);

alter table public.news_notification_events enable row level security;
alter table public.news_notification_deliveries enable row level security;

-- These are server-only operational records. The service role bypasses RLS.
revoke all on table public.news_notification_events from anon, authenticated;
revoke all on table public.news_notification_deliveries from anon, authenticated;

-- Retry only server-owned pending/failed events. Store project_url and
-- news_notification_secret in Supabase Vault before enabling this schedule.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'deliver-news-notifications') then
    perform cron.unschedule('deliver-news-notifications');
  end if;
end $$;

select cron.schedule(
  'deliver-news-notifications',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/notify-news-published',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-news-notification-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'news_notification_secret')
    ),
    body := '{"drain":true}'::jsonb
  );
  $$
);
