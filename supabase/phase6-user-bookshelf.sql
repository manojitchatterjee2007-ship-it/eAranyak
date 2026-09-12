-- =============================================================================
-- eআরণ্যক — Phase 6: User Bookshelf Schema & RLS Policies
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_bookshelf (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  book_id uuid NOT NULL REFERENCES public.online_books(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  last_opened_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_bookshelf_user_book_unique UNIQUE (user_id, book_id)
);

ALTER TABLE public.user_bookshelf ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own bookshelf" ON public.user_bookshelf;
CREATE POLICY "Users can view own bookshelf" ON public.user_bookshelf
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can add to own bookshelf" ON public.user_bookshelf;
CREATE POLICY "Users can add to own bookshelf" ON public.user_bookshelf
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own bookshelf" ON public.user_bookshelf;
CREATE POLICY "Users can update own bookshelf" ON public.user_bookshelf
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete from own bookshelf" ON public.user_bookshelf;
CREATE POLICY "Users can delete from own bookshelf" ON public.user_bookshelf
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS user_bookshelf_user_id_idx ON public.user_bookshelf (user_id);
CREATE INDEX IF NOT EXISTS user_bookshelf_book_id_idx ON public.user_bookshelf (book_id);
