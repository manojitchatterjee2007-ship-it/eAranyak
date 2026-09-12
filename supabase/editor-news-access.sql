-- ============================================================
-- eআরণ্যক — Editor access to wildlife_news (add / update / delete)
-- Run ONCE in: Supabase Dashboard → SQL Editor → New query
-- Safe to re-run.
--
-- Enables the Editor tab's "Add News Article via Website Link" feature:
-- the app fetches an external article, rewrites it in Bengali via the AI
-- editorial edge function (fetch-news-article + bengali-news-editor), and
-- then writes the published article into wildlife_news so it is visible to
-- every user (admin + normal users) in the News section.
--
-- Only users whose email is listed in the public.admins table receive
-- these write permissions, so normal app users cannot add/delete news.
-- ============================================================

-- -------------------------------------------------------------
-- 1. Helper: is the signed-in user an editor?
--    security definer -> runs as the table owner, ignoring RLS,
--    so this works even if public.admins has its own RLS enabled.
-- -------------------------------------------------------------
create or replace function public.is_editor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins a
    where a.email = coalesce((auth.jwt() ->> 'email'), '')
  );
$$;

grant execute on function public.is_editor() to anon, authenticated;

-- -------------------------------------------------------------
-- 2. wildlife_news write policies (restricted to editors).
--    Existing "anyone read wildlife news" select policy stays intact.
-- -------------------------------------------------------------
drop policy if exists "editors add news" on public.wildlife_news;
create policy "editors add news"
  on public.wildlife_news
  for insert
  to authenticated
  with check (public.is_editor());

drop policy if exists "editors update news" on public.wildlife_news;
create policy "editors update news"
  on public.wildlife_news
  for update
  to authenticated
  using (public.is_editor())
  with check (public.is_editor());

drop policy if exists "editors delete news" on public.wildlife_news;
create policy "editors delete news"
  on public.wildlife_news
  for delete
  to authenticated
  using (public.is_editor());

-- -------------------------------------------------------------
-- 3. Sanity check (run after applying the policies):
--    select policyname, cmd, roles from pg_policies
--    where tablename = 'wildlife_news';
-- -------------------------------------------------------------