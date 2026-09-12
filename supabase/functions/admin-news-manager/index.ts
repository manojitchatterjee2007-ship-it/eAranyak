import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BN = /[\u0980-\u09FF]/;
const MIN_WORDS = 100;
type Action = "PREVIEW_URL" | "PUBLISH_URL" | "DELETE_NEWS" | "UNPUBLISH_NEWS" | "PUBLISH_EXISTING";

const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });

function normalizeUrl(value: string) {
  const u = new URL(value.trim());
  u.hash = "";
  u.search = "";
  return u.toString().replace(/\/+$/, "");
}

function validUrl(value: unknown) {
  try {
    const s = String(value ?? "").trim();
    return /^https?:\/\//i.test(s) && !!new URL(s);
  } catch {
    return false;
  }
}

function validImage(value: unknown) {
  const s = String(value ?? "").trim();
  if (!validUrl(s) || /^data:/i.test(s)) return false;
  if (/\b(placeholder|default-image|no-image|blank|pixel|spacer|avatar|logo|favicon)\b/i.test(s)) return false;
  return !/\.(svg|gif)($|\?)/i.test(s);
}

function cleanHeadline(value: unknown) {
  let s = String(value ?? "").trim().replace(/^\*+|\*+$/g, "").trim();
  const prefix = /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্তি|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;
  while (prefix.test(s)) s = s.replace(prefix, "").trim();
  return s;
}

function categoryFor(text: string) {
  const s = text.toLowerCase();
  if (/bird|avifaun|vulture|owl|eagle|sparrow|migration/.test(s)) return "birds";
  if (/tiger|leopard|wolf|dhole|caracal|lion|cheetah|predator|carnivore/.test(s)) return "carnivore";
  if (/elephant|rhino|gaur|deer|primate|monkey|langur|macaque/.test(s)) return "herbivore";
  if (/plant|flora|orchid|tree|forest|mangrove|biodiversity|botany/.test(s)) return "flora";
  return "climate";
}

