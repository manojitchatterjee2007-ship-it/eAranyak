-- Phase 6: KISHORE eআরণ্যক + VANARAKKHI GAMIFICATION

CREATE TABLE IF NOT EXISTS public.kishore_learning_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title_bn TEXT NOT NULL,
    description_bn TEXT,
    category TEXT NOT NULL,
    difficulty_level INTEGER DEFAULT 1,
    content_payload JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_missions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title_bn TEXT NOT NULL,
    description_bn TEXT,
    category TEXT NOT NULL,
    difficulty TEXT DEFAULT 'easy',
    xp_reward INTEGER NOT NULL DEFAULT 10,
    prerequisite_mission_id UUID REFERENCES public.vanarakkhi_missions(id),
    completion_criteria JSONB,
    educational_explanation TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_bn TEXT NOT NULL,
    description_bn TEXT,
    icon_url TEXT,
    criteria JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_user_progress (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    total_xp INTEGER DEFAULT 0,
    current_level INTEGER DEFAULT 1,
    unlocked_species UUID[] DEFAULT '{}',
    last_activity_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_user_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    badge_id UUID REFERENCES public.vanarakkhi_badges(id),
    awarded_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, badge_id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title_bn TEXT NOT NULL,
    description_bn TEXT,
    species_id UUID,
    tasks JSONB,
    xp_reward INTEGER DEFAULT 20,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_question_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title_bn TEXT NOT NULL,
    module_id UUID REFERENCES public.kishore_learning_modules(id),
    questions JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_question_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    question_set_id UUID REFERENCES public.vanarakkhi_question_sets(id),
    score INTEGER NOT NULL,
    max_score INTEGER NOT NULL,
    xp_awarded INTEGER DEFAULT 0,
    attempted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.vanarakkhi_mission_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    mission_id UUID REFERENCES public.vanarakkhi_missions(id),
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    xp_awarded INTEGER,
    UNIQUE(user_id, mission_id)
);

-- RLS
ALTER TABLE public.kishore_learning_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_user_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_user_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_question_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_question_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vanarakkhi_mission_completions ENABLE ROW LEVEL SECURITY;

-- Read Access
CREATE POLICY "Public read active modules" ON public.kishore_learning_modules FOR SELECT USING (is_active = true);
CREATE POLICY "Public read active missions" ON public.vanarakkhi_missions FOR SELECT USING (is_active = true);
CREATE POLICY "Public read active badges" ON public.vanarakkhi_badges FOR SELECT USING (is_active = true);
CREATE POLICY "Public read active challenges" ON public.vanarakkhi_challenges FOR SELECT USING (is_active = true);
CREATE POLICY "Public read active question sets" ON public.vanarakkhi_question_sets FOR SELECT USING (is_active = true);

-- User Progress Access
CREATE POLICY "Users read own progress" ON public.vanarakkhi_user_progress FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own badges" ON public.vanarakkhi_user_badges FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own question attempts" ON public.vanarakkhi_question_attempts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users read own mission completions" ON public.vanarakkhi_mission_completions FOR SELECT USING (auth.uid() = user_id);

-- Write Access for Users (Restricted to RPC to prevent direct tampering)
-- We will rely on security definer functions for progress updates, so no direct INSERT/UPDATE for users.

-- RPC to record mission completion safely
CREATE OR REPLACE FUNCTION public.complete_mission(p_mission_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_xp_reward INTEGER;
    v_already_completed BOOLEAN;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check if mission exists and active
    SELECT xp_reward INTO v_xp_reward FROM public.vanarakkhi_missions WHERE id = p_mission_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mission not found or inactive';
    END IF;

    -- Check if already completed
    SELECT EXISTS(SELECT 1 FROM public.vanarakkhi_mission_completions WHERE user_id = auth.uid() AND mission_id = p_mission_id) INTO v_already_completed;
    IF v_already_completed THEN
        RETURN FALSE; -- Already completed
    END IF;

    -- Insert completion
    INSERT INTO public.vanarakkhi_mission_completions (user_id, mission_id, xp_awarded)
    VALUES (auth.uid(), p_mission_id, v_xp_reward);

    -- Update user progress
    INSERT INTO public.vanarakkhi_user_progress (user_id, total_xp, last_activity_at)
    VALUES (auth.uid(), v_xp_reward, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        total_xp = public.vanarakkhi_user_progress.total_xp + v_xp_reward,
        last_activity_at = NOW();

    RETURN TRUE;
END;
$$;


-- RPC to securely award XP for Citizen Science observations (e.g. called from a trigger when status becomes 'verified')
CREATE OR REPLACE FUNCTION public.award_citizen_science_xp(p_user_id UUID, p_xp_amount INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $x$
BEGIN
    INSERT INTO public.vanarakkhi_user_progress (user_id, total_xp, last_activity_at)
    VALUES (p_user_id, p_xp_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        total_xp = public.vanarakkhi_user_progress.total_xp + p_xp_amount,
        last_activity_at = NOW();
END;
$x$;
