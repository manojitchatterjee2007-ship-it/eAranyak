import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MIN_WORDS = 120;
const MAX_IMAGES = 40;
const MAX_BLOCKS = 500;

type ExtractedImage = {
  url: string;
  credit: string | null;
  caption: string | null;
};

type ContentBlock =
  | {
      type: "heading";
      level: number;
      text: string;
    }
  | {
      type: "paragraph";
      text: string;
    }
  | {
      type: "list";
      ordered: boolean;
      items: string[];
    }
  | {
      type: "image";
      url: string;
      caption: string | null;
      credit: string | null;
    };

type ArticleResult = {
  success: boolean;
  url: string;
  title: string | null;
  description: string | null;
  articleText: string | null;
  wordCount: number;
  images: ExtractedImage[];
  primaryImage: string | null;
  imageCredit: string | null;
  sourceName: string | null;
  contentBlocks: ContentBlock[];
  error?: string;
};

function cleanText(text: string): string {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&apos;/gi, "'")
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&ndash;/gi, "–")
    .replace(/&mdash;/gi, "—")
    .replace(/&lsquo;/gi, "‘")
    .replace(/&rsquo;/gi, "’")
    .replace(/&ldquo;/gi, "“")
    .replace(/&rdquo;/gi, "”")
    .replace(/&hellip;/gi, "…")
    .replace(/&#(\d+);/g, (_m, d) =>
      String.fromCharCode(Number(d)),
    )
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function stripTags(html: string): string {
  return cleanText(
    html
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/p>/gi, "\n")
      .replace(/<\/div>/gi, "\n")
      .replace(/<\/li>/gi, "\n")
      .replace(/<\/h[1-6]>/gi, "\n")
      .replace(/<[^>]+>/g, " "),
  );
}

function decodeAttribute(value: string): string {
  return cleanText(
    value
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/&amp;/gi, "&")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">"),
  );
}

function absoluteUrl(
  base: string,
  value: string,
): string | null {
  try {
    return new URL(value, base).toString();
  } catch (_) {
    return null;
  }
}

function extractMeta(
  html: string,
  name: string,
): string | null {
  const escaped = name.replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&",
  );

  const patterns = [
    new RegExp(
      `<meta[^>]+(?:property|name)=["']${escaped}["'][^>]+content=["']([^"']+)["'][^>]*>`,
      "i",
    ),
    new RegExp(
      `<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${escaped}["'][^>]*>`,
      "i",
    ),
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);

    if (match?.[1]) {
      return decodeAttribute(match[1]);
    }
  }

  return null;
}

function extractTitle(html: string): string | null {
  const ogTitle = extractMeta(html, "og:title");

  if (ogTitle) {
    return ogTitle;
  }

  const match = html.match(
    /<title[^>]*>([\s\S]*?)<\/title>/i,
  );

  return match?.[1]
    ? stripTags(match[1])
    : null;
}

function extractSourceName(
  html: string,
  pageUrl: string,
): string | null {
  const siteName =
    extractMeta(html, "og:site_name") ??
    extractMeta(html, "application-name");

  if (siteName) {
    return siteName;
  }

  try {
    const hostname = new URL(pageUrl).hostname
      .replace(/^www\./i, "");

    return hostname || null;
  } catch (_) {
    return null;
  }
}

function looksLikeBadImageUrl(url: string): boolean {
  const lower = url.toLowerCase();

  if (!/^https?:\/\//i.test(url)) {
    return true;
  }

  if (
    /(logo|favicon|avatar|icon|sprite|tracking|pixel|spacer|placeholder|social-share)/i
      .test(lower)
  ) {
    return true;
  }

  if (
    lower.endsWith(".svg") ||
    lower.endsWith(".ico")
  ) {
    return true;
  }

  return false;
}

