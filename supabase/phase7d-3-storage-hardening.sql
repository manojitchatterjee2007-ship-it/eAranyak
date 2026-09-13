-- =============================================================================
-- eআরণ্যক / eAranyak
-- Phase 7D-3: Storage & Protected Media Hardening Migration
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PRIVATIZE MAGAZINE_PAGES BUCKET
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false
WHERE id = 'magazine_pages';

-- -----------------------------------------------------------------------------
-- 2. STORAGE RLS POLICIES FOR STORAGE.OBJECTS
--
-- ADAPTATION (live-state verified): the live storage policies use different
-- names and several are permissive (TO public, USING (true)). Drop them all
-- before creating the hardened set, otherwise the permissive ones remain
-- active alongside the new policies.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow public page downloads" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated readers to view pages" ON storage.objects;
DROP POLICY IF EXISTS "Allow admin deletions on storage" ON storage.objects;
DROP POLICY IF EXISTS "Allow admin to upload magazine pages" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow gallery uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow gallery reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow gallery deletes" ON storage.objects;
-- -----------------------------------------------------------------------------

-- Magazine Pages (Private Bucket - Signed URLs / Authenticated Access)
DROP POLICY IF EXISTS "Authenticated users read magazine pages" ON storage.objects;
CREATE POLICY "Authenticated users read magazine pages"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'magazine_pages');

DROP POLICY IF EXISTS "Editors manage magazine pages" ON storage.objects;
CREATE POLICY "Editors manage magazine pages"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'magazine_pages' AND public.is_editor())
  WITH CHECK (bucket_id = 'magazine_pages' AND public.is_editor());

-- Wildlife Gallery Storage Writes
DROP POLICY IF EXISTS "Editors manage gallery storage" ON storage.objects;
CREATE POLICY "Editors manage gallery storage"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'wildlife_gallery' AND public.is_editor())
  WITH CHECK (bucket_id = 'wildlife_gallery' AND public.is_editor());

-- Podcasts Storage Writes
DROP POLICY IF EXISTS "Editors manage podcasts storage" ON storage.objects;
CREATE POLICY "Editors manage podcasts storage"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'podcasts' AND public.is_editor())
  WITH CHECK (bucket_id = 'podcasts' AND public.is_editor());

-- Vlogs Storage Writes
DROP POLICY IF EXISTS "Editors manage vlogs storage" ON storage.objects;
CREATE POLICY "Editors manage vlogs storage"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'vlogs' AND public.is_editor())
  WITH CHECK (bucket_id = 'vlogs' AND public.is_editor());

-- Tutorials Storage Writes
DROP POLICY IF EXISTS "Editors manage tutorials storage" ON storage.objects;
CREATE POLICY "Editors manage tutorials storage"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'tutorials' AND public.is_editor())
  WITH CHECK (bucket_id = 'tutorials' AND public.is_editor());

-- Writing Submissions Storage
DROP POLICY IF EXISTS "Users upload writing submissions" ON storage.objects;
CREATE POLICY "Users upload writing submissions"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'writing_submissions');

DROP POLICY IF EXISTS "Editors manage writing submissions storage" ON storage.objects;
CREATE POLICY "Editors manage writing submissions storage"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'writing_submissions' AND public.is_editor())
  WITH CHECK (bucket_id = 'writing_submissions' AND public.is_editor());
