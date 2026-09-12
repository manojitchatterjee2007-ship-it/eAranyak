-- =============================================================================
-- eআরণ্যক — Phase 4: Latest Notifications Editorial Publishing System
-- Database Schema, RLS Policies, Indexes & Storage Setup
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CREATE app_notifications TABLE FOR EDITORIAL NOTIFICATIONS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.app_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title text NOT NULL,
  snippet text,
  content text,
  notification_type text NOT NULL CHECK (notification_type IN ('text', 'image', 'pdf')),
  thumbnail_url text,
  pdf_url text,
  editorial_priority integer NOT NULL DEFAULT 0,
  is_published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  created_by uuid REFERENCES auth.users ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users ON DELETE SET NULL
);

-- -----------------------------------------------------------------------------
-- 2. CREATE app_notification_images TABLE FOR MULTIPLE NOTIFICATION IMAGES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.app_notification_images (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  notification_id uuid NOT NULL REFERENCES public.app_notifications(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  storage_path text,
  caption text,
  display_order integer NOT NULL DEFAULT 0,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3. CREATE INDEXES
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS app_notifications_published_idx
  ON public.app_notifications (is_published, editorial_priority DESC, published_at DESC);

CREATE INDEX IF NOT EXISTS app_notifications_type_idx
  ON public.app_notifications (notification_type);

CREATE INDEX IF NOT EXISTS app_notification_images_notif_idx
  ON public.app_notification_images (notification_id, display_order ASC);

-- -----------------------------------------------------------------------------
-- 4. ENABLE ROW LEVEL SECURITY
-- -----------------------------------------------------------------------------

ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_notification_images ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 5. RLS POLICIES FOR app_notifications
-- -----------------------------------------------------------------------------

-- Public can read ONLY published notifications
DROP POLICY IF EXISTS "public read published notifications" ON public.app_notifications;
CREATE POLICY "public read published notifications"
  ON public.app_notifications
  FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

-- Editors have full management permissions (SELECT, INSERT, UPDATE, DELETE)
DROP POLICY IF EXISTS "editors select all notifications" ON public.app_notifications;
CREATE POLICY "editors select all notifications"
  ON public.app_notifications
  FOR SELECT
  TO authenticated
  USING (public.is_editor());

DROP POLICY IF EXISTS "editors insert notifications" ON public.app_notifications;
CREATE POLICY "editors insert notifications"
  ON public.app_notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors update notifications" ON public.app_notifications;
CREATE POLICY "editors update notifications"
  ON public.app_notifications
  FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete notifications" ON public.app_notifications;
CREATE POLICY "editors delete notifications"
  ON public.app_notifications
  FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 6. RLS POLICIES FOR app_notification_images
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "public read published notification images" ON public.app_notification_images;
CREATE POLICY "public read published notification images"
  ON public.app_notification_images
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.app_notifications n
      WHERE n.id = notification_id
        AND (n.is_published = true OR public.is_editor())
    )
  );

DROP POLICY IF EXISTS "editors insert notification images" ON public.app_notification_images;
CREATE POLICY "editors insert notification images"
  ON public.app_notification_images
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors update notification images" ON public.app_notification_images;
CREATE POLICY "editors update notification images"
  ON public.app_notification_images
  FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete notification images" ON public.app_notification_images;
CREATE POLICY "editors delete notification images"
  ON public.app_notification_images
  FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- -----------------------------------------------------------------------------
-- 7. SUPABASE STORAGE BUCKET & POLICIES SETUP INSTRUCTIONS
--
-- Ensure bucket 'app_notifications' exists and is public:
--   INSERT INTO storage.buckets (id, name, public)
--   VALUES ('app_notifications', 'app_notifications', true)
--   ON CONFLICT (id) DO NOTHING;
--
-- Storage RLS policies for storage.objects:
--   - Allow public/anon SELECT on app_notifications bucket:
--     (bucket_id = 'app_notifications')
--   - Allow editors INSERT, UPDATE, DELETE on app_notifications bucket:
--     (bucket_id = 'app_notifications' AND public.is_editor())
-- -----------------------------------------------------------------------------
