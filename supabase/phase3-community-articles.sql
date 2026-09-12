-- =============================================================================
-- eআরণ্যক — Phase 3: User Articles / Community Articles Editorial Publishing System
-- Database Schema, RLS Policies, Indexes & Storage Setup
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. EXTEND / CREATE writing_submissions TABLE FOR COMMUNITY ARTICLES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.writing_submissions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users ON DELETE SET NULL,
  author_name text NOT NULL,
  title text NOT NULL,
  article_content text NOT NULL,
  word_count integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending',
  photo_urls text[] NOT NULL DEFAULT '{}'::text[],
  submitted_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users ON DELETE SET NULL,
  rejection_reason text,
  editorial_priority integer NOT NULL DEFAULT 0,
  is_published boolean NOT NULL DEFAULT false,
  excerpt text,
  category text NOT NULL DEFAULT 'nature'
);

-- Validate status values
ALTER TABLE public.writing_submissions
  DROP CONSTRAINT IF EXISTS writing_submissions_status_check;

ALTER TABLE public.writing_submissions
  ADD CONSTRAINT writing_submissions_status_check
  CHECK (status IN ('pending', 'pending_review', 'approved', 'published', 'unpublished', 'rejected'));

-- Backfill default values for any existing records
UPDATE public.writing_submissions
SET
  status = COALESCE(status, 'pending'),
  photo_urls = COALESCE(photo_urls, '{}'::text[]),
  editorial_priority = COALESCE(editorial_priority, 0),
  is_published = CASE WHEN status = 'published' THEN true ELSE COALESCE(is_published, false) END,
  category = COALESCE(category, 'nature'),
  submitted_at = COALESCE(submitted_at, created_at, now());

-- -----------------------------------------------------------------------------
-- 2. CREATE community_article_images TABLE FOR MULTIPLE PHOTOGRAPHS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.community_article_images (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid NOT NULL REFERENCES public.writing_submissions(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  storage_path text,
  caption text,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3. CREATE INDEXES
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS writing_submissions_published_idx
  ON public.writing_submissions (is_published, editorial_priority DESC, published_at DESC);

CREATE INDEX IF NOT EXISTS writing_submissions_status_idx
  ON public.writing_submissions (status);

CREATE INDEX IF NOT EXISTS writing_submissions_user_id_idx
  ON public.writing_submissions (user_id);

CREATE INDEX IF NOT EXISTS community_article_images_article_idx
  ON public.community_article_images (article_id, display_order ASC);

-- -----------------------------------------------------------------------------
-- 4. ENABLE ROW LEVEL SECURITY
-- -----------------------------------------------------------------------------

ALTER TABLE public.writing_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_article_images ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 5. RLS POLICIES FOR writing_submissions
-- -----------------------------------------------------------------------------

-- Public can read ONLY published articles
DROP POLICY IF EXISTS "public read published community articles" ON public.writing_submissions;
CREATE POLICY "public read published community articles"
  ON public.writing_submissions
  FOR SELECT
  TO anon, authenticated
  USING (is_published = true AND status = 'published');

-- Authenticated users can insert their own article submissions
DROP POLICY IF EXISTS "users insert own submissions" ON public.writing_submissions;
CREATE POLICY "users insert own submissions"
  ON public.writing_submissions
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Authenticated users can view their own submissions (even if pending/rejected)
DROP POLICY IF EXISTS "users view own submissions" ON public.writing_submissions;
CREATE POLICY "users view own submissions"
  ON public.writing_submissions
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Editors have full management permissions (SELECT, INSERT, UPDATE, DELETE)
DROP POLICY IF EXISTS "editors select all submissions" ON public.writing_submissions;
CREATE POLICY "editors select all submissions"
  ON public.writing_submissions
  FOR SELECT
  TO authenticated
  USING (public.is_editor());

DROP POLICY IF EXISTS "editors update submissions" ON public.writing_submissions;
CREATE POLICY "editors update submissions"
  ON public.writing_submissions
  FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete submissions" ON public.writing_submissions;
CREATE POLICY "editors delete submissions"
  ON public.writing_submissions
  FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 6. RLS POLICIES FOR community_article_images
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "public read published article images" ON public.community_article_images;
CREATE POLICY "public read published article images"
  ON public.community_article_images
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.writing_submissions w
      WHERE w.id = article_id
        AND (
          (w.is_published = true AND w.status = 'published')
          OR (auth.uid() = w.user_id)
          OR public.is_editor()
        )
    )
  );

DROP POLICY IF EXISTS "users insert images for own submissions" ON public.community_article_images;
CREATE POLICY "users insert images for own submissions"
  ON public.community_article_images
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.writing_submissions w
      WHERE w.id = article_id
        AND (w.user_id = auth.uid() OR public.is_editor())
    )
  );

DROP POLICY IF EXISTS "editors update article images" ON public.community_article_images;
CREATE POLICY "editors update article images"
  ON public.community_article_images
  FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete article images" ON public.community_article_images;
CREATE POLICY "editors delete article images"
  ON public.community_article_images
  FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 7. SUPABASE STORAGE BUCKET & POLICIES SETUP INSTRUCTIONS
--
-- Ensure bucket 'writing_submissions' (or 'community-articles') exists and is public:
--   INSERT INTO storage.buckets (id, name, public)
--   VALUES ('writing_submissions', 'writing_submissions', true)
--   ON CONFLICT (id) DO NOTHING;
--
-- Storage RLS policies for storage.objects:
--   - Allow authenticated users to upload to writing_submissions bucket:
--     (bucket_id = 'writing_submissions' AND auth.role() = 'authenticated')
--   - Allow anyone to read objects in writing_submissions bucket:
--     (bucket_id = 'writing_submissions')
--   - Allow editors full control over writing_submissions storage objects:
--     (bucket_id = 'writing_submissions' AND public.is_editor())
-- -----------------------------------------------------------------------------
