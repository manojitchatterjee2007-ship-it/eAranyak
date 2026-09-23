/**
 * eআরণ্যক — Pollinations AI illustration generator (FALLBACK ONLY).
 *
 * Pollinations is invoked ONLY when a source article image is genuinely
 * unavailable, unfetchable or invalid. It is NEVER called when a valid source
 * image exists, and NEVER re-run for an article that already has an image
 * (idempotency lives in the calling pipeline).
 *
 * Secret: uses the EXISTING Supabase Edge Function secret `Pollination_image_API`
 * (server-side only — never exposed to Flutter, never stored in database rows).
 *
 * Verified API shape (from tools/test-pollinations-wildlife-images.ps1 PoC):
 *   GET https://gen.pollinations.ai/image/{urlEncodedPrompt}
 *       ?model={model}&width=1280&height=720&seed={seed}
 *   header: Authorization: Bearer <key>
 *   Model discovery: GET https://gen.pollinations.ai/image/models (no auth)
 *   Observed: openai/gpt-image-2 OK (~40-50s); microsoft/mai-image-2.5-flash
 *   FAILS at 1280x720 (min dimension 768px) — do not reuse those parameters
 *   blindly; tongyi-mai/z-image-turbo OK.
 *
 * Generated images are downloaded server-side, validated, and uploaded to the
 * public `earanyak_illustrations` Supabase Storage bucket, so articles never
 * depend on a temporary Pollinations URL.
 */

const POLLINATIONS_BASE = "https://gen.pollinations.ai";
const POLLINATIONS_MODELS_URI = `${POLLINATIONS_BASE}/image/models`;
/** Production-approved model order (validated in the controlled PoC). */
const PREFERRED_MODELS = ["openai/gpt-image-2", "tongyi-mai/z-image-turbo"];
const GENERATION_TIMEOUT_MS = 120000;
const MODEL_CACHE_TTL_MS = 6 * 60 * 60 * 1000; // discovery cached per isolate

/** Exact controlled visual language validated in the PoC. */
const STYLE_BLOCK =
  "scientifically accurate natural-history wildlife illustration, realistic hand-painted watercolour, detailed natural anatomy, realistic fur and feathers, authentic habitat, subtle pigment variation, visible cold-press watercolour paper texture, delicate transparent washes, controlled pigment granulation, natural earthy colour palette, realistic atmospheric perspective, restrained editorial composition, high-detail wildlife field illustration, museum-quality natural-history artwork, Indian wildlife conservation editorial illustration";

const AVOID_BLOCK =
  "strictly avoid: cartoon, anime, comic, children book illustration, fantasy art, surrealism, glossy generic digital painting, 3D render, CGI, game artwork, exaggerated eyes, incorrect anatomy, extra limbs, duplicate animals, malformed paws, malformed wings, distorted faces, plastic-looking animals, oversaturated colours, artificial neon lighting, any text, captions, labels, typography, logos, watermarks, borders, frames";

export type IllustrationFacts = {
  subject: string;
  scientificName?: string;
  location?: string;
  habitat?: string;
  elements?: string;
  scene?: string;
};

let cachedFreeImageModels: { at: number; names: string[] } | null = null;

function pollinationsKey(): string {
  return Deno.env.get("Pollination_image_API") ?? "";
}

/** Deterministic per-article seed (stable per article, unique across articles). */
export function seedForArticle(title: string): number {
  let h = 5381;
  for (let i = 0; i < title.length; i++) h = ((h << 5) + h + title.charCodeAt(i)) >>> 0;
  return 1 + (h % 999983);
}

/**
 * Extracts structured natural-history facts from the ORIGINAL ENGLISH article.
 * Only facts actually present in the source are used — species, habitat and
 * locations are never invented.
 */
