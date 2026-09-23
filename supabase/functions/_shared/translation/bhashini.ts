/**
 * eআরণ্যক — BHASHINI (Dhruva) English→Bengali provider + residual-English cleaner.
 *
 * IMPORTANT:
 * Dhruva is still called only as English→Bengali. We do NOT send an already-Bengali
 * article as bn→bn. Instead, after Sarvam translates the full article, this module
 * finds residual English spans inside that Bengali output, translates only those
 * spans with Bhashini, and puts the Bengali replacements back in place.
 *
 * Secret: BHASHINI_INFERENCE_API_KEY (server-side only).
 */

import { chunkForTranslation } from "./sarvam.ts";

const BHASHINI_ENDPOINT = "https://dhruva-api.bhashini.gov.in/services/inference/pipeline";
const BHASHINI_PIPELINE_ID = "63483ddab6e5414eb27d4a2c6ff17965";
const BHASHINI_TIMEOUT_MS = 60000;
const BHASHINI_MAX_BLOCK_CHARS = 1500;

export type ProviderFailure = { reason: string; status?: number; ms: number };
export type ProviderSuccess = { ok: true; text: string; ms: number };
export type ProviderResult = ProviderSuccess | { ok: false; failure: ProviderFailure };

export type ResidualCleanupResult =
  | { ok: true; text: string; translatedSpans: number; ms: number }
  | { ok: false; text: string; translatedSpans: number; failure: ProviderFailure };

function bhashiniKey(): string {
  return Deno.env.get("BHASHINI_INFERENCE_API_KEY") ?? "";
}

type SingleResult =
  | { ok: true; outputs: string[] }
  | { ok: false; reason: string; status?: number; transient: boolean };