function extractImageCandidatesFromTag(
  tag: string,
  pageUrl: string,
): string[] {
  const values: string[] = [];

  const add = (raw: string | null) => {
    if (!raw) return;

    const url = absoluteUrl(
      pageUrl,
      decodeAttribute(raw.trim()),
    );

    if (!url || looksLikeBadImageUrl(url)) {
      return;
    }

    if (!values.includes(url)) {
      values.push(url);
    }
  };

  const attributes = [
    "src",
    "data-src",
    "data-lazy-src",
    "data-original",
    "data-image",
    "data-image-src",
    "data-flickity-lazyload",
    "data-lazy",
    "data-original-src",
    "data-fs-original-src",
  ];

  for (const attribute of attributes) {
    const pattern = new RegExp(
      `${attribute}=["']([^"']+)["']`,
      "i",
    );

    const match = tag.match(pattern);

    if (match?.[1]) {
      add(match[1]);
    }
  }

  const srcsetMatch = tag.match(
    /(?:srcset|data-srcset)=["']([^"']+)["']/i,
  );

  if (srcsetMatch?.[1]) {
    const candidates = srcsetMatch[1]
      .split(",")
      .map((candidate) =>
        candidate.trim().split(/\s+/)[0]
      );

    /*
     * Prefer the last/largest candidate in a srcset.
     * This normally gives us a better article image.
     */
    for (const candidate of candidates.reverse()) {
      add(candidate);
    }
  }

  return values;
}