export function extractIllustrationFacts(title: string, articleText: string): IllustrationFacts {
  const facts: IllustrationFacts = {
    subject: title.replace(/\s*[—–|-]\s*[^—–|-]{1,40}$/, "").trim() || title.trim(),
  };

  const scope = articleText.slice(0, 4000);

  // Scientific names: parenthesized Latin binomial/trinomial (validated rule).
  const sci = /\((?:([A-Z][a-zA-Z-]+(?:\s+[a-z][a-z-]+){1,2}))\)/.exec(scope);
  if (sci) facts.scientificName = sci[1];

  // Location: "in/at/from/across <Capitalized Place Words>" in the lede.
  const loc = /(?:\bin|\bat|\bfrom|\bacross)\s+((?:[A-Z][\w''-]+(?:\s+(?:of|the|de|da))?\s*){1,4})/.exec(scope);
  if (loc) {
    const place = loc[1].trim().replace(/\s+(?:the|of|and|with|its|their)$/i, "");
    if (place.length >= 4) facts.location = place;
  }

  // Habitat keywords (only if present verbatim in the article).
  const habitatKeywords: Array<[RegExp, string]> = [
    [/\bmangrove\b/i, "mangrove forest"],
    [/\b(?:tropical|moist|dry|evergreen|deciduous)?\s?rainforest\b|\bdeciduous forest\b/i, "forest"],
    [/\bwetland\b|\bmarsh\b|\bswamp\b/i, "wetland"],
    [/\bgrassland\b|\bmeadow\b|\bsavanna\b/i, "grassland"],
    [/\bcoral reef\b/i, "coral reef"],
    [/\briver\b|\bdelta\b|\bbackwater/i, "river or delta landscape"],
    [/\bHimalaya/i, "Himalayan landscape"],
    [/\bdesert\b|\barid\b/i, "arid landscape"],
    [/\bcoast\b|\bshore\b|\bseagrass\b/i, "coastal landscape"],
    [/\bmountain/i, "mountain landscape"],
  ];
  const habitats: string[] = [];
  for (const [re, label] of habitatKeywords) {
    if (re.test(scope)) habitats.push(label);
    if (habitats.length >= 2) break;
  }
  if (habitats.length) facts.habitat = habitats.join(", ");

  return facts;
}

/** Builds the controlled natural-history illustration prompt from facts. */
export function buildIllustrationPrompt(facts: IllustrationFacts): string {
  const sci = facts.scientificName ? ` (scientific name ${facts.scientificName})` : "";
  const scene =
    facts.scene ??
    `${facts.subject} depicted faithfully in its authentic habitat and characteristic natural behaviour described by the article, restrained natural-history documentary composition, side or three-quarter full-body view, realistic lighting`;
  const parts = [
    `${facts.subject}${sci} in its authentic habitat: ${scene}`,
    facts.location ? `Location context: ${facts.location}.` : "",
    facts.habitat ? `Habitat: ${facts.habitat}.` : "",
    `Style: ${STYLE_BLOCK}.`,
    AVOID_BLOCK,
  ].filter(Boolean);
  return parts.join(" ");
}

/** Cached (per-isolate) free image model discovery. Not run per article. */
async function availableImageModels(): Promise<string[]> {
  if (cachedFreeImageModels && Date.now() - cachedFreeImageModels.at < MODEL_CACHE_TTL_MS) {
    return cachedFreeImageModels.names;
  }
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);
    const res = await fetch(POLLINATIONS_MODELS_URI, { signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const models = await res.json();
    const names = (Array.isArray(models) ? models : [])
      .filter((m: Record<string, unknown>) => m.category === "image" && !m.paid_only)
      .map((m: Record<string, unknown>) => String(m.name))
      .filter(Boolean);
    cachedFreeImageModels = { at: Date.now(), names };
    return names;
  } catch (_) {
    // Discovery failure is non-fatal: fall back to the known-good list.
    return PREFERRED_MODELS;
  }
}

export type GeneratedImage = {
  ok: boolean;
  reason?: string;
  bytes?: Uint8Array;
  mime?: string;
  model?: string;
  ms?: number;
};

function sniffGeneratedImage(bytes: Uint8Array): string | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[8] === 0x57) return "image/webp";
  return null;
}

