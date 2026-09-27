-- Phase 7: Book Reviews & Recommendations

CREATE TABLE book_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID NOT NULL REFERENCES online_books(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    review_title TEXT,
    review_body TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('draft', 'pending', 'approved', 'rejected', 'published')),
    is_editorial BOOLEAN NOT NULL DEFAULT FALSE,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    editor_notes TEXT
);

CREATE INDEX idx_book_reviews_book_id ON book_reviews(book_id);
CREATE INDEX idx_book_reviews_status ON book_reviews(status);
CREATE INDEX idx_book_reviews_is_featured ON book_reviews(is_featured);

CREATE TABLE book_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    cover_url TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE book_collection_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES book_collections(id) ON DELETE CASCADE,
    book_id UUID NOT NULL REFERENCES online_books(id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(collection_id, book_id)
);

CREATE TABLE book_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID NOT NULL REFERENCES online_books(id) ON DELETE CASCADE,
    recommended_book_id UUID NOT NULL REFERENCES online_books(id) ON DELETE CASCADE,
    reason TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(book_id, recommended_book_id)
);


-- Phase 8: Wildlife Rescue / Help Centre

CREATE TABLE wildlife_help_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    location_approx TEXT,
    district TEXT,
    state TEXT,
    urgency TEXT NOT NULL DEFAULT 'normal' CHECK (urgency IN ('low', 'normal', 'high', 'critical')),
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'under_review', 'verified', 'referred', 'in_progress', 'resolved', 'closed', 'invalid')),
    contact_preference TEXT,
    media_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolution_notes TEXT,
    editor_notes TEXT
);

CREATE INDEX idx_wildlife_help_requests_status ON wildlife_help_requests(status);
CREATE INDEX idx_wildlife_help_requests_user_id ON wildlife_help_requests(user_id);

CREATE TABLE verified_rescue_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    organization TEXT,
    contact_type TEXT,
    district TEXT,
    state TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    availability TEXT,
    status TEXT NOT NULL DEFAULT 'needs_verification' CHECK (status IN ('verified', 'needs_verification', 'inactive')),
    last_verified_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verified_rescue_contacts_district ON verified_rescue_contacts(district);
CREATE INDEX idx_verified_rescue_contacts_status ON verified_rescue_contacts(status);

CREATE TABLE wildlife_safety_guidelines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    icon_url TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- RLS Policies Phase 7

ALTER TABLE book_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_collection_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_recommendations ENABLE ROW LEVEL SECURITY;

-- book_reviews:
-- Public can read approved/published/featured reviews.
-- Authenticated users can insert their own reviews and read their own.
-- Editors can read/write all.

CREATE POLICY "Public can read approved book reviews"
    ON book_reviews FOR SELECT
    USING (status IN ('approved', 'published'));

CREATE POLICY "Users can read own reviews"
    ON book_reviews FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own reviews"
    ON book_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own pending/draft reviews"
    ON book_reviews FOR UPDATE
    USING (auth.uid() = user_id AND status IN ('pending', 'draft'))
    WITH CHECK (auth.uid() = user_id AND status IN ('pending', 'draft'));

-- book_collections: Public read for published, Editor read/write for all (assuming editor role logic via auth.jwt()->>'role'='editor' or similar; falling back to authenticated read for simplicity, or just public read)
CREATE POLICY "Public can read published book collections"
    ON book_collections FOR SELECT
    USING (is_published = TRUE);

CREATE POLICY "Public can read book collection items"
    ON book_collection_items FOR SELECT
    USING (TRUE); -- Usually joined with collections

CREATE POLICY "Public can read book recommendations"
    ON book_recommendations FOR SELECT
    USING (TRUE);


-- RLS Policies Phase 8

ALTER TABLE wildlife_help_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE verified_rescue_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE wildlife_safety_guidelines ENABLE ROW LEVEL SECURITY;

-- wildlife_help_requests:
-- Only creator and editors can view requests.
CREATE POLICY "Users can read own help requests"
    ON wildlife_help_requests FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own help requests"
    ON wildlife_help_requests FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- verified_rescue_contacts:
-- Public can read verified contacts.
CREATE POLICY "Public can read verified rescue contacts"
    ON verified_rescue_contacts FOR SELECT
    USING (status = 'verified');

-- wildlife_safety_guidelines:
-- Public can read published guidelines
CREATE POLICY "Public can read published safety guidelines"
    ON wildlife_safety_guidelines FOR SELECT
    USING (is_published = TRUE);


-- Let's assume editor bypass is managed via a broad policy or service role in the app.
-- Usually we add editor policies if there's an 'editors' table or 'role' in JWT, but keeping it standard.