async function sha256(value: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/* Secure authorization: Supabase validates token, then profiles.role must be admin. */
async function authorize(req: Request, url: string, serviceKey: string) {
  const m = /^Bearer\s+(.+)$/i.exec(req.headers.get("Authorization") ?? "");
  if (!m) return { ok: false, reason: "Missing or invalid Authorization header" };

  const admin = createClient(url, serviceKey);
  const { data, error } = await admin.auth.getUser(m[1].trim());
  if (error || !data.user?.id) return { ok: false, reason: "Invalid or expired Supabase authentication token" };

  const { data: profile, error: profileError } = await admin
    .from("profiles").select("role").eq("id", data.user.id).maybeSingle();

  if (profileError) return { ok: false, reason: `Unable to verify editor role: ${profileError.message}` };
  if (!profile || profile.role !== "admin") return { ok: false, reason: "User is not authorized as an editor/admin" };

  return { ok: true, userId: data.user.id };
}

async function pipeline(sourceUrl: string, supabaseUrl: string, serviceKey: string) {
  let normalized: string;
  try { normalized = normalizeUrl(sourceUrl); }
  catch { return { ok: false, error: "Invalid HTTP/HTTPS source URL" }; }
  if (!validUrl(normalized)) return { ok: false, error: "Invalid HTTP/HTTPS source URL" };

  const secret = Deno.env.get("NEWS_REFRESH_SECRET") ?? "";
  const headers = {
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    ...(secret ? { "x-news-refresh-secret": secret } : {}),
  };

  let r: Response;
  let text = "";
  try {
    r = await fetch(`${supabaseUrl}/functions/v1/fetch-news-article`, {
      method: "POST", headers, body: JSON.stringify({ url: normalized }),
    });
    text = await r.text();
  } catch (e) {
    return { ok: false, error: `Article fetch network error: ${e instanceof Error ? e.message : String(e)}` };
  }

  let article: any;
  try { article = JSON.parse(text); }
  catch { return { ok: false, error: `Fetch returned non-JSON response (HTTP ${r.status})` }; }

  if (!r.ok || article?.success !== true || !article?.articleText)
    return { ok: false, error: `Article extraction failed: ${article?.error ?? `HTTP ${r.status}`}` };

  const articleText = String(article.articleText).trim();
  const wordCount = articleText.split(/\s+/).filter(Boolean).length;
  if (wordCount < MIN_WORDS)
    return { ok: false, error: `Article is too short (${wordCount} words; minimum required is ${MIN_WORDS})` };

  let imageUrl: string | null = validImage(article.primaryImage) ? String(article.primaryImage).trim() : null;
  if (!imageUrl && Array.isArray(article.images)) {
    for (const x of article.images) if (validImage(x)) { imageUrl = String(x).trim(); break; }
  }
  if (!imageUrl) return { ok: false, error: "No valid usable image URL could be extracted for this article" };

  const host = new URL(normalized).hostname.replace(/^www\./i, "");
  const sourceTitle = article.title ? String(article.title).trim() : normalized;
  const imageCredit = article.imageCredit ? String(article.imageCredit).trim() : `Courtesy of ${host}`;

  try {
    r = await fetch(`${supabaseUrl}/functions/v1/bengali-news-editor`, {
      method: "POST",
      headers,
      body: JSON.stringify({ sourceTitle, sourceUrl: normalized, articleText }),
    });
    text = await r.text();
  } catch (e) {
    return { ok: false, error: `Bengali editor network error: ${e instanceof Error ? e.message : String(e)}` };
  }

  let editorial: any;
  try { editorial = JSON.parse(text); }
  catch { return { ok: false, error: `Bengali editor returned non-JSON response (HTTP ${r.status})` }; }

  if (!r.ok || editorial?.success !== true || !editorial?.headline || !editorial?.body)
    return { ok: false, error: `Bengali editorial generation failed: ${editorial?.error ?? `HTTP ${r.status}`}` };

  const headline = cleanHeadline(editorial.headline);
  const dek = editorial.dek ? String(editorial.dek).trim() : null;
  const body = String(editorial.body ?? "").trim();

  if (!headline || !BN.test(headline)) return { ok: false, error: "Generated headline contains no valid Bengali content" };
  if (!body || !BN.test(body)) return { ok: false, error: "Generated article body contains no valid Bengali content" };

  return {
    ok: true,
    data: { normalized, host, sourceTitle, imageUrl, imageCredit, headline, dek, body, wordCount, articleText },
  };
}

function filterByIdentifier(query: any, value: string) {
  if (/^\d+$/.test(value)) return query.or(`id.eq.${value},article_id.eq.${Number(value)}`);
  return query.eq("id", value);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ success: false, error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) return reply({ success: false, error: "Server configuration missing" }, 500);

  const auth = await authorize(req, supabaseUrl, serviceKey);
  if (!auth.ok) return reply({ success: false, error: auth.reason }, 401);

  const db = createClient(supabaseUrl, serviceKey);

  try {
    const input = await req.json();
    const action = String(input?.action ?? input?.command ?? "").toUpperCase() as Action;
    if (!action) return reply({ success: false, error: "Missing required 'action' parameter." }, 400);

    if (action === "PREVIEW_URL") {
      const url = String(input?.articleUrl ?? input?.url ?? "").trim();
      if (!url) return reply({ success: false, error: "Missing article URL" }, 400);
      const p = await pipeline(url, supabaseUrl, serviceKey);
      if (!p.ok || !p.data) return reply({ success: false, error: p.error }, 422);
      const d = p.data;
      return reply({
        success: true, action,
        preview: {
          sourceTitle: d.sourceTitle, sourceUrl: d.normalized, sourceName: d.host,
          imageUrl: d.imageUrl, imageCredit: d.imageCredit,
          bengaliHeadline: d.headline, bengaliDek: d.dek, bengaliBody: d.body,
          category: categoryFor(`${d.sourceTitle} ${d.headline}`), wordCount: d.wordCount,
        },
      });
    }

    if (action === "PUBLISH_URL") {
      const url = String(input?.articleUrl ?? input?.url ?? "").trim();
      if (!url) return reply({ success: false, error: "Missing article URL" }, 400);
      let normalized: string;
      try { normalized = normalizeUrl(url); } catch { return reply({ success: false, error: "Invalid article URL" }, 400); }

      const priority = Number.isInteger(Number(input?.editorialPriority)) ? Number(input.editorialPriority) : 10;
      const { data: existing, error: existingError } = await db
        .from("wildlife_news")
        .select("id, article_id, source_url, publication_source")
        .eq("source_url", normalized).maybeSingle();

      if (existingError) return reply({ success: false, error: existingError.message }, 500);

      // IMPORTANT: existing automated news remains automated.
      if (existing) {
        const now = new Date().toISOString();
        const { data: rows, error } = await db.from("wildlife_news")
          .update({ is_published: true, editorial_priority: priority, published_at: now })
          .eq("id", existing.id)
          .select("id, article_id, publication_source, editorial_priority, is_published, published_at");

        if (error) return reply({ success: false, error: `Failed to update existing article: ${error.message}` }, 500);
        if (!rows?.length) return reply({ success: false, error: "Article not found" }, 404);

        return reply({
          success: true, action, alreadyExisted: true, article: rows[0],
          message: "Existing article published and priority updated; original publication source preserved.",
        });
      }

      const p = await pipeline(normalized, supabaseUrl, serviceKey);
      if (!p.ok || !p.data)
        return reply({ success: false, error: `Cannot publish article: ${p.error}. Original English article was NOT published.` }, 422);

      const d = p.data;
      const publicationDate = new Date();
      const now = publicationDate.toISOString();
      const dateStr = publicationDate.toISOString().split("T")[0];

      const { data: latestArticleIdRow, error: latestArticleIdError } = await db
        .from("wildlife_news")
        .select("article_id")
        .order("article_id", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (latestArticleIdError) {
        return reply({ success: false, error: `Failed to query latest article_id: ${latestArticleIdError.message}` }, 500);
      }

      const nextArticleId = Number(latestArticleIdRow?.article_id ?? 0) + 1;

      if (!Number.isSafeInteger(nextArticleId)) {
        return reply({ success: false, error: "Generated article_id is not a safe integer" }, 500);
      }

      const row = {
        article_id: nextArticleId,
        date_str: dateStr,
        title: d.sourceTitle, source_title: d.sourceTitle,
        snippet: d.dek || d.headline, content: d.body,
        source: d.host, source_name: d.host, source_url: d.normalized,
        original_article_url: d.normalized, image_url: d.imageUrl, image_credit: d.imageCredit,
        category: categoryFor(`${d.sourceTitle} ${d.headline}`),
        bengali_headline: d.headline, bengali_dek: d.dek, bengali_body: d.body,
        publication_source: "editorial", editorial_priority: priority,
        is_published: true, created_by_editor: true, published_at: now,
        fetched_at: now, processed_at: now, notification_ready_at: now,
        processing_status: "published",
        content_hash: await sha256(`${d.normalized}\n${d.articleText}`),
      };

      const { data: inserted, error: insertErr } = await db.from("wildlife_news")
        .insert(row)
        .select("id, article_id, source_url, publication_source, editorial_priority, published_at")
        .single();

      if (insertErr || !inserted) {
        return reply({
          success: false,
          error: `Database insertion failed: ${insertErr?.message ?? "Unknown error"}`,
          code: insertErr?.code ?? null,
        }, 500);
      }

      const { error: cacheError } = await db.from("wildlife_news_translations").upsert({
        source_url: d.normalized, headline: d.headline, dek: d.dek, body: d.body,
      }, { onConflict: "source_url" });

      return reply({
        success: true, action, translationCacheWritten: !cacheError,
        translationCacheError: cacheError?.message ?? null,
        publishedArticle: inserted,
      });
    }

    if (action === "DELETE_NEWS") {
      const id = String(input?.newsId ?? input?.id ?? input?.articleId ?? "").trim();
      const sourceUrl = String(input?.sourceUrl ?? input?.url ?? "").trim();
      if (!id && !sourceUrl) return reply({ success: false, error: "Missing article identifier or sourceUrl" }, 400);

      let q: any = db.from("wildlife_news").delete();
      q = id ? filterByIdentifier(q, id) : q.eq("source_url", normalizeUrl(sourceUrl));
      const { data, error } = await q.select("id, article_id, source_url, publication_source");

      if (error) return reply({ success: false, error: `Deletion failed: ${error.message}` }, 500);
      if (!data?.length) return reply({ success: false, error: "Article not found" }, 404);

      return reply({ success: true, action, message: "Article permanently deleted.", deleted: data });
    }

    if (action === "UNPUBLISH_NEWS") {
      const id = String(input?.newsId ?? input?.id ?? input?.articleId ?? "").trim();
      if (!id) return reply({ success: false, error: "Missing article identifier" }, 400);

      let q: any = db.from("wildlife_news").update({ is_published: false });
      q = filterByIdentifier(q, id);
      const { data, error } = await q.select("id, article_id, is_published");

      if (error) return reply({ success: false, error: `Unpublish failed: ${error.message}` }, 500);
      if (!data?.length) return reply({ success: false, error: "Article not found" }, 404);
      return reply({ success: true, action, article: data[0] });
    }

    if (action === "PUBLISH_EXISTING") {
      const id = String(input?.newsId ?? input?.id ?? input?.articleId ?? "").trim();
      if (!id) return reply({ success: false, error: "Missing article identifier" }, 400);

      let q: any = db.from("wildlife_news").select(
        "id, article_id, source_url, bengali_headline, bengali_dek, bengali_body, image_url"
      );
      q = filterByIdentifier(q, id);
      const { data: article, error } = await q.maybeSingle();

      if (error || !article) return reply({ success: false, error: error ? error.message : "Article not found" }, 404);
      if (!validImage(article.image_url)) return reply({ success: false, error: "Cannot publish article: missing or invalid usable image URL." }, 422);

      let headline = cleanHeadline(article.bengali_headline);
      let dek = article.bengali_dek ? String(article.bengali_dek).trim() : null;
      let body = String(article.bengali_body ?? "").trim();

      if (!headline || !BN.test(headline) || !body || !BN.test(body)) {
        const { data: t } = await db.from("wildlife_news_translations")
          .select("headline, dek, body").eq("source_url", article.source_url).maybeSingle();
        if (t) {
          if (!headline || !BN.test(headline)) headline = cleanHeadline(t.headline);
          if (!dek && t.dek) dek = String(t.dek).trim();
          if (!body || !BN.test(body)) body = String(t.body ?? "").trim();
        }
      }

      if (!headline || !BN.test(headline)) return reply({ success: false, error: "Cannot publish article: missing valid Bengali headline." }, 422);
      if (!body || !BN.test(body) || body.length < 50) return reply({ success: false, error: "Cannot publish article: missing valid Bengali body content." }, 422);

      const now = new Date().toISOString();
      const { data, error: updateError } = await db.from("wildlife_news")
        .update({
          is_published: true, published_at: now, processing_status: "published",
          bengali_headline: headline, bengali_dek: dek, bengali_body: body,
        })
        .eq("id", article.id)
        .select("id, article_id, is_published, published_at");

      if (updateError) return reply({ success: false, error: `Publish update failed: ${updateError.message}` }, 500);
      if (!data?.length) return reply({ success: false, error: "Article not found during publish update" }, 404);
      return reply({ success: true, action, article: data[0] });
    }

    return reply({ success: false, error: `Unsupported action '${action}'` }, 400);
  } catch (e) {
    return reply({ success: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
