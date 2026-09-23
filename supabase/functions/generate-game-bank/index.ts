import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("GEMINI_GAME_MODEL") || "gemini-3.1-flash-lite";
const GENERATION_COUNT = 8;
const CATEGORIES = ["photo", "audio", "hint", "scramble"] as const;

type Category = typeof CATEGORIES[number];

const NATURESBOOK_BIRD_NAMES_URL = "https://naturesbook.in/bird-names-in-bengali/";

type BirdName = { english: string; bengali: string };
const wordImageCache = new Map<string, { url: string; source: string; attribution: string | null } | null>();

async function fetchNaturesBookBirdNames(): Promise<BirdName[]> {
  const response = await fetch(NATURESBOOK_BIRD_NAMES_URL, {
    headers: { "User-Agent": "eAranyakGameGenerator/1.0" },
  });
  if (!response.ok) throw new Error(`Nature's Book bird-name list HTTP ${response.status}`);

  const html = await response.text();
  // Preserve HTML block/list boundaries as separators. Removing every tag
  // directly can join the last Bengali name of one group to the next group
  // heading and corrupt the name parser.
  const text = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<(br|hr|p|\/p|li|\/li|div|\/div|h[1-6]|\/h[1-6])\b[^>]*>/gi, " | ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&#8211;|&#x2013;/gi, "–")
    .replace(/&#8212;|&#x2014;/gi, "—")
    .replace(/\s+/g, " ");

  const birds: BirdName[] = [];
  const seen = new Set<string>();

  // The page lists entries as: "1. English name – Bengali name". The
  // separator inserted above keeps each HTML list/paragraph boundary intact.
  const re = /\b\d+\.\s*([A-Za-z][A-Za-z'’().,\-\s]{1,80}?)\s*[–—-]\s*([\u0980-\u09FF][^|]{1,100}?)(?=\s*\||$)/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(text)) !== null) {
    const english = clean(match[1]).replace(/\s+/g, " ");
    const bengali = clean(match[2]).replace(/\s+/g, " ");
    if (!english || !containsBengali(bengali)) continue;
    const key = `${normalize(english)}|${normalize(bengali)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    // Nature's Book may list several Bengali aliases. Use the first listed
    // name consistently so the puzzle has one deterministic answer.
    birds.push({ english, bengali: bengali.split(",")[0].split("/")[0].trim() });
  }

  if (birds.length < 50) {
    throw new Error(`Nature's Book bird-name list could not be parsed reliably (${birds.length} names).`);
  }
  return birds;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function clean(value: unknown): string { return typeof value === "string" ? value.trim() : ""; }
function containsBengali(value: string): boolean { return /[\u0980-\u09FF]/.test(value); }
function normalize(value: string): string { return value.toLowerCase().replace(/[^a-z0-9\u0980-\u09ff]+/gi, " ").trim(); }

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extractJson(text: string): any {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim();
  const candidate = fenced || text.trim();
  try { return JSON.parse(candidate); } catch (_) {}
  const start = candidate.indexOf("[");
  const end = candidate.lastIndexOf("]");
  if (start >= 0 && end > start) return JSON.parse(candidate.slice(start, end + 1));
  throw new Error("Gemini did not return valid JSON.");
}

async function geminiGenerate(apiKey: string): Promise<any[]> {
  const prompt = `You generate educational wildlife game content for eAranyak, an Indian Bengali nature-learning app.
Return EXACTLY ${GENERATION_COUNT} NEW game records as a JSON array. Generate exactly 2 records for each category: photo, audio, hint, scramble. Do NOT generate word records; the Bengali bird-name bank is synchronized deterministically from Nature's Book.

GLOBAL RULES:
- Focus on Indian wildlife, birds, reptiles, amphibians, mammals, conservation species, and Indian natural history.
- Never invent a species, Bengali name, fact, state, habitat, or conservation status.
- Use common English species names that are searchable on iNaturalist/Wikimedia Commons.
- Bengali text must be natural contemporary Bengali.
- Do not repeat the same species within this batch.
- Every record must be self-contained.

PHOTO:
- identify an animal/bird from a photograph.
- options must contain exactly 4 Bengali-first labels in the form "বাংলা নাম (English name)".
- answer must exactly equal one option.

AUDIO:
- bird-call identification only.
- options exactly 4 Bengali-first labels; answer exactly one option.

HINT:
- 3 progressively useful factual Bengali hints.
- options exactly 4 Bengali-first labels; answer exactly one option.

SCRAMBLE:
- an image-based 3x3 puzzle.
- species must be an Indian wildlife species and image-searchable.
- no options required; answer is the English species name.

Return objects with exactly these keys:
{
  "category":"photo|audio|hint|scramble",
  "species":"English common name",
  "bengali":"Bengali common name",
  "question":"Bengali question",
  "options":["..."],
  "answer":"...",
  "hints":["...","...","..."],
  "syllables":["..."],
  "explanation":"brief Bengali explanation",
  "difficulty":"easy|medium|hard"
}`;

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { temperature: 0.35, maxOutputTokens: 12000, responseMimeType: "application/json" } }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Gemini HTTP ${response.status}: ${text.slice(0, 500)}`);
  const body = JSON.parse(text);
  const output = body?.candidates?.[0]?.content?.parts?.map((p: any) => p?.text || "").join("") || "";
  const parsed = extractJson(output);
  if (!Array.isArray(parsed)) throw new Error("Gemini response is not an array.");
  return parsed;
}

async function fetchImage(species: string): Promise<{ url: string; source: string; attribution: string | null } | null> {
  try {
    const url = `https://api.inaturalist.org/v1/taxa?q=${encodeURIComponent(species)}&per_page=1`;
    const r = await fetch(url, { headers: { "User-Agent": "eAranyakGameGenerator/1.0" } });
    if (!r.ok) return null;
    const body = await r.json();
    const taxon = body?.results?.find((t: any) => {
      const name = clean(t?.name);
      const preferred = clean(t?.preferred_common_name);
      return normalize(name) === normalize(species) || normalize(preferred) === normalize(species);
    });
    if (!taxon) return null;

    const photo = taxon?.default_photo;
    const image = photo?.medium_url || photo?.url;
    if (!image) return null;
    return { url: String(image).replace("square", "medium"), source: "iNaturalist", attribution: photo?.attribution ? String(photo.attribution) : null };
  } catch (_) { return null; }
}

function audioRank(mime: string, url: string): number {
  const m = mime.toLowerCase(), u = url.toLowerCase();
  if (m === "audio/mpeg" || u.endsWith(".mp3")) return 0;
  if (m === "audio/wav" || m === "audio/x-wav" || u.endsWith(".wav")) return 1;
  if (m.includes("ogg") || m.includes("opus") || u.endsWith(".ogg") || u.endsWith(".oga") || u.endsWith(".opus")) return 2;
  return m.startsWith("audio/") ? 3 : 99;
}

async function fetchAudio(species: string): Promise<{ url: string; source: string; attribution: string | null } | null> {
  try {
    for (const term of [`"${species}" filetype:audio`, `${species} bird filetype:audio`]) {
      const u = new URL("https://commons.wikimedia.org/w/api.php");
      u.search = new URLSearchParams({ action: "query", format: "json", generator: "search", gsrnamespace: "6", gsrsearch: term, gsrlimit: "30", prop: "imageinfo", iiprop: "url|mime|extmetadata" }).toString();
      const r = await fetch(u, { headers: { "User-Agent": "eAranyakGameGenerator/1.0" } });
      if (!r.ok) continue;
      const body = await r.json();
      const pages = body?.query?.pages;
      if (!pages) continue;
      const candidates: any[] = [];
      for (const page of Object.values(pages) as any[]) {
        const info = page?.imageinfo?.[0];
        const url = clean(info?.url), mime = clean(info?.mime);
        if (!url || !mime.startsWith("audio/")) continue;
        const title = clean(page?.title).toLowerCase();
        let relevance = title.includes(species.toLowerCase()) ? 100 : 0;
        if (title.includes("call")) relevance += 20;
        if (title.includes("song")) relevance += 10;
        candidates.push({ url, mime, relevance, metadata: info?.extmetadata });
      }
      candidates.sort((a,b) => b.relevance - a.relevance || audioRank(a.mime,a.url)-audioRank(b.mime,b.url));
      if (!candidates.length || candidates[0].relevance < 100) continue;
      const best = candidates[0];
      const meta = best.metadata || {};
      const artist = clean(meta.Artist?.value || meta.Credit?.value || meta.Creator?.value);
      const license = clean(meta.LicenseShortName?.value || meta.UsageTerms?.value);
      return { url: best.url, source: "Wikimedia Commons", attribution: [artist && `Recorded by ${artist}`, license, "Wikimedia Commons"].filter(Boolean).join(" • ") || null };
    }
  } catch (_) {}
  return null;
}


function bengaliTiles(input: string): string[] {
  const compact = input.replace(/\s+/g, "").trim();
  if (!compact) return [];
  const matches = compact.match(/[\u0980-\u09FF](?:[\u0981-\u0983\u09BC\u09BE-\u09CD\u09D7\u09E2-\u09E3\u200C\u200D]*)/g);
  return matches && matches.length ? matches : [compact];
}

async function fetchWordImage(species: string): Promise<{ url: string; source: string; attribution: string | null } | null> {
  const key = normalize(species);
  if (wordImageCache.has(key)) return wordImageCache.get(key) ?? null;
  const image = await fetchImage(species);
  wordImageCache.set(key, image);
  return image;
}

async function syncWordBank(admin: any, birdNames: BirdName[]) {
  const { data: existing, error } = await admin
    .from("game_questions")
    .select("id,species,bengali,active,fingerprint,image_url,image_source,attribution")
    .eq("category", "word");
  if (error) throw error;

  const rows = (existing || []) as any[];
  let inserted = 0;
  let corrected = 0;
  let retired = 0;

  for (const bird of birdNames) {
    const speciesKey = normalize(bird.english);
    const bengali = clean(bird.bengali);
    if (!speciesKey || !bengali) continue;
    const tiles = bengaliTiles(bengali);
    const question = "বাংলা নামটি অক্ষর সাজিয়ে সম্পূর্ণ করুন";
    const fingerprint = await sha256(`word|${speciesKey}|${normalize(bengali)}`);
    const matches = rows.filter((row) => normalize(clean(row.species)) === speciesKey);
    const exact = matches.find((row) => normalize(clean(row.bengali)) === normalize(bengali));

    if (exact) {
      const image = clean(exact.image_url)
        ? null
        : await fetchWordImage(bird.english);
      const needsUpdate =
        clean(exact.fingerprint) !== fingerprint ||
        clean(exact.question) !== question ||
        JSON.stringify(exact.syllables || []) !== JSON.stringify(tiles) ||
        exact.active !== true ||
        (!!image && clean(exact.image_url) !== image.url);
      if (needsUpdate) {
        const { error: updateError } = await admin.from("game_questions").update({
          bengali,
          question,
          answer: bengali,
          options: [],
          hints: [],
          syllables: tiles,
          ...(image ? { image_url: image.url, image_source: image.source, attribution: image.attribution } : {}),
          active: true,
          source: "naturesbook",
          generation_provider: "Nature's Book",
          fingerprint,
          updated_at: new Date().toISOString(),
        }).eq("id", exact.id);
        if (updateError) throw updateError;
        corrected++;
      }
    } else {
      const image = await fetchWordImage(bird.english);
      const { error: insertError } = await admin.from("game_questions").upsert({
        category: "word",
        species: bird.english,
        bengali,
        question,
        options: [],
        answer: bengali,
        hints: [],
        syllables: tiles,
        image_url: image?.url ?? null,
        audio_url: null,
        image_source: image?.source ?? null,
        audio_source: null,
        attribution: image?.attribution ?? null,
        explanation: `বাংলা নামটি Nature's Book-এর পাখির নামের তালিকা থেকে নেওয়া হয়েছে।`,
        difficulty: "easy",
        active: true,
        source: "naturesbook",
        generation_provider: "Nature's Book",
        fingerprint,
        updated_at: new Date().toISOString(),
      }, { onConflict: "fingerprint", ignoreDuplicates: true });
      if (insertError) throw insertError;
      inserted++;
    }

    // If the same species has an older/incorrect Bengali spelling, retire it
    // rather than allowing the typo to reappear in the puzzle.
    for (const row of matches) {
      if (exact && row.id === exact.id) continue;
      if (normalize(clean(row.bengali)) === normalize(bengali)) continue;
      if (row.active !== false) {
        const { error: retireError } = await admin.from("game_questions").update({ active: false, updated_at: new Date().toISOString() }).eq("id", row.id);
        if (retireError) throw retireError;
        retired++;
      }
    }
  }

  // Retire active word records that are no longer present in the current
  // Nature's Book source. Keep them permanently in the table for history.
  const sourceKeys = new Set(
    birdNames.map((bird) => `${normalize(bird.english)}|${normalize(clean(bird.bengali).split(",")[0].split("/")[0].trim())}`),
  );
  for (const row of rows) {
    if (row.active === false) continue;
    const key = `${normalize(clean(row.species))}|${normalize(clean(row.bengali))}`;
    if (sourceKeys.has(key)) continue;
    const { error: retireError } = await admin
      .from("game_questions")
      .update({ active: false, updated_at: new Date().toISOString() })
      .eq("id", row.id);
    if (retireError) throw retireError;
    retired++;
  }

  return { inserted, corrected, retired, sourceNames: birdNames.length };
}

function validRecord(r: any): boolean {
  const category = clean(r?.category) as Category;
  if (!CATEGORIES.includes(category)) return false;
  const species = clean(r?.species), bengali = clean(r?.bengali), question = clean(r?.question), answer = clean(r?.answer);
  if (!species || !bengali || !question || !answer || !containsBengali(bengali) || !containsBengali(question)) return false;
  const options = Array.isArray(r?.options) ? r.options.map(clean).filter(Boolean) : [];
  const hints = Array.isArray(r?.hints) ? r.hints.map(clean).filter(Boolean) : [];
  const syllables = Array.isArray(r?.syllables) ? r.syllables.map(clean).filter(Boolean) : [];
  if ((category === "photo" || category === "audio" || category === "hint") && (options.length !== 4 || !options.includes(answer))) return false;
  if (category === "hint" && hints.length !== 3) return false;
  if (category !== "word" && category !== "hint" && hints.length > 3) return false;
  return true;
}

async function enrichMedia(category: Category, species: string) {
  if (category === "audio") {
    const audio = await fetchAudio(species);
    return audio ? { audio_url: audio.url, audio_source: audio.source, attribution: audio.attribution } : null;
  }
  const image = await fetchImage(species);
  return image ? { image_url: image.url, image_source: image.source, attribution: image.attribution } : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST required." }, 405);

  const suppliedSecret = req.headers.get("x-game-generator-secret") || "";
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !supabaseUrl || !serviceRoleKey) return json({ ok: false, error: "Game generator server configuration is incomplete." }, 500);

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: config, error: configError } = await admin.from("game_generator_config").select("secret").eq("id", 1).maybeSingle();
    if (configError || !config?.secret || suppliedSecret !== String(config.secret)) return json({ ok: false, error: "Unauthorized." }, 401);
    const birdNames = await fetchNaturesBookBirdNames();
    const wordSync = await syncWordBank(admin, birdNames);
    let requestBody: any = {};
    try { requestBody = await req.json(); } catch (_) {}
    if (requestBody?.sync_words_only === true) {
      return json({ ok: true, syncOnly: true, wordSync });
    }
    const generated = await geminiGenerate(apiKey);
    let inserted = 0, rejected = 0, noMedia = 0;

    for (const raw of generated) {
      if (!validRecord(raw)) { rejected++; continue; }
      const category = clean(raw.category) as Category;
      const species = clean(raw.species);
      const bengali = clean(raw.bengali);
      const question = clean(raw.question);
      const fingerprint = await sha256(`${category}|${normalize(question)}|${normalize(species)}|${normalize(bengali)}`);
      const media = await enrichMedia(category, species);
      if ((category === "photo" || category === "audio" || category === "scramble") && !media) { noMedia++; continue; }

      const row: any = {
        category, species, bengali, question,
        options: Array.isArray(raw.options) ? raw.options.map(clean) : [],
        answer: clean(raw.answer),
        hints: Array.isArray(raw.hints) ? raw.hints.map(clean) : [],
        syllables: Array.isArray(raw.syllables) ? raw.syllables.map(clean) : [],
        explanation: clean(raw.explanation) || null,
        difficulty: ["easy","medium","hard"].includes(clean(raw.difficulty)) ? clean(raw.difficulty) : "medium",
        active: true,
        source: "gemini",
        generation_provider: `Gemini ${MODEL} — free tier`,
        fingerprint,
        ...(media || {}),
      };

      const { error } = await admin.from("game_questions").upsert(row, { onConflict: "fingerprint", ignoreDuplicates: true });
      if (error) throw new Error(`Game-bank insert failed: ${error.message}`);
      inserted++;
    }

    return json({ ok: true, model: MODEL, requested: GENERATION_COUNT, received: generated.length, inserted, rejected, noMedia, wordSync });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
