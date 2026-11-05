-- =============================================================================
-- eআরণ্যক / eAranyak
-- Fix magazine_pages and wildlife_gallery storage read access
-- =============================================================================

-- Ensure anyone (anonymous or authenticated users) can read and sign magazine pages
DROP POLICY IF EXISTS "Authenticated users read magazine pages" ON storage.objects;
DROP POLICY IF EXISTS "Allow reading magazine pages" ON storage.objects;
CREATE POLICY "Allow reading magazine pages"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'magazine_pages');

-- Ensure anyone (anonymous or authenticated users) can read wildlife gallery assets
DROP POLICY IF EXISTS "Authenticated users read wildlife gallery assets" ON storage.objects;
DROP POLICY IF EXISTS "Allow reading wildlife gallery assets" ON storage.objects;
CREATE POLICY "Allow reading wildlife gallery assets"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'wildlife_gallery');
