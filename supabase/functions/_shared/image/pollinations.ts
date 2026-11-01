/**
 * eআরণ্যক — Pollinations AI illustration generator.
 *
 * Pollinations is invoked ONLY when a source article image is genuinely
 * unavailable, or to perform image-to-image style transfer for watercolors.
 *
 * Secret: uses the EXISTING Supabase Edge Function secret `Pollination_image_API`
 */

const POLLINATIONS_BASE = "https://gen.pollinations.ai";
const POLLINATIONS_MODELS_URI = `${POLLINATIONS_BASE}/image/models`;
const PREFERRED_MODELS = ["microsoft/mai-image-2.6", "openai/gpt-image-2.5-flare"];
const GENERATION_TIMEOUT_MS = 120000;
const MODEL_CACHE_TTL_MS = 6 * 60 * 60 * 1000; // discovery cached per isolate

/** Exact controlled visual language validated in the PoC. */
const STYLE_BLOCK =
  "scientifically accurate natural-history wildlife illustration, realistic hand-painted watercolour, detailed natural anatomy, realistic fur and feathers, authentic habitat, subtle pigment variation, visible cold-press watercolour paper texture, delicate transparent washes, controlled pigment granulation, natural earthy colour palette, realistic atmospheric perspective, restrained editorial composition, high-detail wildlife field illustration, museum-quality natural-history artwork, Indian wildlife conservation editorial illustration";

const AVOID_BLOCK =
  "strictly avoid: cartoon, anime, comic, children book illustration, fantasy art, surrealism, glossy generic digital painting, 3D render, CGI, game artwork, exaggerated eyes, incorrect anatomy, extra limbs, duplicate animals, malformed paws, malformed wings, distorted faces, plastic-looking animals, oversaturated colours, artificial neon lighting, any text, captions, labels, typography, logos, watermarks, borders, frames";

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
      if (!res.ok) {
        const errorText = await res.text();
        console.error(`[Pollinations] Text-to-Image Error (${res.status}): ${errorText}`);
        continue;
      }
      const contentType = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      const buf = await res.arrayBuffer();
      const bytes = new Uint8Array(buf);
      const sniffed = sniffGeneratedImage(bytes);
      if (!sniffed || (contentType && !contentType.startsWith("image/"))) continue;
      if (bytes.length < 2048) continue;
      return { ok: true, bytes, mime: sniffed, model, ms: Date.now() - started };
    } catch (_) {
      continue;
    } finally {
      clearTimeout(timer);
    }
  }
  return { ok: false, reason: "All Pollinations models failed", ms: Date.now() - started };
}

/**
 * Perform a true Image-to-Image style transfer by posting the actual image bytes
 * to the v1/images/edits endpoint.
 */
export async function generateIllustrationFromSource(
  sourceImageBytes: Uint8Array,
  sourceMime: string,
  prompt: string,
  seed: number,
  timeoutMs = GENERATION_TIMEOUT_MS
): Promise<GeneratedImage> {
  const started = Date.now();
  const key = pollinationsKey();
  if (!key) return { ok: false, reason: "Pollinations secret not configured", ms: 0 };

  // IMPORTANT: Do exactly ONE edit request. Do not chain paid fallbacks.
  // A 402 means the account/key balance is insufficient; retrying another
  // model would only risk spending more balance and does not solve 402.
  // FLUX.2 Klein 4B is currently documented by Pollinations as an image
  // generation/editing model and is a much more appropriate budget choice
  // than the previous premium fallback chain.
  const model = Deno.env.get("POLLINATIONS_WILDLIFE_EDIT_MODEL")?.trim()
    || "black-forest-labs/flux.2-klein-4b";

  const fullPrompt = `${prompt} Style: ${STYLE_BLOCK} ${AVOID_BLOCK}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const ext = sourceMime === "image/png" ? "png" : sourceMime === "image/webp" ? "webp" : "jpg";
    const blob = new Blob([sourceImageBytes as any], { type: sourceMime });
    const formData = new FormData();
    formData.append("prompt", fullPrompt);
    formData.append("model", model);
    formData.append("seed", seed.toString());
    formData.append("image", blob, `source.${ext}`);

    const res = await fetch(`${POLLINATIONS_BASE}/v1/images/edits`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${key}` },
      body: formData,
      signal: controller.signal,
    });

    const errorText = res.ok ? "" : await res.text();
    if (!res.ok) {
      if (res.status === 402) {
        return {
          ok: false,
          reason: `HTTP 402: ${errorText.substring(0, 800)}`,
          model,
          ms: Date.now() - started,
        };
      }
      return {
        ok: false,
        reason: `HTTP ${res.status}: ${errorText.substring(0, 800)}`,
        model,
        ms: Date.now() - started,
      };
    }

    const contentType = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
    let outBytes: Uint8Array | null = null;
    let outMime: string | null = null;

    if (contentType.startsWith("application/json")) {
      const json = await res.json();
      const item = json?.data?.[0];
      if (item?.b64_json) {
        const raw = atob(item.b64_json);
        outBytes = Uint8Array.from(raw, c => c.charCodeAt(0));
        outMime = "image/png";
      } else if (item?.url) {
        const imgRes = await fetch(item.url);
        if (imgRes.ok) {
          outMime = (imgRes.headers.get("content-type") || "image/png").split(";")[0];
          outBytes = new Uint8Array(await imgRes.arrayBuffer());
        }
      }
    } else if (contentType.startsWith("image/")) {
      outBytes = new Uint8Array(await res.arrayBuffer());
      outMime = contentType;
    }

    if (!outBytes || outBytes.length < 2048) {
      return { ok: false, reason: "Pollinations returned no valid image", model, ms: Date.now() - started };
    }

    return {
      ok: true,
      bytes: outBytes,
      mime: outMime || "image/png",
      model,
      ms: Date.now() - started,
    };
  } catch (err: any) {
    return {
      ok: false,
      reason: `Exception: ${err?.message || String(err)}`,
      model,
      ms: Date.now() - started,
    };
  } finally {
    clearTimeout(timer);
  }
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
 */
export async function storeIllustration(
  admin: { storage: { from: (bucket: string) => StorageBucketApi } },
  bytes: Uint8Array,
  mime: string,
  articleSlug: string,
): Promise<StoredImage> {
  const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg";
  const path = `generated/${articleSlug}-${Date.now()}.${ext}`;
  const bucket = "daily_wildlife";
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

export async function removeStoredIllustration(
  admin: { storage: { from: (bucket: string) => StorageBucketApi } },
  publicUrl: string,
): Promise<void> {
  try {
    const marker = "/daily_wildlife/";
    const idx = publicUrl.indexOf(marker);
    if (idx === -1) return;
    const path = publicUrl.substring(idx + marker.length).split("?")[0];
    await admin.storage.from("daily_wildlife").remove([path]);
  } catch (_) {
  }
}
