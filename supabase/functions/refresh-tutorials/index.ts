import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { translateArticle } from "../_shared/translation/index.ts";
import { countWords, BENGALI_CHAR } from "../_shared/translation/validate.ts";
import { resolveArticleImage } from "../_shared/image/decision.ts";
import {
  generateIllustration,
  storeIllustration,
  removeStoredIllustration,
  extractIllustrationFacts,
  seedForArticle,
} from "../_shared/image/pollinations.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-tutorial-refresh-secret, x-news-refresh-secret",
};

// --- STRICT LIMITS FOR 100% FREE TIER ---
const TARGET_TUTORIAL_COUNT = 5;
// Reduced to 1 to guarantee the AI has plenty of time to write extremely long-form tutorials
const MAX_CREATIONS_PER_RUN = 1; 
const GLOBAL_RUN_TIMEOUT_MS = 40000;
const MIN_SOURCE_WORDS = 150;
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

type SourceDef = {
  name: string;
  url: string;
  kind: "rss" | "html";
  linkFilter?: string;
};

// NEW SOURCES: Strictly focused on Animal ID, Ecology, and Wildlife Photography
const SOURCES: SourceDef[] = [
  { name: "All About Birds - ID", url: "https://www.allaboutbirds.org/news/category/bird-id-skills/feed/", kind: "rss" },
  { name: "Mongabay - Wildlife", url: "https://india.mongabay.com/category/environment/wildlife-biodiversity/feed/", kind: "rss" },
  { name: "Photography Life", url: "https://photographylife.com/category/wildlife-photography/feed", kind: "rss" },
  { name: "PetaPixel - Guides", url: "https://petapixel.com/category/guides/feed/", kind: "rss" },
  { name: "RG Sustain - Explainers", url: "https://roundglasssustain.com/explainers", kind: "html", linkFilter: "/explainers/" },
  { name: "RG Sustain - Species", url: "https://roundglasssustain.com/species", kind: "html", linkFilter: "/species/" }
];

function getRemainingMs(start: number): number {
  return Math.max(0, GLOBAL_RUN_TIMEOUT_MS - (Date.now() - start));
}

function authorized(req: Request): boolean {
  const secret = Deno.env.get("TUTORIAL_REFRESH_SECRET") || Deno.env.get("NEWS_REFRESH_SECRET");
  const provided = req.headers.get("x-tutorial-refresh-secret") || req.headers.get("x-news-refresh-secret");
  if (secret && provided === secret) return true;

  const auth = req.headers.get("Authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) return false;
  try {
    const rawB64 = m[1].trim().split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(rawB64 + "=".repeat((4 - rawB64.length % 4) % 4)));
    const projectRef = new URL(Deno.env.get("SUPABASE_URL") ?? "http://invalid.invalid").hostname.split(".")[0];
    const iss = String(payload?.iss ?? "");
    return String(payload?.ref ?? "") === projectRef || iss.includes(projectRef);
  } catch (_) {
    return false;
  }
}

function normalizeUrl(raw: string): string {
  try {
    const u = new URL(raw.trim());
    u.hash = "";
    u.search = "";
    return u.toString();
  } catch (_) {
    return raw.trim();
  }
}

function clean(text: string): string {
  return text.replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ").trim();
}

async function fetchWithTimeout(url: string, timeoutMs = 8000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { 
      headers: { 
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
      }, 
      signal: controller.signal 
    });
  } finally {
    clearTimeout(timer);
  }
}

function slugForUrl(url: string): string {
  try {
    const u = new URL(url);
    const parts = u.pathname.split("/").filter(Boolean);
    const last = parts[parts.length - 1] ?? "tutorial";
    return last.toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 60) || "tutorial";
  } catch (_) {
    return "tutorial";
  }
}

