import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-news-refresh-secret",
};

const PROJECT_URL = () => Deno.env.get("SUPABASE_URL") ?? "";

const BENGALI_CHAR = /[\u0980-\u09FF]/;
const SCAFFOLD_LINE_RE =
  /^\s*(?:\(?para(?:graph)?\s*\d+\)?\s*[:.]|[~≈]?\s*\d+\s*words?\s*[.:]*$|dek\s+(?:refine|alternative)|headline\s+(?:refine|alternative|options?)|or\s*:|body\s+polish|final\s+check\b|word\s+count|draft\s*\d+\s*[:.])/im;
const INLINE_WORDCOUNT_RE = /\s*\(\s*[~≈]?\s*\d+\s*(?:bengali\s+)?words?\s*[.:]?\s*\)/gi;

/// Minimum Bengali words a published editorial body must have.
const MIN_BODY_WORDS = 200;

function hasScaffolding(text: string): boolean {
  const t = text ?? "";
  return SCAFFOLD_LINE_RE.test(t) || /<think>[\s\S]*<\/think>/i.test(t) ||
    /\(\s*[~≈]?\s*\d+\s*words?\s*\)/i.test(t);
}

function countBengaliWords(text: string): number {
  return String(text ?? "").split(/\s+/).filter((w) => w && BENGALI_CHAR.test(w)).length;
}

function isUsableBengaliBody(body: string): boolean {
  const t = String(body ?? "").trim();
  if (!t || !BENGALI_CHAR.test(t)) return false;
  if (hasScaffolding(t.replace(INLINE_WORDCOUNT_RE, ""))) return false;
  return countBengaliWords(t) >= MIN_BODY_WORDS;
}

const CATEGORY_PREFIX_RE = /^[\s\u00a0]*(?:পরিবেশ|বন্যপ্রাণী|প্রকৃতি|সংরক্ষণ|গবেষণা|জলবায়ু|বিজ্ঞান|প্রযুক্তি|বন|প্রাণী)\s*[:|—\-–\/]\s*/iu;

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
  const got = req.headers.get("x-news-refresh-secret") ?? "";
  if (secret && got.length > 0 && got === secret) return true;

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

