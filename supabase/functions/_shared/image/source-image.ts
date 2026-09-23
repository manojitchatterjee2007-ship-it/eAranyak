/**
 * eআরণ্যক — source image validation (server-side).
 *
 * SOURCE IMAGE > GENERATED IMAGE is the strict priority: a source image is
 * used ONLY after it is actually fetchable and a real, decodable image with
 * reasonable dimensions. Anything else (HTTP error, HTML error page, empty
 * body, corrupt bytes, tiny tracking pixel) is treated as "source image
 * unavailable" and the caller may invoke Pollinations.
 *
 * Bounded work: at most 1 retry for transient failures. Never called for an
 * article that already has a stored image (idempotency lives in the caller).
 */

const UA = "Mozilla/5.0 (compatible; eAranyakImageValidator/1.0)";
const DEFAULT_TIMEOUT_MS = 8000;
const MIN_BYTES = 2048;
const MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const MIN_WIDTH = 200;
const MIN_HEIGHT = 150;

export type SourceImageValidation = {
  ok: boolean;
  reason?: string;
  mime?: string;
  bytes?: number;
  width?: number;
  height?: number;
};

function sniffImage(bytes: Uint8Array): { mime: string; width?: number; height?: number } | null {
  if (bytes.length < 12) return null;
  // JPEG: FF D8 FF (+ SOF dimension sniffing)
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    let w: number | undefined;
    let h: number | undefined;
    for (let i = 2; i < bytes.length - 9;) {
      if (bytes[i] !== 0xff) { i++; continue; }
      const marker = bytes[i + 1];
      // SOF0..SOF15 except DHT (C4), DAC (CC), JPG (C8)
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        h = (bytes[i + 5] << 8) | bytes[i + 6];
        w = (bytes[i + 7] << 8) | bytes[i + 8];
        break;
      }
      const segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      i += segLen + 2;
    }
    return { mime: "image/jpeg", width: w, height: h };
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A (IHDR at fixed offset)
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    const w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    const h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return { mime: "image/png", width: w >>> 0, height: h >>> 0 };
  }
  // WEBP: RIFF....WEBP
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return { mime: "image/webp" };
  }
  // GIF is deliberately rejected (existing news pipeline rejects .gif too).
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return { mime: "image/gif" };
  return null;
}

type FetchOutcome =
  | { ok: true; mime: string; bytes: Uint8Array }
  | { ok: false; reason: string; transient: boolean };

async function fetchOnce(url: string, timeoutMs: number): Promise<FetchOutcome> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": UA,
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
      },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!res.ok) {
      const transient = res.status === 429 || res.status >= 500;
      return { ok: false, reason: `HTTP ${res.status}`, transient };
    }
    const contentType = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
    // An HTML error/redirect page is NOT an image.
    if (contentType && !contentType.startsWith("image/")) {
      return { ok: false, reason: `non-image content-type (${contentType})`, transient: false };
    }
    const buf = await res.arrayBuffer();
    const bytes = new Uint8Array(buf);
    if (bytes.length === 0) return { ok: false, reason: "empty image body", transient: false };
    if (bytes.length < MIN_BYTES) return { ok: false, reason: `image too small (${bytes.length} bytes)`, transient: false };
    if (bytes.length > MAX_BYTES) return { ok: false, reason: "image too large", transient: false };
    const sniffed = sniffImage(bytes);
    if (!sniffed) return { ok: false, reason: "undecodable image bytes", transient: false };
    if (sniffed.mime === "image/gif") return { ok: false, reason: "gif rejected by existing policy", transient: false };
    return { ok: true, mime: sniffed.mime, bytes };
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "AbortError";
    return { ok: false, reason: timedOut ? `timeout after ${timeoutMs}ms` : "network failure", transient: true };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Validates that a source image URL is genuinely usable.
 * Bounded: one request + at most one retry for transient failures.
 */
export async function validateSourceImage(
  url: string,
  timeoutMs = DEFAULT_TIMEOUT_MS,
): Promise<SourceImageValidation> {
  if (!url || (!url.startsWith("http://") && !url.startsWith("https://"))) {
    return { ok: false, reason: "not an http(s) URL" };
  }

  let outcome = await fetchOnce(url, timeoutMs);
  if (!outcome.ok && outcome.transient) {
    await new Promise((r) => setTimeout(r, 3000));
    outcome = await fetchOnce(url, timeoutMs);
  }
  if (!outcome.ok) return { ok: false, reason: outcome.reason };

  const dims = sniffImage(outcome.bytes);
  const width = dims?.width;
  const height = dims?.height;
  if (width !== undefined && height !== undefined) {
    if (width < MIN_WIDTH || height < MIN_HEIGHT) {
      return { ok: false, reason: `dimensions too small (${width}x${height})`, mime: outcome.mime, bytes: outcome.bytes.length, width, height };
    }
  }
  // WEBP (and other non-JPEG/PNG formats) pass without a dimension check —
  // a valid, decodable image of unknown size is still a valid source image.

  return { ok: true, mime: outcome.mime, bytes: outcome.bytes.length, width, height };
}
