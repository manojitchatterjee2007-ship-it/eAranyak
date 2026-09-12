import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

type EditorialResult = {
  success: boolean;
  headline: string | null;
  dek: string | null;
  body: string | null;
  sourceTitle: string | null;
  sourceUrl: string | null;
  cached?: boolean;
  error?: string;
};

type ValidationResult = {
  valid: boolean;
  reasons: string[];
  headline?: string;
  dek?: string;
  body?: string;
  wordCount?: number;
};

const MIN_SOURCE_WORDS = 100;

const SYSTEM_INSTRUCTIONS = `
You are the Chief Bengali Editor of eআরণ্যক (eAranyak), a premier Bengali magazine and news platform dedicated to wildlife, nature, ecology, and environmental conservation.

Transform the supplied English wildlife/environment article into a polished Bengali news report. This is NOT a literal sentence-by-sentence translation.

EDITORIAL METHOD & PHILOSOPHY:
- First, completely understand the English source article: identify WHO, WHAT, WHERE, WHEN, WHY, HOW, and WHY IT MATTERS ecologically.
- Write the Bengali report afresh in contemporary polished Cholitobhasha (চলিত ভাষা).
- Do NOT translate sentence by sentence. Do NOT preserve English sentence order.
- The report must read as if an experienced Bengali environmental journalist independently authored a concise, factual, and literate Bengali report.

HEADLINE REQUIREMENTS:
1. Write a genuine, compelling Bengali journalistic headline that conveys the core development and significance.
2. ABSOLUTELY FORBIDDEN: NEVER include any category prefix, label, or tag (such as "পরিবেশ:", "বন্যপ্রাণী:", "প্রকৃতি:", "সংরক্ষণ:", "গবেষণা:", "জলবায়ু:", "বিজ্ঞান:", "বন:", "প্রাণী:", etc.). Provide ONLY the raw headline text.
3. Exactly ONE headline choice — do NOT provide draft options, alternatives, or "or:" suggestions.

ARTICLE STRUCTURE & LENGTH:
- Target Length: Approximately 100 to 150 Bengali words in total.
- Use 2 to 3 compact Bengali paragraphs separated by blank lines (double newlines):
  * PARAGRAPH 1: Primary development — key event, subject, location, and timeframe.
  * PARAGRAPH 2: Essential context, background facts, and scientific/ecological significance.
  * PARAGRAPH 3 (optional): Consequences, researcher findings, or conservation outlook.
- Preserve factual accuracy: exact numbers, dates, locations, binomial scientific names (e.g., Panthera uncia), acronyms (IUCN, WWF, UNESCO), and research findings intact.

DESIRED LANGUAGE & TONE:
- Literate, concise, journalistic, elegant, factual, and natural.
- AVOID: textbook Bengali, bureaucratic language, literal translation, excessively Sanskritised vocabulary, sensationalism, or unnatural English syntax.
- Do NOT fabricate quotes.

BENGALI LANGUAGE AND EDITORIAL STANDARD:

All generated Bengali must use প্রমিত আধুনিক ভারতীয় বাংলা (West Bengal / Indian Bengali editorial standard).

The writing must be natural, fluent, grammatically correct, professional, readable, and suitable for Bengali readers in West Bengal and across India. It should read as original editorial writing, not literal translation.

VOCABULARY PREFERENCES:
Prefer modern Indian Bengali vocabulary where contextually appropriate:
- জল, জলের, জলাভূমি, পানীয় জল, বন দপ্তর, রাজ্য সরকার, কেন্দ্রীয় সরকার, পরিবেশ, বন্যপ্রাণী, প্রাণী, সংরক্ষণ, আবাসস্থল, জীববৈচিত্র্য

For example, prefer জল over পানি in normal editorial contexts (নদীর জল, জলাভূমি), and use পানীয় জল where "drinking water" is meant.

CRITICAL CONTEXTUAL RULE:
Do NOT perform mechanical global word substitutions. The model must choose vocabulary naturally according to context:
- পানীয় জল is appropriate for "drinking water"
- জলাভূমি is preferred for "wetland"
- নদীর জল is preferred in normal editorial writing
- Quoted source text must not be artificially altered
- Scientific terminology must remain accurate
- Proper nouns and official programme names must remain unchanged

AVOID UNNECESSARILY REGIONAL BANGLADESHI PHRASING:
Where a natural Indian Bengali equivalent exists, avoid unnecessarily using vocabulary or constructions strongly associated with Bangladesh-specific official or journalistic phrasing. This is not about treating Bangladeshi Bengali as incorrect — it is about maintaining a consistent Indian Bengali editorial voice for this application.

NATURALNESS RULE:
Context, grammar, scientific accuracy, and readability always take priority over mechanical vocabulary substitution. Do not create unnatural constructions merely to avoid a particular word.

IMPORTANT EXECUTION RULES:
- Return ONLY the final editorial output in the exact format below.
- Do NOT explain your reasoning, planning, analysis, translation method, or word-count calculation.
- Do NOT use <think> tags or any hidden/reasoning-style text.
- Start immediately with HEADLINE: and finish the BODY with a complete Bengali sentence.

OUTPUT FORMAT (STRICT):
HEADLINE:
<Bengali headline without category prefix>

DEK:
<1-sentence Bengali summary highlighting story significance>

BODY:
<2-3 compact Bengali paragraphs, total 100-150 words>
`;

