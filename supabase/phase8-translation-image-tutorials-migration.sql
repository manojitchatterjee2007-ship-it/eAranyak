-- =============================================================================
-- eআরণ্যক — Phase 8: Server-side Translation Hierarchy + Generated Illustrations
-- =============================================================================
-- Additive, idempotent, production-safe. NO existing column is dropped, NO
-- existing policy is weakened, NO bucket is made private.
--
-- 1. Provenance columns so AI-generated illustrations are identifiable
--    (Phase 16). Nullable text; existing rows are untouched (NULL = source).
-- 2. Source-tracking columns for tutorials (mirrors the staged
--    tutorials-pipeline-migration.sql; kept idempotent here so a single file
--    provisions a fresh environment too).
-- 3. A dedicated PUBLIC bucket for generated illustrations. This is necessary
--    because every other content bucket is private (Phase 7D-3 hardened) and
--    the `tutorials` bucket may hold editor resources that must NOT become
--    public. Generated illustrations are the only objects stored here, so the
--    AI-image provenance is also structurally clear.
-- 4. Monthly tutorial rotation cron (idempotent; reuses existing Vault-based
--    scheduling conventions).
-- =============================================================================

-- 1. Provenance ---------------------------------------------------------------
ALTER TABLE public.tutorials
  ADD COLUMN IF NOT EXISTS image_provenance text,
  ADD COLUMN IF NOT EXISTS translation_provider text;

ALTER TABLE public.wildlife_news
  ADD COLUMN IF NOT EXISTS image_provenance text,
  ADD COLUMN IF NOT EXISTS translation_provider text;

-- 2. Tutorial source tracking (duplicate protection) ---------------------------
ALTER TABLE public.tutorials
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_name text,
  ADD COLUMN IF NOT EXISTS source_article_id text;

CREATE UNIQUE INDEX IF NOT EXISTS tutorials_source_url_uidx
  ON public.tutorials (source_url)
  WHERE source_url IS NOT NULL AND source_url <> '';

ALTER TABLE public.tutorials ENABLE ROW LEVEL SECURITY;

-- 3. Illustrations bucket (public read only; writes = editor + service-role) --
INSERT INTO storage.buckets (id, name, public)
VALUES ('earanyak_illustrations', 'earanyak_illustrations', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Public read (only this bucket; other buckets' policies are untouched).
DROP POLICY IF EXISTS "Public read generated illustrations" ON storage.objects;
CREATE POLICY "Public read generated illustrations"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'earanyak_illustrations');

-- Editors manage generated illustrations (same pattern as Phase 7D-3).
DROP POLICY IF EXISTS "Editors manage generated illustrations" ON storage.objects;
CREATE POLICY "Editors manage generated illustrations"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'earanyak_illustrations' AND public.is_editor())
  WITH CHECK (bucket_id = 'earanyak_illustrations' AND public.is_editor());
-- Service-role Edge Function uploads bypass RLS (no extra policy required).

-- 4. Monthly tutorial rotation cron (server-side authoritative) ---------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-tutorials-monthly') THEN
    PERFORM cron.unschedule('refresh-tutorials-monthly');
  END IF;
END $$;

SELECT cron.schedule(
  'refresh-tutorials-monthly',
  '30 2 1 * *',
  $$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
           || '/functions/v1/refresh-tutorials',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-tutorial-refresh-secret',
      COALESCE(
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'tutorial_refresh_secret'),
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'news_refresh_secret')
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- 4b. Initial population cron (Phase 19): idempotent, self-limiting backfill.
--     Sends {"mode":"backfill"} which tops the pool up toward 10 tutorials and
--     NEVER rotates. Once ~10 published tutorials exist this job is a no-op, so
--     it requires no editor intervention and costs nothing thereafter.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-tutorials-backfill') THEN
    PERFORM cron.unschedule('refresh-tutorials-backfill');
  END IF;
END $$;

SELECT cron.schedule(
  'refresh-tutorials-backfill',
  '*/30 * * * *',
  $$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
           || '/functions/v1/refresh-tutorials',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-tutorial-refresh-secret',
      COALESCE(
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'tutorial_refresh_secret'),
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'news_refresh_secret')
      )
    ),
    body := '{"mode":"backfill"}'::jsonb
  ) AS request_id;
  $$
);

-- Verification queries (run manually):
-- SELECT jobname, schedule, active FROM cron.job ORDER BY jobname;
-- SELECT id, public FROM storage.buckets WHERE id = 'earanyak_illustrations';
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'tutorials' AND column_name = 'image_provenance';
-- SELECT count(*) FROM public.tutorials WHERE is_published;
