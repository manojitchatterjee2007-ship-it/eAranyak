-- =============================================================================
-- eআরণ্যক — Phase 7E: wildlife_news write security fix
-- The previous "Allow inserts/updates to news" policy (cmd=ALL, qual=true,
-- with_check=NULL) allowed ANY authenticated user to insert/update/delete
-- any news article. Replace it with editor-only policies using the existing
-- public.is_editor() helper (which checks profiles.role = 'admin').
-- =============================================================================

-- Remove the overly permissive legacy policy
DROP POLICY IF EXISTS "Allow inserts/updates to news" ON public.wildlife_news;

-- Editor-only write policies
DROP POLICY IF EXISTS "editors add news" ON public.wildlife_news;
CREATE POLICY "editors add news"
  ON public.wildlife_news
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors update news" ON public.wildlife_news;
CREATE POLICY "editors update news"
  ON public.wildlife_news
  FOR UPDATE
  TO authenticated
  USING (public.is_editor())
  WITH CHECK (public.is_editor());

DROP POLICY IF EXISTS "editors delete news" ON public.wildlife_news;
CREATE POLICY "editors delete news"
  ON public.wildlife_news
  FOR DELETE
  TO authenticated
  USING (public.is_editor());

-- Keep public read access for published articles
-- (existing "Allow public to read news" and "public read published news" SELECT
--  policies remain intact; they are permissive but harmless for reads)
