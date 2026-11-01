-- Migration: quarantine ANY cross-species text/image mismatch on
-- daily_wildlife_features for Gemini regeneration.
--
-- Generic rule (no hardcoded species): when the Bengali/English title or
-- habitat text mentions one animal family while the scheduled
-- scientific_name belongs to another (here: dolphin title/body over
-- Panthera tigris), reset text + image to planned so the Gemini
-- information pass and the verified photo fetch re-run cleanly.

-- Case 1: dolphin-worded text filed under a tiger scientific name.
UPDATE public.daily_wildlife_features
SET
    title_bn = NULL,
    bengali_name = NULL,
    species_description = NULL,
    description_bn = NULL,
    habitat = NULL,
    distribution = NULL,
    diet = NULL,
    behaviour = NULL,
    ecological_role = NULL,
    conservation_status = NULL,
    interesting_facts = NULL,
    did_you_know = NULL,
    original_image_url = NULL,
    image_provenance = NULL,
    image_generation_status = 'pending',
    status = 'planned',
    is_published = FALSE,
    image_generation_error = 'Cross-species text/image mismatch quarantined for Gemini regeneration (dolphin wording under tiger scientific name).'
WHERE
    LOWER(COALESCE(scientific_name, '')) LIKE '%panthera tigris%'
    AND (
        COALESCE(title_bn, '') LIKE '%ডলফিন%'
        OR COALESCE(title, '') LIKE '%ডলফিন%'
        OR COALESCE(common_name, '') LIKE '%ডলফিন%'
        OR COALESCE(bengali_name, '') LIKE '%ডলফিন%'
        OR COALESCE(title_bn, '') ILIKE '%dolphin%'
        OR COALESCE(title, '') ILIKE '%dolphin%'
        OR COALESCE(common_name, '') ILIKE '%dolphin%'
        OR COALESCE(habitat, '') LIKE '%ডলফিন%'
        OR LOWER(COALESCE(original_image_url, '')) LIKE '%dolphin%'
        OR LOWER(COALESCE(original_image_url, '')) LIKE '%platanista%'
        OR LOWER(COALESCE(image_provenance, '')) LIKE '%dolphin%'
        OR LOWER(COALESCE(image_provenance, '')) LIKE '%platanista%'
    );

-- Case 2: generic tiger-art mismatch for non-tiger records (kept from audit).
UPDATE public.daily_wildlife_features
SET
    original_image_url = NULL,
    image_provenance = NULL,
    image_generation_status = 'pending',
    image_generation_error = 'Cross-species image mismatch detected and reset during audit.'
WHERE
    LOWER(COALESCE(scientific_name, '')) NOT LIKE '%panthera tigris%'
    AND (
        LOWER(COALESCE(original_image_url, '')) LIKE '%tiger%'
        OR LOWER(COALESCE(original_image_url, '')) LIKE '%panthera%'
        OR LOWER(COALESCE(image_provenance, '')) LIKE '%tiger%'
        OR LOWER(COALESCE(image_provenance, '')) LIKE '%panthera%'
    );
