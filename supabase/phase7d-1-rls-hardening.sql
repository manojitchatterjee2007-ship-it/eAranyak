-- =============================================================================
-- eআরণ্যক / eAranyak
-- Phase 7D-1: Emergency Database & RLS Hardening Migration
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 7D-1A — PROFILES ROLE ESCALATION PROTECTION
-- Prevent non-admin users from updating or inserting role = 'admin'
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_profile_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service role or database superuser bypasses restriction
  IF (auth.jwt() ->> 'role') = 'service_role' OR current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF (TG_OP = 'INSERT') THEN
    IF NEW.role IS DISTINCT FROM 'user' AND NOT public.is_editor() THEN
      NEW.role := 'user';
    END IF;
  ELSIF (TG_OP = 'UPDATE') THEN
    IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_editor() THEN
      NEW.role := OLD.role;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_profile_role_trigger ON public.profiles;
CREATE TRIGGER protect_profile_role_trigger
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_profile_role();


-- -----------------------------------------------------------------------------
-- 7D-1B — PODCAST / VLOG / TUTORIAL WRITE SECURITY
-- Restrict INSERT, UPDATE, DELETE to public.is_editor()
-- -----------------------------------------------------------------------------

-- Drop overly permissive legacy policies
DROP POLICY IF EXISTS "Authenticated users full access podcasts" ON public.podcasts;
DROP POLICY IF EXISTS "Authenticated users full access vlogs" ON public.vlogs;
DROP POLICY IF EXISTS "Authenticated users full access tutorials" ON public.tutorials;
-- Live legacy editor-write policies (lowercase names) are replaced below
DROP POLICY IF EXISTS "editors insert podcasts" ON public.podcasts;
DROP POLICY IF EXISTS "editors update podcasts" ON public.podcasts;
DROP POLICY IF EXISTS "editors delete podcasts" ON public.podcasts;
DROP POLICY IF EXISTS "editors insert vlogs" ON public.vlogs;
DROP POLICY IF EXISTS "editors update vlogs" ON public.vlogs;
DROP POLICY IF EXISTS "editors delete vlogs" ON public.vlogs;
DROP POLICY IF EXISTS "editors insert tutorials" ON public.tutorials;
DROP POLICY IF EXISTS "editors update tutorials" ON public.tutorials;
DROP POLICY IF EXISTS "editors delete tutorials" ON public.tutorials;

-- Podcasts
DROP POLICY IF EXISTS "Editors insert podcasts" ON public.podcasts;
CREATE POLICY "Editors insert podcasts"
  ON public.podcasts FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors update podcasts" ON public.podcasts;
CREATE POLICY "Editors update podcasts"
  ON public.podcasts FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors delete podcasts" ON public.podcasts;
CREATE POLICY "Editors delete podcasts"
  ON public.podcasts FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- Vlogs
DROP POLICY IF EXISTS "Editors insert vlogs" ON public.vlogs;
CREATE POLICY "Editors insert vlogs"
  ON public.vlogs FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors update vlogs" ON public.vlogs;
CREATE POLICY "Editors update vlogs"
  ON public.vlogs FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors delete vlogs" ON public.vlogs;
CREATE POLICY "Editors delete vlogs"
  ON public.vlogs FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- Tutorials
DROP POLICY IF EXISTS "Editors insert tutorials" ON public.tutorials;
CREATE POLICY "Editors insert tutorials"
  ON public.tutorials FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors update tutorials" ON public.tutorials;
CREATE POLICY "Editors update tutorials"
  ON public.tutorials FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "Editors delete tutorials" ON public.tutorials;
CREATE POLICY "Editors delete tutorials"
  ON public.tutorials FOR DELETE
  TO authenticated
  USING (public.is_editor());


-- -----------------------------------------------------------------------------
-- 7D-1C — DEVICE TOKENS ACCESS CONTROL
-- Restrict device_tokens reads/edits to user's own token row
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "clients manage own token" ON public.device_tokens;
DROP POLICY IF EXISTS "Users read own device token" ON public.device_tokens;
DROP POLICY IF EXISTS "Users insert own device token" ON public.device_tokens;
DROP POLICY IF EXISTS "Users update own device token" ON public.device_tokens;
DROP POLICY IF EXISTS "Users delete own device token" ON public.device_tokens;

CREATE POLICY "Users read own device token"
  ON public.device_tokens FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.is_editor());

CREATE POLICY "Users insert own device token"
  ON public.device_tokens FOR INSERT
  TO anon, authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY "Users update own device token"
  ON public.device_tokens FOR UPDATE
  TO anon, authenticated
  USING (user_id IS NULL OR user_id = auth.uid())
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY "Users delete own device token"
  ON public.device_tokens FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id OR public.is_editor());


-- -----------------------------------------------------------------------------
-- 7D-1D — PROFILES PII PROTECTION
-- Restrict SELECT on profiles to owner or editor
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "Public profiles are viewable by everyone." ON public.profiles;
DROP POLICY IF EXISTS "Users view own profile" ON public.profiles;

CREATE POLICY "Users view own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id OR public.is_editor());


-- -----------------------------------------------------------------------------
-- 7D-1E — WILDLIFE NEWS TRANSLATIONS WRITE SECURITY
-- Restrict INSERT/UPDATE to public.is_editor() (service_role bypasses RLS)
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "anyone can insert translations" ON public.wildlife_news_translations;
DROP POLICY IF EXISTS "anyone can update translations" ON public.wildlife_news_translations;
DROP POLICY IF EXISTS "editors insert translations" ON public.wildlife_news_translations;
DROP POLICY IF EXISTS "editors update translations" ON public.wildlife_news_translations;

CREATE POLICY "editors insert translations"
  ON public.wildlife_news_translations FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

CREATE POLICY "editors update translations"
  ON public.wildlife_news_translations FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());


-- -----------------------------------------------------------------------------
-- 7D-1F — GALLERY RLS HARDENING
-- Require publication & schedule/expiry window for public SELECT
--
-- ADAPTATION (live-state verified):
--  * The live table lacks the schedule/expiry columns; add them (nullable,
--    additive — no defaults, app writes are unaffected; NULL = always visible,
--    preserving current behaviour for existing rows).
--  * The live policies use different (fully permissive, USING (true)) names —
--    drop them all before creating the hardened ones.
-- -----------------------------------------------------------------------------
ALTER TABLE public.wildlife_gallery
  ADD COLUMN IF NOT EXISTS scheduled_publish_at timestamptz;
ALTER TABLE public.wildlife_gallery
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

DROP POLICY IF EXISTS "Anyone can read gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "public read published gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "Allow all users to read gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "Allow insert gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "Allow delete gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "wildlife_gallery_policy" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "editors insert gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "editors update gallery" ON public.wildlife_gallery;
DROP POLICY IF EXISTS "editors delete gallery" ON public.wildlife_gallery;

CREATE POLICY "public read published gallery"
  ON public.wildlife_gallery FOR SELECT
  TO anon, authenticated
  USING (
    (
      is_published = true
      AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
      AND (expires_at IS NULL OR expires_at > now())
    )
    OR public.is_editor()
  );

CREATE POLICY "editors insert gallery"
  ON public.wildlife_gallery FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

CREATE POLICY "editors update gallery"
  ON public.wildlife_gallery FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

CREATE POLICY "editors delete gallery"
  ON public.wildlife_gallery FOR DELETE
  TO authenticated
  USING (public.is_editor());
