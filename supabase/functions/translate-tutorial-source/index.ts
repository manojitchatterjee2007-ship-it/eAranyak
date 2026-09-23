import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Keep the currently configured Gemini model. A future eআরণ্যক-trained
// translator can replace this provider without changing the content-block API.
const GEMINI_MODEL = "gemini-3.1-flash-lite";
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const MAX_ARTICLE_CHARS = 120_000;
const MAX_OUTPUT_TOKENS = 60_000;
const MAX_BLOCKS = 500;
const MAX_TITLE_CHARS = 500;
const MAX_SNIPPET_CHARS = 1_500;
const MAX_DESCRIPTION_CHARS = 4_000;

type HeadingBlock = {
  type: "heading";
  level: number;
  text: string;
};

type ParagraphBlock = {
  type: "paragraph";
  text: string;
};

type ListBlock = {
  type: "list";
  ordered: boolean;
  items: string[];
};

type ImageBlock = {
  type: "image";
  url: string;
  caption: string | null;
  credit: string | null;
};

type ContentBlock =
  | HeadingBlock
  | ParagraphBlock
  | ListBlock
  | ImageBlock;

function json(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function clean(value: unknown): string {
  if (typeof value !== "string") return "";

  return value
    .normalize("NFC")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+/g, " ")
    .trim();
}

