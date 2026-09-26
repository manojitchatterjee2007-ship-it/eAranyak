-- Phase 4: Daily Wildlife Feature & About Us

CREATE TABLE IF NOT EXISTS public.daily_wildlife_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    title TEXT NOT NULL,
    title_bn TEXT,
    common_name TEXT,
    scientific_name TEXT,
    bengali_name TEXT,
    species_description TEXT,
    description_bn TEXT,
    habitat TEXT,
    distribution TEXT,
    diet TEXT,
    behaviour TEXT,
    ecological_role TEXT,
    conservation_status TEXT,
    iucn_status TEXT,
    interesting_facts TEXT,
    did_you_know TEXT,
    source_urls TEXT,
    source_attributions TEXT,
    original_image_url TEXT,
    watercolour_image_url TEXT,
    watercolour_prompt TEXT,
    image_generation_status TEXT DEFAULT 'pending',
    image_generation_provider TEXT,
    image_generation_error TEXT,
    editor_notes TEXT,
    editor_override BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    is_published BOOLEAN DEFAULT FALSE,
    scheduled_publish_at TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    UNIQUE(feature_date)
);

CREATE TABLE IF NOT EXISTS public.about_us_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title_bn TEXT NOT NULL,
    subtitle_bn TEXT,
    body_bn TEXT,
    what_we_do_title_bn TEXT,
    what_we_do_body_bn TEXT,
    hero_image_url TEXT,
    sections_json JSONB,
    is_published BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id)
);

-- RLS for Daily Wildlife Features
ALTER TABLE public.daily_wildlife_features ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can view published daily wildlife features" 
ON public.daily_wildlife_features FOR SELECT 
USING (is_published = true AND (scheduled_publish_at IS NULL OR scheduled_publish_at <= NOW()) OR public.is_editor());

CREATE POLICY "Editors can insert daily wildlife features" 
ON public.daily_wildlife_features FOR INSERT 
WITH CHECK (public.is_editor());

CREATE POLICY "Editors can update daily wildlife features" 
ON public.daily_wildlife_features FOR UPDATE 
USING (public.is_editor())
WITH CHECK (public.is_editor());

CREATE POLICY "Editors can delete daily wildlife features" 
ON public.daily_wildlife_features FOR DELETE 
USING (public.is_editor());


-- RLS for About Us Content
ALTER TABLE public.about_us_content ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can view published about us content"
ON public.about_us_content FOR SELECT
USING (is_published = true OR public.is_editor());

CREATE POLICY "Editors can insert about us content"
ON public.about_us_content FOR INSERT
WITH CHECK (public.is_editor());

CREATE POLICY "Editors can update about us content"
ON public.about_us_content FOR UPDATE
USING (public.is_editor())
WITH CHECK (public.is_editor());

CREATE POLICY "Editors can delete about us content"
ON public.about_us_content FOR DELETE
USING (public.is_editor());