async function discoverCandidates(debugLog: string[]): Promise<Array<{ title: string; url: string; sourceName: string }>> {
  const candidates: Array<{ title: string; url: string; sourceName: string }> = [];

  const promises = SOURCES.map(async (src) => {
    try {
      const res = await fetchWithTimeout(src.url, 8000);
      if (!res.ok) {
        debugLog.push(`[${src.name}] HTTP ${res.status}`);
        return;
      }

      const html = await res.text();
      let count = 0;

      if (src.kind === "rss") {
        const itemMatches = Array.from(html.matchAll(/<(?:item|entry)[^>]*>([\s\S]*?)<\/(?:item|entry)>/gi));
        for (const itemMatch of itemMatches) {
          const itemContent = itemMatch[1];
          const titleMatch = itemContent.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
          const linkMatchHref = itemContent.match(/<link[^>]*href=["']([^"']+)["'][^>]*>/i);
          const linkMatchTag = itemContent.match(/<link[^>]*>([\s\S]*?)<\/link>/i);
          
          let link = linkMatchHref ? linkMatchHref[1] : (linkMatchTag ? linkMatchTag[1] : "");

          if (titleMatch && link) {
            const title = clean(titleMatch[1].replace(/<!\[CDATA\[\vert{}\]\]>/g, ""));
            const finalLink = normalizeUrl(link.replace(/<!\[CDATA\[\vert{}\]\]>/g, ""));
            if (finalLink && title.length > 5) {
              candidates.push({ title, url: finalLink, sourceName: src.name });
              count++;
            }
          }
        }
      } else if (src.kind === "html" && src.linkFilter) {
        const matches = Array.from(html.matchAll(/<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi));
        for (const m of matches) {
          let link = m[1];
          if (!link.includes(src.linkFilter)) continue;
          
          if (link.startsWith("/")) {
            try {
              const u = new URL(src.url);
              link = `${u.protocol}//${u.host}${link}`;
            } catch (_) { continue; }
          }
          link = normalizeUrl(link);
          const title = clean(m[2] ?? "");
          
          if (link.includes('/tag/') || link.includes('/category/') || link.includes('/author/') || link.includes('/page/')) continue;
          
          if (link) {
            candidates.push({ title: title || "Wildlife Guide", url: link, sourceName: src.name });
            count++;
          }
        }
      }
      debugLog.push(`[${src.name}] Found ${count}`);
    } catch (err) {
      debugLog.push(`[${src.name}] Error: ${String(err)}`);
    }
  });

  await Promise.all(promises);

  const unique = [];
  const seen = new Set();
  for (const c of candidates) {
    if (!seen.has(c.url)) {
      seen.add(c.url);
      unique.push(c);
    }
  }
  return unique;
}

async function fetchArticleContent(url: string): Promise<{ title: string; text: string; imageUrl: string | null }> {
  try {
    const res = await fetchWithTimeout(url, 8000);
    if (!res.ok) return { title: "", text: "", imageUrl: null };
    const html = await res.text();

    const ogTitle = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)?.[1];
    const tagTitle = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
    const title = clean(ogTitle || tagTitle || "");

    const ogImg = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)?.[1];
    let imageUrl: string | null = null;
    if (ogImg) {
      try {
        imageUrl = new URL(ogImg, url).toString();
      } catch (_) {}
    }

    const text = clean(html);
    return { title, text, imageUrl };
  } catch (_) {
    return { title: "", text: "", imageUrl: null };
  }
}

