-- =============================================================================
-- eআরণ্যক / eAranyak
-- Phase 7D-2: Database Content Visibility Hardening Migration
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Hardened SELECT Policies for Podcasts, Vlogs, and Tutorials
-- Non-editors see ONLY published items within schedule/expiry window.
-- Editors (public.is_editor()) see ALL items.
-- -----------------------------------------------------------------------------

-- Podcasts
DROP POLICY IF EXISTS "Public read published podcasts" ON public.podcasts;
DROP POLICY IF EXISTS "public read published podcasts" ON public.podcasts;
CREATE POLICY "Public read published podcasts"
  ON public.podcasts FOR SELECT
  TO anon, authenticated
  USING (
    (
      is_published = true
      AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
      AND (expires_at IS NULL OR expires_at > now())
    )
    OR public.is_editor()
  );

-- Vlogs
DROP POLICY IF EXISTS "Public read published vlogs" ON public.vlogs;
DROP POLICY IF EXISTS "public read published vlogs" ON public.vlogs;
CREATE POLICY "Public read published vlogs"
  ON public.vlogs FOR SELECT
  TO anon, authenticated
  USING (
    (
      is_published = true
      AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
      AND (expires_at IS NULL OR expires_at > now())
    )
    OR public.is_editor()
  );

-- Tutorials
DROP POLICY IF EXISTS "Public read published tutorials" ON public.tutorials;
DROP POLICY IF EXISTS "public read published tutorials" ON public.tutorials;
CREATE POLICY "Public read published tutorials"
  ON public.tutorials FOR SELECT
  TO anon, authenticated
  USING (
    (
      is_published = true
      AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
      AND (expires_at IS NULL OR expires_at > now())
    )
    OR public.is_editor()
  );
