-- =============================================================================
-- eআরণ্যক — Phase 2: Editorial News Management Database Schema Migration
-- SAFE VERSION
-- =============================================================================


-- =============================================================================
-- 1. ADD EDITORIAL METADATA TO wildlife_news
-- =============================================================================

ALTER TABLE public.wildlife_news
  ADD COLUMN IF NOT EXISTS publication_source text NOT NULL DEFAULT 'automated',
  ADD COLUMN IF NOT EXISTS editorial_priority integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS published_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by_editor boolean NOT NULL DEFAULT false;


-- =============================================================================
-- 2. VALIDATE publication_source VALUES
-- =============================================================================

ALTER TABLE public.wildlife_news
  DROP CONSTRAINT IF EXISTS wildlife_news_publication_source_check;

ALTER TABLE public.wildlife_news
  ADD CONSTRAINT wildlife_news_publication_source_check
  CHECK (publication_source IN ('automated', 'editorial'));


-- =============================================================================
-- 3. BACKFILL EXISTING ARTICLES
-- =============================================================================

UPDATE public.wildlife_news
SET
  publication_source = COALESCE(publication_source, 'automated'),
  editorial_priority = COALESCE(editorial_priority, 0),
  is_published = COALESCE(is_published, true),
  published_at = COALESCE(published_at, created_at, now()),
  created_by_editor = COALESCE(created_by_editor, false);


-- =============================================================================
-- 4. CREATE INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS wildlife_news_is_published_idx
  ON public.wildlife_news
  (
    is_published,
    editorial_priority DESC,
    published_at DESC
  );

CREATE INDEX IF NOT EXISTS wildlife_news_publication_source_idx
  ON public.wildlife_news (publication_source);

CREATE INDEX IF NOT EXISTS wildlife_news_editorial_priority_idx
  ON public.wildlife_news (editorial_priority DESC);

CREATE INDEX IF NOT EXISTS wildlife_news_published_at_idx
  ON public.wildlife_news (published_at DESC);


-- =============================================================================
-- 5. ENABLE RLS
-- =============================================================================

ALTER TABLE public.wildlife_news ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- 6. PUBLIC READ POLICY
--
-- Users see published news.
-- Existing editor/admin users can see everything through your existing
-- authorization system (only if public.is_editor() already exists).
-- =============================================================================

DROP POLICY IF EXISTS "anyone read wildlife news"
  ON public.wildlife_news;

DROP POLICY IF EXISTS "public read published news"
  ON public.wildlife_news;


-- IMPORTANT:
-- This policy intentionally exposes only published articles publicly.
-- Editorial operations will be handled securely through the
-- admin-news-manager Edge Function using server-side authorization.
CREATE POLICY "public read published news"
  ON public.wildlife_news
  FOR SELECT
  TO anon, authenticated
  USING (is_published = true);


-- =============================================================================
-- 7. REMOVE ANY OLD DIRECT CLIENT WRITE POLICIES
--
-- News creation, modification and deletion will be performed through the
-- secure admin-news-manager Edge Function rather than directly from Flutter.
-- =============================================================================

DROP POLICY IF EXISTS "editors add news"
  ON public.wildlife_news;

DROP POLICY IF EXISTS "editors update news"
  ON public.wildlife_news;

DROP POLICY IF EXISTS "editors delete news"
  ON public.wildlife_news;


-- =============================================================================
-- END OF PHASE 2 DATABASE MIGRATION
-- =============================================================================