-- Add a foreign key relationship so Supabase/PostgREST can join the tables.
-- This allows .select('*, wildlife_news_translations(...)') to work.

alter table public.wildlife_news_translations
drop constraint if exists fk_wildlife_news;

alter table public.wildlife_news_translations
add constraint fk_wildlife_news
foreign key (source_url)
references public.wildlife_news (source_url)
on delete cascade;
