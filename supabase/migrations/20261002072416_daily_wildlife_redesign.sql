-- Daily Wildlife Pipeline Redesign

ALTER TABLE public.daily_wildlife_features
ADD COLUMN IF NOT EXISTS animal_type TEXT,
ADD COLUMN IF NOT EXISTS selection_reason TEXT,
ADD COLUMN IF NOT EXISTS regional_significance TEXT,
ADD COLUMN IF NOT EXISTS economic_importance TEXT,
ADD COLUMN IF NOT EXISTS habitat_threat TEXT,
ADD COLUMN IF NOT EXISTS educational_value TEXT,
ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS audio_url TEXT,
ADD COLUMN IF NOT EXISTS audio_provider TEXT,
ADD COLUMN IF NOT EXISTS audio_id TEXT,
ADD COLUMN IF NOT EXISTS audio_recordist TEXT,
ADD COLUMN IF NOT EXISTS audio_license TEXT,
ADD COLUMN IF NOT EXISTS audio_attribution TEXT,
ADD COLUMN IF NOT EXISTS audio_available BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS image_provenance TEXT;

-- Ensure statuses: planned, preparing, prepared, scheduled, published, unpublished, cancelled, failed
-- We can't strictly enforce an ENUM easily without potentially breaking existing 'draft' etc, but we'll use TEXT.