const BENGALI_CHAR = /[\u0980-\u09FF]/;
const CATEGORY_PREFIX_RE = /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্ত|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;

function clean(text: string): string {
  return text
    .normalize("NFC")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .trim();
}

function countWords(text: string): number {
  if (!text) return 0;
  const cleanText = text
    .replace(/<[^>]*>/g, " ")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/[।.,\/#!$%\^&\*;:{}=\-_`~()?"'’“”-]/g, " ");
  return cleanText.trim().split(/\s+/).filter((w) => w.length > 0).length;
}

function sanitizeBengaliHeadline(headline: string): string {
  if (!headline) return "";
  let cleanStr = headline.trim().replace(/^[\s\u00a0]*\*\*|\*\*\s*$/g, "").trim();
  while (true) {
    const prev = cleanStr;
    cleanStr = cleanStr.replace(CATEGORY_PREFIX_RE, "").trim();
    if (cleanStr === prev) break;
  }
  return cleanStr;
}

function stripThinkBlocks(text: string): string {
  return text
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/<think>[\s\S]*$/i, "");
}

const SCAFFOLD_PATTERNS = [
  /^\s*(?:\(?para(?:graph)?\s*\d+\)?\s*[:.]?)/im,
  /^\s*(?:draft|option|alternative)\s*\d*\s*[:.]?/im,
  /^\s*(?:headline|dek|body)\s+(?:options?|refine|alternative|draft|polish)/im,
  /\b(let'?s\s+(?:refine|check|polish|go|write|start)|let\s+me\s+(?:check|refine|count|polish))/i,
  /\b(word\s+count|final\s+check|note\s+to\s+self|model\s+drafting)\b/i,
  /\b(headline\s+options|alternative\s+headline|or\s*:|অথবা\s*:)\b/i,
  /\b(hmm|off-tone|body\s+polish)\b/i,
  /\(\s*[~≈]?\s*\d+\s*(?:bengali\s+)?words?\s*\)/i,
  /^\s*[~≈]?\s*\d+\s*(?:bengali\s+)?words?\s*[:.]?$/im,
];

function hasScaffolding(text: string): boolean {
  if (!text) return false;
  return SCAFFOLD_PATTERNS.some((pattern) => pattern.test(text));
}

function checkEnglishContamination(text: string): string | null {
  const bengaliChars = (text.match(/[\u0980-\u09FF]/g) || []).length;
  const englishChars = (text.match(/[a-zA-Z]/g) || []).length;
  const totalLetters = bengaliChars + englishChars;

  if (totalLetters > 0 && bengaliChars / totalLetters < 0.75) {
    const engPct = Math.round((englishChars / totalLetters) * 100);
    return `Excessive English prose contamination (${engPct}% English characters)`;
  }

  const paragraphs = text.split(/\n{2,}/);
  for (let i = 0; i < paragraphs.length; i++) {
    const p = paragraphs[i].trim();
    if (!p) continue;
    const pBengali = (p.match(/[\u0980-\u09FF]/g) || []).length;
    const pEnglish = (p.match(/[a-zA-Z]/g) || []).length;
    if (pEnglish > 15 && pEnglish > pBengali) {
      return `Paragraph ${i + 1} contains predominantly English prose`;
    }
  }

  return null;
}

function checkEndingCompleteness(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed) return "Empty text";

  const lastChar = trimmed.slice(-1);
  const badTrailingChars = [",", ":", ";", "-", "—", "–", "(", "[", "{", "/", "\\", "‘", "“", "'", '"'];
  if (badTrailingChars.includes(lastChar)) {
    return `Abrupt ending with trailing character '${lastChar}'`;
  }

  const validEndingPattern = /[।?!.][”"'’\)\}\]]*$/;
  if (!validEndingPattern.test(trimmed)) {
    return "Body does not end with complete sentence terminal punctuation";
  }

  return null;
}

function section(text: string, start: string, end: string | null): string {
  const upper = text.toUpperCase();
  const s = upper.indexOf(start.toUpperCase());
  if (s < 0) return "";
  const from = s + start.length;
  const e = end ? upper.indexOf(end.toUpperCase(), from) : -1;
  return text.substring(from, e >= 0 ? e : text.length).trim();
}

function formatBengaliBody(text: string): string {
  const cleaned = text
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .replace(/^\s*\**BODY:\**\s*/i, "");

  const paragraphs = cleaned
    .split(/\n{2,}/)
    .map((p) => p.replace(/\s+/g, " ").trim())
    .filter((p) => p.length > 0);

  return paragraphs.join("\n\n").trim();
}

function formatDek(text: string): string {
  return text
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/^\s*\**DEK:\**\s*/i, "")
    .replace(/\s+/g, " ")
    .replace(/\u00a0/g, " ")
    .trim();
}

