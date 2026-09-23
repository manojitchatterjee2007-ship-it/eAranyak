-- =============================================================================
-- eআরণ্যক — Phase 7E: Significant Update Delivery Cron Job
-- Ensures pending significant_update_events are drained every 5 minutes.
-- Safe to re-run (idempotent).
-- =============================================================================

do $$
begin
  if exists (select 1 from cron.job where jobname = 'deliver-significant-updates') then
    perform cron.unschedule('deliver-significant-updates');
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