function oneLine(value: unknown): string {
  return clean(value)
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function containsBengali(text: string): boolean {
  return /[\u0980-\u09FF]/.test(text);
}

function hasProviderOrErrorLeak(text: string): boolean {
  return /(?:gemini|openrouter|api key|quota exceeded|rate limit|internal server error|provider error|translation failed|model error|json parse|invalid json)/i
    .test(text);
}

function hasEditorialScaffolding(text: string): boolean {
  return (
    /(?:^|\n)\s*(?:HEADLINE|TITLE|SNIPPET|BODY|DESCRIPTION|TRANSLATION|BENGALI TRANSLATION)\s*:/i
      .test(text) ||
    /```/.test(text)
  );
}

function removeAccidentalMarkdown(text: string): string {
  return clean(text)
    .replace(/^\s*#{1,6}\s+/gm, "")
    .replace(/\*\*(.*?)\*\*/g, "$1")
    .replace(/__(.*?)__/g, "$1")
    .trim();
}

function normaliseParagraph(text: unknown): string {
  return removeAccidentalMarkdown(textToString(text))
    // Gemini sometimes returns one sentence per line. Paragraph blocks
    // must remain essay-like, so collapse artificial line breaks.
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function normaliseHeading(text: unknown): string {
  return removeAccidentalMarkdown(textToString(text))
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function textToString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function normaliseListItem(text: unknown): string {
  return removeAccidentalMarkdown(textToString(text))
    .replace(/\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function isValidImageUrl(url: string): boolean {
  return /^https?:\/\//i.test(url);
}

function normaliseSourceBlocks(raw: unknown): ContentBlock[] {
  if (!Array.isArray(raw)) return [];

  const result: ContentBlock[] = [];

  for (const rawBlock of raw.slice(0, MAX_BLOCKS)) {
    if (!rawBlock || typeof rawBlock !== "object") continue;

    const block = rawBlock as Record<string, unknown>;
    const type = block.type;

    if (type === "image") {
      const url = clean(block.url);

      // Image blocks are deliberately never sent back to Gemini for
      // rewriting. Their URL and position are authoritative source data.
      if (!isValidImageUrl(url)) continue;

      result.push({
        type: "image",
        url,
        caption:
          block.caption == null
            ? null
            : oneLine(block.caption),
        credit:
          block.credit == null
            ? null
            : oneLine(block.credit),
      });
      continue;
    }

    if (type === "heading") {
      const text = normaliseHeading(block.text);

      if (!text) continue;

      const levelNumber = Number(block.level);
      const level =
        Number.isFinite(levelNumber)
          ? Math.min(6, Math.max(1, Math.round(levelNumber)))
          : 2;

      result.push({
        type: "heading",
        level,
        text,
      });
      continue;
    }

    if (type === "paragraph") {
      const text = normaliseParagraph(block.text);

      if (!text) continue;

      result.push({
        type: "paragraph",
        text,
      });
      continue;
    }

    if (type === "list") {
      const items = Array.isArray(block.items)
        ? block.items
            .filter((item): item is string => typeof item === "string")
            .map(normaliseListItem)
            .filter(Boolean)
        : [];

      if (items.length === 0) continue;

      result.push({
        type: "list",
        ordered: Boolean(block.ordered),
        items,
      });
    }
  }

  return result;
}

function mergeArtificialParagraphs(
  blocks: ContentBlock[],
): ContentBlock[] {
  const result: ContentBlock[] = [];

  for (const block of blocks) {
    const previous = result[result.length - 1];

    if (
      previous?.type === "paragraph" &&
      block.type === "paragraph"
    ) {
      const previousWords = previous.text
        .split(/\s+/)
        .filter(Boolean).length;
      const currentWords = block.text
        .split(/\s+/)
        .filter(Boolean).length;

      // Merge only short adjacent source fragments. Never cross a heading,
      // image or list, so the source's meaningful structure is retained.
      if (
        previousWords < 80 &&
        currentWords < 80 &&
        previous.text.length + block.text.length < 1_800
      ) {
        previous.text = `${previous.text} ${block.text}`.trim();
        continue;
      }
    }

    result.push({
      ...block,
      ...(block.type === "list"
        ? { items: [...block.items] }
        : {}),
    } as ContentBlock);
  }

  return result;
}

function blocksToPlainText(blocks: ContentBlock[]): string {
  const parts: string[] = [];

  for (const block of blocks) {
    if (
      block.type === "heading" ||
      block.type === "paragraph"
    ) {
      parts.push(block.text);
    } else if (block.type === "list") {
      parts.push(block.items.join("\n"));
    } else if (block.type === "image") {
      if (block.caption) parts.push(block.caption);
      if (block.credit) parts.push(block.credit);
    }
  }

  return clean(parts.join("\n\n"));
}

function countWords(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

function extractResponseText(data: any): string {
  const candidates = data?.candidates;

  if (!Array.isArray(candidates) || candidates.length === 0) {
    return "";
  }

  const parts = candidates[0]?.content?.parts;

  if (!Array.isArray(parts)) return "";

  return parts
    .map((part: any) =>
      typeof part?.text === "string" ? part.text : "",
    )
    .filter(Boolean)
    .join("")
    .trim();
}

function parseJsonText(text: string): any {
  const cleaned = text
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");

    if (start < 0 || end <= start) {
      throw new Error(
        "Gemini returned invalid JSON instead of tutorial content.",
      );
    }

    try {
      return JSON.parse(cleaned.slice(start, end + 1));
    } catch (_) {
      throw new Error(
        "Gemini returned malformed tutorial JSON.",
      );
    }
  }
}

function extractGeminiError(
  responseStatus: number,
  responseText: string,
): string {
  let parsed: any = null;

  try {
    parsed = JSON.parse(responseText);
  } catch (_) {
    // Use compact raw text below.
  }

  const apiMessage =
    parsed?.error?.message ??
    parsed?.message ??
    "";

  if (apiMessage) {
    return (
      `Gemini API error ${parsed?.error?.code ?? responseStatus}: ` +
      `${String(apiMessage).trim()}`
    );
  }

  const compactRaw = responseText
    .replace(/\s+/g, " ")
    .trim();

  return compactRaw
    ? `Gemini API error ${responseStatus}: ${compactRaw.slice(0, 1000)}`
    : `Gemini API request failed with HTTP ${responseStatus}.`;
}

async function isEditor(
  req: Request,
  supabase: ReturnType<typeof createClient>,
): Promise<boolean> {
  const authHeader =
    req.headers.get("Authorization") ?? "";

  const token = authHeader
    .replace(/^Bearer\s+/i, "")
    .trim();

  if (!token) return false;

  const { data, error } =
    await supabase.auth.getUser(token);

  if (error || !data.user) {
    if (error) {
      console.error(
        "Authenticated user lookup failed:",
        error.message,
      );
    }
    return false;
  }

  const { data: profile, error: profileError } =
    await supabase
      .from("profiles")
      .select("role")
      .eq("id", data.user.id)
      .maybeSingle();

  if (profileError) {
    console.error(
      "Editor role lookup failed:",
      profileError.message,
    );
    return false;
  }

  return profile?.role === "admin";
}

function buildPrompt(
  title: string,
  sourceDescription: string,
  blocks: ContentBlock[],
): string {
  /*
   * Only textual blocks are included in the model's editable payload.
   * Image blocks are represented by immutable placeholders. This makes it
   * structurally impossible for Gemini to change an image URL.
   */
  const modelBlocks = blocks.map((block, index) => {
    if (block.type === "image") {
      return {
        blockIndex: index,
        type: "image",
        url: block.url,
        caption: block.caption,
        credit: block.credit,
        immutable: true,
      };
    }

    return {
      blockIndex: index,
      ...block,
    };
  });

  return `
You are the Bengali editorial translator for eআরণ্যক, a serious Bengali publication about wildlife, nature, ecology, conservation, environmental education and nature photography.

Translate the COMPLETE supplied tutorial into natural, polished contemporary Bengali (চলিত ভাষা) for a knowledgeable Bengali reader in West Bengal/India.

THIS IS A FULL TRANSLATION, NOT A SUMMARY.

EDITORIAL STYLE
1. Translate every meaningful part faithfully.
2. Do not omit information because the source is long.
3. Do not invent facts, examples, species, places, instructions, recommendations or opinions.
4. Preserve the original sequence and meaning.
5. Write like a skilled Bengali science/nature editor, not like literal machine translation.
6. Do NOT create a new paragraph for every sentence.
7. Do NOT split one coherent idea into many tiny paragraphs.
8. Combine adjacent short paragraphs when they form one continuous idea.
9. Prefer substantial, flowing paragraphs, normally around 3–7 sentences when the source permits.
10. Keep paragraph breaks for genuine changes of subject, emphasis or section.
11. Do not create artificial line breaks inside a paragraph.
12. Keep headings as separate heading blocks.
13. Headings must be natural Bengali and must NOT contain Markdown such as # or **.
14. Keep lists as lists and preserve their order.
15. Translate image captions when they contain ordinary descriptive text.
16. Preserve image credits/attribution; never invent attribution.
17. Do not add an introduction or conclusion that is absent from the source.

FACTUAL/TECHNICAL PRESERVATION
- Preserve scientific/binomial names accurately.
- Preserve species names, place names, dates, measurements, percentages, quantities and numerical values.
- Preserve camera bodies, lenses, exposure settings and other technical identifiers accurately.
- Preserve recognized acronyms where appropriate.
- Translate ordinary English terminology naturally where a standard Bengali expression exists.
- If an English technical term is important for precision, Bengali may be followed by the English term in parentheses.
- Do not translate or alter URLs.
- Do not alter image URLs.
- Do not generate, substitute, remove or reorder images.
- Do not mention AI, Gemini, translation, this prompt, APIs or the source website in the translated article.

OUTPUT
Return ONLY valid JSON with exactly:
{
  "title": "Bengali title",
  "snippet": "one concise Bengali sentence",
  "description": "Bengali article description",
  "contentBlocks": [...]
}

contentBlocks MUST contain exactly the same number of blocks as the supplied input and exactly the same order.

For every block:
- heading: same type and same level; translate only the text.
- paragraph: same type; translate the text into one coherent Bengali paragraph.
- list: same type, same ordered value and same number/order of items; translate each item.
- image: return the image object EXACTLY unchanged, including URL, caption, credit and position.

IMAGE IMMUTABILITY IS CRITICAL.
Do not modify even one character of an image URL.
Do not change the number, order or position of image blocks.

The description field should be a Bengali description of the article, not a second summary of it. If the supplied source description is short, keep it correspondingly concise.

SOURCE TITLE:
${title}

SOURCE DESCRIPTION:
${sourceDescription || "(none)"}

SOURCE CONTENT BLOCKS:
${JSON.stringify(modelBlocks, null, 2)}
`;
}

function validateTranslatedBlocks(
  sourceBlocks: ContentBlock[],
  candidate: unknown,
): { valid: boolean; blocks: ContentBlock[]; reasons: string[] } {
  const reasons: string[] = [];

  if (!Array.isArray(candidate)) {
    return {
      valid: false,
      blocks: [],
      reasons: ["Gemini did not return contentBlocks as an array."],
    };
  }

  if (candidate.length !== sourceBlocks.length) {
    return {
      valid: false,
      blocks: [],
      reasons: [
        `Block count changed from ${sourceBlocks.length} to ${candidate.length}.`,
      ],
    };
  }

  const translated: ContentBlock[] = [];

  for (let i = 0; i < sourceBlocks.length; i++) {
    const source = sourceBlocks[i];
    const raw = candidate[i];

    if (!raw || typeof raw !== "object") {
      reasons.push(`Block ${i + 1} is invalid.`);
      continue;
    }

    const target = raw as Record<string, unknown>;

    if (target.type !== source.type) {
      reasons.push(
        `Block ${i + 1} changed type from ${source.type} to ${String(target.type)}.`,
      );
      continue;
    }

    if (source.type === "image") {
      /*
       * Image blocks are immutable source data. Gemini is not trusted to
       * translate or preserve their fields. We only require that the model
       * returned an image block at this exact position; the original source
       * block is then copied back verbatim.
       *
       * This deliberately does NOT compare URL/caption/credit because some
       * Gemini responses normalize, omit, or rewrite those fields even when
       * instructed not to. Since the source block is authoritative, accepting
       * the block type/position and restoring the original object is safer.
       */
      translated.push({ ...source });
      continue;
    }

    if (source.type === "heading") {
      const text = normaliseHeading(target.text);

      if (!text || !containsBengali(text)) {
        reasons.push(
          `Heading block ${i + 1} is not valid Bengali.`,
        );
        continue;
      }

      const level = Number(target.level);

      if (
        !Number.isFinite(level) ||
        Math.round(level) !== source.level
      ) {
        reasons.push(
          `Heading level changed at block ${i + 1}.`,
        );
        continue;
      }

      if (
        hasProviderOrErrorLeak(text) ||
        hasEditorialScaffolding(text)
      ) {
        reasons.push(
          `Editorial/provider scaffolding detected in heading ${i + 1}.`,
        );
        continue;
      }

      translated.push({
        type: "heading",
        level: source.level,
        text,
      });
      continue;
    }

    if (source.type === "paragraph") {
      const text = normaliseParagraph(target.text);

      if (!text || !containsBengali(text)) {
        reasons.push(
          `Paragraph block ${i + 1} is not valid Bengali.`,
        );
        continue;
      }

      if (
        hasProviderOrErrorLeak(text) ||
        hasEditorialScaffolding(text)
      ) {
        reasons.push(
          `Editorial/provider scaffolding detected in paragraph ${i + 1}.`,
        );
        continue;
      }

      translated.push({
        type: "paragraph",
        text,
      });
      continue;
    }

    if (source.type === "list") {
      const items = Array.isArray(target.items)
        ? target.items
            .filter((item): item is string => typeof item === "string")
            .map(normaliseListItem)
            .filter(Boolean)
        : [];

      if (
        Boolean(target.ordered) !== source.ordered ||
        items.length !== source.items.length ||
        items.some((item) => !containsBengali(item)) ||
        items.some(
          (item) =>
            hasProviderOrErrorLeak(item) ||
            hasEditorialScaffolding(item),
        )
      ) {
        reasons.push(
          `List block ${i + 1} failed structural/Bengali validation.`,
        );
        continue;
      }

      translated.push({
        type: "list",
        ordered: source.ordered,
        items,
      });
    }
  }

  return {
    valid:
      reasons.length === 0 &&
      translated.length === sourceBlocks.length,
    blocks: translated,
    reasons,
  };
}

async function translateWithGemini(
  title: string,
  sourceDescription: string,
  blocks: ContentBlock[],
): Promise<{
  title: string;
  snippet: string;
  description: string;
  contentBlocks: ContentBlock[];
}> {
  const apiKey =
    Deno.env.get("GEMINI_API_KEY")?.trim();

  if (!apiKey) {
    throw new Error(
      "GEMINI_API_KEY is not configured in Supabase secrets.",
    );
  }

  const prompt = buildPrompt(
    title,
    sourceDescription,
    blocks,
  );

  console.log(
    `Starting Gemini tutorial translation with model ${GEMINI_MODEL}. ` +
    `Blocks: ${blocks.length}.`,
  );

  const response = await fetch(
    GEMINI_ENDPOINT,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [{ text: prompt }],
          },
        ],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: MAX_OUTPUT_TOKENS,
          responseMimeType: "application/json",
        },
      }),
    },
  );

  const responseText = await response.text();

  if (!response.ok) {
    throw new Error(
      extractGeminiError(
        response.status,
        responseText,
      ),
    );
  }

  let responseJson: any;

  try {
    responseJson = JSON.parse(responseText);
  } catch (_) {
    throw new Error(
      "Gemini returned an unreadable API response.",
    );
  }

  if (responseJson?.promptFeedback?.blockReason) {
    throw new Error(
      `Gemini blocked the tutorial request: ` +
      `${responseJson.promptFeedback.blockReason}.`,
    );
  }

  const finishReason =
    responseJson?.candidates?.[0]?.finishReason;

  if (finishReason === "SAFETY") {
    throw new Error(
      "Gemini stopped the tutorial translation because of its safety filters.",
    );
  }

  if (finishReason === "MAX_TOKENS") {
    throw new Error(
      "Gemini reached the output-token limit before completing the tutorial.",
    );
  }

  const modelText =
    extractResponseText(responseJson);

  if (!modelText) {
    throw new Error(
      "Gemini returned no translation text.",
    );
  }

  const parsed = parseJsonText(modelText);

  const translatedTitle =
    normaliseHeading(parsed?.title)
      .slice(0, MAX_TITLE_CHARS);

  const translatedSnippet =
    normaliseParagraph(parsed?.snippet)
      .slice(0, MAX_SNIPPET_CHARS);

  const translatedDescription =
    normaliseParagraph(parsed?.description)
      .slice(0, MAX_DESCRIPTION_CHARS);

  if (
    !translatedTitle ||
    !translatedSnippet ||
    !translatedDescription
  ) {
    throw new Error(
      "Gemini returned incomplete Bengali tutorial metadata.",
    );
  }

  const metadata = [
    translatedTitle,
    translatedSnippet,
    translatedDescription,
  ];

  if (
    metadata.some(
      (text) =>
        !containsBengali(text) ||
        hasProviderOrErrorLeak(text) ||
        hasEditorialScaffolding(text),
    )
  ) {
    throw new Error(
      "Gemini returned invalid Bengali tutorial metadata.",
    );
  }

  const validation =
    validateTranslatedBlocks(
      blocks,
      parsed?.contentBlocks,
    );

  if (!validation.valid) {
    throw new Error(
      `Tutorial block validation failed: ${validation.reasons.join(" ")}`,
    );
  }

  const articleText =
    blocksToPlainText(validation.blocks);

  if (
    !containsBengali(articleText) ||
    hasProviderOrErrorLeak(articleText) ||
    hasEditorialScaffolding(articleText)
  ) {
    throw new Error(
      "Translated tutorial failed final Bengali content validation.",
    );
  }

  return {
    title: translatedTitle,
    snippet: translatedSnippet,
    description: translatedDescription,
    contentBlocks: validation.blocks,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return json(
      {
        success: false,
        error: "POST required.",
      },
      405,
    );
  }

  const supabaseUrl =
    Deno.env.get("SUPABASE_URL");

  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return json(
      {
        success: false,
        error:
          "Supabase server configuration is incomplete.",
      },
      500,
    );
  }

  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  try {
    /*
     * Editor-only endpoint.
     *
     * This function translates content only. It does not:
     * - publish tutorials
     * - insert/update tutorials
     * - schedule tutorials
     * - discover source articles
     * - generate images
     * - use a paid fallback provider
     */
    if (!(await isEditor(req, supabase))) {
      return json(
        {
          success: false,
          error: "Editor/admin access is required.",
        },
        403,
      );
    }

    let body: any;

    try {
      body = await req.json();
    } catch (_) {
      return json(
        {
          success: false,
          error: "Invalid JSON request body.",
        },
        400,
      );
    }

    const title = oneLine(body?.title);
    const sourceDescription =
      oneLine(body?.description);
    const sourceUrl = oneLine(body?.sourceUrl);

    let sourceBlocks =
      normaliseSourceBlocks(body?.contentBlocks);

    /*
     * Backward compatibility with the old admin screen.
     * New Phase-1 UI should send contentBlocks.
     */
    if (
      sourceBlocks.length === 0 &&
      typeof body?.articleText === "string"
    ) {
      const articleText = clean(body.articleText);

      if (articleText) {
        sourceBlocks = [
          {
            type: "paragraph",
            text: articleText,
          },
        ];
      }
    }

    if (!title) {
      return json(
        {
          success: false,
          error: "Title is required.",
        },
        400,
      );
    }

    if (sourceBlocks.length === 0) {
      return json(
        {
          success: false,
          error: "No tutorial content blocks were supplied.",
        },
        400,
      );
    }

    sourceBlocks =
      mergeArtificialParagraphs(sourceBlocks);

    const sourceText =
      blocksToPlainText(sourceBlocks);

    if (!sourceText) {
      return json(
        {
          success: false,
          error: "No readable tutorial text was supplied.",
        },
        400,
      );
    }

    if (sourceText.length > MAX_ARTICLE_CHARS) {
      return json(
        {
          success: false,
          error:
            `The tutorial is too large for one translation request ` +
            `(${sourceText.length} characters; maximum ${MAX_ARTICLE_CHARS}).`,
        },
        413,
      );
    }

    console.log(
      `Tutorial translation request received. ` +
      `Source URL: ${sourceUrl || "(not supplied)"}. ` +
      `Blocks: ${sourceBlocks.length}. ` +
      `Words: ${countWords(sourceText)}.`,
    );

    const translated =
      await translateWithGemini(
        title,
        sourceDescription,
        sourceBlocks,
      );

    return json({
      success: true,
      title: translated.title,
      snippet: translated.snippet,
      description: translated.description,
      articleText:
        blocksToPlainText(
          translated.contentBlocks,
        ),
      contentBlocks:
        translated.contentBlocks,
      sourceUrl,
      provider:
        `Gemini ${GEMINI_MODEL} — free tier`,
      translatedAt:
        new Date().toISOString(),
    });
  } catch (error) {
    console.error(
      "Tutorial translation failed:",
      error,
    );

    const message =
      error instanceof Error
        ? error.message
        : "Bengali translation failed.";

    return json(
      {
        success: false,
        error: message,
      },
      502,
    );
  }
});