function validateEditorialOutput(
  rawText: string,
  finishReason: string | null
): ValidationResult {
  const reasons: string[] = [];

  // 1. Truncation check
  if (finishReason === "length") {
    reasons.push("Output truncated (finish_reason=length)");
  }

  // 2. Reasoning / think leakage check
  if (/<think>/i.test(rawText) || /<\/think>/i.test(rawText)) {
    reasons.push("Contains <think> or reasoning tags");
  }

  // 3. Raw text scaffolding check
  if (hasScaffolding(rawText)) {
    reasons.push("Contains drafting scaffolding or metadata commentary");
  }

  // 4. Extract required sections
  const rawHeadline = section(rawText, "HEADLINE:", "DEK:");
  const rawDek = section(rawText, "DEK:", "BODY:");
  const rawBody = section(rawText, "BODY:", null);

  if (!rawHeadline) {
    reasons.push("Missing or malformed HEADLINE section tag");
  }
  if (!rawDek) {
    reasons.push("Missing or malformed DEK section tag");
  }
  if (!rawBody) {
    reasons.push("Missing or malformed BODY section tag");
  }

  // Headline validation
  let headline = sanitizeBengaliHeadline(rawHeadline);
  headline = headline.replace(/^HEADLINE:\s*/i, "").trim();

  if (headline) {
    if (headline.includes("\n")) {
      reasons.push("Headline contains newline/multiple options");
    }
    if (/\b(?:or|option|alternative|অথবা)\b/i.test(headline)) {
      reasons.push("Headline contains alternative options or choices");
    }
    if (!BENGALI_CHAR.test(headline)) {
      reasons.push("Headline contains no Bengali text");
    }
    if (hasScaffolding(headline)) {
      reasons.push("Headline contains scaffolding or drafting commentary");
    }
    const hWords = countWords(headline);
    if (hWords < 3 || hWords > 30) {
      reasons.push(`Headline word count out of bounds (${hWords} words)`);
    }
  }

  // Dek validation
  let dek = formatDek(rawDek);
  dek = dek.replace(/^DEK:\s*/i, "").trim();
  if (dek) {
    if (!BENGALI_CHAR.test(dek)) {
      reasons.push("DEK contains no Bengali text");
    }
    if (hasScaffolding(dek)) {
      reasons.push("DEK contains scaffolding");
    }
  }

  // Body validation
  let body = formatBengaliBody(rawBody);
  body = body.replace(/^BODY:\s*/i, "").trim();

  let bodyWords = 0;
  if (body) {
    if (!BENGALI_CHAR.test(body)) {
      reasons.push("Body contains no Bengali text");
    }

    if (hasScaffolding(body)) {
      reasons.push("Body contains scaffolding or drafting commentary");
    }

    const engError = checkEnglishContamination(body);
    if (engError) {
      reasons.push(engError);
    }

    bodyWords = countWords(body);
    if (bodyWords < 85) {
      reasons.push(`Body word count too low (${bodyWords} words; minimum 85)`);
    } else if (bodyWords > 175) {
      reasons.push(`Body word count too high (${bodyWords} words; maximum 175)`);
    }

    const endingError = checkEndingCompleteness(body);
    if (endingError) {
      reasons.push(endingError);
    }
  }

  const valid = reasons.length === 0;

  return {
    valid,
    reasons,
    headline: valid ? headline : undefined,
    dek: valid ? dek : undefined,
    body: valid ? body : undefined,
    wordCount: bodyWords,
  };
}

