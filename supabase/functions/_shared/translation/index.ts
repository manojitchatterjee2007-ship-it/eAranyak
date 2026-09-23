/**
 * eআরণ্যক — shared 3-checkpoint translation orchestrator.
 *
 * CHECKPOINT 1: Sarvam translates the complete English source to Bengali.
 * CHECKPOINT 2: Bhashini translates only ordinary English leakage remaining in
 *               Sarvam's Bengali output.
 * FALLBACK:     If Sarvam itself fails, Bhashini translates the complete English source.
 * VALIDATION:   Final Bengali text is checked deterministically before the caller
 *               sends it to the editorial LLM (checkpoint 3).
 */

import { translateSarvam } from "./sarvam.ts";
import {
  translateBhashini,
  translateResidualEnglishWithBhashini,
} from "./bhashini.ts";
import { validateBengaliTranslation } from "./validate.ts";

export type TranslationProvider =
  | "sarvam+bhashini-cleanup"
  | "sarvam"
  | "bhashini-fallback";

export type TranslationAttempt = {
  provider: string;
  ok: boolean;
  reason?: string;
  ms: number;
};

export type TranslationOutcome = {
  ok: boolean;
  provider: TranslationProvider | null;
  headline: string;
  body: string;
  attempts: TranslationAttempt[];
};

export type TranslateArticleInput = {
  title: string;
  articleText: string;
  budgetMs?: number;
};

function remaining(end: number, reserve = 0): number {
  return Math.max(0, end - Date.now() - reserve);
}

export async function translateArticle(
  input: TranslateArticleInput,
): Promise<TranslationOutcome> {
  const attempts: TranslationAttempt[] = [];
  const started = Date.now();
  const budgetEnd = started + (input.budgetMs ?? 90000);

  const sourceTitle = input.title.trim();
  const sourceBody = input.articleText.trim();

  if (!sourceBody) {
    return { ok: false, provider: null, headline: "", body: "", attempts: [
      { provider: "input", ok: false, reason: "empty article text", ms: 0 },
    ] };
  }

  // ---------- CHECKPOINT 1: SARVAM ----------
  const sarvamBudget = Math.max(10000, Math.min(60000, remaining(budgetEnd, 25000)));
  const sTitle = sourceTitle
    ? await translateSarvam(sourceTitle, Math.min(15000, sarvamBudget))
    : { ok: true as const, text: "", ms: 0 };

  const sBody = await translateSarvam(sourceBody, sarvamBudget);

  if (sTitle.ok && sBody.ok) {
    attempts.push({
      provider: "sarvam",
      ok: true,
      ms: sTitle.ms + sBody.ms,
    });

    let headline = sTitle.text;
    let body = sBody.text;
    let usedCleanup = false;

    // ---------- CHECKPOINT 2: BHASHINI RESIDUAL CLEANUP ----------
    const cleanupBudget = Math.min(30000, remaining(budgetEnd, 8000));
    if (cleanupBudget >= 5000) {
      const [cTitle, cBody] = await Promise.all([
        sourceTitle
          ? translateResidualEnglishWithBhashini(headline, cleanupBudget)
          : Promise.resolve({ ok: true as const, text: "", translatedSpans: 0, ms: 0 }),
        translateResidualEnglishWithBhashini(body, cleanupBudget),
      ]);

      if (cTitle.ok && cBody.ok) {
        headline = cTitle.text;
        body = cBody.text;
        usedCleanup = cTitle.translatedSpans + cBody.translatedSpans > 0;
        attempts.push({
          provider: "bhashini-residual-cleanup",
          ok: true,
          reason: `translated ${cTitle.translatedSpans + cBody.translatedSpans} residual English span(s)`,
          ms: cTitle.ms + cBody.ms,
        });
      } else {
        const reason = !cTitle.ok ? cTitle.failure.reason : !cBody.ok ? cBody.failure.reason : "unknown";
        attempts.push({
          provider: "bhashini-residual-cleanup",
          ok: false,
          reason,
          ms: (!cTitle.ok ? cTitle.failure.ms : 0) + (!cBody.ok ? cBody.failure.ms : 0),
        });
        // Deliberately keep Sarvam text. Checkpoint 3 LLM can repair remaining leakage.
      }
    }

    const validation = validateBengaliTranslation({
      provider: usedCleanup ? "sarvam+bhashini-cleanup" : "sarvam",
      headline,
      body,
      sourceText: sourceBody,
      sourceTitle,
    });

    if (validation.valid) {
      return {
        ok: true,
        provider: usedCleanup ? "sarvam+bhashini-cleanup" : "sarvam",
        headline: validation.headline,
        body: validation.body,
        attempts,
      };
    }

    attempts.push({
      provider: "validation",
      ok: false,
      reason: validation.reasons.join("; "),
      ms: 0,
    });
  } else {
    attempts.push({
      provider: "sarvam",
      ok: false,
      reason: !sTitle.ok ? sTitle.failure.reason : !sBody.ok ? sBody.failure.reason : "unknown",
      ms: (!sTitle.ok ? sTitle.failure.ms : 0) + (!sBody.ok ? sBody.failure.ms : 0),
    });
  }

  // ---------- FULL BHASHINI FALLBACK ----------
  // This remains necessary when Sarvam itself is unavailable or invalid.
  const fallbackBudget = remaining(budgetEnd, 3000);
  if (fallbackBudget >= 5000) {
    const bTitle = sourceTitle
      ? await translateBhashini(sourceTitle, Math.min(15000, fallbackBudget))
      : { ok: true as const, text: "", ms: 0 };
    const bBody = await translateBhashini(sourceBody, fallbackBudget);

    if (bTitle.ok && bBody.ok) {
      attempts.push({ provider: "bhashini-fallback", ok: true, ms: bTitle.ms + bBody.ms });

      const validation = validateBengaliTranslation({
        provider: "bhashini-fallback",
        headline: bTitle.text,
        body: bBody.text,
        sourceText: sourceBody,
        sourceTitle,
      });

      if (validation.valid) {
        return {
          ok: true,
          provider: "bhashini-fallback",
          headline: validation.headline,
          body: validation.body,
          attempts,
        };
      }

      attempts.push({
        provider: "validation",
        ok: false,
        reason: validation.reasons.join("; "),
        ms: 0,
      });
    } else {
      attempts.push({
        provider: "bhashini-fallback",
        ok: false,
        reason: !bTitle.ok ? bTitle.failure.reason : !bBody.ok ? bBody.failure.reason : "unknown",
        ms: (!bTitle.ok ? bTitle.failure.ms : 0) + (!bBody.ok ? bBody.failure.ms : 0),
      });
    }
  }

  return { ok: false, provider: null, headline: "", body: "", attempts };
}
