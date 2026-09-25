-- =============================================================================
-- eআরণ্যক / eAranyak
-- Content Protection System Backend Migration
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PRIVATIZE STORAGE BUCKETS
-- Enforce private storage for both magazine pages and wildlife gallery images.
-- Direct unauthenticated public URLs will be rejected by Supabase Storage.
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false
WHERE id IN ('magazine_pages', 'wildlife_gallery');

-- -----------------------------------------------------------------------------
-- 2. PROTECTION SESSIONS TABLE
-- Tracks short-lived active content protection sessions for audit & watermarking.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.protection_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id TEXT UNIQUE NOT NULL,
    scope TEXT NOT NULL,
    content_id TEXT NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.protection_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users insert own protection sessions" ON public.protection_sessions;
CREATE POLICY "Authenticated users insert own protection sessions"
  ON public.protection_sessions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

DROP POLICY IF EXISTS "Users read own protection sessions" ON public.protection_sessions;
CREATE POLICY "Users read own protection sessions"
  ON public.protection_sessions FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.is_editor());

-- -----------------------------------------------------------------------------
-- 3. PROTECTION SECURITY EVENTS TABLE
-- Audit log for security events (screenshots, capture detection, rate limiting).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.protection_security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    session_id TEXT,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.protection_security_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users log protection events" ON public.protection_security_events;
CREATE POLICY "Authenticated users log protection events"
  ON public.protection_security_events FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

DROP POLICY IF EXISTS "Editors view protection security events" ON public.protection_security_events;
CREATE POLICY "Editors view protection security events"
  ON public.protection_security_events FOR SELECT
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 4. STORAGE RLS HARDENING
-- Restrict direct read access to authenticated users via signed URLs.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Authenticated users read wildlife gallery assets" ON storage.objects;
CREATE POLICY "Authenticated users read wildlife gallery assets"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'wildlife_gallery');