// OpenRouter's official free router dynamically selects from the currently
// available compatible free-model pool, avoiding permanent dependence on
// a hard-coded model list.
const OPENROUTER_FREE_ROUTER = "openrouter/free";
const MAX_FREE_ROUTER_ATTEMPTS = 2;
const FREE_ROUTER_ATTEMPT_TIMEOUT_MS = 18000;

function authorized(req: Request): boolean {
  const expected = Deno.env.get("NEWS_REFRESH_SECRET");
  const got = req.headers.get("x-news-refresh-secret") ?? "";
  if (expected && got.length > 0 && got === expected) return true;

  const auth = req.headers.get("Authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) return false;
  const bearer = m[1].trim();
  try {
    const rawB64 = bearer.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(rawB64 + "=".repeat((4 - rawB64.length % 4) % 4)));
    const projectRef = new URL(Deno.env.get("SUPABASE_URL") ?? "http://invalid.invalid").hostname.split(".")[0];
    const iss = String(payload?.iss ?? "");
    return String(payload?.ref ?? "") === projectRef || iss.includes(projectRef);
  } catch (_) {
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (!authorized(req)) {
    return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const sourceTitle = typeof body?.sourceTitle === "string" ? body.sourceTitle.trim() : "";
    const sourceUrl = typeof body?.sourceUrl === "string" ? body.sourceUrl.trim() : "";
    const articleText = typeof body?.articleText === "string" ? body.articleText.trim() : "";
    const force = Boolean(body?.force);

    if (!sourceUrl || !articleText) {
      throw new Error("sourceUrl and articleText are required.");
    }

    const words = articleText.split(/\s+/).filter(Boolean);
    if (words.length < MIN_SOURCE_WORDS) {
      return new Response(JSON.stringify({
        success: false,
        error: `Source article is too short (${words.length} words; minimum ${MIN_SOURCE_WORDS}).`,
      }), {
        status: 422,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const apiKey = Deno.env.get("OPENROUTER_API_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) throw new Error("Supabase service configuration is missing.");
    if (!apiKey) throw new Error("OPENROUTER_API_KEY is not configured.");

    const supabase = createClient(supabaseUrl, serviceKey);

    if (!force) {
      const { data: existing, error: cacheError } = await supabase
        .from("wildlife_news_translations")
        .select("source_url, headline, dek, body")
        .eq("source_url", sourceUrl)
        .maybeSingle();

      if (cacheError) throw new Error(`Translation cache lookup failed: ${cacheError.message}`);

      if (existing && existing.headline && existing.body) {
        const cachedHeadline = sanitizeBengaliHeadline(String(existing.headline));
        const cachedBody = formatBengaliBody(String(existing.body));
        const cachedDek = formatDek(String(existing.dek ?? ""));

        const bodyWords = countWords(cachedBody);
        const isClean =
          BENGALI_CHAR.test(cachedHeadline) &&
          BENGALI_CHAR.test(cachedBody) &&
          bodyWords >= 85 &&
          !hasScaffolding(cachedHeadline) &&
          !hasScaffolding(cachedBody) &&
          checkEnglishContamination(cachedBody) === null &&
          checkEndingCompleteness(cachedBody) === null;

        if (isClean) {
          return new Response(JSON.stringify({
            success: true,
            cached: true,
            headline: cachedHeadline,
            dek: cachedDek || null,
            body: cachedBody,
            sourceTitle: sourceTitle || null,
            sourceUrl,
          } satisfies EditorialResult), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
          });
        }
      }
    }

    const userPrompt = `SOURCE TITLE:\n${sourceTitle || "(not available)"}\n\nSOURCE URL:\n${sourceUrl}\n\nCOMPLETE SOURCE ARTICLE:\n${articleText}`;

    const attemptLogs: string[] = [];
    let successfulEditorial: { headline: string; dek: string | null; body: string } | null = null;

    // Keep retries tightly bounded. Each request goes through OpenRouter's official
    // free router, which selects from the currently available compatible free pool.
    for (let attempt = 1; attempt <= MAX_FREE_ROUTER_ATTEMPTS; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), FREE_ROUTER_ATTEMPT_TIMEOUT_MS);

        const aiResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${apiKey}`,
            "HTTP-Referer": "https://earanyak.app",
            "X-Title": "eAranyak Bengali News Editor",
          },
          body: JSON.stringify({
            model: OPENROUTER_FREE_ROUTER,
            messages: [
              { role: "system", content: SYSTEM_INSTRUCTIONS },
              { role: "user", content: userPrompt },
            ],
            temperature: 0.2,
            max_tokens: 2200,
            stream: false,
          }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);
        const responseText = await aiResponse.text();

        if (!aiResponse.ok) {
          if (aiResponse.status === 402) {
            attemptLogs.push(`free-router attempt ${attempt}: HTTP 402 (payment/in-flight budget required)`);
          } else if (aiResponse.status === 429) {
            attemptLogs.push(`free-router attempt ${attempt}: HTTP 429 (rate limit)`);
          } else {
            attemptLogs.push(
              `free-router attempt ${attempt}: HTTP ${aiResponse.status} (${responseText.slice(0, 140)})`
            );
          }
          continue;
        }

        let aiJson: Record<string, unknown>;
        try {
          aiJson = JSON.parse(responseText);
        } catch (_) {
          attemptLogs.push(`free-router attempt ${attempt}: Invalid JSON response`);
          continue;
        }

        const routedModel =
          typeof aiJson.model === "string" && aiJson.model.trim()
            ? aiJson.model.trim()
            : OPENROUTER_FREE_ROUTER;

        const choices = aiJson.choices;
        if (!Array.isArray(choices) || choices.length === 0) {
          attemptLogs.push(`free-router attempt ${attempt} (${routedModel}): No choices returned in JSON`);
          continue;
        }

        const choice = choices[0] as Record<string, unknown>;
        const finishReason = typeof choice.finish_reason === "string" ? choice.finish_reason : null;
        const message = choice.message as Record<string, unknown> | undefined;

        let generated = typeof message?.content === "string" ? message.content : "";
        if (!generated && Array.isArray(message?.content)) {
          generated = (message?.content as unknown[])
            .map((part) => (
              typeof part === "string"
                ? part
                : ((part as Record<string, unknown>)?.text ?? "")
            ))
            .join("");
        }

        if (!generated && typeof message?.reasoning === "string" && message.reasoning.trim()) {
          const reasoningText = clean(stripThinkBlocks(message.reasoning));
          if (/HEADLINE:/i.test(reasoningText)) generated = stripThinkBlocks(reasoningText);
        }

        generated = clean(generated);
        if (!generated) {
          attemptLogs.push(
            `free-router attempt ${attempt} (${routedModel}): Empty output (finish_reason=${finishReason})`
          );
          continue;
        }

        const validation = validateEditorialOutput(generated, finishReason);
        if (validation.valid && validation.headline && validation.body) {
          successfulEditorial = {
            headline: validation.headline,
            dek: validation.dek || null,
            body: validation.body,
          };
          break;
        }

        attemptLogs.push(
          `free-router attempt ${attempt} (${routedModel}): Validation failed [${validation.reasons.join("; ")}]`
        );
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        attemptLogs.push(`free-router attempt ${attempt}: Request error (${errMsg})`);
      }
    }

    if (!successfulEditorial) {
      return new Response(JSON.stringify({
        success: false,
        headline: null,
        dek: null,
        body: null,
        sourceTitle: sourceTitle || null,
        sourceUrl: sourceUrl || null,
        error: `No free-router attempt produced valid Bengali editorial output. Tried ${attemptLogs.length} attempts: ${attemptLogs.join(" | ")}`,
      } satisfies EditorialResult), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: upsertError } = await supabase
      .from("wildlife_news_translations")
      .upsert({
        source_url: sourceUrl,
        headline: successfulEditorial.headline,
        dek: successfulEditorial.dek,
        body: successfulEditorial.body,
      }, { onConflict: "source_url" });

    // The editorial result is authoritative. Cache persistence is an optimization
    // and must never turn a successfully generated editorial into a failed request.
    // This is especially important for direct/manual editor tests where the source
    // article may not yet exist in wildlife_news and the FK therefore cannot resolve.
    const cacheWarning = upsertError
      ? `Translation cache write skipped: ${upsertError.message}`
      : undefined;

    if (upsertError) {
      console.warn(cacheWarning);
    }

    const result: EditorialResult = {
      success: true,
      cached: false,
      headline: successfulEditorial.headline,
      dek: successfulEditorial.dek,
      body: successfulEditorial.body,
      sourceTitle: sourceTitle || null,
      sourceUrl,
      ...(cacheWarning ? { error: cacheWarning } : {}),
    };

    return new Response(JSON.stringify({ ...result, success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