async function bhashiniRequest(blocks: string[], timeoutMs: number): Promise<SingleResult> {
  const key = bhashiniKey();
  if (!key) return { ok: false, reason: "Bhashini secret not configured", transient: false };

  const payload = {
    pipelineTasks: [{
      taskType: "translation",
      config: { language: { sourceLanguage: "en", targetLanguage: "bn" } },
    }],
    inputData: { input: blocks.map((source) => ({ source })) },
    pipelineRequestConfig: { pipelineId: BHASHINI_PIPELINE_ID },
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(BHASHINI_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": key,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    const raw = await res.text();
    if (!res.ok) {
      const transient = res.status === 429 || res.status >= 500;
      return { ok: false, reason: `HTTP ${res.status}`, status: res.status, transient };
    }

    let json: Record<string, unknown>;
    try {
      json = JSON.parse(raw);
    } catch (_) {
      return { ok: false, reason: "malformed JSON response", status: res.status, transient: true };
    }

    const pipelineResponse = Array.isArray(json.pipelineResponse) ? json.pipelineResponse : [];
    const outputs: string[] = [];
    for (const pr of pipelineResponse) {
      const entry = pr as Record<string, unknown>;
      if (entry.taskType !== "translation") continue;
      const output = Array.isArray(entry.output) ? entry.output : [];
      for (const o of output) {
        const target = (o as Record<string, unknown>)?.target;
        if (typeof target === "string" && target.trim()) outputs.push(target.trim());
      }
    }

    if (outputs.length !== blocks.length) {
      return {
        ok: false,
        reason: `block count mismatch (sent ${blocks.length}, received ${outputs.length})`,
        status: res.status,
        transient: true,
      };
    }
    return { ok: true, outputs };
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

async function requestWithRetry(blocks: string[], budgetEnd: number): Promise<SingleResult> {
  const timeoutMs = Math.max(5000, Math.min(BHASHINI_TIMEOUT_MS, budgetEnd - Date.now()));
  let result = await bhashiniRequest(blocks, timeoutMs);
  if (!result.ok && result.transient && Date.now() < budgetEnd - 10000) {
    await new Promise((r) => setTimeout(r, 5000));
    result = await bhashiniRequest(
      blocks,
      Math.max(5000, Math.min(BHASHINI_TIMEOUT_MS, budgetEnd - Date.now())),
    );
  }
  return result;
}

/** Full English→Bengali fallback translator. */
export async function translateBhashini(
  text: string,
  budgetMs = 60000,
): Promise<ProviderResult> {
  const started = Date.now();
  const budgetEnd = started + budgetMs;

  if (!bhashiniKey()) {
    return { ok: false, failure: { reason: "Bhashini secret not configured", ms: 0 } };
  }

  const blocks = chunkForTranslation(text, BHASHINI_MAX_BLOCK_CHARS);
  if (blocks.length === 0) {
    return { ok: false, failure: { reason: "empty input", ms: 0 } };
  }

  const result = await requestWithRetry(blocks, budgetEnd);
  if (!result.ok) {
    return {
      ok: false,
      failure: { reason: result.reason, status: result.status, ms: Date.now() - started },
    };
  }

  return { ok: true, text: result.outputs.join("\n\n"), ms: Date.now() - started };
}

/*
 * Residual-English detection deliberately ignores:
 * - protected placeholders (ZZZPROT...ZZZ)
 * - URLs/emails
 * - scientific binomials/trinomials
 * - all-caps acronyms
 * - short isolated abbreviations
 *
 * It targets ordinary English words/phrases that a Bengali MT pass left behind.
 */
const PROTECTED_TOKEN_RE = /^ZZZPROT[A-Z]+ZZZ$/;
const URL_RE = /^https?:\/\/\S+$/i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ACRONYM_RE = /^[A-Z0-9][A-Z0-9._/+&-]{1,11}$/;
const SCI_NAME_RE = /^[A-Z][a-z-]+\s+[a-z][a-z-]+(?:\s+[a-z][a-z-]+)?$/;

/** Returns ordinary English runs worth sending to Bhashini. */
export function findResidualEnglishSpans(text: string): string[] {
  const candidates = text.match(/[A-Za-z][A-Za-z'’.-]*(?:[ \t]+[A-Za-z][A-Za-z'’.-]*)*/g) ?? [];
  const seen = new Set<string>();
  const spans: string[] = [];

  for (const raw of candidates) {
    const s = raw.trim();
    if (!s || s.length < 3) continue;
    if (PROTECTED_TOKEN_RE.test(s) || URL_RE.test(s) || EMAIL_RE.test(s)) continue;
    if (ACRONYM_RE.test(s) || SCI_NAME_RE.test(s)) continue;

    const words = s.split(/\s+/);
    // Preserve a lone capitalized proper name; LLM can inspect it later.
    if (words.length === 1 && /^[A-Z][a-z]+$/.test(s)) continue;

    const key = s.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      spans.push(s);
    }
  }
  return spans;
}

/**
 * Checkpoint 2: translate only leaked ordinary English spans in Sarvam's Bengali.
 * On Bhashini failure, returns the original Sarvam text unchanged so the final LLM
 * checkpoint can still repair it.
 */
export async function translateResidualEnglishWithBhashini(
  bengaliText: string,
  budgetMs = 30000,
): Promise<ResidualCleanupResult> {
  const started = Date.now();
  const budgetEnd = started + budgetMs;
  const spans = findResidualEnglishSpans(bengaliText);

  if (spans.length === 0) {
    return { ok: true, text: bengaliText, translatedSpans: 0, ms: Date.now() - started };
  }
  if (!bhashiniKey()) {
    return {
      ok: false,
      text: bengaliText,
      translatedSpans: 0,
      failure: { reason: "Bhashini secret not configured", ms: Date.now() - started },
    };
  }

  // Each residual phrase is a separate input so replacement mapping stays deterministic.
  const batches: string[][] = [];
  let current: string[] = [];
  let chars = 0;
  for (const span of spans) {
    const cost = span.length + 1;
    if (current.length && chars + cost > BHASHINI_MAX_BLOCK_CHARS) {
      batches.push(current);
      current = [];
      chars = 0;
    }
    current.push(span);
    chars += cost;
  }
  if (current.length) batches.push(current);

  const replacements = new Map<string, string>();
  for (const batch of batches) {
    if (Date.now() >= budgetEnd - 5000) {
      return {
        ok: false,
        text: bengaliText,
        translatedSpans: replacements.size,
        failure: { reason: "time budget exhausted during residual cleanup", ms: Date.now() - started },
      };
    }
    const result = await requestWithRetry(batch, budgetEnd);
    if (!result.ok) {
      return {
        ok: false,
        text: bengaliText,
        translatedSpans: replacements.size,
        failure: { reason: result.reason, status: result.status, ms: Date.now() - started },
      };
    }
    batch.forEach((source, i) => replacements.set(source, result.outputs[i]));
  }

  let cleaned = bengaliText;
  // Longest first avoids a shorter phrase replacing part of a longer one.
  for (const source of [...replacements.keys()].sort((a, b) => b.length - a.length)) {
    const target = replacements.get(source) ?? source;
    cleaned = cleaned.split(source).join(target);
  }

  return {
    ok: true,
    text: cleaned,
    translatedSpans: replacements.size,
    ms: Date.now() - started,
  };
}
