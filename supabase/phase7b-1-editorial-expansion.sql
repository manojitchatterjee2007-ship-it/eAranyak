-- ============================================================
-- Phase 7B-1 Database Expansion Migration Documentation
-- eআরণ্যক / eAranyak - Editorial Expansion
-- ============================================================

-- 1. Extend wildlife_gallery with editorial metadata
ALTER TABLE IF EXISTS public.wildlife_gallery
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS location text,
  ADD COLUMN IF NOT EXISTS photographer_credit text,
  ADD COLUMN IF NOT EXISTS category text DEFAULT 'Wildlife',
  ADD COLUMN IF NOT EXISTS editorial_priority integer DEFAULT 10,
  ADD COLUMN IF NOT EXISTS is_featured boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_published boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS published_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Extend app_notifications with event metadata
ALTER TABLE IF EXISTS public.app_notifications
  ADD COLUMN IF NOT EXISTS category text DEFAULT 'General',
  ADD COLUMN IF NOT EXISTS event_date timestamptz,
  ADD COLUMN IF NOT EXISTS venue text,
  ADD COLUMN IF NOT EXISTS registration_url text,
  ADD COLUMN IF NOT EXISTS contact_info text,
  ADD COLUMN IF NOT EXISTS is_featured boolean DEFAULT false;

-- 3. Create podcasts table
CREATE TABLE IF NOT EXISTS public.podcasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  episode_number integer,
  description text,
  snippet text,
  thumbnail_url text,
  audio_url text,
  storage_path text,
  duration_seconds integer,
  category text DEFAULT 'General',
  editorial_priority integer DEFAULT 10,
  is_featured boolean DEFAULT false,
  is_published boolean DEFAULT false,
  scheduled_publish_at timestamptz,
  expires_at timestamptz,
  published_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 4. Create vlogs table
CREATE TABLE IF NOT EXISTS public.vlogs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  snippet text,
  thumbnail_url text,
  video_url text,
  storage_path text,
  duration_seconds integer,
  category text DEFAULT 'Nature',
  editorial_priority integer DEFAULT 10,
  is_featured boolean DEFAULT false,
  is_published boolean DEFAULT false,
  scheduled_publish_at timestamptz,
  expires_at timestamptz,
  published_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- 5. Create tutorials table
CREATE TABLE IF NOT EXISTS public.tutorials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  snippet text,
  thumbnail_url text,
  resource_url text,
  storage_path text,
  resource_type text DEFAULT 'video',
  category text DEFAULT 'General',
  difficulty text DEFAULT 'beginner',
  duration_minutes integer,
  editorial_priority integer DEFAULT 10,
  is_featured boolean DEFAULT false,
  is_published boolean DEFAULT false,
  scheduled_publish_at timestamptz,
  expires_at timestamptz,
  published_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Enable RLS for newly created tables
ALTER TABLE public.podcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vlogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tutorials ENABLE ROW LEVEL SECURITY;

-- Read policies for published items
CREATE POLICY "Public read published podcasts" ON public.podcasts
  FOR SELECT USING (is_published = true);

CREATE POLICY "Public read published vlogs" ON public.vlogs
  FOR SELECT USING (is_published = true);

CREATE POLICY "Public read published tutorials" ON public.tutorials
  FOR SELECT USING (is_published = true);

-- Admin CRUD policies
CREATE POLICY "Authenticated users full access podcasts" ON public.podcasts
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users full access vlogs" ON public.vlogs
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users full access tutorials" ON public.tutorials
  FOR ALL USING (auth.role() = 'authenticated');