function extractCaptionFromFigure(
  figureHtml: string,
): string | null {
  const figcaption = figureHtml.match(
    /<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/i,
  );

  if (figcaption?.[1]) {
    const text = stripTags(figcaption[1]);

    if (text.length >= 2) {
      return text;
    }
  }

  /*
   * Squarespace and other CMSs sometimes use nearby
   * caption/description classes rather than <figcaption>.
   */
  const captionMatch = figureHtml.match(
    /<(?:div|p|span)\b[^>]*(?:class|id)=["'][^"']*(?:caption|image-caption|photo-caption|description)[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|p|span)>/i,
  );

  if (captionMatch?.[1]) {
    const text = stripTags(captionMatch[1]);

    if (text.length >= 2) {
      return text;
    }
  }

  return null;
}

function extractCreditFromFigure(
  figureHtml: string,
): string | null {
  const candidates: string[] = [];

  const patterns = [
    /<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/gi,
    /<(?:p|div|span)\b[^>]*(?:class|id)=["'][^"']*(?:caption|credit|photo-credit|image-credit)[^"']*["'][^>]*>([\s\S]*?)<\/(?:p|div|span)>/gi,
  ];

  for (const pattern of patterns) {
    for (const match of figureHtml.matchAll(pattern)) {
      const text = stripTags(match[1] ?? "");

      if (
        /(?:image|photo|photograph)\s+(?:by|courtesy of)|courtesy of|©|credit/i
          .test(text)
      ) {
        candidates.push(text);
      }
    }
  }

  return candidates
    .map((x) => x.replace(/\s+/g, " ").trim())
    .find(
      (x) =>
        x.length >= 8 &&
        x.length <= 240,
    ) ?? null;
}

function extractImages(
  html: string,
  pageUrl: string,
): ExtractedImage[] {
  const result: ExtractedImage[] = [];

  const add = (
    url: string | null,
    caption: string | null = null,
    credit: string | null = null,
  ) => {
    if (!url || looksLikeBadImageUrl(url)) {
      return;
    }

    if (result.some((item) => item.url === url)) {
      return;
    }

    result.push({
      url,
      caption,
      credit,
    });
  };

  /*
   * Extract <figure> blocks first so that captions and
   * credits stay associated with their image.
   */
  const figurePattern =
    /<figure\b[^>]*>[\s\S]*?<\/figure>/gi;

  for (const match of html.matchAll(figurePattern)) {
    const figureHtml = match[0];

    const caption =
      extractCaptionFromFigure(figureHtml);

    const credit =
      extractCreditFromFigure(figureHtml);

    const imgTags = [
      ...figureHtml.matchAll(
        /<img\b[^>]*>/gi,
      ),
    ];

    for (const imgMatch of imgTags) {
      const candidates =
        extractImageCandidatesFromTag(
          imgMatch[0],
          pageUrl,
        );

      /*
       * candidates are ordered with the best/largest
       * source first.
       */
      if (candidates.length > 0) {
        add(
          candidates[0],
          caption,
          credit,
        );
      }
    }
  }

  /*
   * Then process images that aren't inside <figure>.
   */
  const imgTags = [
    ...html.matchAll(
      /<img\b[^>]*>/gi,
    ),
  ];

  for (const match of imgTags) {
    const candidates =
      extractImageCandidatesFromTag(
        match[0],
        pageUrl,
      );

    if (candidates.length === 0) {
      continue;
    }

    /*
     * Look around the image for a nearby <figcaption>
     * or caption container if one wasn't already found.
     */
    const index = match.index ?? 0;

    const surrounding =
      html.slice(
        Math.max(0, index - 1500),
        Math.min(
          html.length,
          index + 2500,
        ),
      );

    const caption =
      extractCaptionFromFigure(
        surrounding,
      );

    const credit =
      extractCreditFromFigure(
        surrounding,
      );

    add(
      candidates[0],
      caption,
      credit,
    );
  }

  return result.slice(0, MAX_IMAGES);
}

function extractSocialImageFallbacks(
  html: string,
  pageUrl: string,
): string[] {
  const result: string[] = [];

  const add = (value: string | null) => {
    if (
      !value ||
      looksLikeBadImageUrl(value) ||
      result.includes(value)
    ) {
      return;
    }

    result.push(value);
  };

  const ogImage = extractMeta(html, "og:image");
  add(
    ogImage
      ? absoluteUrl(pageUrl, ogImage)
      : null,
  );

  const ogImageUrl = extractMeta(
    html,
    "og:image:url",
  );
  add(
    ogImageUrl
      ? absoluteUrl(pageUrl, ogImageUrl)
      : null,
  );

  const twitterImage = extractMeta(
    html,
    "twitter:image",
  );
  add(
    twitterImage
      ? absoluteUrl(pageUrl, twitterImage)
      : null,
  );

  return result;
}

function extractImageCredit(
  images: ExtractedImage[],
  html: string,
): string | null {
  for (const image of images) {
    if (image.credit) {
      return image.credit;
    }
  }

  const plain = cleanText(
    html
      .replace(
        /<script[\s\S]*?<\/script>/gi,
        " ",
      )
      .replace(
        /<style[\s\S]*?<\/style>/gi,
        " ",
      )
      .replace(/<[^>]+>/g, " "),
  );

  const phrase = plain.match(
    /(?:Image|Photo|Photograph)\s+(?:by|courtesy of)\s+[^.]{2,180}\.?/i,
  );

  return phrase?.[0]
    ? phrase[0].trim()
    : null;
}

function removeNoise(
  html: string,
): string {
  return html
    .replace(
      /<(script|style|noscript|svg|nav|header|footer|aside|form|button|iframe|template|dialog)[^>]*>[\s\S]*?<\/\1>/gi,
      " ",
    )
    .replace(
      /<!--[\s\S]*?-->/g,
      " ",
    );
}

const BOILERPLATE_PATTERNS = [
  /^in this issue of/i,
  /^subscribe to/i,
  /^read more/i,
  /^sign up for/i,
  /^follow us on/i,
  /^related stories/i,
  /^recommended articles/i,
  /^leave a reply/i,
  /^share this article/i,
  /^click here to/i,
  /^copyright ©/i,
  /^all rights reserved/i,
];

function isBoilerplate(text: string): boolean {
  const clean = text.trim();

  if (!clean) {
    return true;
  }

  return BOILERPLATE_PATTERNS.some(
    (pattern) => pattern.test(clean),
  );
}

function extractArticleContainer(
  html: string,
): string {
  const cleaned = removeNoise(html);

  /*
   * Prefer <article>.
   */
  const articles = [
    ...cleaned.matchAll(
      /<article\b[^>]*>([\s\S]*?)<\/article>/gi,
    ),
  ];

  if (articles.length > 0) {
    const source = articles
      .map((m) => m[1])
      .join("\n\n");

    if (stripTags(source).split(/\s+/).filter(Boolean).length >= MIN_WORDS) {
      return source;
    }
  }

  /*
   * Fall back to <main>.
   */
  const mains = [
    ...cleaned.matchAll(
      /<main\b[^>]*>([\s\S]*?)<\/main>/gi,
    ),
  ];

  if (mains.length > 0) {
    const source = mains
      .map((m) => m[1])
      .join("\n\n");

    if (stripTags(source).split(/\s+/).filter(Boolean).length >= MIN_WORDS) {
      return source;
    }
  }

  /*
   * Final fallback: use the complete cleaned document.
   */
  return cleaned;
}

function normaliseInlineHtml(
  html: string,
): string {
  return html
    .replace(
      /<strong\b[^>]*>([\s\S]*?)<\/strong>/gi,
      "$1",
    )
    .replace(
      /<b\b[^>]*>([\s\S]*?)<\/b>/gi,
      "$1",
    )
    .replace(
      /<em\b[^>]*>([\s\S]*?)<\/em>/gi,
      "$1",
    )
    .replace(
      /<i\b[^>]*>([\s\S]*?)<\/i>/gi,
      "$1",
    )
    .replace(
      /<span\b[^>]*>([\s\S]*?)<\/span>/gi,
      "$1",
    );
}

function parseContentBlocks(
  articleHtml: string,
  pageUrl: string,
): ContentBlock[] {
  const blocks: ContentBlock[] = [];
  const seenImageUrls = new Set<string>();

  /*
   * Work from article-level block elements so the original reading order
   * survives extraction:
   *
   * paragraph -> paragraph -> heading -> image -> paragraph -> image ...
   *
   * Images are represented as their own blocks.  This is deliberately kept
   * separate from the translation layer: the translator can translate the
   * textual blocks while leaving image URLs untouched.
   */
  const blockPattern =
    /<(h[1-6]|p|figure|picture|ul|ol|blockquote)\b[^>]*>[\s\S]*?<\/\1>|<img\b[^>]*>/gi;

  const matches = [
    ...articleHtml.matchAll(blockPattern),
  ];

  const addParagraph = (raw: string) => {
    const text = stripTags(
      normaliseInlineHtml(raw),
    )
      .replace(/\s+/g, " ")
      .trim();

    if (!text || isBoilerplate(text) || text.length < 2) {
      return;
    }

    blocks.push({
      type: "paragraph",
      text,
    });
  };

  const addHeading = (
    raw: string,
    level: number,
  ) => {
    const text = stripTags(raw)
      .replace(/\s+/g, " ")
      .trim();

    if (!text || isBoilerplate(text)) {
      return;
    }

    blocks.push({
      type: "heading",
      level: Math.min(6, Math.max(1, level)),
      text,
    });
  };

  const addList = (
    raw: string,
    ordered: boolean,
  ) => {
    const items: string[] = [];
    const liPattern =
      /<li\b[^>]*>([\s\S]*?)<\/li>/gi;

    for (const li of raw.matchAll(liPattern)) {
      const text = stripTags(li[1] ?? "")
        .replace(/\s+/g, " ")
        .trim();

      if (text && !isBoilerplate(text)) {
        items.push(text);
      }
    }

    if (items.length > 0) {
      blocks.push({
        type: "list",
        ordered,
        items,
      });
    }
  };

  const addImageFromHtml = (
    raw: string,
    surroundingHtml?: string,
  ) => {
    /*
     * Prefer the largest/best candidate from an img/source tag.  A picture
     * element may contain both <source> and <img>; collecting candidates from
     * the complete element lets us use the highest-quality source while
     * avoiding duplicate image blocks.
     */
    const imageTags = [
      ...raw.matchAll(/<(?:img|source)\b[^>]*>/gi),
    ];

    const candidates: string[] = [];

    for (const imageTag of imageTags) {
      const found = extractImageCandidatesFromTag(
        imageTag[0],
        pageUrl,
      );

      for (const url of found) {
        if (!candidates.includes(url)) {
          candidates.push(url);
        }
      }
    }

    if (candidates.length === 0) {
      return;
    }

    const url = candidates[0];

    if (seenImageUrls.has(url)) {
      return;
    }

    let caption: string | null = null;
    let credit: string | null = null;

    const figure = raw.match(
      /<figure\b[^>]*>[\s\S]*?<\/figure>/i,
    );

    if (figure) {
      caption = extractCaptionFromFigure(figure[0]);
      credit = extractCreditFromFigure(figure[0]);
    }

    if (!caption && surroundingHtml) {
      caption = extractCaptionFromFigure(surroundingHtml);
    }

    if (!credit && surroundingHtml) {
      credit = extractCreditFromFigure(surroundingHtml);
    }

    seenImageUrls.add(url);

    blocks.push({
      type: "image",
      url,
      caption,
      credit,
    });
  };

  if (matches.length === 0) {
    const paragraphs = [
      ...articleHtml.matchAll(
        /<p\b[^>]*>([\s\S]*?)<\/p>/gi,
      ),
    ];

    for (const paragraph of paragraphs) {
      addParagraph(paragraph[1] ?? "");
    }

    return blocks.slice(0, MAX_BLOCKS);
  }

  for (let i = 0; i < matches.length; i++) {
    if (blocks.length >= MAX_BLOCKS) {
      break;
    }

    const match = matches[i];
    const tagName = (match[1] ?? "").toLowerCase();
    const raw = match[0];

    if (/^h[1-6]$/.test(tagName)) {
      addHeading(
        raw,
        Number(tagName.substring(1)),
      );
      continue;
    }

    if (tagName === "p") {
      addParagraph(raw);
      continue;
    }

    if (tagName === "ul") {
      addList(raw, false);
      continue;
    }

    if (tagName === "ol") {
      addList(raw, true);
      continue;
    }

    if (tagName === "blockquote") {
      addParagraph(raw);
      continue;
    }

    if (
      tagName === "figure" ||
      tagName === "picture" ||
      tagName === "img"
    ) {
      const start = Math.max(
        0,
        (match.index ?? 0) - 1400,
      );
      const end = Math.min(
        articleHtml.length,
        (match.index ?? 0) + raw.length + 2600,
      );

      addImageFromHtml(
        raw,
        articleHtml.slice(start, end),
      );
    }
  }

  /*
   * Some publishers wrap article text in arbitrary <div> elements.  The
   * block-level parser intentionally avoids treating every div as a new
   * paragraph because doing so creates the excessive paragraph breaks that
   * the Bengali tutorial should not have.  As a final safety net, recover
   * image tags that were not captured by the block matcher.
   */
  const allImageTags = [
    ...articleHtml.matchAll(
      /<(?:img|picture)\b[^>]*>[\s\S]*?(?:<\/picture>)?/gi,
    ),
  ];

  for (const imageMatch of allImageTags) {
    if (blocks.length >= MAX_BLOCKS) {
      break;
    }

    addImageFromHtml(
      imageMatch[0],
      articleHtml.slice(
        Math.max(0, (imageMatch.index ?? 0) - 1400),
        Math.min(
          articleHtml.length,
          (imageMatch.index ?? 0) + imageMatch[0].length + 2600,
        ),
      ),
    );
  }

  return blocks.slice(0, MAX_BLOCKS);
}

function blocksToPlainText(
  blocks: ContentBlock[],
): string {
  const parts: string[] = [];

  for (const block of blocks) {
    if (
      block.type === "paragraph" ||
      block.type === "heading"
    ) {
      parts.push(block.text);
    } else if (block.type === "list") {
      parts.push(
        block.items.join("\n"),
      );
    }
  }

  return cleanText(
    parts.join("\n\n"),
  );
}

function looksBlocked(
  title: string | null,
  text: string,
): boolean {
  const combined =
    `${title ?? ""} ${text}`.toLowerCase();

  return [
    "sign in to continue",
    "subscribe to continue",
    "subscription required",
    "paywall",
    "log in to read",
    "login to read",
    "please subscribe",
    "access denied",
    "403 forbidden",
    "captcha",
  ].some((value) =>
    combined.includes(value),
  );
}

async function verifyEditor(
  req: Request,
): Promise<{
  userId: string;
  email: string | null;
}> {
  const authorization =
    req.headers.get("Authorization") ?? "";

  if (!authorization.startsWith("Bearer ")) {
    throw new Error(
      "Authentication required.",
    );
  }

  const token =
    authorization
      .substring("Bearer ".length)
      .trim();

  if (!token) {
    throw new Error(
      "Authentication token missing.",
    );
  }

  const supabaseUrl =
    Deno.env.get("SUPABASE_URL");

  const supabaseAnonKey =
    Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      "Supabase environment is not configured.",
    );
  }

  const supabase =
    createClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        global: {
          headers: {
            Authorization:
              `Bearer ${token}`,
          },
        },
      },
    );

  const {
    data: userData,
    error: userError,
  } =
    await supabase.auth.getUser(token);

  if (
    userError ||
    !userData.user
  ) {
    throw new Error(
      "Invalid or expired authentication.",
    );
  }

  const userId =
    userData.user.id;

  const {
    data: profile,
    error: profileError,
  } =
    await supabase
      .from("profiles")
      .select("id, role")
      .eq("id", userId)
      .maybeSingle();

  if (
    profileError ||
    !profile ||
    profile.role !== "admin"
  ) {
    throw new Error(
      "Editor access required.",
    );
  }

  return {
    userId,
    email:
      userData.user.email ?? null,
  };
}

