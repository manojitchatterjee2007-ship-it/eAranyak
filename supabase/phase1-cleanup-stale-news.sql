-- =============================================================================
-- eআরণ্যক — Phase 1: Safe Cleanup of Incomplete Wildlife News Records
-- =============================================================================
--
-- PURPOSE
-- Remove legacy wildlife news records that cannot be properly displayed in the
-- current Bengali-first news system.
--
-- A record is considered incomplete only when it clearly lacks one or more
-- essential requirements:
--
--   1. A valid HTTP/HTTPS image URL
--   2. A Bengali headline in wildlife_news OR translations cache
--   3. A usable Bengali body in wildlife_news OR translations cache
--
-- IMPORTANT:
-- Run the PREVIEW query first.
-- Inspect the results before running the DELETE query.
--
-- Bengali detection uses actual Bengali Unicode characters [অ-৿].
-- =============================================================================


-- =============================================================================
-- 1. PREVIEW — RUN THIS FIRST
-- =============================================================================

SELECT
  n.id,
  n.article_id,
  n.source,
  n.source_url,
  n.title AS original_title,

  n.bengali_headline,
  t.headline AS cached_bengali_headline,

  n.bengali_body,
  t.body AS cached_bengali_body,

  n.image_url,
  n.processing_status,
  n.created_at,

  CASE
    WHEN n.image_url IS NULL
      OR trim(n.image_url) = ''
      OR n.image_url !~* '^https?://'
    THEN 'Missing or invalid image URL'

    WHEN
      (
        n.bengali_headline IS NULL
        OR trim(n.bengali_headline) = ''
        OR n.bengali_headline !~ '[অ-৿]'
      )
      AND
      (
        t.headline IS NULL
        OR trim(t.headline) = ''
        OR t.headline !~ '[অ-৿]'
      )
    THEN 'Missing Bengali headline'

    WHEN
      (
        n.bengali_body IS NULL
        OR trim(n.bengali_body) = ''
        OR length(trim(n.bengali_body)) < 50
        OR n.bengali_body !~ '[অ-৿]'
      )
      AND
      (
        t.body IS NULL
        OR trim(t.body) = ''
        OR length(trim(t.body)) < 50
        OR t.body !~ '[অ-৿]'
      )
    THEN 'Missing usable Bengali body'

    WHEN
      coalesce(n.processing_status, 'pending') <> 'published'
      AND
      (
        n.bengali_headline IS NULL
        OR trim(n.bengali_headline) = ''
        OR n.bengali_headline !~ '[অ-৿]'
      )
      AND
      (
        t.headline IS NULL
        OR trim(t.headline) = ''
        OR t.headline !~ '[অ-৿]'
      )
    THEN 'Incomplete processing status with no Bengali edition'

    ELSE 'Incomplete record'
  END AS incompletion_reason

FROM public.wildlife_news n

LEFT JOIN public.wildlife_news_translations t
  ON t.source_url = n.source_url

WHERE

  -- Missing or invalid image URL
  (
    n.image_url IS NULL
    OR trim(n.image_url) = ''
    OR n.image_url !~* '^https?://'
  )

  OR

  -- Missing Bengali headline everywhere
  (
    (
      n.bengali_headline IS NULL
      OR trim(n.bengali_headline) = ''
      OR n.bengali_headline !~ '[অ-৿]'
    )
    AND
    (
      t.headline IS NULL
      OR trim(t.headline) = ''
      OR t.headline !~ '[অ-৿]'
    )
  )

  OR

  -- Missing usable Bengali body everywhere
  (
    (
      n.bengali_body IS NULL
      OR trim(n.bengali_body) = ''
      OR length(trim(n.bengali_body)) < 50
      OR n.bengali_body !~ '[অ-৿]'
    )
    AND
    (
      t.body IS NULL
      OR trim(t.body) = ''
      OR length(trim(t.body)) < 50
      OR t.body !~ '[অ-৿]'
    )
  )

  OR

  -- Non-published processing state AND no Bengali edition anywhere
  (
    coalesce(n.processing_status, 'pending') <> 'published'

    AND

    (
      n.bengali_headline IS NULL
      OR trim(n.bengali_headline) = ''
      OR n.bengali_headline !~ '[অ-৿]'
    )

    AND

    (
      t.headline IS NULL
      OR trim(t.headline) = ''
      OR t.headline !~ '[অ-৿]'
    )
  )

ORDER BY n.created_at DESC;


-- =============================================================================
-- 2. DELETE — ONLY RUN AFTER REVIEWING THE PREVIEW RESULTS
-- =============================================================================

WITH candidate_stale AS (

  SELECT DISTINCT n.id

  FROM public.wildlife_news n

  LEFT JOIN public.wildlife_news_translations t
    ON t.source_url = n.source_url

  WHERE

    (
      n.image_url IS NULL
      OR trim(n.image_url) = ''
      OR n.image_url !~* '^https?://'
    )

    OR

    (
      (
        n.bengali_headline IS NULL
        OR trim(n.bengali_headline) = ''
        OR n.bengali_headline !~ '[অ-৿]'
      )
      AND
      (
        t.headline IS NULL
        OR trim(t.headline) = ''
        OR t.headline !~ '[অ-৿]'
      )
    )

    OR

    (
      (
        n.bengali_body IS NULL
        OR trim(n.bengali_body) = ''
        OR length(trim(n.bengali_body)) < 50
        OR n.bengali_body !~ '[অ-৿]'
      )
      AND
      (
        t.body IS NULL
        OR trim(t.body) = ''
        OR length(trim(t.body)) < 50
        OR t.body !~ '[অ-৿]'
      )
    )

    OR

    (
      coalesce(n.processing_status, 'pending') <> 'published'

      AND

      (
        n.bengali_headline IS NULL
        OR trim(n.bengali_headline) = ''
        OR n.bengali_headline !~ '[অ-৿]'
      )

      AND

      (
        t.headline IS NULL
        OR trim(t.headline) = ''
        OR t.headline !~ '[অ-৿]'
      )
    )
)

DELETE FROM public.wildlife_news
WHERE id IN (
  SELECT id
  FROM candidate_stale
)

RETURNING
  id,
  source,
  source_url,
  title,
  created_at;