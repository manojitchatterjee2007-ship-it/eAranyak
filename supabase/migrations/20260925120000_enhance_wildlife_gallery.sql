-- Phase 2: Wildlife Gallery Editorial Upgrade
-- Adding new metadata fields to the existing `wildlife_gallery` table.

ALTER TABLE wildlife_gallery
ADD COLUMN IF NOT EXISTS bengali_description TEXT,
ADD COLUMN IF NOT EXISTS photographer_profile_link TEXT,
ADD COLUMN IF NOT EXISTS camera TEXT,
ADD COLUMN IF NOT EXISTS lens TEXT,
ADD COLUMN IF NOT EXISTS aperture TEXT,
ADD COLUMN IF NOT EXISTS shutter_speed TEXT,
ADD COLUMN IF NOT EXISTS iso TEXT,
ADD COLUMN IF NOT EXISTS focal_length TEXT,
ADD COLUMN IF NOT EXISTS common_name TEXT,
ADD COLUMN IF NOT EXISTS scientific_name TEXT,
ADD COLUMN IF NOT EXISTS species_description TEXT,
ADD COLUMN IF NOT EXISTS iucn_status TEXT,
ADD COLUMN IF NOT EXISTS district TEXT,
ADD COLUMN IF NOT EXISTS state TEXT,
ADD COLUMN IF NOT EXISTS country TEXT,
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