async function extractArticle(
  inputUrl: string,
): Promise<ArticleResult> {
  const parsed =
    new URL(inputUrl);

  if (
    !/^https?:$/.test(
      parsed.protocol,
    )
  ) {
    throw new Error(
      "Only HTTP/HTTPS article URLs are supported.",
    );
  }

  const response =
    await fetch(
      inputUrl,
      {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (compatible; eAranyakTutorialEditor/1.0)",
          "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language":
            "en-US,en;q=0.8",
          "Cache-Control":
            "no-cache",
        },
        redirect: "follow",
      },
    );

  if (!response.ok) {
    throw new Error(
      `Article request failed with HTTP ${response.status}.`,
    );
  }

  const bytes =
    new Uint8Array(
      await response.arrayBuffer(),
    );

  let html: string;

  try {
    html =
      new TextDecoder(
        "utf-8",
        { fatal: true },
      ).decode(bytes);
  } catch (_) {
    html =
      new TextDecoder(
        "windows-1252",
      ).decode(bytes);
  }

  if (html.length < 1000) {
    throw new Error(
      "The source page did not return enough HTML.",
    );
  }

  const finalUrl =
    response.url ||
    parsed.toString();

  const title =
    extractTitle(html);

  const description =
    extractMeta(
      html,
      "og:description",
    ) ??
    extractMeta(
      html,
      "description",
    );

  const articleContainer =
    extractArticleContainer(html);

  const contentBlocks =
    parseContentBlocks(
      articleContainer,
      finalUrl,
    );

  const articleText =
    blocksToPlainText(
      contentBlocks,
    );

  const words =
    articleText
      .split(/\s+/)
      .filter(Boolean);

  const extractedImages =
    extractImages(
      html,
      finalUrl,
    );

  /*
   * Merge structured-block images into the global image
   * collection. This is important for pages where the
   * image exists inside the article but not in the
   * <article>/<main> image scan.
   *
   * The collection intentionally contains article images,
   * not OG/Twitter social preview images.
   */
  const imageMap =
    new Map<
      string,
      ExtractedImage
    >();

  for (
    const image of extractedImages
  ) {
    imageMap.set(
      image.url,
      image,
    );
  }

  for (
    const block of contentBlocks
  ) {
    if (
      block.type === "image"
    ) {
      const existing =
        imageMap.get(
          block.url,
        );

      if (existing) {
        if (
          !existing.caption &&
          block.caption
        ) {
          existing.caption =
            block.caption;
        }

        if (
          !existing.credit &&
          block.credit
        ) {
          existing.credit =
            block.credit;
        }
      } else {
        imageMap.set(
          block.url,
          {
            url: block.url,
            caption:
              block.caption,
            credit:
              block.credit,
          },
        );
      }
    }
  }

  const images =
    Array.from(
      imageMap.values(),
    ).slice(0, MAX_IMAGES);

  const imageCredit =
    extractImageCredit(
      images,
      html,
    );

  const blocked =
    looksBlocked(
      title,
      articleText,
    );

  const readable =
    words.length >= MIN_WORDS &&
    !blocked;

  const sourceName =
    extractSourceName(
      html,
      finalUrl,
    );

  /*
   * Primary image preference:
   *
   * 1. First actual image in the article content.
   * 2. Only if the article contains no image, use an
   *    Open Graph / Twitter image as a fallback thumbnail.
   *
   * Social preview images are therefore never placed before
   * actual article images in the `images` collection.
   */
  const firstArticleImage =
    contentBlocks.find(
      (block) =>
        block.type === "image",
    );

  const socialImageFallbacks =
    extractSocialImageFallbacks(
      html,
      finalUrl,
    );

  const primaryImage =
    firstArticleImage &&
    firstArticleImage.type === "image"
      ? firstArticleImage.url
      : images[0]?.url ??
        socialImageFallbacks[0] ??
        null;

  return {
    success: readable,
    url: finalUrl,
    title,
    description,
    articleText: readable
      ? articleText
      : null,
    wordCount:
      words.length,
    images,
    primaryImage,
    imageCredit,
    sourceName,
    contentBlocks:
      readable
        ? contentBlocks
        : [],
    error: readable
      ? undefined
      : blocked
      ? "The source appears blocked, login-gated, or subscription-gated."
      : `Only ${words.length} readable words were extracted; minimum is ${MIN_WORDS}.`,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(
      "ok",
      {
        headers: corsHeaders,
      },
    );
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({
        success: false,
        error:
          "Only POST requests are supported.",
      }),
      {
        status: 405,
        headers: {
          ...corsHeaders,
          "Content-Type":
            "application/json",
        },
      },
    );
  }

  try {
    const editor =
      await verifyEditor(req);

    const body =
      await req.json();

    const url =
      typeof body?.url === "string"
        ? body.url.trim()
        : "";

    if (!url) {
      throw new Error(
        "Missing article URL.",
      );
    }

    const article =
      await extractArticle(url);

    if (!article.success) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            article.error ??
            "Unable to extract a readable article.",
          article,
        }),
        {
          status: 422,
          headers: {
            ...corsHeaders,
            "Content-Type":
              "application/json; charset=utf-8",
          },
        },
      );
    }

    /*
     * IMPORTANT:
     *
     * This function ONLY extracts the source article.
     *
     * It does NOT:
     * - translate
     * - generate tutorial text
     * - publish
     * - call an AI provider
     * - schedule anything
     * - copy source images into storage
     */

    return new Response(
      JSON.stringify({
        success: true,

        editor: {
          id: editor.userId,
          email: editor.email,
        },

        article,

        draftDefaults: {
          isPublished: false,

          translationProvider:
            null,

          imageProvenance:
            article.imageCredit ??
            article.sourceName ??
            null,
        },
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type":
            "application/json; charset=utf-8",
        },
      },
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    const status =
      message ===
        "Authentication required." ||
      message ===
        "Authentication token missing." ||
      message ===
        "Invalid or expired authentication."
        ? 401
        : message ===
            "Editor access required."
        ? 403
        : 500;

    return new Response(
      JSON.stringify({
        success: false,
        error: message,
      }),
      {
        status,
        headers: {
          ...corsHeaders,
          "Content-Type":
            "application/json; charset=utf-8",
        },
      },
    );
  }
});