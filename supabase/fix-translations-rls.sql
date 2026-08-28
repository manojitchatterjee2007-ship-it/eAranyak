-- ============================================================
-- eআরণ্যক — FIX: client-side Bengali cache writes blocked by RLS
--
-- Symptom in `flutter run` logs:
--   cache write failed (non-fatal): PostgrestException(message:
--   new row violates row-level security policy for table
--   "wildlife_news_translations", code: 42501)
--
-- The app translates articles on-device as a fallback and caches the result
-- in wildlife_news_translations so every user reuses it. The live project's
-- INSERT/UPDATE policies for anon/authenticated are missing or stricter than
-- intended. Run this ONCE in the Supabase SQL Editor. Safe to re-run.
-- ============================================================

-- Read: everyone (unchanged intent)
drop policy if exists "translations readable by everyone"
  on public.wildlife_news_translations;
create policy "translations readable by everyone"
  on public.wildlife_news_translations for select
  using (true);

-- Insert: any app user may add a newly translated edition.
drop policy if exists "anyone can insert translations"
  on public.wildlife_news_translations;
create policy "anyone can insert translations"
  on public.wildlife_news_translations for insert
  to anon, authenticated
  with check (true);

-- Update: any app user may improve/replace an existing edition
-- (the editor upserts with onConflict = source_url).
drop policy if exists "anyone can update translations"
  on public.wildlife_news_translations;
create policy "anyone can update translations"
  on public.wildlife_news_translations for update
  to anon, authenticated
  using (true)
  with check (true);
