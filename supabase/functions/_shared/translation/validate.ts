/**
 * eআরণ্যক — shared server-side Bengali translation validation.
 *
 * Reuses the same editorial standards as bengali-news-editor:
 * Bengali-character presence, scaffolding/metadata rejection, English
 * contamination check, factual-preservation checks (numbers, scientific
 * names, acronyms, URLs) and garbage/error-output rejection.
 *
 * SECURITY: never logs or returns secrets; only structural findings.
 */

export const BENGALI_CHAR = /[\u0980-\u09FF]/;

/** Matches a Bengali headline category prefix such as "পরিবেশ:" */
export const CATEGORY_PREFIX_RE =
  /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্ত|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;

export function countWords(text: string): number {
  if (!text) return 0;
  return text
    .replace(/<[^>]*>/g, " ")
    .replace(/[।.,/#!$%^&*;:{}=\-_`~()?"'’“”–—]/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
}

export function bengaliRatio(text: string): number {
  const b = (text.match(/[\u0980-\u09FF]/g) || []).length;
  const e = (text.match(/[a-zA-Z]/g) || []).length;
  const total = b + e;
  return total > 0 ? b / total : 0;
}

/** Sanitizes an MT headline the same way the editorial pipeline does. */
export function sanitizeBengaliHeadline(headline: string): string {
  if (!headline) return "";
  let clean = headline.trim().replace(/^[\s\u00a0]*\*\*|\*\*\s*$/g, "").trim();
  for (;;) {
    const prev = clean;
    clean = clean.replace(CATEGORY_PREFIX_RE, "").trim();
    if (clean === prev) break;
  }
  // Strip wrapping quotes / markdown bold that MT sometimes adds.
  return clean.replace(/^["'“”‘’]+|["'“”‘’]+$/g, "").replace(/^\*\*|\*\*$/g, "").trim();
}

/** Extracts Latin binomial/trinomial names from parenthesized context only. */
export function extractScientificNames(source: string): string[] {
  const names = new Set<string>();
  const paren = /\(([\s\S]{3,80}?)\)/g;
  let m: RegExpExecArray | null;
  while ((m = paren.exec(source)) !== null) {
    const inner = m[1].trim();
    if (/^[A-Z][a-zA-Z-]+(\s+[a-z][a-z-]+){1,2}$/.test(inner) && !/^(?:The|This|That|And|For|But|With|From|Photo|Image|Credit)\b/i.test(inner)) {
      names.add(inner);
    }
  }
  return [...names];
}

export type TranslationValidationInput = {
  provider: string;
  /** Bengali translated headline/title (may be empty if not translated). */
  headline?: string;
  /** Bengali translated body text (required). */
  body: string;
  /** Original English article text. */
  sourceText: string;
  /** Original English title. */
  sourceTitle?: string;
};

function normalizeNumberToken(n: string): string {
  return n.replace(/[,\s]/g, "");
}

export type TranslationValidationResult = {
  valid: boolean;
  reasons: string[];
  headline: string;
  body: string;
};

/**
 * Full validation gate for a machine-translated Bengali article.
 * The caller must treat `valid === false` as a provider failure and fall over
 * to the next provider.
 */
export function validateBengaliTranslation(
  input: TranslationValidationInput,
): TranslationValidationResult {
  const reasons: string[] = [];
  const headline = sanitizeBengaliHeadline((input.headline ?? "").trim());
  const body = input.body.replace(/\r\n/g, "\n").trim();

  // 1-2. Non-empty output.
  if (!body) reasons.push("empty body");
  if (input.sourceTitle && input.headline !== undefined && !headline) {
    reasons.push("empty headline");
  }

  if (body) {
    // 3. Not suspiciously short relative to the source.
    const srcWords = countWords(input.sourceText);
    const outWords = countWords(body);
    const minWords = Math.max(40, Math.floor(srcWords * 0.2));
    if (outWords < minWords) {
      reasons.push(`suspiciously short (${outWords} words vs source ${srcWords}; min ${minWords})`);
    }

    // Bengali presence + 8. no obvious English-only output.
    if (!BENGALI_CHAR.test(body)) reasons.push("no Bengali characters in body");
    const ratio = bengaliRatio(body);
    if (ratio < 0.55) {
      reasons.push(`excessive English contamination (${Math.round((1 - ratio) * 100)}% Latin characters)`);
    }

    // 5. Important numbers preserved (>= 60% of distinct numeric tokens).
    const srcNumbers = new Set(
      (input.sourceText.match(/\d[\d,.]*/g) || []).map(normalizeNumberToken).filter((n) => n.length >= 2),
    );
    if (srcNumbers.size > 0) {
      const outNumbers = new Set(
        (body.match(/\d[\d,.]*/g) || []).map(normalizeNumberToken),
      );
      let preserved = 0;
      for (const n of srcNumbers) if (outNumbers.has(n)) preserved++;
      if (preserved / srcNumbers.size < 0.6) {
        reasons.push(`numbers lost (${preserved}/${srcNumbers.size} preserved)`);
      }
    }

    // 4. Scientific names preserved.
    const sciNames = extractScientificNames(input.sourceText);
    for (const name of sciNames.slice(0, 8)) {
      if (!body.includes(name)) reasons.push(`scientific name lost: ${name}`);
    }

    // 6. URLs not corrupted (first source URL must survive).
    const srcUrl = (input.sourceText.match(/https?:\/\/[^\s"'<>]+/g) || [])[0];
    if (srcUrl && !body.includes(srcUrl)) reasons.push("URL lost or corrupted");

    // Acronyms (IUCN, NTCA, WWF...) mostly preserved.
    const acronyms = new Set((input.sourceText.match(/\b[A-Z]{3,6}\b/g) || []));
    if (acronyms.size > 0) {
      let preserved = 0;
      for (const a of acronyms) if (body.includes(a)) preserved++;
      if (preserved / acronyms.size < 0.5) reasons.push("acronyms lost (possible mistranslation)");
    }

    // 7. No API error JSON accidentally stored as content.
    if (/^\s*\{/.test(body) || body.includes('"translated_text"') || body.includes('"pipelineResponse"')) {
      reasons.push("provider JSON leaked into output");
    }

    // 10-11. Prompt leakage / failure text / provider metadata.
    if (/\b(sarvam|bhashini|dhruva|pollinations|openrouter)\b/i.test(body)) {
      reasons.push("provider metadata leaked into output");
    }
    if (/(translation failed|translation unavailable|api key|unauthorized|forbidden|rate limit)/i.test(body)) {
      reasons.push("error text leaked into output");
    }
    if (/অনুবাদ (ব্যর্থ|করা হয়নি)/.test(body)) {
      reasons.push("failure text leaked into output");
    }

    // 12. Markdown/code garbage not produced by MT.
    if (/```|<think|<\/think>/.test(body)) {
      reasons.push("markdown/code or reasoning artifacts in output");
    }
    if (/^(?:HEADLINE|DEK|BODY)\s*:/im.test(body)) {
      reasons.push("editorial scaffolding leaked into output");
    }
  }

  // Headline sanity (only when a headline was requested/translated).
  if (headline && !BENGALI_CHAR.test(headline)) {
    reasons.push("headline contains no Bengali characters");
  }

  return { valid: reasons.length === 0, reasons, headline, body };
}


/**
 * Counts ordinary residual English runs after protected/scientific material is ignored.
 * This is intentionally a lightweight final leakage signal; the editorial LLM remains
 * responsible for contextual polishing.
 */
export function countResidualEnglishRuns(text: string): number {
  const stripped = text
    .replace(/ZZZPROT[A-Z]+ZZZ/g, " ")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/\b[A-Z]{2,8}\b/g, " ")
    .replace(/\b[A-Z][a-z-]+\s+[a-z][a-z-]+(?:\s+[a-z][a-z-]+)?\b/g, " ");
  return (stripped.match(/\b[A-Za-z][A-Za-z'’.-]{2,}(?:\s+[A-Za-z][A-Za-z'’.-]{2,})*/g) ?? []).length;
}