async function generateBengaliTutorial(title: string, sourceText: string, sourceName: string): Promise<{
  title: string;
  snippet: string;
  description: string;
  category: string;
  difficulty: string;
  durationMinutes: number;
}> {
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY") || Deno.env.get("OPENAI_API_KEY");
  if (!openRouterKey) throw new Error("Missing AI API Key");

  // NEW PROMPT: Forces AI to generate 6 to 8 paragraphs of rich, long-form content
  const prompt = `You are the Chief Educational Editor of eAranyak (eআরণ্যক), an expert in wildlife, nature, forestry, and environmental conservation education in India.
Transform the following English source article from "${sourceName}" into a comprehensive, authoritative, natural Bengali tutorial / learning guide in polite Cholitobhasha.

SOURCE TITLE: ${title}
SOURCE CONTENT:
${sourceText.slice(0, 5000)}

REQUIREMENTS:
1. Create a compelling, professional Bengali tutorial title (WITHOUT category prefixes).
2. Create a concise 1-sentence snippet summarizing the tutorial.
3. Write a HIGHLY DETAILED, comprehensive tutorial description in 6 to 8 paragraphs. This must be a long-form article (at least 400-500 words). Include deep explanations, step-by-step guides, behavioral traits (for animals), or camera settings/techniques (for photography).
4. Select category: 'Wildlife', 'Conservation', 'Flora', 'Ecology', 'Photography' or 'General'.
5. Select difficulty: 'beginner', 'intermediate', or 'advanced'.
6. Estimate duration in minutes (e.g., 5 to 15).

Return valid JSON with keys:
{
  "title": "...",
  "snippet": "...",
  "description": "...",
  "category": "...",
  "difficulty": "...",
  "duration_minutes": 8
}
`;

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openRouterKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://earanyak.app", 
      "X-Title": "eAranyak",
    },
    body: JSON.stringify({
      model: "google/gemini-2.0-flash-exp:free",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.3,
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`HTTP ${response.status}: ${errText}`);
  }

  const json = await response.json();
  const content = json.choices?.[0]?.message?.content ?? "";
  const jsonMatch = content.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("Invalid AI JSON format");

  const parsed = JSON.parse(jsonMatch[0]);
  return {
    title: parsed.title || title,
    snippet: parsed.snippet || "বন্যপ্রাণী ও প্রকৃতি সংরক্ষণের একটি গুরুত্বপূর্ণ নির্দেশিকা।",
    description: parsed.description || sourceText.slice(0, 1000),
    category: parsed.category || "Conservation",
    difficulty: parsed.difficulty || "beginner",
    durationMinutes: Number(parsed.duration_minutes) || 8,
  };
}

function snippetFromBengali(body: string, maxChars = 170): string {
  const firstParagraph = body.split(/\n{2,}/)[0].trim();
  const sentences = firstParagraph.split(/(?<=[।.!?])\s+/).filter(Boolean);
  let snippet = "";
  for (const s of sentences) {
    if ((snippet + " " + s).trim().length > maxChars) break;
    snippet = (snippet ? snippet + " " : "") + s;
  }
  return snippet.trim() || firstParagraph.slice(0, maxChars);
}

function deriveTutorialMetadata(title: string, text: string) {
  const scope = `${title} ${text.slice(0, 2000)}`.toLowerCase();
  const category =
    /\b(photography|camera|lens|iso|shutter|aperture|exposure)\b/.test(scope) ? "Photography"
    : /\b(tiger|elephant|leopard|bird|heron|dolphin|crocodile|turtle|species|mammal|amphibian|reptile|insect|butterfly)\b/.test(scope) ? "Wildlife"
    : /\b(conservation|protect|reserve|sanctuary|project tiger|iucn|poaching)\b/.test(scope) ? "Conservation"
    : /\b(forest|tree|flora|plant|orchid|bamboo)\b/.test(scope) ? "Flora"
    : /\b(ecosystem|habitat|biodiversity|ecology|wetland|mangrove|climate)\b/.test(scope) ? "Ecology"
    : "General";
  const words = countWords(text);
  const difficulty = words > 900 ? "advanced" : words > 450 ? "intermediate" : "beginner";
  const durationMinutes = Math.min(15, Math.max(5, Math.ceil(words / 130)));
  return { category, difficulty, durationMinutes };
}

