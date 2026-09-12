import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

const SHORTLIST_LIMIT = 3;
const MIN_SOURCE_WORDS = 100;
const GLOBAL_REFRESH_TIMEOUT_MS = 115000; // 115 seconds safety limit
const SOURCE_FETCH_TIMEOUT_MS = 8000;     // 8 seconds per source
const FAILED_CANDIDATE_CLEANUP_RESERVE_MS = 8000; // keep time reserved for safety
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36";
const PROJECT_URL = () => Deno.env.get("SUPABASE_URL") ?? "";

type SourceDef = {
  name: string;
  url: string;
  kind: "rss" | "html";
  origin?: string;
  linkRe?: RegExp;
  maxItems?: number;
};
type NewsItem = Record<string, unknown>;

const SOURCES: SourceDef[] = [
  { name: "Mongabay India", url: "https://india.mongabay.com/feed/", kind: "rss" },
  {
    name: "Sanctuary Nature Foundation", url: "https://www.sanctuarynaturefoundation.org/articles", kind: "html", maxItems: 10,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.sanctuarynaturefoundation\.org\/article\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "Down To Earth (RSS)", url: "https://www.downtoearth.org.in/rss/wildlife-and-biodiversity", kind: "rss",
  },
  {
    name: "Down To Earth", url: "https://www.downtoearth.org.in/", kind: "html", maxItems: 10,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.downtoearth\.org\.in\/[a-z0-9-]+\/[^"#?]{20,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "NatGeo Traveller India", url: "https://www.natgeotraveller.in/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/(?:www\.)?nationalgeographic\.com\/travel\/article\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  { name: "Current Conservation", url: "https://www.currentconservation.org/feed/", kind: "rss" },
  {
    name: "Nature In Focus", url: "https://www.natureinfocus.in/", origin: "https://www.natureinfocus.in", kind: "html", maxItems: 10,
    linkRe: /<a[^>]+href="\s*(\/(?!(?:stories|partnerships|community|search|festival|awards|productions|podcast|cdn-cgi|add-your-story)\b)[a-z0-9-]+\/[a-z0-9-]{6,}\/?)[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "India Water Portal", url: "https://www.indiawaterportal.org/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.indiawaterportal\.org\/(?:[a-z0-9-]+\/){0,2}[a-z0-9-]{20,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "PARI", url: "https://ruralindiaonline.org/en/articles/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/ruralindiaonline\.org\/en\/articles\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "Gaon Connection", url: "https://www.gaonconnection.com/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.gaonconnection\.com\/[a-z0-9-]+\/[a-z0-9-]{12,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "The Wire Environment", url: "https://thewire.in/environment", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/thewire\.in\/[a-z-]+\/[a-z0-9-]{10,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
];

const CATEGORY_PREFIX_RE = /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্ত|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;
const BENGALI_CHAR = /[\u0980-\u09FF]/;

function getRemainingTimeMs(startTime: number): number {
  return Math.max(0, GLOBAL_REFRESH_TIMEOUT_MS - (Date.now() - startTime));
}

function isValidSourceUrl(url: unknown): boolean {
  if (!url || typeof url !== "string") return false;
  const trimmed = url.trim();
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) return false;
  try {
    new URL(trimmed);
    return true;
  } catch (_) {
    return false;
  }
}

function isValidImageUrl(url: unknown): boolean {
  if (!url || typeof url !== "string") return false;
  const trimmed = url.trim();
  if (!trimmed) return false;
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) return false;
  if (/^data:/i.test(trimmed)) return false;
  const lower = trimmed.toLowerCase();
  if (/\b(placeholder|default-image|no-image|blank|pixel|spacer|avatar|logo|favicon)\b/i.test(lower)) return false;
  if (/\.(svg|gif)($|\?)/i.test(lower)) return false;
  try {
    new URL(trimmed);
    return true;
  } catch (_) {
    return false;
  }
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

function authorized(req: Request): boolean {
  const secret = Deno.env.get("NEWS_REFRESH_SECRET");
  return !!secret && (req.headers.get("x-news-refresh-secret") ?? "") === secret;
}

function clean(text: string): string {
  return text.replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ").trim();
}

function tidyTitle(text: string): string {
  return clean(text)
    .replace(/â†'|â†→|→|»|›/g, " ")
    .replace(/\s+—\s+[^—]+$/g, " ")
    .replace(/^[\s.,:;\-–—|#*]*(?:\d[\s.,:;\-–—&]*)+/, "")
    .replace(/^\s*(?:photo|image)\s*:\s*/i, "")
    .replace(/\s+/g, " ")
    .trim();
}

function extractTag(block: string, tag: string): string | null {
  const m = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\/${tag}>`, "i").exec(block);
  return m ? m[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").trim() : null;
}

function categoryFor(text: string): string {
  const l = text.toLowerCase();
  if (/bird|avifaun|vulture|owl|eagle|sparrow|nest|migration|wing|beak/.test(l)) return "birds";
  if (/tiger|leopard|wolf|dhole|caracal|lion|cheetah|predator|carnivore|panther/.test(l)) return "carnivore";
  if (/elephant|rhino|gaur|deer|herbivore|primate|monkey|langur|macaque|mammal/.test(l)) return "herbivore";
  if (/plant|flora|orchid|tree|forest|mangrove|western ghats|himalaya|biodiversity|botany|flower|seed/.test(l)) return "flora";
  return "climate";
}

function normalizeUrl(url: string): string {
  try {
    const u = new URL(url);
    u.hash = "";
    u.search = "";
    return u.toString().replace(/\/+$/, "");
  } catch (_) {
    return url.split("#")[0].split("?")[0].replace(/\/+$/, "");
  }
}

function baseItem(title: string, source: string, sourceUrl: string, snippet: string): NewsItem | null {
  const t = tidyTitle(title);
  const s = clean(snippet);
  if (!t || t.length < 8) return null;
  const normUrl = normalizeUrl(sourceUrl);
  const category = categoryFor(`${t} ${s}`);
  return {
    title: t,
    source_title: t,
    source,
    source_name: source,
    source_url: normUrl,
    original_article_url: normUrl,
    snippet: (s ? tidyTitle(s) : "").slice(0, 220) || t,
    content: s || t,
    image_url: null,
    image_credit: null,
    category,
    date_str: "",
    img_tags: "wildlife,nature,watercolor",
    fetched_at: new Date().toISOString(),
    processing_status: "pending",
  };
}

async function contentHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function parseRss(xml: string, sourceName: string): NewsItem[] {
  const out: NewsItem[] = [];
  for (const m of xml.matchAll(/<(?:item|entry)[\s\S]*?<\/(?:item|entry)>/g)) {
    const block = m[0];
    const title = clean(extractTag(block, "title") ?? "");
    const link = (extractTag(block, "link") ?? /<link[^>]+href=["']([^"']+)["']/i.exec(block)?.[1] ?? "").trim();
    if (!title || !/^https?:\/\//i.test(link)) continue;
    const desc = clean(extractTag(block, "description") ?? extractTag(block, "summary") ?? "");
    const body = clean(extractTag(block, "content:encoded") ?? "") || desc;
    const item = baseItem(title, sourceName, link, desc);
    if (!item) continue;
    const enclosure = /<enclosure[^>]*url=["']([^"']+)["']/i.exec(block)?.[1] ?? /<img[^>]+src=["']([^"']+)["']/i.exec(extractTag(block, "content:encoded") ?? "")?.[1];
    out.push({
      ...item,
      content: body || title,
      date_str: (extractTag(block, "pubDate") ?? extractTag(block, "published") ?? "").trim(),
      ...(enclosure ? { image_url: enclosure } : {}),
    });
    if (out.length >= 12) break;
  }
  return out;
}

function parseHtml(html: string, src: SourceDef): NewsItem[] {
  const out: NewsItem[] = [];
  const seen = new Set<string>();
  if (!src.linkRe) return out;
  for (const m of html.matchAll(src.linkRe)) {
    let url = (m[1] ?? "").trim();
    if (url.startsWith("/")) url = `${src.origin ?? new URL(src.url).origin}${url}`;
    if (!/^https?:\/\//i.test(url)) continue;
    const norm = normalizeUrl(url);
    if (seen.has(norm)) continue;
    seen.add(norm);

    const currentYear = new Date().getFullYear();
    const slugYear = /(?:^|[^0-9])(20\d{2})(?:[^0-9]|$)/.exec(norm);
    if (slugYear && Number(slugYear[1]) <= currentYear - 2) continue;

    const segments = (m[2] ?? "")
      .replace(/<[^>]+>/g, "\n")
      .split(/\n+/)
      .map((seg) => tidyTitle(seg))
      .filter((seg) => /[A-Za-z]/.test(seg) && seg.length >= 4);
    segments.sort((a, b) => b.length - a.length);
    const anchor = segments[0] ?? "";
    const slug = decodeURIComponent(norm.split("/").filter(Boolean).pop() ?? "").replace(/-+/g, " ").trim();
    const title = anchor.length >= 12 ? anchor : slug.split(" ").slice(0, 14).join(" ");
    const item = baseItem(title, src.name, norm, anchor || title);
    if (!item) continue;
    out.push(item);
    if (out.length >= (src.maxItems ?? 8)) break;
  }
  return out;
}

async function rest(method: string, path: string, key: string, body?: unknown): Promise<Response> {
  return fetch(`${PROJECT_URL()}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function scoreCandidate(item: NewsItem): number {
  const title = String(item.title ?? "").toLowerCase();
  const snippet = String(item.snippet ?? "").toLowerCase();
  const text = `${title} ${snippet}`;

  let score = 0;

  const highPriorityKeywords = [
    "tiger", "leopard", "elephant", "rhino", "snow leopard", "lion", "cheetah",
    "vulture", "bustard", "hornbill", "gharial", "dolphin", "dugong", "pangolin",
    "sundarbans", "western ghats", "mangrove", "national park", "tiger reserve",
    "endangered", "new species", "camera trap", "poaching", "biodiversity",
    "conservation", "wildlife", "forest"
  ];

  for (const kw of highPriorityKeywords) {
    if (title.includes(kw)) score += 10;
    else if (snippet.includes(kw)) score += 4;
  }

  const secondaryKeywords = [
    "bird", "avifauna", "migration", "wetland", "himalaya", "sanctuary",
    "ecosystem", "habitat", "corridor", "coexistence", "research", "scientists",
    "flora", "orchid", "reptile", "amphibian", "climate", "nature", "river"
  ];

  for (const kw of secondaryKeywords) {
    if (title.includes(kw)) score += 5;
    else if (snippet.includes(kw)) score += 2;
  }

  if (title.length >= 25 && title.length <= 120) score += 3;
  if (snippet.length >= 40) score += 2;

  if (/\b(?:resort|hotel|luxury|itinerary|flight|shopping|booking|resorts|hotels)\b/i.test(text)) {
    score -= 15;
  }

  return score;
}

function extractKeyTokens(item: NewsItem): Set<string> {
  const text = `${String(item.title ?? "")} ${String(item.snippet ?? "")}`.toLowerCase();
  const words = text.match(/[a-z]{4,}/g) || [];
  const stopWords = new Set(["with", "from", "that", "this", "have", "been", "were", "where", "about", "their", "there", "which"]);
  return new Set(words.filter((w) => !stopWords.has(w)));
}

function isTooSimilar(candidate: NewsItem, selectedPool: NewsItem[]): boolean {
  const cTokens = extractKeyTokens(candidate);
  if (cTokens.size === 0) return false;

  for (const existing of selectedPool) {
    const eTokens = extractKeyTokens(existing);
    if (eTokens.size === 0) continue;

    let overlap = 0;
    for (const t of cTokens) {
      if (eTokens.has(t)) overlap++;
    }

    const similarity = overlap / Math.min(cTokens.size, eTokens.size);
    if (similarity > 0.45) return true;
  }

  return false;
}

async function processSingleCandidate(
  row: NewsItem,
  serviceKey: string,
  refreshStartTime: number
): Promise<{ ok: boolean; reason?: string; publishedArticle?: NewsItem }> {
  const secret = Deno.env.get("NEWS_REFRESH_SECRET") ?? "";
  const headers = {
    "Authorization": `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    "x-news-refresh-secret": secret,
  };
  const sourceUrl = String(row.source_url ?? "").trim();

  // 1. Source URL Validation Gate
  if (!isValidSourceUrl(sourceUrl)) {
    return { ok: false, reason: "Invalid or non-HTTP(S) source URL" };
  }

  try {
    // 2. Article Extraction with Timeout & Defensive Response Parsing
    const extractionTimeoutMs = Math.min(
      15000,
      Math.max(0, getRemainingTimeMs(refreshStartTime) - FAILED_CANDIDATE_CLEANUP_RESERVE_MS)
    );
    if (extractionTimeoutMs < 3000) {
      return { ok: false, reason: "Insufficient runtime budget remaining for article extraction." };
    }

    const extractController = new AbortController();
    const extractTimeoutId = setTimeout(() => extractController.abort(), extractionTimeoutMs);

    let fetchRes: Response;
    let extractText = "";
    let article: Record<string, unknown> | null = null;

    try {
      fetchRes = await fetch(`${PROJECT_URL()}/functions/v1/fetch-news-article`, {
        method: "POST",
        headers,
        body: JSON.stringify({ url: sourceUrl }),
        signal: extractController.signal,
      });
      extractText = await fetchRes.text();
    } catch (err) {
      const isTimeout = err instanceof Error && err.name === "AbortError";
      return {
        ok: false,
        reason: isTimeout
          ? `Extraction timed out after ${Math.round(extractionTimeoutMs / 1000)}s`
          : `Extraction network error: ${err instanceof Error ? err.message : String(err)}`,
      };
    } finally {
      clearTimeout(extractTimeoutId);
    }

    try {
      article = JSON.parse(extractText);
    } catch (_) {
      return {
        ok: false,
        reason: `Extraction returned non-JSON response (HTTP ${fetchRes.status}): ${extractText.slice(0, 100)}`,
      };
    }

    if (!fetchRes.ok || !article || article.success !== true || !article.articleText) {
      const errDetail = typeof article?.error === "string" ? article.error : `HTTP ${fetchRes.status}`;
      return { ok: false, reason: `Extraction failed: ${errDetail}` };
    }

    const articleWords = String(article.articleText).split(/\s+/).filter(Boolean).length;
    if (articleWords < MIN_SOURCE_WORDS) {
      return { ok: false, reason: `Article too thin (${articleWords} words; min ${MIN_SOURCE_WORDS})` };
    }

    // 3. Image URL Extraction & Image Validation Gate
    let imageUrl: string | null = null;
    if (article.primaryImage && isValidImageUrl(article.primaryImage)) {
      imageUrl = String(article.primaryImage).trim();
    } else if (row.image_url && isValidImageUrl(row.image_url)) {
      imageUrl = String(row.image_url).trim();
    } else if (Array.isArray(article.images)) {
      for (const img of article.images) {
        if (img && isValidImageUrl(img)) {
          imageUrl = String(img).trim();
          break;
        }
      }
    }

    if (!imageUrl) {
      return { ok: false, reason: "No valid usable image URL extracted for article" };
    }

    const imageCredit = article.imageCredit
      ? String(article.imageCredit)
      : (row.image_credit ? String(row.image_credit) : String(row.source ?? "the source publication"));

    // Title and snippet metadata preparation
    const ogTitle = article.title ? tidyTitle(String(article.title)) : "";
    const currentTitle = String(row.title ?? "").trim();
    const finalTitle = (
      ogTitle.length >= 8 &&
      /[A-Za-z]{4}/.test(ogTitle) &&
      currentTitle.length >= 8 &&
      tidyTitle(currentTitle) !== ogTitle
    ) ? ogTitle : currentTitle;

    const ogDesc = article.description ? tidyTitle(String(article.description)) : "";
    const finalSnippet = (ogDesc.length >= 24 && ogDesc !== finalTitle)
      ? ogDesc.slice(0, 220)
      : (finalTitle || String(row.snippet ?? "")).slice(0, 220);

    // 4. Bengali Editorial Generation & Validation Gate
    const currentRemainingMs = getRemainingTimeMs(refreshStartTime);
    const editorTimeoutMs = Math.min(
      45000,
      Math.max(0, currentRemainingMs - FAILED_CANDIDATE_CLEANUP_RESERVE_MS)
    );
    if (editorTimeoutMs < 5000) {
      return { ok: false, reason: "Insufficient runtime budget remaining for Bengali editor." };
    }

    const editorController = new AbortController();
    const editorTimeoutId = setTimeout(() => editorController.abort(), editorTimeoutMs);

    let editorRes: Response;
    let editorText = "";
    let editorial: Record<string, unknown> | null = null;

    try {
      editorRes = await fetch(`${PROJECT_URL()}/functions/v1/bengali-news-editor`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          sourceTitle: finalTitle,
          sourceUrl,
          articleText: String(article.articleText),
        }),
        signal: editorController.signal,
      });
      editorText = await editorRes.text();
    } catch (err) {
      const isTimeout = err instanceof Error && err.name === "AbortError";
      return {
        ok: false,
        reason: isTimeout
          ? `Bengali editor timed out after ${Math.round(editorTimeoutMs / 1000)}s`
          : `Bengali editor network error: ${err instanceof Error ? err.message : String(err)}`,
      };
    } finally {
      clearTimeout(editorTimeoutId);
    }

    try {
      editorial = JSON.parse(editorText);
    } catch (_) {
      return {
        ok: false,
        reason: `Bengali editor returned non-JSON response (HTTP ${editorRes.status}): ${editorText.slice(0, 100)}`,
      };
    }

    if (!editorRes.ok || !editorial || editorial.success !== true || !editorial.headline || !editorial.body) {
      const errDetail = typeof editorial?.error === "string" ? editorial.error : `HTTP ${editorRes.status}`;
      return { ok: false, reason: `Editorial editor failed: ${errDetail}` };
    }

    const cleanHeadline = sanitizeBengaliHeadline(String(editorial.headline));
    const cleanBody = String(editorial.body ?? "").trim();
    const cleanDek = editorial.dek ? String(editorial.dek).trim() : null;

    if (!cleanHeadline || !BENGALI_CHAR.test(cleanHeadline)) {
      return { ok: false, reason: "Editorial headline missing or contains no Bengali content" };
    }

    if (!cleanBody || !BENGALI_CHAR.test(cleanBody)) {
      return { ok: false, reason: "Editorial body missing or contains no Bengali content" };
    }

    // 5. Publication Gate Passed — Insert Complete Article into DB
    const now = new Date().toISOString();
    const fullArticle: NewsItem = {
      ...row,
      title: finalTitle,
      source_title: finalTitle,
      snippet: finalSnippet,
      image_url: imageUrl,
      image_credit: imageCredit,
      bengali_headline: cleanHeadline,
      bengali_dek: cleanDek,
      bengali_body: cleanBody,
      content_hash: await contentHash(`${sourceUrl}\n${article.articleText}`),
      processing_status: "published",
      processed_at: now,
      published_at: now,
      notification_ready_at: now,
    };

    const insertRes = await rest("POST", "/rest/v1/wildlife_news", serviceKey, [fullArticle]);
    if (!insertRes.ok) {
      const errText = await insertRes.text();
      return { ok: false, reason: `Database insert failed (${insertRes.status}): ${errText.slice(0, 100)}` };
    }

    return { ok: true, publishedArticle: fullArticle };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

async function createNewsNotificationEvent(
  row: NewsItem,
  serviceKey: string,
  remainingMs: number
): Promise<void> {
  if (remainingMs < 10000) {
    console.warn(`Skipping notification processing for ${row.source_url}: remaining runtime budget too low (${Math.round(remainingMs / 1000)}s).`);
    return;
  }

  const sourceUrl = String(row.source_url ?? "");

  try {
    const newsRes = await rest(
      "GET",
      `/rest/v1/wildlife_news?select=id,bengali_headline,bengali_dek,source_url,processing_status&source_url=eq.${encodeURIComponent(sourceUrl)}&limit=1`,
      serviceKey,
    );
    if (!newsRes.ok) {
      console.warn(`Notification skipped: Could not read published article (${newsRes.status}).`);
      return;
    }
    const newsRows = (await newsRes.json()) as NewsItem[];
    const news = newsRows[0];
    if (!news || news.processing_status !== "published" || !news.bengali_headline) return;

    const eventController = new AbortController();
    const eventTimeoutId = setTimeout(() => eventController.abort(), 5000);
    let eventRes: Response;
    try {
      // Insert into unified significant_update_events pipeline
      await fetch(`${PROJECT_URL()}/rest/v1/significant_update_events?on_conflict=content_type,content_id`, {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
          Prefer: "resolution=ignore-duplicates",
        },
        body: JSON.stringify({
          content_type: "news",
          content_id: String(news.id),
          title: "📰 এখন আরণ্যক",
          body: String(news.bengali_headline),
          sound_key: "elephant_trumpet",
          payload: { type: "news", id: String(news.id), source_url: String(news.source_url ?? "") },
        }),
      }).catch(() => {});

      eventRes = await fetch(`${PROJECT_URL()}/rest/v1/news_notification_events?on_conflict=news_id`, {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
          Prefer: "resolution=ignore-duplicates,return=representation",
        },
        body: JSON.stringify({
          news_id: news.id,
          title: "📰 এখন আরণ্যক",
          body: String(news.bengali_headline),
          payload: { type: "news", id: String(news.id), source_url: String(news.source_url ?? "") },
        }),
        signal: eventController.signal,
      });
    } catch (e) {
      console.warn(`Notification event insert network error for ${sourceUrl}:`, e);
      return;
    } finally {
      clearTimeout(eventTimeoutId);
    }

    if (!eventRes.ok) {
      console.warn(`Notification event insert failed (${eventRes.status}):`, await eventRes.text());
      return;
    }

    const created = (await eventRes.json()) as NewsItem[];
    const event = created[0];
    const internalSecret = Deno.env.get("SIGNIFICANT_UPDATE_SECRET") || Deno.env.get("NEWS_NOTIFICATION_SECRET");

    if (internalSecret) {
      // Trigger universal send-significant-update
      fetch(`${PROJECT_URL()}/functions/v1/send-significant-update`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-significant-update-secret": internalSecret },
        body: JSON.stringify({ drain: true }),
      }).catch(() => {});

      if (event?.id) {
        const notifyController = new AbortController();
        const notifyTimeoutId = setTimeout(() => notifyController.abort(), 5000);
        try {
          await fetch(`${PROJECT_URL()}/functions/v1/notify-news-published`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "x-news-notification-secret": internalSecret },
            body: JSON.stringify({ eventId: String(event.id) }),
            signal: notifyController.signal,
          });
      } catch (e) {
        console.warn(`Notify function call failed for event ${event.id}:`, e);
      } finally {
        clearTimeout(notifyTimeoutId);
      }
    }
  } catch (err) {
    console.warn(`Notification creation caught unexpected error for ${sourceUrl}:`, err);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!authorized(req)) {
    return new Response(JSON.stringify({ ok: false, error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const refreshStartTime = Date.now();

  try {
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!serviceKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");

    const perSource: Record<string, number> = {};
    const fetched: NewsItem[] = [];

    // Fetch fresh items from sources with individual 8-second timeouts
    await Promise.all(SOURCES.map(async (src) => {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), SOURCE_FETCH_TIMEOUT_MS);
      try {
        const res = await fetch(src.url, {
          headers: { "User-Agent": UA, Accept: "*/*" },
          redirect: "follow",
          signal: controller.signal,
        });
        if (!res.ok) { perSource[src.name] = -res.status; return; }
        const text = await res.text();
        const items = src.kind === "rss" ? parseRss(text, src.name) : parseHtml(text, src);
        perSource[src.name] = items.length;
        fetched.push(...items);
      } catch (_) {
        perSource[src.name] = -1;
      } finally {
        clearTimeout(timeoutId);
      }
    }));

    // 2. Filter out URLs already present in the database
    const knownRes = await rest("GET", "/rest/v1/wildlife_news?select=source_url&limit=1000", serviceKey);
    const known = new Set<string>();
    if (knownRes.ok) {
      for (const row of await knownRes.json()) known.add(String(row.source_url ?? ""));
    }

    const seen = new Set<string>();
    const fresh = fetched.filter((item) => {
      const url = String(item.source_url ?? "");
      if (!url || known.has(url) || seen.has(url)) return false;
      seen.add(url);
      return true;
    });

    // 3. Deterministically score and shortlist up to 3 candidates in memory
    const scoredFresh = fresh
      .map((item) => ({ item, score: scoreCandidate(item) }))
      .sort((a, b) => b.score - a.score);

    const shortlisted: NewsItem[] = [];
    for (const entry of scoredFresh) {
      if (shortlisted.length >= SHORTLIST_LIMIT) break;
      if (!isTooSimilar(entry.item, shortlisted)) {
        shortlisted.push(entry.item);
      }
    }

    if (shortlisted.length === 0) {
      return new Response(JSON.stringify({
        ok: true,
        fetched: fetched.length,
        freshFound: fresh.length,
        shortlisted: 0,
        attempted: 0,
        published: false,
        publishedUrl: null,
        failures: [],
        perSource,
      }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 4. Process shortlisted candidates sequentially with the Publication Gate
    let publishedArticle: NewsItem | null = null;
    let attempted = 0;
    const failures: Array<{ url: string; reason: string }> = [];

    for (let i = 0; i < shortlisted.length; i++) {
      const candidate = shortlisted[i];
      const sourceUrl = String(candidate.source_url ?? "");

      // Check remaining runtime budget before processing candidate
      const remainingMs = getRemainingTimeMs(refreshStartTime);
      if (remainingMs < 15000) {
        console.warn(`Global refresh deadline approaching (${Math.round(remainingMs / 1000)}s remaining); skipping candidate ${i + 1}.`);
        break;
      }

      attempted++;
      const res = await processSingleCandidate(candidate, serviceKey, refreshStartTime);

      if (res.ok && res.publishedArticle) {
        publishedArticle = res.publishedArticle;

        // Trigger push notification event safely if runtime permits
        try {
          await createNewsNotificationEvent(publishedArticle, serviceKey, getRemainingTimeMs(refreshStartTime));
        } catch (e) {
          console.warn(`Notification event creation failed for ${sourceUrl}:`, e);
        }

        // STOP processing immediately after first successful publication
        break;
      } else {
        failures.push({
          url: sourceUrl,
          reason: res.reason ?? "unknown error",
        });
      }
    }

    return new Response(JSON.stringify({
      ok: true,
      fetched: fetched.length,
      freshFound: fresh.length,
      shortlisted: shortlisted.length,
      attempted,
      published: publishedArticle !== null,
      publishedUrl: publishedArticle ? String(publishedArticle.source_url ?? "") : null,
      failures,
      perSource,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
