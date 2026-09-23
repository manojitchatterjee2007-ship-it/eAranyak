import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

type EditorialResult = {
  success: boolean;
  headline: string | null;
  dek: string | null;
  body: string | null;
  sourceTitle: string | null;
  sourceUrl: string | null;
  cached?: boolean;
  provider?: string;
  englishSummary?: string | null;
  error?: string;
  logs?: string[];
};

const MIN_SOURCE_WORDS = 100;
const MAX_GROQ_SUMMARY_WORDS = 150;
const HARD_MAX_GROQ_SUMMARY_WORDS = 170;
const MIN_BODY_BENGALI_WORDS = 30;
const BENGALI_CHAR = /[\u0980-\u09FF]/;
const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions";
const GROQ_MODEL = "openai/gpt-oss-20b";
const GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODEL = "gemini-3.1-flash-lite";

const CATEGORY_PREFIX_RE =
  /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্তি|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;

const JUNK_LINE_PATTERNS: RegExp[] = [
  /subscribe (to|for)\s/i,
  /sign up for our newsletter/i,
  /share this (article|story|post)/i,
  /follow us on/i,
  /related (article|stor|post)/i,
  /read (more|also)[:\s]/i,
  /advertisement/i,
  /cookie(s)? (policy|notice|consent)/i,
  /this website uses cookies/i,
  /all rights reserved/i,
  /^\s*(tags?|categories?)\s*:/i,
  /click here/i,
  /leave a (comment|reply)/i,
  /^\s*(by|written by)\s+[A-Z][a-zA-Z.\- ]{1,40}\s*$/,
];

function clean(text: string): string {
  return text.normalize("NFC")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .trim();
}