async function safeResolveImage(
  admin: ReturnType<typeof createClient>,
  title: string,
  articleText: string,
  sourceImageUrl: string | null,
  budgetMs: number,
): Promise<{ thumbnailUrl: string | null; provenance: string | null; source: string; reason?: string }> {
  try {
    const outcome = await resolveArticleImage({
      sourceImageUrl,
      budgetMs,
      minGenerationBudgetMs: 12000,
      generate: async () => {
        const facts = extractIllustrationFacts(title, articleText);
        const subject = facts.mainSubject || title.split(" ").slice(0, 4).join(" ");
        const prompt = `A highly detailed, realistic watercolor painting of ${subject}. Scientific wildlife illustration, field guide aesthetic, masterpiece.`;
        const gen = await generateIllustration(prompt, seedForArticle(title), Math.min(budgetMs, 60000));
        if (!gen.ok || !gen.bytes || !gen.mime) return { ok: false, reason: gen.reason ?? "failed" };
        return { ok: true, bytes: gen.bytes, mime: gen.mime };
      },
      store: async (bytes, mime) => {
        const stored = await storeIllustration(admin, bytes, mime, slugForUrl(title));
        if (!stored.ok || !stored.publicUrl) return { ok: false, reason: stored.reason ?? "storage failed" };
        return { ok: true, publicUrl: stored.publicUrl };
      },
    });
    
    return {
      thumbnailUrl: outcome.url,
      provenance: outcome.provenance === "none" ? null : outcome.provenance,
      source: outcome.source,
      reason: outcome.reason,
    };
  } catch (err) {
    return { thumbnailUrl: null, provenance: null, source: "error", reason: String(err) };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!authorized(req)) {
    return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" }});
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const debugLog: string[] = [];

  try {
    const runStart = Date.now();
    const bodyPayload: unknown = await req.json().catch(() => ({}));
    const runMode = String((bodyPayload as { mode?: unknown } | null)?.mode ?? "").toLowerCase();
    const backfillOnly = runMode === "backfill";

    const { data: existingTutorials, error: fetchErr } = await supabase
      .from("tutorials")
      .select("id, source_url, thumbnail_url, image_provenance, created_at, is_published")
      .order("created_at", { ascending: true });
    
    if (fetchErr) {
      debugLog.push(`DB Fetch Error: ${JSON.stringify(fetchErr)}`);
      throw new Error("Failed to load existing tutorials");
    }

    const allTutorials = existingTutorials ?? [];
    const publishedTutorials = allTutorials.filter((t: any) => t.is_published === true);
    const existingSourceUrls = new Set(allTutorials.map((t: any) => String(t.source_url ?? "").trim()).filter(Boolean));

    const candidates = await discoverCandidates(debugLog);
    const newCandidates = candidates.filter((c) => {
      const normalized = normalizeUrl(c.url);
      return normalized && !existingSourceUrls.has(normalized);
    });

    const deficit = Math.max(0, TARGET_TUTORIAL_COUNT - publishedTutorials.length);
    const rotationActive = !backfillOnly && publishedTutorials.length >= TARGET_TUTORIAL_COUNT;
    let targetCreations = 0;
    if (deficit > 0) targetCreations = Math.min(deficit, MAX_CREATIONS_PER_RUN);
    else if (rotationActive) targetCreations = 1;

    if (targetCreations === 0) {
      return new Response(JSON.stringify({
        success: true,
        runMode: runMode || "default",
        createdCount: 0,
        deletedCount: 0,
        publishedCountNow: publishedTutorials.length,
        candidatesFound: candidates.length,
        newCandidatesReady: newCandidates.length,
        debugLog,
        results: ["Pool already at target; nothing to do."],
        failures: [],
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" }});
    }

    const results: string[] = [];
    const failures: Array<{ url: string; reason: string }> = [];
    let createdCount = 0;
    let deletedCount = 0;

    for (const candidate of newCandidates) {
      if (createdCount >= targetCreations) break;
      
      if (getRemainingMs(runStart) < 20000) {
        results.push("Time budget reached; stopping gracefully to prevent timeout.");
        break;
      }

      const candidateUrl = normalizeUrl(candidate.url);
      
      try {
        const article = await fetchArticleContent(candidateUrl);
        const articleText = (article.text ?? "").trim();
        if (!articleText || countWords(articleText) < MIN_SOURCE_WORDS) {
          failures.push({ url: candidateUrl, reason: "article too short or unreadable" });
          continue;
        }
        
        const englishTitle = (article.title || candidate.title || "Wildlife Tutorial").trim();

        let finalTitle = "";
        let finalSnippet = "";
        let finalDescription = "";
        let category = "";
        let difficulty = "";
        let durationMinutes = 0;
        let providerUsed = "none";

        let translation: any = { ok: false };
        try {
          translation = await translateArticle({
            title: englishTitle,
            // Provide 5000 chars context to ensure long-form output
            articleText: articleText.slice(0, 5000), 
            budgetMs: Math.max(5000, Math.min(15000, getRemainingMs(runStart) - 20000)),
          });
        } catch (transErr) {
          debugLog.push(`[Translation] ${candidateUrl}: ${String(transErr)}`);
        }

        if (translation && translation.ok) {
          providerUsed = translation.provider ?? "mt";
          finalTitle = translation.headline ?? englishTitle;
          finalDescription = translation.body ?? articleText.slice(0, 5000);
          finalSnippet = snippetFromBengali(finalDescription);
          const meta = deriveTutorialMetadata(englishTitle, articleText);
          category = meta.category;
          difficulty = meta.difficulty;
          durationMinutes = meta.durationMinutes;
        } else {
          try {
            const aiData = await generateBengaliTutorial(englishTitle, articleText, candidate.sourceName);
            finalTitle = aiData.title;
            finalSnippet = aiData.snippet;
            finalDescription = aiData.description;
            category = aiData.category;
            difficulty = aiData.difficulty;
            durationMinutes = aiData.durationMinutes;
            providerUsed = "ai_editorial_free";
            
            if (!BENGALI_CHAR.test(finalTitle) || !BENGALI_CHAR.test(finalDescription)) {
              failures.push({ url: candidateUrl, reason: "AI fallback produced non-Bengali content" });
              continue;
            }
          } catch (aiErr) {
            failures.push({ url: candidateUrl, reason: `Free AI failed: ${String(aiErr)}` });
            continue;
          }
        }

        const image = await safeResolveImage(
          supabase,
          englishTitle,
          articleText,
          article.imageUrl,
          getRemainingMs(runStart) - 5000,
        );

        if (!BENGALI_CHAR.test(finalTitle) || !BENGALI_CHAR.test(finalDescription)) {
          failures.push({ url: candidateUrl, reason: "publication gate: Bengali content missing" });
          continue;
        }

        const now = new Date().toISOString();
        const insertPayload = {
          title: finalTitle,
          snippet: finalSnippet || finalDescription.split(/\n{2,}/)[0].slice(0, 170),
          description: finalDescription,
          thumbnail_url: image.thumbnailUrl,
          image_provenance: image.provenance,
          translation_provider: providerUsed,
          resource_url: candidateUrl,
          resource_type: "external",
          category: category || "General",
          difficulty: difficulty || "beginner",
          duration_minutes: durationMinutes || 8,
          editorial_priority: 10,
          is_featured: false,
          is_published: true,
          published_at: now,
          source_url: candidateUrl,
          source_name: candidate.sourceName,
          source_article_id: slugForUrl(candidateUrl),
          created_at: now,
          updated_at: now,
        };

        const { data: newTutorial, error: insertErr } = await supabase
          .from("tutorials")
          .insert(insertPayload)
          .select("id, title")
          .single();

        if (insertErr || !newTutorial) {
          failures.push({ url: candidateUrl, reason: `insert failed: ${JSON.stringify(insertErr)}` });
          if (image.provenance === "ai_generated" && image.thumbnailUrl) {
            try { await removeStoredIllustration(supabase, image.thumbnailUrl); } catch (_) {}
          }
          continue;
        }

        createdCount++;
        results.push(`Published "${finalTitle.slice(0, 48)}"`);

        if (rotationActive) {
          const remainingPublished = allTutorials
            .filter((t: any) => t.is_published === true && t.id !== newTutorial.id)
            .sort((a: any, b: any) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
            
          const oldest = remainingPublished[0];
          if (oldest) {
            const { error: delErr } = await supabase.from("tutorials").delete().eq("id", oldest.id);
            if (!delErr) {
              deletedCount++;
              if (oldest.image_provenance === "ai_generated" && oldest.thumbnail_url) {
                try { await removeStoredIllustration(supabase, oldest.thumbnail_url); } catch (_) {}
              }
            }
          }
        }
        
      } catch (fatalLoopError) {
        debugLog.push(`[Processing Crash] ${candidateUrl}: ${String(fatalLoopError)}`);
        failures.push({ url: candidateUrl, reason: "Internal script crash during processing" });
      }
    }

    return new Response(JSON.stringify({
      success: true,
      runMode: runMode || "default",
      createdCount,
      deletedCount,
      publishedCountNow: publishedTutorials.length - deletedCount + createdCount,
      publishedBefore: publishedTutorials.length,
      targetCreations,
      candidatesFound: candidates.length,
      newCandidatesReady: newCandidates.length,
      debugLog,
      results,
      failures,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
    
  } catch (err) {
    debugLog.push(`Global Function Error: ${String(err)}`);
    return new Response(JSON.stringify({ success: false, error: String(err), debugLog }), {
      status: 200, 
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});