-- =============================================================================
-- eআরণ্যক — Server-Driven Significant Update Notification Pipeline
-- Supports news, gallery, magazine, quiz, app_notification, and community_article.
-- =============================================================================

create table if not exists public.significant_update_events (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('news', 'gallery', 'magazine', 'quiz', 'app_notification', 'community_article')),
  content_id text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  sound_key text not null default 'elephant_trumpet'
    check (sound_key in ('elephant_trumpet', 'owl_hoot', 'tiger_roar', 'cricket', 'deer_call')),
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer not null default 0,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text,
  unique (content_type, content_id)
);

create index if not exists significant_update_events_pending_idx
  on public.significant_update_events (status, created_at)
  where status in ('pending', 'failed');

create table if not exists public.significant_update_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.significant_update_events(id) on delete cascade,
  token text not null,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'invalid', 'failed')),
  attempted_at timestamptz,
  delivered_at timestamptz,
  fcm_message_id text,
  last_error text,
  unique (event_id, token)
);

create index if not exists significant_update_deliveries_event_idx
  on public.significant_update_deliveries (event_id, status);

alter table public.significant_update_events enable row level security;
alter table public.significant_update_deliveries enable row level security;

-- Operational records are server-only. Service role bypasses RLS.
revoke all on table public.significant_update_events from anon, authenticated;
revoke all on table public.significant_update_deliveries from anon, authenticated;

-- Schedule delivery worker via pg_cron (5-minute frequency)
do $$
begin
  if exists (select 1 from cron.job where jobname = 'deliver-significant-updates') then
    perform cron.unschedule('deliver-significant-updates');
  end if;
  if exists (select 1 from cron.job where jobname = 'deliver-news-notifications') then
    perform cron.unschedule('deliver-news-notifications');
  end if;
end $$;

select cron.schedule(
  'deliver-significant-updates',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
      || '/functions/v1/send-significant-update',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-significant-update-secret',
      coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'significant_update_secret'),
        (select decrypted_secret from vault.decrypted_secrets where name = 'news_notification_secret')
      )
    ),
    body := '{"drain":true}'::jsonb
  );
  $$
);
