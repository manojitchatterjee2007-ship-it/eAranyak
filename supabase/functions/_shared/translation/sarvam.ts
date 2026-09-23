/**
 * eআরণ্যক — Sarvam English→Bengali translation provider (PRIMARY).
 *
 * Uses the EXISTING Supabase Edge Function secret `Sarvam_Bengali_Translation_Key`
 * (server-side only — never exposed to Flutter, never logged, never stored).
 *
 * Verified request shape (from tools/test-sarvam-bengali.ps1 PoC, 2026-09-14):
 *   POST https://api.sarvam.ai/translate
 *   header: api-subscription-key: <raw key, no Bearer prefix>
 *   body:   { input, source_language_code: "en-IN", target_language_code: "bn-IN",
 *             model: "sarvam-translate:v1" }   (mode defaults to `formal`)
 *   response: { translated_text } (or { translatedText })
 *
 * `sarvam-translate:v1` limits input to 2000 characters — content is NEVER
 * truncated; it is chunked paragraph-aware and reassembled in order.
 */

const SARVAM_ENDPOINT = "https://api.sarvam.ai/translate";
const SARVAM_MODEL = "sarvam-translate:v1";
const SARVAM_TIMEOUT_MS = 45000;
/** API hard limit is 2000 chars; keep headroom for token boundaries. */
const SARVAM_MAX_CHUNK_CHARS = 1900;

export type ProviderFailure = { reason: string; status?: number; ms: number };
export type ProviderSuccess = { ok: true; text: string; ms: number };
export type ProviderResult = ProviderSuccess | { ok: false; failure: ProviderFailure };

function sarvamKey(): string {
  return Deno.env.get("Sarvam_Bengali_Translation_Key") ?? "";
}

/** Splits text into sentence units without breaking tokens. */
function splitSentences(text: string): string[] {
  const parts: string[] = [];
  let start = 0;
  const re = /[।.!?]+["'”’)\]]*\s/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const end = m.index + m[0].length;
    const seg = text.slice(start, end).trim();
    if (seg) parts.push(seg);
    start = end;
  }
  const tail = text.slice(start).trim();
  if (tail) parts.push(tail);
  return parts;
}

/**
 * Paragraph-aware chunking: whole paragraphs are packed into chunks of at most
 * `maxChars`; overlong paragraphs are split at sentence boundaries, then (only
 * as a last resort) at word boundaries — never mid-number/mid-URL/mid-scientific
 * name, because those are never split at whitespace.
 */
export function chunkForTranslation(text: string, maxChars = SARVAM_MAX_CHUNK_CHARS): string[] {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (normalized.length <= maxChars) return normalized ? [normalized] : [];

  const units: string[] = [];
  for (const paragraph of normalized.split(/\n{2,}/).map((p) => p.trim()).filter(Boolean)) {
    if (paragraph.length <= maxChars) {
      units.push(paragraph);
      continue;
    }
    let cur = "";
    for (const sentence of splitSentences(paragraph)) {
      if (sentence.length > maxChars) {
        if (cur) { units.push(cur); cur = ""; }
        let wcur = "";
        for (const w of sentence.split(/\s+/)) {
          const cand = wcur ? `${wcur} ${w}` : w;
          if (cand.length > maxChars) { units.push(wcur); wcur = w; } else wcur = cand;
        }
        if (wcur) units.push(wcur);
        continue;
      }
      const cand = cur ? `${cur} ${sentence}` : sentence;
      if (cand.length > maxChars) { units.push(cur); cur = sentence; } else cur = cand;
    }
    if (cur) units.push(cur);
  }

  const chunks: string[] = [];
  let chunk = "";
  for (const unit of units) {
    const cand = chunk ? `${chunk}\n\n${unit}` : unit;
    if (cand.length > maxChars) { if (chunk) chunks.push(chunk); chunk = unit; } else chunk = cand;
  }
  if (chunk) chunks.push(chunk);
  return chunks;
}

type SingleResult =
  | { ok: true; text: string }
  | { ok: false; reason: string; status?: number; transient: boolean };

async function sarvamRequest(input: string, timeoutMs: number): Promise<SingleResult> {
  const key = sarvamKey();
  if (!key) return { ok: false, reason: "Sarvam secret not configured", transient: false };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(SARVAM_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "api-subscription-key": key,
      },
      body: JSON.stringify({
        input,
        source_language_code: "en-IN",
        target_language_code: "bn-IN",
        model: SARVAM_MODEL,
      }),
      signal: controller.signal,
    });
    const raw = await res.text();
    if (!res.ok) {
      // 400/403/422 are treated as recoverable — the caller falls over to
      // BHASHINI. Only 429/5xx are retried once.
      const transient = res.status === 429 || res.status >= 500;
      return { ok: false, reason: `HTTP ${res.status}`, status: res.status, transient };
    }
    let json: Record<string, unknown>;
    try {
      json = JSON.parse(raw);
    } catch (_) {
      return { ok: false, reason: "malformed JSON response", status: res.status, transient: true };
    }
    const text =
      typeof json.translated_text === "string" ? json.translated_text :
      typeof json.translatedText === "string" ? json.translatedText : "";
    if (!text.trim()) {
      return { ok: false, reason: "missing/empty translated_text", status: res.status, transient: true };
    }
    return { ok: true, text };
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "AbortError";
    return {
      ok: false,
      reason: timedOut ? `timeout after ${timeoutMs}ms` : "network failure",
      transient: true,
    };
  } finally {
    clearTimeout(timer);
  }
}

/** Translates one chunk with a single bounded retry for transient failures. */
async function translateChunk(input: string, budgetEnd: number): Promise<SingleResult> {
  let result = await sarvamRequest(input, Math.max(5000, Math.min(SARVAM_TIMEOUT_MS, budgetEnd - Date.now())));
  if (!result.ok && result.transient && Date.now() < budgetEnd - 6000) {
    await new Promise((r) => setTimeout(r, 5000));
    result = await sarvamRequest(input, Math.max(5000, Math.min(SARVAM_TIMEOUT_MS, budgetEnd - Date.now())));
  }
  return result;
}

/**
 * Translates arbitrary-length English text to Bengali without truncation.
 * Chunks are translated independently and reassembled in the original order.
 */
export async function translateSarvam(
  text: string,
  budgetMs = 60000,
): Promise<ProviderResult> {
  const started = Date.now();
  const budgetEnd = started + budgetMs;
  if (!sarvamKey()) {
    return { ok: false, failure: { reason: "Sarvam secret not configured", ms: 0 } };
  }

  const chunks = chunkForTranslation(text);
  const outputs: string[] = [];
  for (let i = 0; i < chunks.length; i++) {
    if (Date.now() >= budgetEnd - 5000) {
      return { ok: false, failure: { reason: `time budget exhausted at chunk ${i + 1}/${chunks.length}`, ms: Date.now() - started } };
    }
    const r = await translateChunk(chunks[i], budgetEnd);
    if (!r.ok) {
      return { ok: false, failure: { reason: `chunk ${i + 1}/${chunks.length}: ${r.reason}`, status: r.status, ms: Date.now() - started } };
    }
    outputs.push(r.text);
  }

  return { ok: true, text: outputs.join("\n\n"), ms: Date.now() - started };
}
