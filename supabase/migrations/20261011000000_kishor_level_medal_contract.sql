-- Kishor Aranyak Level Completion and Medal Eligibility Migration

-- 1. Table for persistent level completions
CREATE TABLE IF NOT EXISTS public.kishor_level_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    level_number INTEGER NOT NULL CHECK (level_number >= 1),
    category TEXT NOT NULL DEFAULT 'general',
    score INTEGER NOT NULL DEFAULT 0 CHECK (score >= 0),
    max_score INTEGER NOT NULL DEFAULT 0 CHECK (max_score >= 0),
    is_eligible BOOLEAN NOT NULL DEFAULT false,
    xp_awarded INTEGER NOT NULL DEFAULT 0,
    achievement_id UUID REFERENCES public.vanarakkhi_badges(id) ON DELETE SET NULL,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_kishor_level_completion UNIQUE (user_id, level_number, category)
);

-- RLS for level completions
ALTER TABLE public.kishor_level_completions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own level completions" ON public.kishor_level_completions;
CREATE POLICY "Users read own level completions" ON public.kishor_level_completions
    FOR SELECT USING (auth.uid() = user_id);

-- Restrict direct insert/update for normal users (RPC must be used for safe verification)
DROP POLICY IF EXISTS "Editors full access level completions" ON public.kishor_level_completions;
CREATE POLICY "Editors full access level completions" ON public.kishor_level_completions
    FOR ALL USING (public.is_editor());

-- 2. RPC function to securely record level completion and calculate medal eligibility
CREATE OR REPLACE FUNCTION public.record_kishor_level_completion(
    p_level INTEGER,
    p_score INTEGER,
    p_max_score INTEGER,
    p_category TEXT DEFAULT 'general'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_is_eligible BOOLEAN;
    v_xp_to_award INTEGER := 0;
    v_badge_id UUID := NULL;
    v_existing_score INTEGER := -1;
    v_completed_at TIMESTAMPTZ := NOW();
    v_pass_ratio NUMERIC := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_level < 1 THEN
        RAISE EXCEPTION 'Invalid level number';
    END IF;

    IF p_max_score <= 0 OR p_score < 0 OR p_score > p_max_score THEN
        RAISE EXCEPTION 'Invalid score payload';
    END IF;

    -- Calculate pass ratio (70% or higher required for medal eligibility)
    v_pass_ratio := (p_score::NUMERIC / p_max_score::NUMERIC);
    v_is_eligible := (v_pass_ratio >= 0.70);

    -- Base XP = 10 * score
    v_xp_to_award := p_score * 10;
    IF v_is_eligible THEN
        v_xp_to_award := v_xp_to_award + 25; -- Bonus XP for eligible completion
    END IF;

    -- Find matching badge/achievement if eligible
    IF v_is_eligible THEN
        SELECT id INTO v_badge_id
        FROM public.vanarakkhi_badges
        WHERE is_active = true AND (criteria->>'level')::INTEGER = p_level
        LIMIT 1;
    END IF;

    -- Check existing best score
    SELECT score INTO v_existing_score
    FROM public.kishor_level_completions
    WHERE user_id = v_user_id AND level_number = p_level AND category = COALESCE(p_category, 'general');

    IF v_existing_score IS NOT NULL AND v_existing_score >= p_score THEN
        -- Level already completed with equal or better score; do not re-award duplicate XP/medals
        SELECT is_eligible, completed_at, achievement_id
        INTO v_is_eligible, v_completed_at, v_badge_id
        FROM public.kishor_level_completions
        WHERE user_id = v_user_id AND level_number = p_level AND category = COALESCE(p_category, 'general');

        RETURN jsonb_build_object(
            'participant_id', v_user_id,
            'completed_level', p_level,
            'category', COALESCE(p_category, 'general'),
            'achievement_id', v_badge_id,
            'completion_timestamp', v_completed_at,
            'is_eligible', v_is_eligible,
            'score', v_existing_score,
            'max_score', p_max_score,
            'xp_awarded', 0,
            'already_completed', true
        );
    END IF;

    -- Upsert completion
    INSERT INTO public.kishor_level_completions (
        user_id, level_number, category, score, max_score, is_eligible, xp_awarded, achievement_id, completed_at, updated_at
    )
    VALUES (
        v_user_id, p_level, COALESCE(p_category, 'general'), p_score, p_max_score, v_is_eligible, v_xp_to_award, v_badge_id, NOW(), NOW()
    )
    ON CONFLICT (user_id, level_number, category) DO UPDATE SET
        score = EXCLUDED.score,
        max_score = EXCLUDED.max_score,
        is_eligible = EXCLUDED.is_eligible,
        xp_awarded = EXCLUDED.xp_awarded,
        achievement_id = EXCLUDED.achievement_id,
        updated_at = NOW();

    -- Award badge safely if eligible and badge exists
    IF v_is_eligible AND v_badge_id IS NOT NULL THEN
        INSERT INTO public.vanarakkhi_user_badges (user_id, badge_id, awarded_at)
        VALUES (v_user_id, v_badge_id, NOW())
        ON CONFLICT (user_id, badge_id) DO NOTHING;
    END IF;

    -- Update user progress securely
    INSERT INTO public.vanarakkhi_user_progress (user_id, total_xp, current_level, last_activity_at)
    VALUES (v_user_id, v_xp_to_award, GREATEST(1, p_level), NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        total_xp = public.vanarakkhi_user_progress.total_xp + v_xp_to_award,
        current_level = GREATEST(public.vanarakkhi_user_progress.current_level, p_level),
        last_activity_at = NOW();

    RETURN jsonb_build_object(
        'participant_id', v_user_id,
        'completed_level', p_level,
        'category', COALESCE(p_category, 'general'),
        'achievement_id', v_badge_id,
        'completion_timestamp', NOW(),
        'is_eligible', v_is_eligible,
        'score', p_score,
        'max_score', p_max_score,
        'xp_awarded', v_xp_to_award,
        'already_completed', false
    );
END;
$$;
