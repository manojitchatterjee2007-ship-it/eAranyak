import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

const MODEL = "stealth/ox-alpha";
const MIN_WORDS = 120;
const MIN_CACHED_BENGALI_WORDS = 280;

const SYSTEM_INSTRUCTIONS = `
You are the Chief Bengali Editor of eআরণ্যক, a Bengali wildlife, nature and ecology publication.

Transform the supplied English wildlife/environment article into a polished Bengali editorial excerpt.
This is NOT a literal sentence-by-sentence translation.

RULES:
1. Write a fresh, accurate Bengali headline that conveys the ESSENCE of the story the way a professional Bengali newspaper would. NEVER translate the English headline word by word; rephrase it naturally so a Bengali reader immediately understands what happened and why it matters.
2. Preserve facts, numbers, places, people, dates and scientific names accurately.
3. Preserve species names in English or use natural Bengali + English in parentheses where useful.
4. Use natural, elegant modern Bengali (Cholitobhasha), with a serious magazine/news tone.
5. Write a fuller editorial report of roughly 300–450 Bengali words. Do not compress away important evidence, statistics, locations, study findings or conservation implications.
6. Focus on who, what, where, why it matters for wildlife/nature, and the key evidence. Retain the most important quantitative findings and relevant expert observations.
7. Remove website navigation, boilerplate and non-essential quotations.
8. COMPLETELY OMIT every trace of photographs and illustrations from the writeup: no image references, no "[Image: ...]" or "[Photo: ...]" placeholders, no picture captions/legends, and no photographer or image credits (e.g. "Photo courtesy ..."). Only the actual journalistic text of the article belongs in the body.
9. Never invent facts or imply information not present in the source.
10. Do not mention AI, generation, summarisation, or these instructions.
11. The output must contain ONLY the finished editorial — nothing else. NEVER output paragraph labels such as "Para 1", word counts such as "(~65 words)" or "Total body ≈ 260 words", planning notes, draft alternatives, refinement commentary ("DEK refine:", "Body polish", "Final check"), or ANY English meta-commentary. Reason silently and internally; emit only your final answer. The BODY must consist exclusively of polished Bengali prose.
12. Every line of the BODY must be Bengali prose (English is allowed only inline for species/scientific names in parentheses).
13. The BODY must be ONE SINGLE CONTINUOUS PARAGRAPH: flowing prose with sentences joined seamlessly. Do NOT split it into multiple paragraphs, do NOT leave blank lines, and do NOT insert line breaks inside it.
14. The HEADLINE must be EXACTLY ONE line and the DEK at most two lines. NEVER offer alternatives or drafts: no "Or:", "অথবা:", "Alternative:", "Option", "Something like:", "or try:" prefixes or follow-up headline suggestions. One headline only — your single best choice.

OUTPUT EXACTLY:
HEADLINE:
<one meaningful Bengali headline>

DEK:
<1–2 sentence Bengali summary>

BODY:
<ONE single continuous paragraph of polished Bengali, approximately 300–450 Bengali words>
`;

function clean(text: string): string {
  return text
    .normalize("NFC")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .trim();
}

const BENGALI_CHAR = /[\u0980-\u09FF]/;

/// Reasoning models sometimes emit <think> blocks inside the content.
function stripThinkBlocks(text: string): string {
  return text
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/<think>[\s\S]*$/i, "");
}