function countWords(text: string): number {
  if (!text) return 0;
  return text
    .replace(/<[^>]*>/g, " ")
    .replace(/[।.,\/#!$%\^&\*;:{}=\-_`~()?”?\"'’“”\[\]]/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
}

function sanitizeHeadline(text: string): string {
  let value = clean(text)
    .replace(/^\s*\**(?:headline|শিরোনাম)\s*:\**\s*/iu, "")
    .replace(/^\s*\*\*|\*\*\s*$/g, "")
    .trim();

  while (true) {
    const previous = value;
    value = value.replace(CATEGORY_PREFIX_RE, "").trim();
    if (value === previous) break;
  }
  return value;
}

function normalizeJournalisticBengali(text: string): string {
  return clean(text)
    .replace(/মানব[-–—]বন্যপ্রাণী\s*(?:দ্বন্দ্ব|সংঘাত)/g, "মানুষ ও বন্যপ্রাণীর সংঘাত")
    .replace(/মানব[-–—]বাঘের\s*(?:দ্বন্দ্ব|সংঘাত)/g, "মানুষ ও বাঘের সংঘাত")
    .replace(/মানব\s+নিরাপত্তা/g, "মানুষের নিরাপত্তা")
    .replace(/মানব\s+সুরক্ষা/g, "মানুষের সুরক্ষা")
    .replace(/মানব\s+স্বাস্থ্য/g, "মানুষের স্বাস্থ্য")
    .replace(/মানব\s+বসতি/g, "জনবসতি")
    .replace(/একটি বাঘের দ্বারা আক্রান্ত হন/g, "একটি বাঘের হামলার শিকার হন")
    .replace(/একটি বাঘের দ্বারা হামলার শিকার হন/g, "একটি বাঘের হামলার শিকার হন")
    .replace(/বাঘগুলি ভূখণ্ডের জন্য ছড়িয়ে পড়ে/g, "বাঘেরা নতুন এলাকা বা বিচরণক্ষেত্রের সন্ধানে ছড়িয়ে পড়ে")
    .replace(/বাঘেরা ভূখণ্ডের জন্য ছড়িয়ে পড়ে/g, "বাঘেরা নতুন এলাকা বা বিচরণক্ষেত্রের সন্ধানে ছড়িয়ে পড়ে")
    .replace(/একই ধরনের দখল ঘটে/g, "একই ধরনের বাঘ ধরার ঘটনা ঘটে")
    .replace(/সংরক্ষণাগারের বাইরে/g, "সংরক্ষিত এলাকার বাইরে")
    .replace(/(?<![অ-হ])মানব(?!াধিকার|সম্পদ|দেহ|জাতি|সভ্যতা|িক)/g, "মানুষ")
    .replace(/দ্বন্দ্বকে/g, "সংঘাতকে")
    .replace(/দ্বন্দ্বের/g, "সংঘাতের")
    .replace(/দ্বন্দ্বে/g, "সংঘাতে")
    .replace(/দ্বন্দ্ব/g, "সংঘাত")
    .replace(/\s+([।,;:!?])/g, "$1")
    .trim();
}

function cleanJunk(text: string): string {
  return text.split(/\n+/).map((line) => line.trim()).filter((line) => {
    if (!line) return false;
    if (line.split(/\s+/).length < 3) return false;
    return !JUNK_LINE_PATTERNS.some((re) => re.test(line));
  }).join("\n");
}

function extractSentences(text: string): string[] {
  return text.replace(/\s+/g, " ")
    .split(/(?<=[।.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function makeDek(body: string, maxChars = 360): string {
  const sentences = extractSentences(body);
  let result = "";

  for (const sentence of sentences.slice(0, 2)) {
    const candidate = result ? `${result} ${sentence}` : sentence;
    if (candidate.length > maxChars) break;
    result = candidate;
  }

  if (result) return result;

  const compact = body.replace(/\s+/g, " ").trim();
  if (compact.length <= maxChars) return compact;

  const clipped = compact.slice(0, maxChars);
  const lastSpace = clipped.lastIndexOf(" ");
  return (lastSpace > 80 ? clipped.slice(0, lastSpace) : clipped).trim();
}

function formatBody(text: string): string {
  const cleaned = clean(text)
    .replace(/<br\s*\/?>(?=\S)/gi, "\n")
    .replace(/^\s*(?:BODY|মূল লেখা|মূল প্রতিবেদন)\s*:\s*/iu, "")
    .trim();

  const paragraphs = cleaned.split(/\n{2,}/)
    .map((p) => p.replace(/\s+/g, " ").trim())
    .filter(Boolean);

  if (paragraphs.length > 1) return paragraphs.join("\n\n");

  const sentences = extractSentences(cleaned);
  if (sentences.length <= 4) return cleaned;

  const grouped: string[] = [];
  let current: string[] = [];
  for (const sentence of sentences) {
    current.push(sentence);
    if (current.length >= 4) {
      grouped.push(current.join(" "));
      current = [];
    }
  }
  if (current.length) grouped.push(current.join(" "));
  return grouped.join("\n\n").trim();
}

function ensureTerminalPunctuation(text: string): string {
  const value = text.trim();
  if (!value) return value;
  if (/[।?!.][”"'’\)\}\]]*$/.test(value)) return value;
  return `${value}।`;
}

const PROTECTED_ACRONYMS = [
  "IUCN", "CITES", "WWF", "NTCA", "WII", "GPS", "GIS", "DNA",
  "RNA", "AI", "IPCC", "UNESCO", "UNEP", "ISRO", "MoEFCC", "BMC", "PCR",
];

function checkEnglishContamination(text: string): string | null {
  let value = text;
  value = value.replace(/\bhttps?:\/\/\S+|\bwww\.\S+|\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/gi, "");
  for (const acronym of PROTECTED_ACRONYMS) {
    value = value.replace(new RegExp(`\\b${acronym.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "g"), "");
  }

  const bengaliChars = (value.match(/[\u0980-\u09FF]/g) || []).length;
  const englishChars = (value.match(/[a-zA-Z]/g) || []).length;
  const totalLetters = bengaliChars + englishChars;
  if (totalLetters === 0) return null;

  if (englishChars > 20 && bengaliChars / totalLetters < 0.80) {
    return `Excessive ordinary English prose contamination (${Math.round((englishChars / totalLetters) * 100)}% English characters)`;
  }

  for (const paragraph of value.split(/\n{2,}/)) {
    const p = paragraph.trim();
    if (!p) continue;
    const pBengali = (p.match(/[\u0980-\u09FF]/g) || []).length;
    const pEnglish = (p.match(/[a-zA-Z]/g) || []).length;
    if (pEnglish > 20 && pEnglish > pBengali) {
      return "A paragraph contains predominantly ordinary English prose";
    }
  }
  return null;
}

function validateOutput(headline: string, dek: string, body: string) {
  const reasons: string[] = [];
  if (!headline || !BENGALI_CHAR.test(headline)) reasons.push("Headline missing or not Bengali");
  if (!dek || !BENGALI_CHAR.test(dek)) reasons.push("DEK missing or not Bengali");
  if (!body || !BENGALI_CHAR.test(body)) reasons.push("Body missing or not Bengali");

  const h = checkEnglishContamination(headline);
  const d = checkEnglishContamination(dek);
  const b = checkEnglishContamination(body);
  if (h) reasons.push(`Headline: ${h}`);
  if (d) reasons.push(`DEK: ${d}`);
  if (b) reasons.push(`Body: ${b}`);

  const bodyWords = countWords(body);
  if (bodyWords < MIN_BODY_BENGALI_WORDS) {
    reasons.push(`Body too short (${bodyWords} words; minimum ${MIN_BODY_BENGALI_WORDS})`);
  }
  if (!/[।?!.][”"'’\)\}\]]*$/.test(body.trim())) {
    reasons.push("Body does not end with complete sentence punctuation");
  }

  for (const artifact of ["ZZZPROT", "undefined", "[TRANSLATION]", "<translation>", "NaN"]) {
    if (new RegExp(artifact, "i").test(`${headline}\n${dek}\n${body}`)) {
      reasons.push(`Internal translation artifact detected: ${artifact}`);
    }
  }

  return { valid: reasons.length === 0, reasons };
}

function deriveSourceName(sourceUrl: string): string {
  try {
    return new URL(sourceUrl).hostname.replace(/^www\./i, "");
  } catch {
    return "Unknown source";
  }
}

function makeSourceSnippet(text: string, maxChars = 220): string {
  const value = clean(text).replace(/\s+/g, " ").trim();
  if (!value) return "Preview article";
  if (value.length <= maxChars) return value;
  const clipped = value.slice(0, maxChars);
  const lastSpace = clipped.lastIndexOf(" ");
  return `${(lastSpace > 80 ? clipped.slice(0, lastSpace) : clipped).trim()}…`;
}

async function ensureParentNewsRecord(
  supabase: ReturnType<typeof createClient>,
  sourceUrl: string,
  sourceTitle: string,
  articleText: string,
): Promise<{ id: string | null; created: boolean }> {
  const existing = await supabase
    .from("wildlife_news")
    .select("id, source_url")
    .eq("source_url", sourceUrl)
    .maybeSingle();

  if (existing.error) throw new Error(`Parent article lookup failed: ${existing.error.message}`);
  if (existing.data) return { id: String(existing.data.id), created: false };

  const sourceName = deriveSourceName(sourceUrl);
  const parent = {
    title: sourceTitle || sourceUrl,
    source: sourceName,
    date_str: new Date().toISOString(),
    snippet: makeSourceSnippet(articleText),
    content: articleText,
    source_url: sourceUrl,
    original_article_url: sourceUrl,
    source_title: sourceTitle || sourceUrl,
    source_name: sourceName,
    publication_source: "editorial",
    is_published: false,
    created_by_editor: true,
  };

  const inserted = await supabase
    .from("wildlife_news")
    .insert(parent)
    .select("id, source_url")
    .single();

  if (!inserted.error && inserted.data) {
    return { id: String(inserted.data.id), created: true };
  }

  const recovered = await supabase
    .from("wildlife_news")
    .select("id, source_url")
    .eq("source_url", sourceUrl)
    .maybeSingle();

  if (!recovered.error && recovered.data) {
    return { id: String(recovered.data.id), created: false };
  }

  throw new Error(`Parent article creation failed: ${inserted.error?.message ?? "unknown database error"}`);
}

function authorized(req: Request): boolean {
  const expected = Deno.env.get("NEWS_REFRESH_SECRET");
  const supplied = req.headers.get("x-news-refresh-secret") ?? "";
  if (expected && supplied && supplied === expected) return true;

  const auth = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(auth);
  if (!match) return false;

  try {
    const raw = match[1].trim().split(".")[1]
      .replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(raw + "=".repeat((4 - (raw.length % 4)) % 4)));
    const projectRef = new URL(Deno.env.get("SUPABASE_URL") ?? "http://invalid.invalid").hostname.split(".")[0];
    return String(payload?.ref ?? "") === projectRef || String(payload?.iss ?? "").includes(projectRef);
  } catch {
    return false;
  }
}

function sentenceTrimToMaxWords(text: string, maxWords: number): string {
  const normalized = clean(text).replace(/\s+/g, " ").trim();
  const words = normalized.split(/\s+/).filter(Boolean);
  if (words.length <= maxWords) return normalized;

  const clipped = words.slice(0, maxWords).join(" ");
  const matches = [...clipped.matchAll(/[^.!?।]+[.!?।]+/g)];
  if (matches.length) {
    const last = matches[matches.length - 1][0].trim();
    if (countWords(last) >= 40) {
      const candidate = clipped.slice(0, (matches[matches.length - 1].index ?? clipped.length) + last.length).trim();
      if (countWords(candidate) <= maxWords) return candidate;
    }
  }

  return clipped.replace(/[,;:—–-]+\s*$/, "").trim() + "…";
}

function firstSentence(text: string): string {
  const sentence = extractSentences(text)[0] ?? text;
  return sentence.trim();
}

async function groqCompress(sourceText: string): Promise<{ summary: string; model: string }> {
  const key = Deno.env.get("GROQ_API_KEY") ?? "";
  if (!key) throw new Error("GROQ_API_KEY is not configured.");

  const system = `You are the eআরণ্যক editorial compression engine.

Rewrite the supplied English news article into a concise, factual English editorial summary for later Bengali translation.

STRICT RULES:
- Target about ${MAX_GROQ_SUMMARY_WORDS} words or fewer.
- NEVER exceed ${HARD_MAX_GROQ_SUMMARY_WORDS} words.
- Preserve important facts, numbers, dates, names, places, organizations, species, scientific facts, causal relationships and important quoted claims.
- Do not invent, infer, update, correct, or add facts.
- Do not change numerical values.
- Remove repetition, navigation text, advertisements, SEO material, tag lists and photo-caption clutter.
- Do not add analysis or opinions absent from the source.
- Use clear neutral news English suitable for translation into Indian Bengali.
- Output ONLY the summary text.
- Do NOT output JSON, XML, Markdown, bullet points, a heading, or the words “Summary:” or “Headline:”.`;

  const user = `SOURCE ARTICLE:\n${sourceText}`;

  async function request(extraInstruction = ""): Promise<string> {
    const response = await fetch(GROQ_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        temperature: 0.1,
        max_completion_tokens: 2048,
        reasoning_effort: "low",
        include_reasoning: false,
        messages: [
          { role: "system", content: system + extraInstruction },
          { role: "user", content: user },
        ],
      }),
    });

    const raw = await response.text();
    if (!response.ok) throw new Error(`Groq HTTP ${response.status}: ${raw.slice(0, 500)}`);

    let outer: any;
    try { outer = JSON.parse(raw); } catch { throw new Error("Groq returned an invalid API response."); }

    const content = outer?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) throw new Error("Groq returned an empty summary.");
    return clean(content.replace(/^```(?:text|markdown)?\s*/i, "").replace(/\s*```$/i, "").trim());
  }

  const sourceWords = countWords(sourceText);
  let summary = await request();
  let words = countWords(summary);

  // GPT-OSS can spend completion budget on reasoning. If a long source
  // produces an implausibly short or unfinished summary, retry once with
  // an explicit completeness instruction.
  if (sourceWords > 700 && (words < 100 || !/[.!?]$/.test(summary.trim()))) {
    summary = await request(`\n\nCOMPLETENESS CHECK: The source article is ${sourceWords} words. Your previous response was incomplete or too short. Rewrite it as a COMPLETE factual summary of approximately 140-${MAX_GROQ_SUMMARY_WORDS} words. It MUST end at a complete sentence. Preserve the important facts, numbers, dates, names, places and causal relationships. Output ONLY the summary text.`);
    words = countWords(summary);
  }

  if (words > HARD_MAX_GROQ_SUMMARY_WORDS) {
    summary = await request(`\n\nFINAL LENGTH CHECK: Your previous response was too long. The next response MUST be no more than ${MAX_GROQ_SUMMARY_WORDS} words. Output only the rewritten summary text.`);
    words = countWords(summary);
  }

  if (words > HARD_MAX_GROQ_SUMMARY_WORDS) {
    summary = sentenceTrimToMaxWords(summary, HARD_MAX_GROQ_SUMMARY_WORDS);
    words = countWords(summary);
  }

  if (sourceWords > 700 && (words < 100 || !/[.!?]$/.test(summary.trim()))) {
    throw new Error(`Groq summary appears incomplete (${words} words for a ${sourceWords}-word source).`);
  }
  if (words < 70) throw new Error(`Groq summary is unexpectedly short (${words} words).`);
  if (/^[\s\S]*[\u0980-\u09FF]/.test(summary)) throw new Error("Groq returned Bengali text; expected English editorial source.");

  return { summary, model: GROQ_MODEL };
}

async function translateWithGemini(
  headline: string,
  dek: string,
  body: string,
): Promise<{ headline: string; dek: string; body: string }> {
  const key = Deno.env.get("GEMINI_API_KEY") ?? "";
  if (!key) throw new Error("GEMINI_API_KEY is not configured.");

  const endpoint = `${GEMINI_ENDPOINT}/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(key)}`;

  const system = `You are the Bengali translation engine for the eআরণ্যক wildlife and nature news platform.

Translate the supplied English news package into natural, contemporary Indian Bengali (চলিত বাংলা).

IMPORTANT:
- Translate faithfully; do not summarize, expand, interpret, or invent facts.
- Preserve every factual detail, number, date, place, organization, species name, scientific name, measurement, quotation, and causal relationship.
- Keep internationally recognized scientific names, acronyms, technical identifiers, URLs, and proper nouns where appropriate.
- Do not produce a literal machine-translation style. Write fluent, readable Bengali journalism.
- Do not add a heading such as "অনুবাদ", "শিরোনাম", "ডেক", or commentary.
- Do not mention AI, Gemini, translation, or these instructions.
- The body is already an editorially compressed English source. Translate the complete supplied body; do not compress it further.
- Return ONLY valid JSON with exactly these three string fields:
  {"headline":"...","dek":"...","body":"..."}
- Do not wrap the JSON in Markdown fences.`;

  const user = `ENGLISH HEADLINE:
${headline}

ENGLISH DEK:
${dek}

ENGLISH BODY:
${body}`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: `${system}\n\n${user}` }],
        },
      ],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
      },
    }),
  });

  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`Gemini HTTP ${response.status}: ${raw.slice(0, 700)}`);
  }

  let outer: any;
  try {
    outer = JSON.parse(raw);
  } catch {
    throw new Error("Gemini returned an invalid API response.");
  }

  const content = outer?.candidates?.[0]?.content?.parts
    ?.map((part: any) => typeof part?.text === "string" ? part.text : "")
    .join("")
    .trim();

  if (!content) throw new Error("Gemini returned an empty translation.");

  let translated: any;
  try {
    translated = JSON.parse(content);
  } catch {
    const cleaned = content
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/i, "")
      .trim();
    try {
      translated = JSON.parse(cleaned);
    } catch {
      throw new Error("Gemini returned translation that was not valid JSON.");
    }
  }

  const translatedHeadline =
    typeof translated?.headline === "string" ? clean(translated.headline) : "";
  const translatedDek =
    typeof translated?.dek === "string" ? clean(translated.dek) : "";
  const translatedBody =
    typeof translated?.body === "string" ? clean(translated.body) : "";

  if (!translatedHeadline || !translatedDek || !translatedBody) {
    throw new Error("Gemini translation was missing headline, dek, or body.");
  }

  return {
    headline: sanitizeHeadline(normalizeJournalisticBengali(translatedHeadline)),
    dek: normalizeJournalisticBengali(translatedDek),
    body: ensureTerminalPunctuation(
      formatBody(normalizeJournalisticBengali(translatedBody)),
    ),
  };
}

async function getFinalTranslation(
  groq: { headline: string; dek: string; summary: string },
  logs: string[],
): Promise<{ headline: string; dek: string; body: string; provider: string }> {
  // PRIMARY AND ONLY TRANSLATOR: Gemini 3.1 Flash-Lite.
  // This is the same free-tier translation model used by the tutorial pipeline.
  // There is deliberately NO paid fallback and NO secondary translator.
  try {
    const gemini = finalizeTranslation(
      await translateWithGemini(
        groq.headline,
        groq.dek,
        groq.summary,
      ),
    );

    const validation = validateOutput(
      gemini.headline,
      gemini.dek,
      gemini.body,
    );

    if (validation.valid) {
      logs.push(`MT Gemini ${GEMINI_MODEL}: OK; final Bengali generated from Groq English source.`);
      return {
        ...gemini,
        provider: `Gemini ${GEMINI_MODEL}`,
      };
    }

    logs.push(
      `MT Gemini ${GEMINI_MODEL}: FAILED validation (${validation.reasons.join("; ")})`,
    );
    throw new Error(validation.reasons.join("; "));
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    logs.push(`MT Gemini ${GEMINI_MODEL}: FAILED (${reason})`);
    throw new Error(
      `Bengali translation failed using the free Gemini translator. No paid or alternate translator was used. ${reason}`,
    );
  }
}

function finalizeTranslation(
  pkg: { headline: string; dek: string; body: string },
): { headline: string; dek: string; body: string } {
  let headline = sanitizeHeadline(normalizeJournalisticBengali(pkg.headline));
  let dek = normalizeJournalisticBengali(pkg.dek);
  let body = ensureTerminalPunctuation(formatBody(normalizeJournalisticBengali(pkg.body)));

  if (!BENGALI_CHAR.test(headline)) {
    const fallback = extractSentences(body).find((s) => BENGALI_CHAR.test(s)) ?? "";
    headline = sanitizeHeadline(fallback);
  }

  if (!BENGALI_CHAR.test(dek)) dek = makeDek(body);

  return { headline, dek, body };
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
    const payload = await req.json();
    const sourceTitle = typeof payload?.sourceTitle === "string" ? payload.sourceTitle.trim() : "";
    const sourceUrl = typeof payload?.sourceUrl === "string" ? payload.sourceUrl.trim() : "";
    const articleText = typeof payload?.articleText === "string" ? payload.articleText.trim() : "";
    const force = Boolean(payload?.force);

    if (!sourceUrl || !articleText) throw new Error("sourceUrl and articleText are required.");

    const sourceWords = countWords(articleText);
    if (sourceWords < MIN_SOURCE_WORDS) {
      return new Response(JSON.stringify({
        success: false,
        error: `Source article is too short. Minimum ${MIN_SOURCE_WORDS} words required.`,
      }), { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) throw new Error("Supabase configuration is missing.");
    const supabase = createClient(supabaseUrl, serviceKey);

    if (!force) {
      const { data: existing } = await supabase
        .from("wildlife_news_translations")
        .select("source_url, headline, dek, body")
        .eq("source_url", sourceUrl)
        .maybeSingle();

      if (existing?.headline && existing?.body) {
        return new Response(JSON.stringify({
          success: true,
          cached: true,
          headline: existing.headline,
          dek: existing.dek,
          body: existing.body,
          sourceTitle,
          sourceUrl,
        } satisfies EditorialResult), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
        });
      }
    }

    const logs: string[] = [];
    const cleanedSource = cleanJunk(clean(articleText));
    const cleanedTitle = clean(sourceTitle);
    if (!cleanedSource) throw new Error("Source article became empty after cleanup.");

    // -------------------------------------------------------------------
    // 1. ENGLISH EDITORIAL SOURCE
    //    Articles already within the hard limit are passed through unchanged.
    //    Longer articles are compressed by Groq to a target of approximately 150 words.
    // -------------------------------------------------------------------
    let groq: { headline: string; dek: string; summary: string; model: string };
    const cleanedSourceWords = countWords(cleanedSource);

    if (cleanedSourceWords <= HARD_MAX_GROQ_SUMMARY_WORDS) {
      groq = {
        headline: cleanedTitle || firstSentence(cleanedSource),
        dek: firstSentence(cleanedSource),
        summary: cleanedSource,
        model: "not-used-source-under-170",
      };
      logs.push(`GROQ skipped: source already ${cleanedSourceWords} words (<=${HARD_MAX_GROQ_SUMMARY_WORDS})`);
    } else {
      const compressed = await groqCompress(cleanedSource);
      groq = {
        headline: cleanedTitle || firstSentence(compressed.summary),
        dek: firstSentence(compressed.summary),
        summary: compressed.summary,
        model: compressed.model,
      };
      logs.push(`GROQ ${compressed.model}: OK (${countWords(compressed.summary)} words; target ~${MAX_GROQ_SUMMARY_WORDS}, hard max ${HARD_MAX_GROQ_SUMMARY_WORDS})`);
    }

    // -------------------------------------------------------------------
    // 2. BENGALI TRANSLATION
    //    Gemini 3.1 Flash-Lite is the same long-term free-tier translator
    //    used by the tutorial pipeline.
    //    There is deliberately no paid or alternate fallback.
    // -------------------------------------------------------------------
    const finalTranslation = await getFinalTranslation(
      {
        headline: groq.headline,
        dek: groq.dek,
        summary: groq.summary,
      },
      logs,
    );

    const headline = finalTranslation.headline;
    const dek = finalTranslation.dek;
    const body = finalTranslation.body;

    const validation = validateOutput(headline, dek, body);
    if (!validation.valid) {
      return new Response(JSON.stringify({
        success: false,
        headline: null,
        dek: null,
        body: null,
        sourceTitle,
        sourceUrl,
        englishSummary: groq.summary,
        error: `Final Bengali translation/validation failed: [${validation.reasons.join("; ")}] Logs: ${logs.join(" | ")}`,
      } satisfies EditorialResult), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
      });
    }

    const parent = await ensureParentNewsRecord(supabase, sourceUrl, sourceTitle, articleText);
    logs.push(parent.created ? "Parent wildlife_news record created." : "Parent wildlife_news record found.");

    const { error: upsertError } = await supabase
      .from("wildlife_news_translations")
      .upsert({ source_url: sourceUrl, headline, dek, body }, { onConflict: "source_url" });

    if (upsertError) throw new Error(`Database upsert failed: ${upsertError.message}`);

    return new Response(JSON.stringify({
      success: true,
      cached: false,
      headline,
      dek,
      body,
      sourceTitle,
      sourceUrl,
      englishSummary: groq.summary,
      provider: `Groq -> ${finalTranslation.provider}`,
      logs,
    } satisfies EditorialResult), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
    });
  }
});
