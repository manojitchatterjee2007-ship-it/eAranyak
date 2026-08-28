import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

const DAILY_LIMIT = 10;
const MAX_HISTORY = 120;
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
    name: "Sanctuary Nature Foundation", url: "https://www.sanctuarynaturefoundation.org/articles", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.sanctuarynaturefoundation\.org\/article\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "Down To Earth", url: "https://www.downtoearth.org.in/", kind: "html", maxItems: 10,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.downtoearth\.org\.in\/[a-z0-9-]+\/[^"#?]{28,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "NatGeo Traveller India", url: "https://www.natgeotraveller.in/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.nationalgeographic\.com\/travel\/article\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  { name: "Current Conservation", url: "https://www.currentconservation.org/feed/", kind: "rss" },
  {
    name: "Nature In Focus", url: "https://www.natureinfocus.in/", origin: "https://www.natureinfocus.in", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(\/(?!(?:stories|partnerships|community|search|festival|awards|productions|podcast|cdn-cgi|add-your-story)\b)[a-z0-9-]+\/[a-z0-9-]{8,}\/?)[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "India Water Portal", url: "https://www.indiawaterportal.org/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.indiawaterportal\.org\/(?:[a-z0-9-]+\/){0,2}[a-z0-9-]{25,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "PARI", url: "https://ruralindiaonline.org/en/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/ruralindiaonline\.org\/article\/[^"#?]+)"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "Gaon Connection", url: "https://www.gaonconnection.com/", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/www\.gaonconnection\.com\/[a-z0-9-]+\/[a-z0-9-]{15,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
  {
    name: "The Wire", url: "https://thewire.in/environment", kind: "html", maxItems: 8,
    linkRe: /<a[^>]+href="\s*(https?:\/\/thewire\.in\/[a-z-]+\/[a-z0-9-]{12,})"[^>]*>([\s\S]*?)<\/a>/gi,
  },
];

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

/// Removes scrape noise from titles/snippets:
/// - leading digit counters emitted by card widgets ("0 3 Environment ..."),
/// - trailing link arrows (including mojibake "â†'" for "→"),
/// - trailing " — Source Name" suffixes duplicated from <title> tags.
function tidyTitle(text: string): string {
  return clean(text)
    .replace(/â†'|â†’|→|»|›/g, " ")
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

function categoryFor(text: string): string | null {
  const l = text.toLowerCase();
  if (/bird|avifaun|vulture|owl|eagle|sparrow|nest|migration|wing|beak/.test(l)) return "birds";
  if (/tiger|leopard|wolf|dhole|caracal|lion|cheetah|predator|carnivore|panther/.test(l)) return "carnivore";
  if (/elephant|rhino|gaur|deer|herbivore|primate|monkey|langur|macaque|mammal/.test(l)) return "herbivore";
  if (/plant|flora|orchid|tree|forest|mangrove|western ghats|himalaya|biodiversity|botany|flower|seed/.test(l)) return "flora";
  if (/water|river|wetland|climate|carbon|pollution|monsoon|emission|warming|environment|ecology|conservation|sustainability|wildlife|nature|earth|ocean|habitat|reserve|sanctuary|park|zoo|ecological/.test(l)) return "climate";
  return null;
}

function baseItem(title: string, source: string, sourceUrl: string, snippet: string): NewsItem | null {
  const t = tidyTitle(title);
  const s = clean(snippet);
  const category = categoryFor(`${t} ${s}`);
  if (!t || !category) return null;
  return {
    title: t,
    source,
    source_url: sourceUrl.split("#")[0].split("?")[0],
    snippet: (s ? tidyTitle(s) : "").slice(0, 220) || t,
    content: s || t,
    image_url: null,
    image_credit: null,
    category,
    date_str: "",
    img_tags: "wildlife,nature,watercolor",
  };
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
    if (!/^https?:\/\//i.test(url) || seen.has(url)) continue;
    seen.add(url);
    // Skip evergreen links whose slug embeds an old publication year, e.g.
    // "the-best-aurora-photographs-of-2020" / "nif-photography-awards-2019".
    // Some homepages list these indefinitely and they would otherwise flood
    // wildlife_news with stale clips every refresh run.
    const currentYear = new Date().getFullYear();
    const slugYear = /(?:^|[^0-9])(20\d{2})(?:[^0-9]|$)/.exec(url);
    if (slugYear && Number(slugYear[1]) <= currentYear - 2) continue;
    // Card markup nests counters ("0", "3"), category labels ("Environment")
    // and arrows inside the anchor. Instead of concatenating everything into
    // one polluted title, split on tag boundaries and keep the longest real
    // text segment as the headline.
    const segments = (m[2] ?? "")
      .replace(/<[^>]+>/g, "\n")
      .split(/\n+/)
      .map((seg) => tidyTitle(seg))
      .filter((seg) => /[A-Za-z]/.test(seg) && seg.length >= 4);
    segments.sort((a, b) => b.length - a.length);
    const anchor = segments[0] ?? "";
    const slug = decodeURIComponent(url.split("/").filter(Boolean).pop() ?? "").replace(/-+/g, " ").trim();
    const title = anchor.length >= 12 ? anchor : slug.split(" ").slice(0, 14).join(" ");
    const item = baseItem(title, src.name, url, anchor || title);
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

function utcDayStart(): string {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  return d.toISOString();
}

/// Detects AI drafting scaffolding that leaked into cached Bengali editions,
/// e.g. "Para 1:", "(~90 words)", "DEK refine:", "Body polish", "Final check
/// on word count". These lines often mix Bengali words in, so a script-based
/// filter alone cannot catch them.
const SCAFFOLD_RE =
  /(?:^|\n)[^\n]*(?:\bpara\s*\d+\s*[:.]|\(\s*[~≈]?\s*\d+\s*words?\s*\)|^[~≈]?\s*\d+\s*words?[.:]*\s*$|\bdek\s+(?:refine|alternative)|\bbody\s+polish\b|\bfinal\s+check\b|\bi'?ll\s+go\s+with\b|\blet me\s+(?:count|refine|polish)\b)/i;

function hasScaffolding(text: string): boolean {
  return SCAFFOLD_RE.test(text ?? "");
}

async function countRows(path: string, key: string): Promise<number> {
  const res = await rest("GET", path, key);
  if (!res.ok) return 0;
  const data = await res.json();
  return Array.isArray(data) ? data.length : 0;
}

async function processArticle(row: NewsItem, serviceKey: string): Promise<{ ok: boolean; reason?: string }> {
  const secret = Deno.env.get("NEWS_REFRESH_SECRET") ?? "";
  const headers = {
    "Authorization": `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    "x-news-refresh-secret": secret,
  };
  const sourceUrl = String(row.source_url ?? "");
  try {
    const fetchRes = await fetch(`${PROJECT_URL()}/functions/v1/fetch-news-article`, {
      method: "POST", headers, body: JSON.stringify({ url: sourceUrl }),
    });
    const article = await fetchRes.json();
    if (!fetchRes.ok || !article.success || !article.articleText) {
      return { ok: false, reason: `article extraction: ${article.error ?? fetchRes.status}` };
    }

    const mediaPatch: Record<string, unknown> = {};
    // The article page is authoritative for the lead photograph. This also
    // replaces RSS thumbnails that are logos, placeholders or stale images.
    if (article.primaryImage) {
      mediaPatch.image_url = article.primaryImage;
    }
    if (article.imageCredit) {
      mediaPatch.image_credit = String(article.imageCredit);
    } else if (article.primaryImage) {
      // Plain attribution only; the app UI adds its own "Photo:" prefix.
      mediaPatch.image_credit = String(row.source ?? "the source publication");
    }
    // Repair rows whose scraped title carries homepage card noise (leading
    // counters like "0 3", category labels, " — Source" suffixes). The page's
    // og:title / og:description are clean, so adopt them when they differ.
    const ogTitle = article.title ? tidyTitle(String(article.title)) : "";
    const currentTitle = String(row.title ?? "").trim();
    if (
      ogTitle.length >= 8 &&
      /[A-Za-z]{4}/.test(ogTitle) &&
      currentTitle.length >= 8 &&
      (tidyTitle(currentTitle) !== ogTitle)
    ) {
      mediaPatch.title = ogTitle;
    }
    const ogDesc = article.description ? tidyTitle(String(article.description)) : "";
    if (ogDesc.length >= 24 && ogDesc !== ogTitle) {
      mediaPatch.snippet = ogDesc.slice(0, 220);
    } else if (mediaPatch.title) {
      mediaPatch.snippet = ogTitle;
    }
    if (Object.keys(mediaPatch).length > 0) {
      await rest("PATCH", `/rest/v1/wildlife_news?source_url=eq.${encodeURIComponent(sourceUrl)}`, serviceKey, mediaPatch);
    }

    const editorRes = await fetch(`${PROJECT_URL()}/functions/v1/bengali-news-editor`, {
      method: "POST", headers,
      body: JSON.stringify({
        // Prefer the clean page title over any scraped homepage noise.
        sourceTitle: mediaPatch.title ?? row.title,
        sourceUrl,
        articleText: article.articleText,
      }),
    });
    const editorial = await editorRes.json();
    if (!editorRes.ok || !editorial.success) {
      return { ok: false, reason: `editor: ${editorial.error ?? editorRes.status}` };
    }
    return { ok: true };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
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

  try {
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!serviceKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");

    const start = utcDayStart();
    const perSource: Record<string, number> = {};
    const fetched: NewsItem[] = [];

    await Promise.all(SOURCES.map(async (src) => {
      try {
        const res = await fetch(src.url, { headers: { "User-Agent": UA, Accept: "*/*" }, redirect: "follow" });
        if (!res.ok) { perSource[src.name] = -res.status; return; }
        const text = await res.text();
        const items = src.kind === "rss" ? parseRss(text, src.name) : parseHtml(text, src);
        perSource[src.name] = items.length;
        fetched.push(...items);
      } catch (_) {
        perSource[src.name] = -1;
      }
    }));

    // Existing URLs prevent duplicates.
    const knownRes = await rest("GET", "/rest/v1/wildlife_news?select=source_url&limit=500", serviceKey);
    const known = new Set<string>();
    if (knownRes.ok) for (const row of await knownRes.json()) known.add(String(row.source_url ?? ""));

    const seen = new Set<string>();
    const fresh = fetched.filter((item) => {
      const url = String(item.source_url ?? "");
      if (!url || known.has(url) || seen.has(url)) return false;
      seen.add(url);
      return true;
    });

    const insertedToday = await countRows(`/rest/v1/wildlife_news?select=id&created_at=gte.${encodeURIComponent(start)}&limit=100`, serviceKey);
    const intakeRemaining = Math.max(0, DAILY_LIMIT - insertedToday);
    const intake = fresh.slice(0, intakeRemaining);

    if (intake.length > 0) {
      const insertRes = await rest("POST", "/rest/v1/wildlife_news", serviceKey, intake);
      if (!insertRes.ok) {
        const errorText = await insertRes.text();
        throw new Error(`wildlife_news insert failed (${insertRes.status}): ${errorText.slice(0, 1000)}`);
      }

      // ---------------------------------------------------------------
      // Notify all users that fresh wildlife articles are available.
      // Delegated to the notify-users edge function (already handles FCM
      // auth + token cleanup). Only INSERT triggers a push — deletions
      // never notify. Best-effort: a notification failure must not fail
      // the refresh run.
      // ---------------------------------------------------------------
      try {
        const freshest = await rest(
          "GET",
          "/rest/v1/wildlife_news?select=id,title,snippet&order=created_at.desc&limit=1",
          serviceKey,
        );
        if (freshest.ok) {
          const rows = (await freshest.json()) as Array<Record<string, unknown>>;
          const top = rows[0];
          const head = String(top?.title ?? "").slice(0, 90);
          await fetch(`${PROJECT_URL()}/functions/v1/notify-users`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-earanyak-key": "earanyak-notify-2026",
            },
            body: JSON.stringify({
              title: "নতুন বন্যপ্রাণ সংবাদ",
              body: head
                ? `${head} — পড়তে ট্যাপ করুন।`
                : "শেয়ার সি নতুন খবর এসেছে — পড়তে ট্যাপ করুন।",
              data: {
                type: "news",
                id: String(top?.id ?? ""),
                title: head,
              },
            }),
          });
        }
      } catch (_) {
        // Best-effort — never fail the refresh because of a push error.
      }
    }

    // Work from the newest history, not only the rows inserted in this run.
    const latestRes = await rest("GET", `/rest/v1/wildlife_news?select=*&order=created_at.desc&limit=${MAX_HISTORY}`, serviceKey);
    if (!latestRes.ok) throw new Error(`Could not read wildlife_news (${latestRes.status}).`);
    const latestRows = await latestRes.json() as NewsItem[];

    const urls = latestRows.map((r) => String(r.source_url ?? "")).filter(Boolean);
    const encodedUrls = urls.map((u) => encodeURIComponent(u)).join(",");
    const translated = new Set<string>();
    if (encodedUrls) {
      const trRes = await rest("GET", `/rest/v1/wildlife_news_translations?select=source_url,body&source_url=in.(${encodedUrls})`, serviceKey);
      if (trRes.ok) {
        for (const row of await trRes.json()) {
          const body = String(row.body ?? "").trim();
          const bodyWords = body.split(/\s+/).filter(Boolean).length;
          // Reprocess older short editorials after the new length target.
          // Scaffold-polluted bodies (leaked "Para 1:" style drafts) are also
          // treated as untranslated so they get regenerated from scratch.
          if (bodyWords >= 280 && !hasScaffolding(body)) translated.add(String(row.source_url ?? ""));
        }
      }
    }

    const translatedToday = await countRows(`/rest/v1/wildlife_news_translations?select=source_url&created_at=gte.${encodeURIComponent(start)}&limit=100`, serviceKey);
    const generationRemaining = Math.max(0, DAILY_LIMIT - translatedToday);

    // Also revisit recent rows that have no real source photograph/credit.
    // This backfills media for older articles without making the Flutter app
    // call the protected article-fetching function with a secret.
    const mediaCandidates = latestRows.filter((row) => {
      const url = String(row.source_url ?? "");
      const image = String(row.image_url ?? "").trim();
      const credit = String(row.image_credit ?? "").trim();
      return url && (!image || !credit);
    }).slice(0, 20);

    const translationCandidates = latestRows.filter((row) => {
      const url = String(row.source_url ?? "");
      return url && !translated.has(url);
    }).slice(0, generationRemaining);

    const processMap = new Map<string, NewsItem>();
    for (const row of mediaCandidates) processMap.set(String(row.source_url), row);
    for (const row of translationCandidates) processMap.set(String(row.source_url), row);
    const toProcess = [...processMap.values()];

    let generated = 0;
    let mediaUpdated = 0;
    const failures: Array<{ url: string; reason: string }> = [];
    for (const row of toProcess) {
      const result = await processArticle(row, serviceKey);
      if (result.ok) {
        if (translationCandidates.some((r) => String(r.source_url) === String(row.source_url))) generated++;
        if (mediaCandidates.some((r) => String(r.source_url) === String(row.source_url))) mediaUpdated++;
      } else failures.push({ url: String(row.source_url), reason: result.reason ?? "unknown" });
      if (Date.now() % 2 === 0) await new Promise((resolve) => setTimeout(resolve, 150));
    }

    return new Response(JSON.stringify({
      ok: true,
      dailyLimit: DAILY_LIMIT,
      fetched: fetched.length,
      freshFound: fresh.length,
      insertedThisRun: intake.length,
      insertedTodayAfterRun: insertedToday + intake.length,
      generatedThisRun: generated,
      generatedTodayBeforeRun: translatedToday,
      generatedTodayAfterRun: translatedToday + generated,
      mediaUpdatedThisRun: mediaUpdated,
      pendingCandidates: toProcess.length - generated - failures.length,
      failures,
      perSource,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