/**
 * Generates a natural-history illustration via Pollinations.
 * Bounded: tries at most the two production-approved models, one request each.
 * Failures are always recoverable — the caller must not publish a broken URL.
 */
export async function generateIllustration(
  prompt: string,
  seed: number,
  timeoutMs = GENERATION_TIMEOUT_MS,
): Promise<GeneratedImage> {
  const started = Date.now();
  const key = pollinationsKey();
  if (!key) return { ok: false, reason: "Pollinations secret not configured", ms: 0 };

  const available = await availableImageModels();
  const candidates = PREFERRED_MODELS.filter((m) => available.length === 0 || available.includes(m));
  const models = candidates.length ? candidates : PREFERRED_MODELS;

  for (const model of models) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const uri = `${POLLINATIONS_BASE}/image/${encodeURIComponent(prompt)}?model=${encodeURIComponent(model)}&width=1280&height=720&seed=${seed}`;
      const res = await fetch(uri, {
        headers: { "Authorization": `Bearer ${key}` },
        signal: controller.signal,
      });
      if (!res.ok) continue; // 401/402/429/500 — recoverable, try next model
      const contentType = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      const buf = await res.arrayBuffer();
      const bytes = new Uint8Array(buf);
      const sniffed = sniffGeneratedImage(bytes);
      if (!sniffed || (contentType && !contentType.startsWith("image/"))) continue;
      if (bytes.length < 2048) continue;
      return { ok: true, bytes, mime: sniffed, model, ms: Date.now() - started };
    } catch (_) {
      continue; // timeout/network — try next model
    } finally {
      clearTimeout(timer);
    }
  }
  return { ok: false, reason: "all Pollinations models failed", ms: Date.now() - started };
}

export type StoredImage = {
  ok: boolean;
  reason?: string;
  publicUrl?: string;
  path?: string;
  bucket?: string;
};

interface StorageBucketApi {
  upload: (path: string, body: Uint8Array, options?: { contentType?: string; upsert?: boolean }) => Promise<{ error: { message: string } | null }>;
  getPublicUrl: (path: string) => { data: { publicUrl: string } | null };
  remove: (paths: string[]) => Promise<{ error: { message: string } | null }>;
}

/**
 * Uploads a generated illustration to the public `earanyak_illustrations`
 * bucket (service-role client bypasses RLS; bucket + policies are provisioned
 * by the accompanying SQL migration). Returns the permanent public URL so the
 * article row never depends on a temporary Pollinations URL.
 */
export async function storeIllustration(
  admin: { storage: { from: (bucket: string) => StorageBucketApi } },
  bytes: Uint8Array,
  mime: string,
  articleSlug: string,
): Promise<StoredImage> {
  const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
  const path = `generated/${articleSlug}-${Date.now()}.${ext}`;
  const bucket = "earanyak_illustrations";
  try {
    const { error } = await admin.storage.from(bucket).upload(path, bytes, {
      contentType: mime,
      upsert: false,
    });
    if (error) return { ok: false, reason: `storage upload failed: ${error.message}` };
    const { data } = admin.storage.from(bucket).getPublicUrl(path);
    const publicUrl = data?.publicUrl;
    if (!publicUrl) return { ok: false, reason: "public URL unavailable after upload" };
    return { ok: true, publicUrl, path, bucket };
  } catch (err) {
    return { ok: false, reason: `storage upload error: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/** Removes a previously stored generated illustration (rotation cleanup). */
export async function removeStoredIllustration(
  admin: { storage: { from: (bucket: string) => StorageBucketApi } },
  publicUrl: string,
): Promise<void> {
  try {
    const marker = "/earanyak_illustrations/";
    const idx = publicUrl.indexOf(marker);
    if (idx === -1) return; // not one of ours (a source image) — never touch it
    const path = publicUrl.substring(idx + marker.length).split("?")[0];
    await admin.storage.from("earanyak_illustrations").remove([path]);
  } catch (_) {
    // Cleanup is best-effort and must never break rotation.
  }
}