/// Removes any line that carries no Bengali script. This drops AI drafting
/// scaffolding that occasionally leaks into the output, e.g. "Para 1 (~65
/// words):" labels or English word-count / planning notes, while keeping
/// normal Bengali paragraphs (English appears only inline for species names).
function stripNonBengaliLines(text: string): string {
  return text
    .split("\n")
    .filter((line) => {
      const t = line.trim();
      return t === "" || BENGALI_CHAR.test(t);
    })
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/// Some reasoning models draft *in English around* Bengali sentences, so a
/// script filter alone cannot remove leaked planning notes such as:
///   Para 1: / Para 2 (~90 words): / ~90 words.
///   DEK refine: / Body polish — make it ... / Final check on word count ...
///   I'll go with: ... / Let me count carefully: ...
///   Or: "..." / অথবা: "..." (leaked alternative headlines)
///   Something like: ... (leaked draft deks)
/// These lines often CONTAIN Bengali quotes, so drop them by pattern instead.
const SCAFFOLD_LINE_RE =
  /^\s*(?:\(?para(?:graph)?\s*\d+\)?\s*[:.]|[~≈]?\s*\d+\s*words?\s*[.:]*$|dek\s+(?:refine|alternative)|headline\s+(?:refine|alternative|options?)|or\s*:|অথবা\s*:|something\s+like|alternative\s*(?:headline|dek)?\s*\d*\s*:|body\s+polish|polish\b.*:|final\s+check\b|word\s+count\s*(?:for|check)|i'?ll\s+(?:go|use|pick|write)|let'?s\s|let me\s+(?:count|refine|polish|check)|draft\s*\d+\s*[:.]|option\s*\d+\s*[:.]|note\s+to\s+self)/im;

/// Anywhere-in-text markers that unambiguously betray drafting commentary.
const SCAFFOLD_ANYWHERE_RE = /\bhmm\b|\balternative\s*:|\brefine\b|\boff-tone\b/i;

const INLINE_WORDCOUNT_RE = /\s*\(\s*[~≈]?\s*\d+\s*(?:bengali\s+)?words?\s*[.:]?\s*\)/gi;

function hasScaffolding(text: string): boolean {
  const t = text ?? "";
  if (SCAFFOLD_LINE_RE.test(t)) return true;
  if (SCAFFOLD_ANYWHERE_RE.test(t)) return true;
  if (/^\s*(?:para(?:graph)?\s*\d+|\d+\s*words?\b)/im.test(t)) return true;
  return /\(\s*[~≈]?\s*\d+\s*words?\s*\)/i.test(t);
}

function stripScaffolding(text: string): string {
  return text
    .split("\n")
    .filter((line) => {
      const t = line.trim();
      if (t === "") return true;
      // Never drop real content lines: only drop a scaffolding-pattern line
      // when it is short-ish meta commentary (not a full paragraph).
      const isMeta =
        (SCAFFOLD_LINE_RE.test(t) || SCAFFOLD_ANYWHERE_RE.test(t)) &&
        t.length <= 220;
      return !isMeta;
    })
    .join("\n")
    .replace(INLINE_WORDCOUNT_RE, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/// True when a cached/generated body still carries visible drafting
/// scaffolding after cleaning — such an edition must not be served.
/// (Detected by hasScaffolding() above; stripScaffolding() cleans it.)

function section(text: string, start: string, end: string | null): string {
  const upper = text.toUpperCase();
  const s = upper.indexOf(start.toUpperCase());
  if (s < 0) return "";
  const from = s + start.length;
  const e = end ? upper.indexOf(end.toUpperCase(), from) : -1;
  return text.substring(from, e >= 0 ? e : text.length).trim();
}

/// Collapses a body into ONE single continuous paragraph: every line break /
/// blank line becomes a single space so the editorial reads as one flowing
/// paragraph. Guards against models that still emit multi-paragraph bodies.
function toSingleParagraph(text: string): string {
  return text
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/\s*\n+\s*/g, " ")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function authorized(req: Request): boolean {
  const expected = Deno.env.get("NEWS_REFRESH_SECRET");
  const got = req.headers.get("x-news-refresh-secret") ?? "";
  if (expected && got.length > 0 && got === expected) return true;

  // Mobile-app path: also accept a bearer token issued for THIS project
  // (the app's anon/publishable key or a signed-in user's access token).
  // Two Supabase JWT shapes exist:
  //   - API keys:      {"iss":"supabase","ref":"<project-ref>","role":"anon"}
  //   - user tokens:   {"iss":"<SUPABASE_URL>/auth/v1", ...}
  // Matching either pins the token to our project without the JWT secret.
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

    if (!sourceUrl || !articleText) {
      throw new Error("sourceUrl and articleText are required.");
    }

    const words = articleText.split(/\s+/).filter(Boolean);
    if (words.length < MIN_WORDS) {
      return new Response(JSON.stringify({
        success: false,
        error: `Source article is too short (${words.length} words; minimum ${MIN_WORDS}).`,
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

    const { data: existing, error: cacheError } = await supabase
      .from("wildlife_news_translations")
      .select("source_url, headline, dek, body")
      .eq("source_url", sourceUrl)
      .maybeSingle();

    if (cacheError) throw new Error(`Translation cache lookup failed: ${cacheError.message}`);

    const cachedBodyWords = String(existing?.body ?? "").split(/\s+/).filter(Boolean).length;
    const cachedClean =
      !!existing?.headline && !!existing?.body &&
      cachedBodyWords >= MIN_CACHED_BENGALI_WORDS &&
      !hasScaffolding(String(existing.body)) &&
      !hasScaffolding(String(existing.headline ?? ""));
    if (cachedClean) {
      return new Response(JSON.stringify({
        success: true,
        cached: true,
        headline: existing.headline,
        dek: existing.dek,
        // Normalize legacy multi-paragraph bodies into one flowing paragraph.
        body: toSingleParagraph(String(existing.body)),
        sourceTitle: sourceTitle || null,
        sourceUrl,
      } satisfies EditorialResult), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
      });
    }

    const userPrompt = `SOURCE TITLE:\n${sourceTitle || "(not available)"}\n\nSOURCE URL:\n${sourceUrl}\n\nCOMPLETE SOURCE ARTICLE:\n${articleText}`;

    const aiResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "HTTP-Referer": "https://earanyak.app",
        // NOTE: HTTP header values must be ByteStrings (Latin-1). Bengali text
        // here made Deno throw "Failed to construct 'Request': 'headers' ...
        // is not a valid ByteString" and every editorial request returned 500.
        "X-Title": "eAranyak Bengali News Editor",
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: "system", content: SYSTEM_INSTRUCTIONS },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.25,
        // Generous budget: reasoning models spend tokens thinking before they
        // emit the editorial; 3000 was exhausted before any content appeared,
        // yielding finish_reason=length and empty text.
        max_tokens: 16000,
        stream: false,
      }),
    });

    const responseText = await aiResponse.text();
    if (!aiResponse.ok) {
      throw new Error(`OpenRouter ${aiResponse.status}: ${responseText.slice(0, 1200)}`);
    }

    const aiJson = JSON.parse(responseText) as Record<string, unknown>;
    const choices = aiJson.choices;
    if (!Array.isArray(choices) || choices.length === 0) throw new Error("OpenRouter returned no choices.");

    const choice = choices[0] as Record<string, unknown>;
    const message = choice.message as Record<string, unknown> | undefined;
    let generated = typeof message?.content === "string" ? message.content : "";

    // Some reasoning models can expose structured content as an array of parts.
    if (!generated && Array.isArray(message?.content)) {
      generated = (message?.content as unknown[])
        .map((part) => typeof part === "string" ? part : ((part as Record<string, unknown>)?.text ?? ""))
        .join("");
    }

    // Reasoning models sometimes place the final prose in the `reasoning`
    // field and leave `content` empty (especially under tight token budgets).
    if (!generated && typeof message?.reasoning === "string" && message.reasoning.trim()) {
      const r = clean(stripThinkBlocks(message.reasoning));
      // Only fall back when the reasoning block itself looks like finished
      // prose containing the required section markers.
      if (/HEADLINE:/i.test(r)) generated = stripThinkBlocks(r);
    }

    generated = clean(stripThinkBlocks(generated));
    if (!generated) {
      const finish = typeof choice.finish_reason === "string" ? choice.finish_reason : "unknown";
      throw new Error(
        `OpenRouter returned empty editorial text (finish_reason=${finish}).`
      );
    }
    // Remove leaked planning notes BEFORE splitting into sections so that
    // stray commentary never lands inside HEADLINE / DEK / BODY.
    generated = stripScaffolding(generated);
    if (!generated) throw new Error("OpenRouter returned empty editorial text.");

    let headline = section(generated, "HEADLINE:", "DEK:");
    let dek = section(generated, "DEK:", "BODY:");
    let editorialBody = section(generated, "BODY:", null);

    if (!headline) {
      headline = generated.split("\n").map((x) => x.trim()).find((x) => BENGALI_CHAR.test(x)) ?? sourceTitle;
    }
    if (!editorialBody) editorialBody = generated.replace(/^HEADLINE:[\s\S]*?DEK:/i, "").trim();

    headline = stripNonBengaliLines(stripScaffolding(headline.replace(/^HEADLINE:\s*/i, "")));
    // A headline is exactly ONE line: keep only the first non-empty line so a
    // leaked alternative ("Or: ...") can never reach readers.
    headline = headline.split("\n").map((x) => x.trim()).firstWhere((x) => x.isNotEmpty, orElse: () => "");
    dek = stripNonBengaliLines(stripScaffolding(dek.replace(/^DEK:\s*/i, "")));
    editorialBody = stripNonBengaliLines(stripScaffolding(editorialBody.replace(/^BODY:\s*/i, "")));
    // The body must read as ONE long paragraph — collapse any residual line
    // breaks the model may still have emitted despite the instructions.
    editorialBody = toSingleParagraph(editorialBody);
    dek = toSingleParagraph(dek);

    if (!headline || !editorialBody) throw new Error("The AI response could not be parsed into headline/body.");
    // Never cache scaffolding / untranslated English output as an edition.
    if (!BENGALI_CHAR.test(editorialBody)) {
      throw new Error("Editorial body contained no Bengali text; refusing to cache.");
    }
    if (hasScaffolding(editorialBody) || hasScaffolding(headline)) {
      throw new Error("Editorial output still contained drafting scaffolding; refusing to cache.");
    }

    const { error: upsertError } = await supabase
      .from("wildlife_news_translations")
      .upsert({
        source_url: sourceUrl,
        headline,
        dek: dek || null,
        body: editorialBody,
      }, { onConflict: "source_url" });

    if (upsertError) throw new Error(`Translation cache write failed: ${upsertError.message}`);

    const result: EditorialResult = {
      success: true,
      cached: false,
      headline,
      dek: dek || null,
      body: editorialBody,
      sourceTitle: sourceTitle || null,
      sourceUrl,
    };

    return new Response(JSON.stringify(result), {
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
