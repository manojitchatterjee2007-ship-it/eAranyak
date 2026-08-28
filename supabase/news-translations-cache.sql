-- ============================================================
-- wildlife_news_translations
-- Shared cache of Bengali editorial rewrites for live news.
-- Keyed by source article URL so translations are generated
-- once and reused by every user/device (saves AI tokens).
--
-- Run this once in Supabase Dashboard -> SQL Editor.
-- ============================================================

create table if not exists public.wildlife_news_translations (
  source_url text primary key,
  headline   text not null,
  dek        text,
  body       text,
  created_at timestamptz not null default now()
);

alter table public.wildlife_news_translations enable row level security;

drop policy if exists "translations readable by everyone"
  on public.wildlife_news_translations;
create policy "translations readable by everyone"
  on public.wildlife_news_translations for select
  using (true);

drop policy if exists "anyone can insert translations"
  on public.wildlife_news_translations;
create policy "anyone can insert translations"
  on public.wildlife_news_translations for insert
  to anon, authenticated
  with check (true);

drop policy if exists "anyone can update translations"
  on public.wildlife_news_translations;
create policy "anyone can update translations"
  on public.wildlife_news_translations for update
  to anon, authenticated
  using (true)
  with check (true);