type ReprocessDetail = {
  id: string;
  article_id: string | null;
  source_url: string;
  beforeHeadline: string;
  afterHeadline: string;
  beforeBodyExcerpt: string;
  afterBodyExcerpt: string;
  status: "success" | "failed";
  reason?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!authorized(req)) {
    return new Response(JSON.stringify({ ok: false, error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const refreshSecret = Deno.env.get("NEWS_REFRESH_SECRET") ?? "";
    if (!supabaseUrl || !serviceKey) throw new Error("Supabase service configuration missing.");

    const supabase = createClient(supabaseUrl, serviceKey);

    // Batch control (JSON body): { limit, offset, force }
    // limit  : how many stale articles to reprocess in this invocation (1-20, default 8)
    // offset : pagination offset into the ordered backlog
    // force  : reprocess even articles that already look good
    const reqBody = await req.json().catch(() => ({} as Record<string, unknown>));
    const limit = Math.min(Math.max(Number(reqBody?.limit) || 4, 1), 8);
    const offset = Math.max(Number(reqBody?.offset) || 0, 0);
    const force = Boolean(reqBody?.force);

    // Fetch all existing wildlife_news rows (newest first) — never deleted,
    // only their Bengali edition is regenerated.
    const { data: allRows, error: fetchErr } = await supabase
      .from("wildlife_news")
      .select("id, article_id, source_url, title, source, bengali_headline, bengali_dek, bengali_body, image_url, image_credit")
      .order("created_at", { ascending: false })
      .range(offset, offset + 2000);

    if (fetchErr) throw new Error(`Could not query wildlife_news: ${fetchErr.message}`);
    if (!allRows || allRows.length === 0) {
      return new Response(JSON.stringify({ ok: true, total: 0, reprocessed: 0, message: "No articles found." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // A row is stale when its Bengali edition is missing, carries a category
    // prefix, contains drafting scaffolding, or has a too-short body.
    const needsReprocess = (row: Record<string, unknown>): boolean => {
      if (force) return true;
      const headline = String(row.bengali_headline ?? "").trim();
      const body = String(row.bengali_body ?? "").trim();
      if (!headline || !body) return true;
      if (CATEGORY_PREFIX_RE.test(headline)) return true;
      if (hasScaffolding(headline) || hasScaffolding(body)) return true;
      return !isUsableBengaliBody(body);
    };

    const staleCount = allRows.filter(needsReprocess).length;
    const rows = allRows.filter(needsReprocess).slice(0, limit);
    if (rows.length === 0) {
      return new Response(JSON.stringify({
        ok: true,
        total: allRows.length,
        staleBacklog: 0,
        reprocessed: 0,
        message: "All articles already carry a valid Bengali edition.",
      }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const headers = {
      "Authorization": `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      "x-news-refresh-secret": refreshSecret,
    };

    let succeeded = 0;
    let failed = 0;
    const details: ReprocessDetail[] = [];

    // Process the whole batch in parallel: the slow parts (network fetches
    // and LLM generation) are async I/O, so concurrency keeps the invocation
    // wall-clock inside the Edge Function budget (150s free / 400s paid).
    async function reprocessRow(
      row: Record<string, unknown>,
    ): Promise<ReprocessDetail> {
      const sourceUrl = String(row.source_url ?? "").trim();
      const articleId = row.article_id ? String(row.article_id) : null;
      const beforeHeadline = String(row.bengali_headline ?? row.title ?? "");
      const beforeBody = String(row.bengali_body ?? "");

      if (!sourceUrl) {
        return {
          id: String(row.id),
          article_id: articleId,
          source_url: "",
          beforeHeadline,
          afterHeadline: "",
          beforeBodyExcerpt: beforeBody.slice(0, 100),
          afterBodyExcerpt: "",
          status: "failed",
          reason: "Missing source_url",
        };
      }

      try {
        // 1. Fetch clean article text
        const fetchRes = await fetch(`${PROJECT_URL()}/functions/v1/fetch-news-article`, {
          method: "POST", headers, body: JSON.stringify({ url: sourceUrl }),
        });
        const article = await fetchRes.json();
        if (!fetchRes.ok || !article.success || !article.articleText) {
          return {
            id: String(row.id),
            article_id: articleId,
            source_url: sourceUrl,
            beforeHeadline,
            afterHeadline: "",
            beforeBodyExcerpt: beforeBody.slice(0, 100),
            afterBodyExcerpt: "",
            status: "failed",
            reason: `fetch-news-article failed: ${article.error ?? fetchRes.status}`,
          };
        }

        // 2. Invoke bengali-news-editor with force: true
        const editorRes = await fetch(`${PROJECT_URL()}/functions/v1/bengali-news-editor`, {
          method: "POST", headers,
          body: JSON.stringify({
            sourceTitle: row.title ?? "",
            sourceUrl,
            articleText: article.articleText,
            force: true,
          }),
        });
        const editorial = await editorRes.json();
        if (!editorRes.ok || !editorial.success || !editorial.headline || !editorial.body) {
          return {
            id: String(row.id),
            article_id: articleId,
            source_url: sourceUrl,
            beforeHeadline,
            afterHeadline: "",
            beforeBodyExcerpt: beforeBody.slice(0, 100),
            afterBodyExcerpt: "",
            status: "failed",
            reason: `bengali-news-editor failed: ${editorial.error ?? editorRes.status}`,
          };
        }

        // 3. Sanitize headline and validate the full editorial output.
        const afterHeadline = sanitizeBengaliHeadline(String(editorial.headline));
        const afterDek = editorial.dek ? String(editorial.dek).trim() : null;
        const afterBody = String(editorial.body).trim();

        // Part 7 quality gate: publish only when headline + body are valid,
        // prefix-free, scaffold-free and long enough. Otherwise the row keeps
        // its pending status and will be retried on a later run.
        if (
          !afterHeadline || !afterBody ||
          CATEGORY_PREFIX_RE.test(afterHeadline) ||
          hasScaffolding(afterHeadline) ||
          !isUsableBengaliBody(afterBody)
        ) {
          return {
            id: String(row.id),
            article_id: articleId,
            source_url: sourceUrl,
            beforeHeadline,
            afterHeadline,
            beforeBodyExcerpt: beforeBody.slice(0, 100),
            afterBodyExcerpt: "",
            status: "failed",
            reason: "Editorial output failed the quality gate (empty/prefixed headline, scaffolding, or body under 200 Bengali words). Row left pending for retry.",
          };
        }

        // 4. Update SAME wildlife_news row (preserving id, article_id,
        //    source_url, etc.). Only Bengali fields and bookkeeping columns
        //    are touched; source metadata is preserved.
        const { error: updateNewsErr } = await supabase
          .from("wildlife_news")
          .update({
            bengali_headline: afterHeadline,
            bengali_dek: afterDek,
            bengali_body: afterBody,
            processing_status: "published",
            processed_at: new Date().toISOString(),
          })
          .eq("id", row.id);

        if (updateNewsErr) {
          return {
            id: String(row.id),
            article_id: articleId,
            source_url: sourceUrl,
            beforeHeadline,
            afterHeadline,
            beforeBodyExcerpt: beforeBody.slice(0, 100),
            afterBodyExcerpt: "",
            status: "failed",
            reason: `wildlife_news update failed: ${updateNewsErr.message}`,
          };
        }

        // 5. Update SAME wildlife_news_translations cache entry
        const { error: upsertTransErr } = await supabase
          .from("wildlife_news_translations")
          .upsert({
            source_url: sourceUrl,
            headline: afterHeadline,
            dek: afterDek,
            body: afterBody,
          }, { onConflict: "source_url" });

        if (upsertTransErr) {
          console.warn(`Translation cache write failed for ${sourceUrl}: ${upsertTransErr.message}`);
        }

        return {
          id: String(row.id),
          article_id: articleId,
          source_url: sourceUrl,
          beforeHeadline,
          afterHeadline,
          beforeBodyExcerpt: beforeBody.slice(0, 150),
          afterBodyExcerpt: afterBody.slice(0, 150),
          status: "success",
        };
      } catch (err) {
        return {
          id: String(row.id),
          article_id: articleId,
          source_url: sourceUrl,
          beforeHeadline,
          afterHeadline: "",
          beforeBodyExcerpt: beforeBody.slice(0, 100),
          afterBodyExcerpt: "",
          status: "failed",
          reason: err instanceof Error ? err.message : String(err),
        };
      }
    }

    const results = await Promise.all(rows.map((row) => reprocessRow(row)));
    for (const d of results) {
      if (d.status === "success") succeeded++;
      else failed++;
      details.push(d);
    }

    return new Response(JSON.stringify({
      ok: true,
      total: allRows.length,
      staleBacklog: staleCount,
      attempted: rows.length,
      succeeded,
      failed,
      details,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
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
