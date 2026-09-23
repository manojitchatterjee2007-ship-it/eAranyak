-- =============================================================================
-- eআরণ্যক — Seed Sample Published Tutorial
-- =============================================================================

INSERT INTO public.tutorials (
  id,
  title,
  snippet,
  description,
  thumbnail_url,
  resource_url,
  resource_type,
  category,
  difficulty,
  duration_minutes,
  editorial_priority,
  is_featured,
  is_published,
  published_at,
  source_url,
  source_name,
  created_at,
  updated_at
) VALUES (
  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
  'বাঘ সংরক্ষণ ও গতিবিধি: একটি প্রাথমিক গাইড',
  'সুন্দরবনের রয়্যাল বেঙ্গল টাইগার সংরক্ষণের আধুনিক পদ্ধতি ও কৌশল।',
  'সুন্দরবনের বাঘ আমাদের জাতীয় গর্ব। এই টিউটোরিয়ালে আমরা আলোচনা করব কীভাবে বন্যপ্রাণী কর্মীরা বাঘের গতিবিধি পর্যবেক্ষণ করেন, ক্যামেরা ট্র্যাপ ব্যবহার করেন এবং মানব-বন্যপ্রাণী সংঘাত এড়ানোর উপায়। ক্যামেরা ট্র্যাপ এবং স্যাটেলাইট রেডিও কলারের মাধ্যমে বাঘের আচরণ বুঝতে গবেষকরা গুরুত্বপূর্ণ তথ্য সংগ্রহ করেন।',
  'https://images.unsplash.com/photo-1534188753412-3e26d0d618d6?q=80&w=1000&auto=format&fit=crop',
  'https://india.mongabay.com/tiger-conservation-guide',
  'external',
  'Conservation',
  'beginner',
  8,
  100,
  true,
  true,
  now(),
  'https://india.mongabay.com/tiger-conservation-guide',
  'Mongabay India',
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET
  is_published = true,
  published_at = coalesce(tutorials.published_at, now());
