-- Explicitly separate publisher dates from discovery and record modification.
-- Older records remain available for detail links and archive queries.
alter table public.wildlife_news
  add column if not exists first_seen_at timestamptz,
  add column if not exists last_fetched_at timestamptz,
  add column if not exists source_published_at timestamptz,
  add column if not exists updated_at timestamptz;

create or replace function public.try_parse_news_date(value text)
returns timestamptz
language plpgsql
stable
strict
as $$
begin
  return value::timestamptz;
exception when others then
  return null;
end;
$$;

update public.wildlife_news
set first_seen_at = coalesce(first_seen_at, created_at),
    source_published_at = coalesce(source_published_at, public.try_parse_news_date(date_str))
where first_seen_at is null
   or source_published_at is null;

create or replace function public.set_wildlife_news_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists wildlife_news_set_updated_at on public.wildlife_news;
create trigger wildlife_news_set_updated_at
before update on public.wildlife_news
for each row execute function public.set_wildlife_news_updated_at();

comment on column public.wildlife_news.published_at is
  'Publication/approval timestamp used by editorial workflows; automated stories set this to a verified publisher date when available.';
comment on column public.wildlife_news.source_published_at is
  'Verified original publication timestamp reported by the publisher; null when missing or malformed.';
comment on column public.wildlife_news.first_seen_at is
  'Timestamp when this system first discovered the article.';
comment on column public.wildlife_news.last_fetched_at is
  'Timestamp when this system last fetched or verified the article.';
comment on column public.wildlife_news.updated_at is
  'Timestamp when this database record was last modified.';

create index if not exists wildlife_news_recent_source_published_idx
  on public.wildlife_news (source_published_at desc, id desc)
  where is_published = true and source_published_at is not null;

create index if not exists wildlife_news_recent_editorial_published_idx
  on public.wildlife_news (published_at desc, id desc)
  where is_published = true and publication_source = 'editorial';

