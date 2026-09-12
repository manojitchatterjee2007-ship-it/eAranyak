-- =============================================================================
-- eআরণ্যক — Phase 5: Online Books, Analytics, Scheduled Publishing & Expiry
-- Database Schema, RLS Policies, Indexes & Storage Setup
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CREATE online_books TABLE FOR EKHON ARANYAK ONLINE BOOK STORE
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.online_books (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title text NOT NULL,
  author text,
  publisher text NOT NULL,
  description text,
  price numeric NOT NULL,
  original_price numeric,
  currency text NOT NULL DEFAULT 'INR',
  thumbnail_url text,
  storage_path text,
  order_url text,
  is_available boolean NOT NULL DEFAULT true,
  editorial_priority integer NOT NULL DEFAULT 0,
  is_published boolean NOT NULL DEFAULT false,
  scheduled_publish_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  created_by uuid REFERENCES auth.users ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users ON DELETE SET NULL
);

-- Validate original_price when provided
ALTER TABLE public.online_books
  DROP CONSTRAINT IF EXISTS online_books_price_check;

ALTER TABLE public.online_books
  ADD CONSTRAINT online_books_price_check
  CHECK (price >= 0 AND (original_price IS NULL OR original_price >= price));

-- -----------------------------------------------------------------------------
-- 2. CREATE content_analytics_events TABLE FOR LIGHTWEIGHT ANALYTICS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.content_analytics_events (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  content_type text NOT NULL, -- 'news', 'community_article', 'notification', 'online_book'
  content_id text NOT NULL,
  event_type text NOT NULL, -- 'open', 'order_click'
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Validate content_type
ALTER TABLE public.content_analytics_events
  DROP CONSTRAINT IF EXISTS content_analytics_events_type_check;

ALTER TABLE public.content_analytics_events
  ADD CONSTRAINT content_analytics_events_type_check
  CHECK (content_type IN ('news', 'community_article', 'notification', 'online_book'));

-- -----------------------------------------------------------------------------
-- 3. ADD SCHEDULED PUBLISHING & EXPIRY TO EXISTING TABLES
-- -----------------------------------------------------------------------------

ALTER TABLE public.wildlife_news
  ADD COLUMN IF NOT EXISTS scheduled_publish_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.app_notifications
  ADD COLUMN IF NOT EXISTS scheduled_publish_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.writing_submissions
  ADD COLUMN IF NOT EXISTS scheduled_publish_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- -----------------------------------------------------------------------------
-- 4. CREATE INDEXES
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS online_books_published_idx
  ON public.online_books (is_published, editorial_priority DESC, published_at DESC);

CREATE INDEX IF NOT EXISTS online_books_available_idx
  ON public.online_books (is_available);

CREATE INDEX IF NOT EXISTS content_analytics_events_type_id_idx
  ON public.content_analytics_events (content_type, content_id, event_type);

CREATE INDEX IF NOT EXISTS content_analytics_events_created_idx
  ON public.content_analytics_events (created_at DESC);

-- -----------------------------------------------------------------------------
-- 5. ENABLE ROW LEVEL SECURITY
-- -----------------------------------------------------------------------------

ALTER TABLE public.online_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_analytics_events ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 6. RLS POLICIES FOR online_books
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "public read published books" ON public.online_books;
CREATE POLICY "public read published books"
  ON public.online_books FOR SELECT
  TO anon, authenticated
  USING (
    is_published = true
    AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
    AND (expires_at IS NULL OR expires_at > now())
  );

DROP POLICY IF EXISTS "editors select all online books" ON public.online_books;
CREATE POLICY "editors select all online books"
  ON public.online_books FOR SELECT
  TO authenticated
  USING (public.is_editor());

DROP POLICY IF EXISTS "editors insert online books" ON public.online_books;
CREATE POLICY "editors insert online books"
  ON public.online_books FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors update online books" ON public.online_books;
CREATE POLICY "editors update online books"
  ON public.online_books FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete online books" ON public.online_books;
CREATE POLICY "editors delete online books"
  ON public.online_books FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 7. RLS POLICIES FOR content_analytics_events
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "anyone record analytics events" ON public.content_analytics_events;
CREATE POLICY "anyone record analytics events"
  ON public.content_analytics_events FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "editors read analytics events" ON public.content_analytics_events;
CREATE POLICY "editors read analytics events"
  ON public.content_analytics_events FOR SELECT
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 8. UPDATE EXISTING RLS POLICIES FOR SCHEDULED PUBLISHING & EXPIRY
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "public read published news" ON public.wildlife_news;
CREATE POLICY "public read published news"
  ON public.wildlife_news
  FOR SELECT
  TO anon, authenticated
  USING (
    is_published = true
    AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
    AND (expires_at IS NULL OR expires_at > now())
  );

DROP POLICY IF EXISTS "public read published notifications" ON public.app_notifications;
CREATE POLICY "public read published notifications"
  ON public.app_notifications
  FOR SELECT
  TO anon, authenticated
  USING (
    is_published = true
    AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
    AND (expires_at IS NULL OR expires_at > now())
  );

DROP POLICY IF EXISTS "public read published community articles" ON public.writing_submissions;
CREATE POLICY "public read published community articles"
  ON public.writing_submissions
  FOR SELECT
  TO anon, authenticated
  USING (
    is_published = true
    AND status = 'published'
    AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= now())
    AND (expires_at IS NULL OR expires_at > now())
  );

-- -----------------------------------------------------------------------------
-- END OF PHASE 5 DATABASE MIGRATION
-- -------------------------------------------------------------
