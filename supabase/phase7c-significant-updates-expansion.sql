-- ============================================================
-- Phase 7C Database Migration
-- eআরণ্যক / eAranyak - Significant Update Events Expansion
-- Adds podcast, vlog, and tutorial to supported content types.
-- ============================================================

ALTER TABLE IF EXISTS public.significant_update_events
  DROP CONSTRAINT IF EXISTS significant_update_events_content_type_check;

ALTER TABLE IF EXISTS public.significant_update_events
  ADD CONSTRAINT significant_update_events_content_type_check
  CHECK (content_type IN ('news', 'gallery', 'magazine', 'quiz', 'app_notification', 'community_article', 'podcast', 'vlog', 'tutorial'));
