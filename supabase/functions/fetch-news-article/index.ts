import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

type ArticleResult = {
  success: boolean;
  url: string;
  title: string | null;
  description: string | null;
  articleText: string | null;
  wordCount: number;
  images: string[];
  primaryImage: string | null;
  imageCredit: string | null;
  error?: string;
};

const MIN_WORDS = 120;

function authorized(req: Request): boolean {
  const expected = Deno.env.get("NEWS_REFRESH_SECRET");
  if (expected) {
    const got = req.headers.get("x-news-refresh-secret") ?? "";
    if (got === expected) return true;
  }

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

function absoluteUrl(base: string, value: string): string | null {
  try { return new URL(value, base).toString(); } catch (_) { return null; }
}

function decodeEntities(text: string): string {
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
    .replace(/&#(\d+);/g, (_m, d) => String.fromCharCode(Number(d)));
}

function repairMojibake(text: string): string {
  return text
    .replace(/\u00e2\u20ac\u2122/g, "’")
    .replace(/\u00e2\u20ac\u02dc/g, "‘")
    .replace(/\u00e2\u20ac\u0153/g, "“")
    .replace(/\u00e2\u20ac\u009d/g, "”")
    .replace(/\u00e2\u20ac\u201d/g, "—")
    .replace(/\u00e2\u20ac\u201c/g, "–")
    .replace(/\u00e2\u20ac\u00a6/g, "…")
    .replace(/\u00c2\u00b0/g, "°")
    .replace(/\u00c2/g, "");
}

function cleanText(text: string): string {
  return repairMojibake(decodeEntities(text))
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function extractMeta(html: string, name: string): string | null {
  const patterns = [
    new RegExp(`<meta[^>]+(?:property|name)=["']${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]+content=["']([^"']+)["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]*>`, "i"),
  ];
  for (const p of patterns) {
    const m = html.match(p);
    if (m?.[1]) return cleanText(m[1]);
  }
  return null;
}

function extractTitle(html: string): string | null {
  return extractMeta(html, "og:title") ?? (() => {
    const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    return m?.[1] ? cleanText(m[1].replace(/<[^>]+>/g, " ")) : null;
  })();
}

function extractImages(html: string, pageUrl: string): string[] {
  const result: string[] = [];
  const add = (value: string | null) => {
    if (!value) return;
    const url = absoluteUrl(pageUrl, decodeEntities(value.trim()));
    if (!url || !/^https?:\/\//i.test(url)) return;
    const lower = url.toLowerCase();
    if (/(logo|favicon|avatar|icon|sprite|tracking|pixel)\b/.test(lower) || lower.endsWith(".svg")) return;
    if (!result.includes(url)) result.push(url);
  };

  add(extractMeta(html, "og:image"));
  add(extractMeta(html, "og:image:url"));
  add(extractMeta(html, "twitter:image"));

  const blocks = [...html.matchAll(/<(article|main|figure)\b[^>]*>[\s\S]*?<\/\1>/gi)].map((m) => m[0]).join("\n");
  const imagePattern = /<img\b[^>]*(?:src|data-src|data-lazy-src|data-original|data-image)=["']([^"']+)["'][^>]*>/gi;
  for (const m of blocks.matchAll(imagePattern)) add(m[1]);
  const srcsetPattern = /<img\b[^>]*srcset=["']([^"']+)["'][^>]*>/gi;
  for (const m of blocks.matchAll(srcsetPattern)) {
    for (const candidate of m[1].split(",")) add(candidate.trim().split(/\s+/)[0]);
  }
  return result.slice(0, 12);
}

function extractImageCredit(html: string): string | null {
  const candidates: string[] = [];
  const patterns = [
    /<figcaption\b[^>]*>([\s\S]*?)<\/figcaption>/gi,
    /<(?:p|div|span)\b[^>]*(?:class|id)=["'][^"']*(?:caption|credit|photo-credit|image-credit)[^"']*["'][^>]*>([\s\S]*?)<\/(?:p|div|span)>/gi,
  ];
  for (const pattern of patterns) {
    for (const match of html.matchAll(pattern)) {
      const text = cleanText(match[1] ?? "");
      if (/(?:image|photo|photograph)\s+(?:by|courtesy of)|courtesy of|©|credit/i.test(text)) {
        candidates.push(text);
      }
    }
  }
  const plain = cleanText(
    html.replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " "),
  );
  const phrase = plain.match(/(?:Image|Photo|Photograph)\s+(?:by|courtesy of)\s+[^.]{2,180}\.?/i);
  if (phrase?.[0]) candidates.push(phrase[0].trim());
  return candidates.map((x) => x.replace(/\s+/g, " ").trim())
    .find((x) => x.length >= 8 && x.length <= 240) ?? null;
}

function removeNoise(html: string): string {
  return html
    .replace(/<(script|style|noscript|svg|nav|header|footer|aside|form|button|iframe|template)[^>]*>[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
}

function extractArticleText(html: string): string {
  const cleaned = removeNoise(html);
  const article = [...cleaned.matchAll(/<article\b[^>]*>([\s\S]*?)<\/article>/gi)].map((m) => m[1]).join("\n\n");
  let source = article;
  if (source.length < 1200) {
    source = [...cleaned.matchAll(/<main\b[^>]*>([\s\S]*?)<\/main>/gi)].map((m) => m[1]).join("\n\n");
  }
  if (source.length < 1200) {
    source = [...cleaned.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].map((m) => m[1]).join("\n");
  }
  return cleanText(source
    .replace(/<br\s*\/?>(?=.)/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<\/div>/gi, "\n")
    .replace(/<\/section>/gi, "\n")
    .replace(/<[^>]+>/g, " "));
}

function looksBlocked(title: string | null, text: string): boolean {
  const combined = `${title ?? ""} ${text}`.toLowerCase();
  return [
    "sign in to continue", "subscribe to continue", "subscription required",
    "paywall", "log in to read", "login to read", "please subscribe",
    "access denied", "403 forbidden", "captcha",
  ].some((x) => combined.includes(x));
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
    const url = typeof body?.url === "string" ? body.url.trim() : "";
    if (!url) throw new Error("Missing article URL.");
    const parsed = new URL(url);
    if (!/^https?:$/.test(parsed.protocol)) throw new Error("Only HTTP/HTTPS article URLs are supported.");

    const response = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; eAranyakNewsReader/2.0)",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.8",
        "Cache-Control": "no-cache",
      },
      redirect: "follow",
    });
    if (!response.ok) throw new Error(`Article request failed with HTTP ${response.status}.`);

    const bytes = new Uint8Array(await response.arrayBuffer());
    let html: string;
    try { html = new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
    catch (_) { html = new TextDecoder("windows-1252").decode(bytes); }
    if (html.length < 1000) throw new Error("The source page did not return enough HTML.");

    const title = extractTitle(html);
    const description = extractMeta(html, "og:description") ?? extractMeta(html, "description");
    const articleText = extractArticleText(html);
    const words = articleText.split(/\s+/).filter(Boolean);
    const images = extractImages(html, response.url || parsed.toString());
    const imageCredit = extractImageCredit(html);
    const blocked = looksBlocked(title, articleText);
    const readable = words.length >= MIN_WORDS && !blocked;

    const result: ArticleResult = {
      success: readable,
      url: response.url || parsed.toString(),
      title,
      description,
      articleText: readable ? articleText : null,
      wordCount: words.length,
      images,
      primaryImage: images[0] ?? null,
      imageCredit,
      error: readable ? undefined : blocked
        ? "The source appears blocked, login-gated, or subscription-gated."
        : `Only ${words.length} readable words were extracted; minimum is ${MIN_WORDS}.`,
    };

    return new Response(JSON.stringify(result), {
      status: readable ? 200 : 422,
      headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: error instanceof Error ? error.message : String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
