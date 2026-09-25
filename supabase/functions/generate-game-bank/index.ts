import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("GEMINI_GAME_MODEL") || "gemini-3.5-flash-lite";
const GENERATION_COUNT = 60;
const DIFFICULTIES = ["easy", "medium", "hard"] as const;
const CATEGORIES = ["photo", "audio", "hint", "scramble"] as const;
const GENERATED_CATEGORIES = ["photo", "audio", "hint"] as const;

type Category = typeof CATEGORIES[number];
type GeneratedCategory = typeof GENERATED_CATEGORIES[number];

const NATURESBOOK_BIRD_NAMES_URL =
  "https://naturesbook.in/bird-names-in-bengali/";

type BirdName = {
  english: string;
  bengali: string;
};

type Media = {
  url: string;
  source: string;
  attribution: string | null;
};

const wordImageCache = new Map<string, Media | null>();

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-game-generator-secret",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function containsBengali(value: string): boolean {
  return /[\u0980-\u09FF]/.test(value);
}

function imageIdentity(value: string): string {
  return clean(value).replace(/\/(?:square|tiny|small|medium|large|original)\./gi, '/IMAGE.');
}

function normalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\u0980-\u09ff]+/gi, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#8211;|&#x2013;/gi, "–")
    .replace(/&#8212;|&#x2014;/gi, "—")
    .replace(/&#8217;|&#x2019;/gi, "’")
    .replace(/&#8220;|&#x201c;/gi, "“")
    .replace(/&#8221;|&#x201d;/gi, "”")
    .replace(/&#(\d+);/g, (_m, n) => {
      try {
        return String.fromCodePoint(Number(n));
      } catch {
        return "";
      }
    })
    .replace(/&#x([0-9a-f]+);/gi, (_m, n) => {
      try {
        return String.fromCodePoint(parseInt(n, 16));
      } catch {
        return "";
      }
    });
}

function htmlToSearchText(html: string): string {
  return decodeHtmlEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, "\n")
      .replace(/<style[\s\S]*?<\/style>/gi, "\n")
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, "\n")
      .replace(
        /<(br|hr|p|\/p|li|\/li|div|\/div|h[1-6]|\/h[1-6]|tr|\/tr|td|\/td)\b[^>]*>/gi,
        "\n",
      )
      .replace(/<[^>]+>/g, " ")
      .replace(/\r/g, "\n")
      .replace(/[ \t]+/g, " ")
      .replace(/\n[ \t]+/g, "\n")
      .replace(/\n{3,}/g, "\n")
      .trim(),
  );
}

function parseBirdEntries(text: string): BirdName[] {
  const birds: BirdName[] = [];
  const seen = new Set<string>();

  const add = (englishRaw: string, bengaliRaw: string) => {
    let english = clean(englishRaw)
      .replace(/^[•·\-–—]+/, "")
      .replace(/\s+/g, " ")
      .trim();

    let bengali = clean(bengaliRaw)
      .replace(/^[–—:\-]+/, "")
      .replace(/\s+/g, " ")
      .trim();

    bengali = bengali
      .split(/\s+(?:English|Scientific|Family|Order|Habitat)\s*:/i)[0]
      .trim();

    if (!english || !bengali) return;
    if (!/^[A-Za-z][A-Za-z'’().,&/\- ]{1,100}$/.test(english)) return;
    if (!containsBengali(bengali)) return;

    bengali = bengali
      .split(/[,/|;]/)[0]
      .replace(/[।.]+$/, "")
      .trim();

    if (!containsBengali(bengali)) return;

    const key = `${normalize(english)}|${normalize(bengali)}`;
    if (seen.has(key)) return;

    seen.add(key);
    birds.push({ english, bengali });
  };

  for (const rawLine of text.split(/\n+/)) {
    const line = rawLine.replace(/\s+/g, " ").trim();
    if (!line) continue;

    const re =
      /(?:^|\s)\d{1,3}\s*[.)]\s*([A-Za-z][A-Za-z'’().,&/\- ]{1,100}?)\s*(?:–|—|:|-)\s*([\u0980-\u09FF][\u0980-\u09FF\s\u0981-\u09FF\u200C\u200D,;/()\-–—।.]{1,120}?)(?=\s+\d{1,3}\s*[.)]\s*|$)/u;

    const match = re.exec(line);
    if (match) add(match[1], match[2]);
  }

  if (birds.length < 50) {
    const collapsed = text.replace(/\s+/g, " ").trim();

    const re =
      /(?:^|\s)\d{1,3}\s*[.)]\s*([A-Za-z][A-Za-z'’().,&/\- ]{1,100}?)\s*(?:–|—|:|-)\s*([\u0980-\u09FF][\u0980-\u09FF\s\u0981-\u09FF\u200C\u200D,;/()\-–—।.]{1,120}?)(?=\s+\d{1,3}\s*[.)]\s*|$)/gu;

    let match: RegExpExecArray | null;
    while ((match = re.exec(collapsed)) !== null) {
      add(match[1], match[2]);
    }
  }

  return birds;
}

async function fetchNaturesBookBirdNames(): Promise<BirdName[]> {
  const response = await fetch(NATURESBOOK_BIRD_NAMES_URL, {
    headers: {
      "User-Agent": "eAranyakGameGenerator/2.0",
      Accept: "text/html,application/xhtml+xml",
    },
  });

  if (!response.ok) {
    throw new Error(`Nature's Book bird-name list HTTP ${response.status}`);
  }

  const html = await response.text();
  const text = htmlToSearchText(html);
  const birds = parseBirdEntries(text);

  if (birds.length < 50) {
    throw new Error(
      `Nature's Book bird-name list could not be parsed reliably (${birds.length} names).`,
    );
  }

  return birds;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function extractJson(text: string): any {
  const fenced = text
    .match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]
    ?.trim();

  const candidate = fenced || text.trim();

  try {
    return JSON.parse(candidate);
  } catch (_) {
    // continue
  }

  const start = candidate.indexOf("[");
  const end = candidate.lastIndexOf("]");

  if (start >= 0 && end > start) {
    return JSON.parse(candidate.slice(start, end + 1));
  }

  throw new Error("Gemini did not return valid JSON.");
}

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableGeminiStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 ||
    status === 503 || status === 504;
}

async function callGemini(
  apiKey: string,
  model: string,
  prompt: string,
): Promise<any[]> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const maxAttempts = 5;
  let lastError = "";

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.35,
          maxOutputTokens: 16000,
          responseMimeType: "application/json",
        },
      }),
    });

    const text = await response.text();

    if (response.ok) {
      const body = JSON.parse(text);
      const output =
        body?.candidates?.[0]?.content?.parts
          ?.map((p: any) => p?.text || "")
          .join("") || "";

      const parsed = extractJson(output);
      if (!Array.isArray(parsed)) {
        throw new Error("Gemini response is not an array.");
      }
      return parsed;
    }

    lastError = `Gemini HTTP ${response.status}: ${text.slice(0, 700)}`;

    if (!isRetryableGeminiStatus(response.status) || attempt === maxAttempts) {
      break;
    }

    const delay = Math.min(16000, 1500 * Math.pow(2, attempt - 1)) +
      Math.floor(Math.random() * 500);
    await sleep(delay);
  }

  throw new Error(lastError || "Gemini request failed.");
}

async function geminiGenerate(apiKey: string): Promise<any[]> {
  const plans = [
    {
      category: "photo",
      count: 20,
      promptRules: `
PHOTO SET (UNIVERSAL VISUAL POOL):
- Generate exactly 20 UNIQUE Indian wildlife species.
- Birds, mammals, reptiles, amphibians and other Indian wildlife are allowed.
- Use a balanced difficulty distribution: easy, medium and hard.
- The Bengali question MUST clearly ask the user to identify the animal from a
  photograph. Prefer exactly: "ছবি দেখে চিনুন".
- options exactly 4 Bengali-first labels in the form "বাংলা নাম (English name)".
- answer must exactly equal one option.
- Every species must have a reliable searchable image in iNaturalist.
- Do not repeat a species in this set.
- Do not generate scramble records. The backend will create a scramble record
  from every valid PHOTO record and reuse the exact same image, attribution and
  difficulty.
`,
    },
    {
      category: "audio",
      count: 20,
      promptRules: `
AUDIO SET (SEPARATE RESOURCE POOL):
- Generate exactly 20 UNIQUE Indian bird species.
- Bird-call identification only.
- options exactly 4 Bengali-first labels and answer must exactly equal one option.
- The question must clearly refer to hearing a bird call.
- Choose birds for which a species-specific recording is realistically searchable
  in Xeno-canto/eBird/Macaulay.
- Do not invent a call description.
`,
    },
    {
      category: "hint",
      count: 20,
      promptRules: `
HINT SET (FIELD-MARK IDENTIFICATION):
- Generate exactly 20 UNIQUE Indian wildlife species.
- Prefer species commonly found in the PHOTO universal pool.
- Produce exactly 3 progressively useful, FACTUAL Bengali hints.
- Each hint must describe an OBSERVABLE FIELD CHARACTERISTIC of the species:
  habitat, region/state, plumage or fur colour, body shape, bill/beak shape,
  tail length, size relative to a familiar species, call quality, diet,
  behaviour, or a distinctive marking.
- HINT 1 (broad): habitat or region clue.
- HINT 2 (medium): one distinctive visual or behavioural feature.
- HINT 3 (narrow): a second feature that together with HINT 2 narrows the
  answer to a single option among the four choices.
- FORBIDDEN hint content (must NOT appear in any hint):
  * the species' English common name or any part of it,
  * the Bengali common name or any part of it,
  * the first letter / first syllable / word count of either name,
  * the scientific name or any part of it,
  * any restatement of the question,
  * phrases like "প্রথম অক্ষর", "শব্দের", "বৈজ্ঞানিক নাম".
- Good hint example: "সাধারণত নদীর ধারে বা জলাশয়ের কাছে দেখা যায়।"
- Good hint example: "এর ডানা ও লেজে সাদা-কালো ডোরাকাটা দাগ থাকে।"
- Bad hint example: "ইংরেজি নামের প্রথম অক্ষর C।"
- Bad hint example: "এর বৈজ্ঞানিক নামের প্রথম অংশ Corvus।"
- options exactly 4 Bengali-first labels and answer must exactly equal one option.
`,
    },
  ];

  const commonRules = `
GLOBAL RULES:
- Focus on Indian wildlife, birds, reptiles, amphibians, mammals,
  conservation species, and Indian natural history.
- Never invent a species, Bengali name, fact, state, habitat, or conservation status.
- Use established English common names.
- Bengali text must be natural contemporary Bengali.
- Difficulty must reflect identification challenge, not merely rarity.
- The requested difficulty must be respected exactly.
- easy = familiar species and distinctive characteristics.
- medium = requires recognition of more specific characteristics.
- hard = requires distinguishing a less obvious species or closely related species
  using reliable field characteristics.
- Never make a question hard by using an obscure or unverifiable fact.

Return objects with exactly these keys:
{
  "category":"photo|audio|hint",
  "species":"English common name",
  "bengali":"Bengali common name",
  "question":"Bengali question",
  "options":["..."],
  "answer":"...",
  "hints":["...","...","..."],
  "syllables":[],
  "explanation":"brief Bengali explanation",
  "difficulty":"easy|medium|hard"
}
Do not add markdown, commentary, or extra JSON fields.
`;

  const generated: any[] = [];
  let photoSpeciesForHints: string[] = [];

  for (const plan of plans) {
    const hintSubsetRule = plan.category === "hint" && photoSpeciesForHints.length
      ? `\nHINT SUBSET RULE: Use ONLY species from this PHOTO universal-set list:\n${photoSpeciesForHints.map((x) => `- ${x}`).join("\n")}\nDo not invent a hint species outside this list.`
      : "";

    const prompt = `
You generate educational wildlife game content for eAranyak, an Indian Bengali nature-learning app.

Return EXACTLY ${plan.count} NEW game records. Every record must have category "${plan.category}".
${plan.promptRules}${hintSubsetRule}
Do NOT generate word or scramble records.
${commonRules}
`;

    const call = async (model: string) => callGemini(apiKey, model, prompt);

    let batch: any[];
    try {
      batch = await call(MODEL);
    } catch (primaryError) {
      const fallback =
        Deno.env.get("GEMINI_GAME_FALLBACK_MODEL") ||
        "gemini-3.1-flash-lite";
      if (!fallback || fallback === MODEL) throw primaryError;
      try {
        batch = await call(fallback);
      } catch (fallbackError) {
        throw new Error(
          `${plan.category} generation failed. Primary (${MODEL}): ${primaryError instanceof Error ? primaryError.message : String(primaryError)}; ` +
          `fallback (${fallback}): ${fallbackError instanceof Error ? fallbackError.message : String(fallbackError)}`,
        );
      }
    }

    generated.push(...batch);

    if (plan.category === "photo") {
      photoSpeciesForHints = batch
        .map((r) => clean(r?.species))
        .filter(Boolean);
    }
  }

  return generated;
}

async function fetchWikimediaImage(species: string): Promise<Media | null> {
  try {
    const uri = new URL("https://commons.wikimedia.org/w/api.php");
    uri.search = new URLSearchParams({
      action: "query",
      format: "json",
      generator: "search",
      gsrnamespace: "6",
      gsrsearch: `\"${species}\" filetype:bitmap`,
      gsrlimit: "30",
      prop: "imageinfo",
      iiprop: "url|mime|extmetadata",
    }).toString();

    const response = await fetch(uri, {
      headers: { "User-Agent": "eAranyakGameGenerator/5.0" },
    });
    if (!response.ok) return null;

    const body = await response.json();
    const pages = body?.query?.pages;
    if (!pages) return null;

    const target = normalize(species);
    const candidates: any[] = [];
    for (const page of Object.values(pages) as any[]) {
      const title = clean(page?.title);
      const info = page?.imageinfo?.[0];
      const url = clean(info?.url);
      const mime = clean(info?.mime).toLowerCase();
      if (!url || !mime.startsWith("image/")) continue;

      const titleNorm = normalize(title);
      const score = titleNorm === target ? 0 :
        titleNorm.includes(target) ? 1 :
        target.includes(titleNorm) ? 2 : 99;
      if (score >= 99) continue;

      const meta = info?.extmetadata || {};
      const artist = clean(meta.Artist?.value || meta.Credit?.value || meta.Creator?.value);
      const license = clean(meta.LicenseShortName?.value || meta.UsageTerms?.value);
      candidates.push({ url, score, artist, license, title });
    }

    candidates.sort((a, b) => a.score - b.score);
    const best = candidates[0];
    if (!best) return null;

    return {
      url: best.url,
      source: "Wikimedia Commons",
      attribution: [
        best.artist && `Photographer: ${best.artist}`,
        best.license,
        "Wikimedia Commons",
      ].filter(Boolean).join(" • ") || null,
    };
  } catch (_) {
    return null;
  }
}

async function fetchINaturalistTaxonImage(query: string): Promise<Media | null> {
  try {
    const url =
      `https://api.inaturalist.org/v1/taxa?q=${encodeURIComponent(query)}&per_page=20`;
    const r = await fetch(url, {
      headers: { "User-Agent": "eAranyakGameGenerator/6.0" },
    });
    if (!r.ok) return null;

    const body = await r.json();
    const target = normalize(query);
    const taxon = (body?.results || []).find((t: any) => {
      const scientific = normalize(clean(t?.name));
      const common = normalize(clean(t?.preferred_common_name));
      return scientific === target || common === target;
    });

    const photo = taxon?.default_photo;
    const image = photo?.medium_url || photo?.large_url || photo?.url;
    if (!image) return null;

    return {
      url: String(image).replace("square", "medium"),
      source: "iNaturalist",
      attribution: photo?.attribution ? String(photo.attribution) : null,
    };
  } catch (_) {
    return null;
  }
}

async function fetchImage(species: string): Promise<Media | null> {
  const direct = await fetchINaturalistTaxonImage(species);
  if (direct) return direct;

  try {
    const bird = await fetchEBirdTaxon(species);
    if (bird?.scientificName) {
      const exactScientific = await fetchINaturalistTaxonImage(bird.scientificName);
      if (exactScientific) return exactScientific;
    }
  } catch (_) {}

  return await fetchWikimediaImage(species);
}

function audioRank(mime: string, url: string): number {
  const m = mime.toLowerCase();
  const u = url.toLowerCase();

  if (m === "audio/mpeg" || u.endsWith(".mp3")) return 0;
  if (m === "audio/wav" || m === "audio/x-wav" || u.endsWith(".wav")) {
    return 1;
  }
  if (
    m.includes("ogg") ||
    m.includes("opus") ||
    u.endsWith(".ogg") ||
    u.endsWith(".oga") ||
    u.endsWith(".opus")
  ) {
    return 2;
  }

  return m.startsWith("audio/") ? 3 : 99;
}

type EBirdTaxon = {
  speciesCode: string;
  scientificName: string;
  commonName: string;
};

let eBirdTaxonomyCache: EBirdTaxon[] | null = null;
let eBirdTaxonomyPromise: Promise<EBirdTaxon[] | null> | null = null;

async function loadEBirdTaxonomy(): Promise<EBirdTaxon[] | null> {
  if (eBirdTaxonomyCache) return eBirdTaxonomyCache;
  if (eBirdTaxonomyPromise) return eBirdTaxonomyPromise;

  const apiKey =
    Deno.env.get("EBIRD_API_KEY") ||
    Deno.env.get("eBird_API") ||
    Deno.env.get("EBIRD_API");

  if (!apiKey) return null;

  eBirdTaxonomyPromise = (async () => {
    try {
      const url =
        `https://api.ebird.org/v2/ref/taxonomy/ebird?fmt=json&cat=species`;
      const response = await fetch(url, {
        headers: {
          "X-eBirdApiToken": apiKey,
          "User-Agent": "eAranyakGameGenerator/4.0",
        },
      });
      if (!response.ok) return null;

      const raw = await response.json();
      if (!Array.isArray(raw)) return null;

      const taxonomy = raw
        .map((item: any) => ({
          speciesCode: clean(item?.speciesCode),
          scientificName: clean(item?.sciName),
          commonName: clean(item?.comName),
        }))
        .filter((x: EBirdTaxon) => x.commonName || x.scientificName);

      eBirdTaxonomyCache = taxonomy;
      return taxonomy;
    } catch (_) {
      return null;
    } finally {
      eBirdTaxonomyPromise = null;
    }
  })();

  return eBirdTaxonomyPromise;
}

async function fetchEBirdTaxon(species: string): Promise<EBirdTaxon | null> {
  const taxonomy = await loadEBirdTaxonomy();
  if (!taxonomy) return null;

  const target = normalize(species);
  return taxonomy.find((item) =>
    normalize(item.commonName) === target ||
    normalize(item.scientificName) === target
  ) ?? null;
}

async function filterToVerifiedBirds(birdNames: BirdName[]): Promise<{
  birds: BirdName[];
  rejected: number;
}> {
  const taxonomy = await loadEBirdTaxonomy();

  if (!taxonomy) {
    throw new Error(
      "Cannot verify the Nature's Book bird list: eBird taxonomy is unavailable. Set EBIRD_API_KEY (or eBird_API) in Supabase secrets.",
    );
  }

  const verified: BirdName[] = [];
  for (const bird of birdNames) {
    const target = normalize(bird.english);
    const match = taxonomy.find((item) => normalize(item.commonName) === target);
    if (match) verified.push(bird);
  }

  if (verified.length < 50) {
    throw new Error(
      `Nature's Book bird list failed biological validation: only ${verified.length} verified bird names remained from ${birdNames.length} parsed names.`,
    );
  }

  return { birds: verified, rejected: birdNames.length - verified.length };
}

async function fetchXenoCantoAudio(
  scientificName: string,
  commonName: string,
  apiKey: string,
): Promise<Media | null> {
  try {
    const query = encodeURIComponent(`gen:${scientificName}`);
    const url =
      `https://xeno-canto.org/api/3/recordings?query=${query}&key=${encodeURIComponent(apiKey)}`;

    const response = await fetch(url, {
      headers: { "User-Agent": "eAranyakGameGenerator/3.0" },
    });

    if (!response.ok) return null;

    const body = await response.json();
    const recordings = Array.isArray(body?.recordings)
      ? body.recordings
      : [];

    if (!recordings.length) return null;

    const exact = recordings.find((recording: any) => {
      const scientific = normalize(clean(recording?.sci_name));
      const english = normalize(clean(recording?.en));
      return scientific === normalize(scientificName) ||
        english === normalize(commonName);
    });

    if (!exact) return null;

    const file = clean(exact?.file);
    if (!file) return null;

    const recorder = clean(exact?.rec);
    const license = clean(exact?.lic);
    const id = clean(exact?.id);

    return {
      url: file,
      source: "Xeno-canto",
      attribution:
        [
          recorder && `Recorded by ${recorder}`,
          license && `License ${license}`,
          id && `Xeno-canto recording ${id}`,
        ]
          .filter(Boolean)
          .join(" • ") || null,
    };
  } catch (_) {
    return null;
  }
}

/**
 * Search Wikimedia Commons for a species recording.  Commons names audio
 * files after the SCIENTIFIC name far more often than after the English
 * common name (e.g. "Corvus_splendens_call.ogg").  We therefore search by
 * both, then accept any candidate whose title shares a meaningful token
 * with either name.
 */
async function fetchWikimediaAudio(
  species: string,
  scientificName?: string,
): Promise<Media | null> {
  try {
    const terms: string[] = [];
    if (scientificName) terms.push(`"${scientificName}" filetype:audio`);
    terms.push(`"${species}" filetype:audio`);

    const speciesTokens = normalize(species).split(" ").filter((t) => t.length > 3);
    const sciTokens = scientificName
      ? normalize(scientificName).split(" ").filter((t) => t.length > 3)
      : [];

    for (const term of terms) {
      const uri = new URL("https://commons.wikimedia.org/w/api.php");
      uri.search = new URLSearchParams({
        action: "query",
        format: "json",
        generator: "search",
        gsrnamespace: "6",
        gsrsearch: term,
        gsrlimit: "30",
        prop: "imageinfo",
        iiprop: "url|mime|extmetadata",
      }).toString();

      const response = await fetch(uri, {
        headers: { "User-Agent": "eAranyakGameGenerator/4.0" },
      });
      if (!response.ok) continue;

      const body = await response.json();
      const pages = body?.query?.pages;
      if (!pages) continue;

      const candidates: any[] = [];
      for (const page of Object.values(pages) as any[]) {
        const title = clean(page?.title);
        const info = page?.imageinfo?.[0];
        const url = clean(info?.url);
        const mime = clean(info?.mime).toLowerCase();
        if (!url || !mime.startsWith("audio/")) continue;

        const titleTokens = new Set(normalize(title).split(" "));
        const overlap =
          speciesTokens.filter((t) => titleTokens.has(t)).length +
          sciTokens.filter((t) => titleTokens.has(t)).length;
        if (overlap === 0) continue;

        const meta = info?.extmetadata || {};
        const artist = clean(meta.Artist?.value || meta.Credit?.value || meta.Creator?.value);
        const license = clean(meta.LicenseShortName?.value || meta.UsageTerms?.value);
        candidates.push({
          url,
          artist,
          license,
          title,
          overlap,
          rank: audioRank(mime, url),
        });
      }

      candidates.sort((a, b) => b.overlap - a.overlap || a.rank - b.rank);
      const best = candidates[0];
      if (!best) continue;

      return {
        url: best.url,
        source: "Wikimedia Commons",
        attribution: [
          best.artist && `Recorded by ${best.artist}`,
          best.license,
          "Wikimedia Commons",
        ].filter(Boolean).join(" • ") || null,
      };
    }

    return null;
  } catch (_) {
    return null;
  }
}

async function fetchAudio(species: string): Promise<Media | null> {
  try {
    const ebirdTaxon = await fetchEBirdTaxon(species);

    if (!ebirdTaxon?.scientificName) return null;

    const xenoKey = Deno.env.get("XENO_CANTO_API_KEY");
    if (xenoKey) {
      const xeno = await fetchXenoCantoAudio(
        ebirdTaxon.scientificName,
        ebirdTaxon.commonName || species,
        xenoKey,
      );
      if (xeno) return xeno;
    }

    return await fetchWikimediaAudio(
      ebirdTaxon.commonName || species,
      ebirdTaxon.scientificName,
    );
  } catch (_) {
    return null;
  }
}

function bengaliTiles(input: string): string[] {
  const compact = input.replace(/\s+/g, "").trim();

  if (!compact) return [];

  const matches = compact.match(
    /[\u0980-\u09FF](?:[\u0981-\u0983\u09BC\u09BE-\u09CD\u09D7\u09E2-\u09E3\u200C\u200D]*)/g,
  );

  return matches && matches.length ? matches : [compact];
}

async function fetchWordImage(species: string): Promise<Media | null> {
  const key = normalize(species);

  if (wordImageCache.has(key)) {
    return wordImageCache.get(key) ?? null;
  }

  let image: Media | null = null;

  try {
    const bird = await fetchEBirdTaxon(species);
    if (bird?.scientificName) {
      image = await fetchINaturalistTaxonImage(bird.scientificName);
    }
  } catch (_) {}

  if (!image) image = await fetchINaturalistTaxonImage(species);
  if (!image) image = await fetchWikimediaImage(species);

  wordImageCache.set(key, image);
  return image;
}

// ---------------------------------------------------------------------------
// Deterministic shuffle — same input + same seed always produces the same
// order, so re-running the generator does not churn existing rows.
// ---------------------------------------------------------------------------

function deterministicShuffle<T>(arr: T[], seedStr: string): T[] {
  let h = 2166136261;
  for (let i = 0; i < seedStr.length; i++) {
    h ^= seedStr.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  const rng = () => {
    h ^= h << 13;
    h ^= h >>> 17;
    h ^= h << 5;
    return ((h >>> 0) % 100000) / 100000;
  };
  const out = arr.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

// ---------------------------------------------------------------------------
// Difficulty — a single deterministic rebalancer.  Sort by fingerprint (a
// stable key) and split into three nearly equal buckets.  No other code path
// is allowed to write difficulty.
// ---------------------------------------------------------------------------

function bucketSizes(total: number, buckets = DIFFICULTIES.length): number[] {
  const base = Math.floor(total / buckets);
  const rem = total % buckets;
  return Array.from({ length: buckets }, (_, i) => base + (i < rem ? 1 : 0));
}

async function rebalanceCategory(
  admin: any,
  category: Category | "word",
): Promise<Record<string, number>> {
  const { data, error } = await admin
    .from("game_questions")
    .select("id")
    .eq("category", category)
    .eq("active", true)
    .order("fingerprint", { ascending: true });
  if (error) throw error;

  const rows = (data || []) as any[];
  const sizes = bucketSizes(rows.length);
  const labels = DIFFICULTIES;
  const result: Record<string, number> = { easy: 0, medium: 0, hard: 0 };

  let cursor = 0;
  for (let i = 0; i < labels.length; i++) {
    const slice = rows.slice(cursor, cursor + sizes[i]);
    cursor += sizes[i];
    const ids = slice.map((r) => clean(r.id)).filter(Boolean);
    if (!ids.length) continue;
    const { error: u } = await admin
      .from("game_questions")
      .update({ difficulty: labels[i], updated_at: new Date().toISOString() })
      .in("id", ids);
    if (u) throw u;
    result[labels[i]] = ids.length;
  }

  return result;
}

async function rebalanceAllCategories(
  admin: any,
): Promise<Record<string, Record<string, number>>> {
  const result: Record<string, Record<string, number>> = {};
  for (const category of ["photo", "audio", "hint", "scramble", "word"] as const) {
    result[category] = await rebalanceCategory(admin, category);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Hint validation — reject hints that leak the answer or describe spelling.
// ---------------------------------------------------------------------------

const FORBIDDEN_HINT_RE =
  /(প্রথম\s*অক্ষর|প্রথম\s*বর্ণ|অক্ষরটি|বর্ণটি|শব্দের\s*সংখ্যা|বৈজ্ঞানিক\s*নাম|ইংরেজি\s*নামের\s*প্রথম)/;

function hintsAreValid(
  hints: string[],
  species: string,
  bengali: string,
): boolean {
  if (hints.length !== 3) return false;
  const speciesNorm = normalize(species);
  const bengaliNorm = normalize(bengali);
  const speciesTokens = speciesNorm.split(" ").filter((t) => t.length > 3);

  for (const hint of hints) {
    const h = clean(hint);
    if (!h || !containsBengali(h)) return false;
    if (FORBIDDEN_HINT_RE.test(h)) return false;

    const hNorm = normalize(h);
    // English species name (full or any significant token) must not appear.
    if (speciesNorm && hNorm.includes(speciesNorm)) return false;
    for (const token of speciesTokens) {
      if (hNorm.includes(token)) return false;
    }
    // Bengali species name must not appear.
    if (bengaliNorm && hNorm.includes(bengaliNorm)) return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Audio bank repair
// ---------------------------------------------------------------------------

async function repairAudioBank(
  admin: any,
  birdNames: BirdName[],
): Promise<{
  audioInsertedOrUpdated: number;
  audioRetired: number;
  audioSpecies: number;
  audioMissing: number;
  audioMissingSample: string[];
}> {
  const found: Array<{ bird: BirdName; audio: Media }> = [];
  const missing: string[] = [];
  const concurrency = 5;

  for (let start = 0; start < birdNames.length; start += concurrency) {
    const batch = birdNames.slice(start, start + concurrency);
    const results = await Promise.all(
      batch.map(async (bird) => ({ bird, audio: await fetchAudio(bird.english) })),
    );
    for (const result of results) {
      if (result.audio) found.push({ bird: result.bird, audio: result.audio });
      else missing.push(result.bird.english);
    }
  }

  console.log(
    `audio repair: ${found.length} birds with audio, ${missing.length} without`,
  );
  if (missing.length) {
    console.log("audio missing sample:", missing.slice(0, 40).join(", "));
  }

  const { data: oldUniversal, error: oldUniversalError } = await admin
    .from("game_questions")
    .select("id")
    .eq("category", "audio")
    .eq("source", "audio-universal-set")
    .eq("active", true);
  if (oldUniversalError) throw oldUniversalError;

  const oldIds = (oldUniversal || []).map((row: any) => clean(row.id)).filter(Boolean);
  if (oldIds.length) {
    const { error } = await admin
      .from("game_questions")
      .update({ active: false, updated_at: new Date().toISOString() })
      .in("id", oldIds);
    if (error) throw error;
  }

  let audioInsertedOrUpdated = 0;
  const activeFingerprints = new Set<string>();

  for (let index = 0; index < found.length; index++) {
    const { bird, audio } = found[index];
    const species = bird.english;
    const bengali = bird.bengali;
    const answer = `${bengali} (${species})`;

    const optionLabels: string[] = [answer];
    for (let offset = 1; offset <= birdNames.length && optionLabels.length < 4; offset++) {
      const candidate = birdNames[(index + offset) % birdNames.length];
      if (normalize(candidate.english) === normalize(species)) continue;
      const label = `${candidate.bengali} (${candidate.english})`;
      if (!optionLabels.includes(label)) optionLabels.push(label);
    }
    if (optionLabels.length !== 4) continue;

    const fingerprint = await sha256(
      `audio-universal|${normalize(species)}|${normalize(audio.url)}`,
    );
    activeFingerprints.add(fingerprint);

    const shuffledOptions = deterministicShuffle(optionLabels, fingerprint);
    if (!shuffledOptions.includes(answer)) {
      throw new Error(`audio shuffle lost answer for ${species}`);
    }

    const row = {
      category: "audio",
      species,
      bengali,
      question: "ডাক শুনে পাখিটিকে চিনুন",
      options: shuffledOptions,
      answer,
      hints: [],
      syllables: [],
      explanation: `${bengali} পাখিটির স্বর শুনে প্রজাতিটি শনাক্ত করুন।`,
      difficulty: "medium", // rebalanceCategory owns the final label
      active: true,
      image_url: null,
      audio_url: audio.url,
      image_source: null,
      audio_source: audio.source,
      attribution: audio.attribution,
      source: "audio-universal-set",
      generation_provider: "Xeno-canto/Wikimedia bird-call universal set",
      fingerprint,
      updated_at: new Date().toISOString(),
    };

    const { error } = await admin
      .from("game_questions")
      .upsert(row, { onConflict: "fingerprint" });
    if (error) throw error;
    audioInsertedOrUpdated++;
  }

  return {
    audioInsertedOrUpdated,
    audioRetired: oldIds.length,
    audioSpecies: found.length,
    audioMissing: missing.length,
    audioMissingSample: missing.slice(0, 20),
  };
}

// ---------------------------------------------------------------------------
// Visual bank repair
// ---------------------------------------------------------------------------

async function fetchScientificNameForHint(species: string): Promise<string | null> {
  try {
    const url = `https://api.inaturalist.org/v1/taxa?q=${encodeURIComponent(species)}&per_page=10`;
    const response = await fetch(url, {
      headers: { "User-Agent": "eAranyakGameGenerator/5.0" },
    });
    if (!response.ok) return null;
    const body = await response.json();
    const taxon = body?.results?.find((t: any) =>
      normalize(clean(t?.preferred_common_name)) === normalize(species) ||
      normalize(clean(t?.name)) === normalize(species)
    );
    const scientific = clean(taxon?.name);
    return scientific || null;
  } catch (_) {
    return null;
  }
}

function buildVisualOptions(
  visualSources: any[],
  index: number,
  species: string,
  bengali: string,
  seed: string,
): string[] {
  const answer = `${bengali} (${species})`;
  const candidates: string[] = [];
  for (
    let offset = 1;
    offset <= visualSources.length && candidates.length < 3;
    offset++
  ) {
    const candidate = visualSources[(index + offset) % visualSources.length];
    const candidateSpecies = clean(candidate?.species);
    const candidateBengali = clean(candidate?.bengali);
    if (
      !candidateSpecies ||
      !candidateBengali ||
      normalize(candidateSpecies) === normalize(species)
    ) continue;
    const label = `${candidateBengali} (${candidateSpecies})`;
    if (!candidates.includes(label)) candidates.push(label);
  }
  if (candidates.length < 3) return [];
  return deterministicShuffle([answer, ...candidates], seed);
}

async function repairVisualBank(admin: any): Promise<{
  photoRetired: number;
  photoFromWordInsertedOrUpdated: number;
  scrambleInsertedOrUpdated: number;
  scrambleRetired: number;
  universalVisualSpecies: number;
  hintsInserted: number;
}> {
  const { data, error } = await admin
    .from("game_questions")
    .select(
      "id,category,species,bengali,question,options,answer,hints,explanation,difficulty,active,image_url,image_source,audio_url,audio_source,attribution,source,generation_provider,fingerprint",
    )
    .in("category", ["photo", "word", "scramble"])
    .eq("active", true)
    .order("created_at", { ascending: true });

  if (error) throw error;

  const rows = (data || []) as any[];
  const wordRows = rows.filter((r) => clean(r.category) === "word");
  const photoRows = rows.filter(
    (r) => clean(r.category) === "photo" && clean(r.image_url),
  );

  const visualSources: any[] = [];
  const seenImages = new Set<string>();
  const seenSpecies = new Set<string>();
  let photoRetired = 0;

  for (const row of photoRows) {
    const imageUrl = clean(row.image_url);
    const imageKey = imageIdentity(imageUrl);
    const speciesKey = normalize(clean(row.species));
    if (
      !imageUrl ||
      !speciesKey ||
      seenImages.has(imageKey) ||
      seenSpecies.has(speciesKey)
    ) {
      if (clean(row.id)) {
        const { error: retireError } = await admin
          .from("game_questions")
          .update({ active: false, updated_at: new Date().toISOString() })
          .eq("id", row.id);
        if (retireError) throw retireError;
        photoRetired++;
      }
      continue;
    }
    seenImages.add(imageKey);
    seenSpecies.add(speciesKey);
    visualSources.push(row);
  }

  let photoFromWordInsertedOrUpdated = 0;
  for (const row of wordRows) {
    const species = clean(row.species);
    const bengali = clean(row.bengali);
    const speciesKey = normalize(species);
    if (!species || !bengali || !speciesKey || seenSpecies.has(speciesKey)) {
      continue;
    }

    let imageUrl = clean(row.image_url);
    let imageSource = clean(row.image_source);
    let attribution = clean(row.attribution);

    if (!imageUrl) {
      const repaired = await fetchWordImage(species);
      if (repaired) {
        imageUrl = repaired.url;
        imageSource = repaired.source;
        attribution = repaired.attribution || "";
        const { error: repairError } = await admin
          .from("game_questions")
          .update({
            image_url: imageUrl,
            image_source: imageSource,
            attribution: attribution || null,
            active: true,
            updated_at: new Date().toISOString(),
          })
          .eq("id", row.id);
        if (repairError) throw repairError;
      }
    }

    if (!imageUrl) continue;

    const imageKey = imageIdentity(imageUrl);
    if (seenImages.has(imageKey)) continue;

    const enrichedRow = {
      ...row,
      image_url: imageUrl,
      image_source: imageSource,
      attribution,
    };
    visualSources.push(enrichedRow);
    seenImages.add(imageKey);
    seenSpecies.add(speciesKey);
  }

  const labelBySpecies = new Map<string, string>();
  for (const row of visualSources) {
    labelBySpecies.set(
      normalize(clean(row.species)),
      `${clean(row.bengali)} (${clean(row.species)})`,
    );
  }

  for (let index = 0; index < visualSources.length; index++) {
    const source = visualSources[index];
    const category = clean(source.category);
    const species = clean(source.species);
    const bengali = clean(source.bengali);
    const imageUrl = clean(source.image_url);
    if (!species || !bengali || !imageUrl) continue;

    const speciesKey = normalize(species);

    const candidates: string[] = [];
    for (
      let offset = 1;
      offset <= visualSources.length && candidates.length < 3;
      offset++
    ) {
      const candidate = visualSources[(index + offset) % visualSources.length];
      const candidateKey = normalize(clean(candidate.species));
      const label = labelBySpecies.get(candidateKey);
      if (!label || candidateKey === speciesKey || candidates.includes(label)) {
        continue;
      }
      candidates.push(label);
    }
    if (candidates.length < 3) continue;

    const answer = `${bengali} (${species})`;
    const fingerprint = await sha256(
      `photo-universal|${speciesKey}|${normalize(imageUrl)}`,
    );

    const options = deterministicShuffle([answer, ...candidates], fingerprint);
    if (!options.includes(answer)) {
      throw new Error(`photo shuffle lost answer for ${species}`);
    }

    const row = {
      category: "photo",
      species,
      bengali,
      question: "ছবি দেখে চিনুন",
      options,
      answer,
      hints: Array.isArray(source.hints)
        ? source.hints.map(clean).filter(Boolean)
        : [],
      syllables: [],
      explanation: clean(source.explanation) || null,
      difficulty: "medium", // rebalanceCategory owns final label
      active: true,
      image_url: imageUrl,
      image_source: clean(source.image_source) || "iNaturalist",
      audio_url: null,
      audio_source: null,
      attribution: clean(source.attribution) || null,
      source:
        category === "word"
          ? "visual-universal-set"
          : clean(source.source) || "visual-universal-set",
      generation_provider:
        category === "word"
          ? "Visual universal set from Nature's Book image bank"
          : clean(source.generation_provider) || "Visual universal set",
      fingerprint,
      updated_at: new Date().toISOString(),
    };

    const { error: upsertError } = await admin
      .from("game_questions")
      .upsert(row, { onConflict: "fingerprint" });
    if (upsertError) throw upsertError;

    if (category === "word") photoFromWordInsertedOrUpdated++;
  }

  // Ensure every visual species has a HINT row.  We DO NOT synthesise
  // template hints here — the species list is instead handed to Gemini by
  // the caller, and rows are created there.  If the species still has no
  // hint row after that pass, it simply has none; better no hint than a
  // tautological hint.
  //
  // (The generator's Gemini hint plan already covers the visual pool via
  // photoSpeciesForHints.  This function therefore only projects SCRAMBLE.)
  const { data: existingHints } = await admin
    .from("game_questions")
    .select("id,species,active")
    .eq("category", "hint");
  const hintSpecies = new Set(
    ((existingHints || []) as any[])
      .filter((r) => r.active === true)
      .map((r) => normalize(clean(r.species)))
      .filter(Boolean),
  );

  // Reload active PHOTO universe for scramble projection.
  const { data: activePhotos, error: activePhotoError } = await admin
    .from("game_questions")
    .select(
      "id,species,bengali,question,options,answer,hints,explanation,difficulty,image_url,image_source,attribution,source,generation_provider,fingerprint",
    )
    .eq("category", "photo")
    .eq("active", true)
    .order("created_at", { ascending: true });
  if (activePhotoError) throw activePhotoError;

  const active = (activePhotos || []) as any[];
  const validScrambleFingerprints = new Set<string>();
  const seenScrambleImages = new Set<string>();
  let scrambleInsertedOrUpdated = 0;
  let scrambleRetired = 0;

  for (const photo of active) {
    const imageUrl = clean(photo.image_url);
    const species = clean(photo.species);
    const imageKey = imageIdentity(imageUrl);
    if (!imageUrl || !species || seenScrambleImages.has(imageKey)) continue;
    seenScrambleImages.add(imageKey);

    const fingerprint = await sha256(
      `scramble|${normalize(species)}|${normalize(imageUrl)}`,
    );
    validScrambleFingerprints.add(fingerprint);

    const scrambleRow = {
      category: "scramble",
      species,
      bengali: clean(photo.bengali),
      question: "ছবিটি জোড়া লাগিয়ে চিনুন",
      options: [],
      answer: species,
      hints: Array.isArray(photo.hints)
        ? photo.hints.map(clean).filter(Boolean)
        : [],
      syllables: [],
      image_url: imageUrl,
      audio_url: null,
      image_source: clean(photo.image_source) || "iNaturalist",
      audio_source: null,
      attribution: clean(photo.attribution) || null,
      explanation: clean(photo.explanation) || null,
      difficulty: "medium",
      active: true,
      source: "visual-universal-set",
      generation_provider: "Visual universal set",
      fingerprint,
      updated_at: new Date().toISOString(),
    };

    const { error: upsertError } = await admin
      .from("game_questions")
      .upsert(scrambleRow, { onConflict: "fingerprint" });
    if (upsertError) throw upsertError;
    scrambleInsertedOrUpdated++;
  }

  const { data: scrambleRows, error: scrambleReadError } = await admin
    .from("game_questions")
    .select("id,fingerprint,image_url,active")
    .eq("category", "scramble")
    .eq("active", true);
  if (scrambleReadError) throw scrambleReadError;

  for (const row of (scrambleRows || []) as any[]) {
    const fp = clean(row.fingerprint);
    if (fp && validScrambleFingerprints.has(fp)) continue;
    if (!clean(row.id)) continue;
    const { error: retireError } = await admin
      .from("game_questions")
      .update({ active: false, updated_at: new Date().toISOString() })
      .eq("id", row.id);
    if (retireError) throw retireError;
    scrambleRetired++;
  }

  return {
    photoRetired,
    photoFromWordInsertedOrUpdated,
    scrambleInsertedOrUpdated,
    scrambleRetired,
    universalVisualSpecies: visualSources.length,
    hintsInserted: 0,
  };
}

function validRecord(r: any): boolean {
  const category = clean(r?.category) as Category;

  if (!GENERATED_CATEGORIES.includes(category as GeneratedCategory)) return false;

  const species = clean(r?.species);
  const bengali = clean(r?.bengali);
  const question = clean(r?.question);
  const answer = clean(r?.answer);

  if (
    !species ||
    !bengali ||
    !question ||
    !answer ||
    !containsBengali(bengali) ||
    !containsBengali(question)
  ) {
    return false;
  }

  const options = Array.isArray(r?.options)
    ? r.options.map(clean).filter(Boolean)
    : [];

  const hints = Array.isArray(r?.hints)
    ? r.hints.map(clean).filter(Boolean)
    : [];

  if (
    (category === "photo" || category === "audio" || category === "hint") &&
    (options.length !== 4 || !options.includes(answer))
  ) {
    return false;
  }

  if (category === "hint") {
    if (!hintsAreValid(hints, species, bengali)) return false;
  }

  if (!DIFFICULTIES.includes(clean(r?.difficulty) as any)) return false;

  const wordPhrase = "বাংলা নামটি অক্ষর সাজিয়ে সম্পূর্ণ করুন";
  if (question.includes(wordPhrase)) return false;
  if (category === "audio" && !/পাখ|ডাক|শব্দ|কণ্ঠ|গান/.test(question)) return false;
  if (
    category === "photo" &&
    !/ছবি|ছবিতে|ছবিটি|প্রাণী|পাখি|সরীসৃপ|উভচর|স্তন্যপায়ী/.test(question)
  ) return false;
  if (
    category === "hint" &&
    !/ইঙ্গিত|লক্ষণ|চিহ্ন|চেন|প্রাণী|পাখি/.test(question)
  ) return false;

  return true;
}

async function enrichMedia(category: Category, species: string) {
  if (category === "audio") {
    const audio = await fetchAudio(species);
    return audio
      ? {
        audio_url: audio.url,
        audio_source: audio.source,
        attribution: audio.attribution,
      }
      : null;
  }

  const image = await fetchImage(species);
  return image
    ? {
      image_url: image.url,
      image_source: image.source,
      attribution: image.attribution,
    }
    : null;
}

async function syncWordBank(admin: any, birdNames: BirdName[]) {
  const { data: existing, error } = await admin
    .from("game_questions")
    .select(
      "id,species,bengali,active,fingerprint,image_url,image_source,attribution,question,syllables,source,generation_provider",
    )
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

    const matches = rows.filter(
      (row) => normalize(clean(row.species)) === speciesKey,
    );

    const exact = matches.find(
      (row) => normalize(clean(row.bengali)) === normalize(bengali),
    );

    if (exact) {
      const image = clean(exact.image_url) ? null : await fetchWordImage(bird.english);

      const needsUpdate =
        clean(exact.fingerprint) !== fingerprint ||
        clean(exact.question) !== question ||
        JSON.stringify(exact.syllables || []) !== JSON.stringify(tiles) ||
        exact.active !== true ||
        clean(exact.source).toLowerCase() !== "naturesbook" ||
        clean(exact.generation_provider).toLowerCase() !== "nature's book" ||
        (!!image && clean(exact.image_url) !== image.url);

      if (needsUpdate) {
        const { error: updateError } = await admin
          .from("game_questions")
          .update({
            bengali,
            question,
            answer: bengali,
            options: [],
            hints: [],
            syllables: tiles,
            ...(image
              ? {
                image_url: image.url,
                image_source: image.source,
                attribution: image.attribution,
              }
              : {}),
            active: true,
            source: "naturesbook",
            generation_provider: "Nature's Book",
            fingerprint,
            updated_at: new Date().toISOString(),
          })
          .eq("id", exact.id);

        if (updateError) throw updateError;
        corrected++;
      }
    } else {
      const image = await fetchWordImage(bird.english);

      const { error: insertError } = await admin
        .from("game_questions")
        .upsert(
          {
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
            explanation:
              "বাংলা নামটি Nature's Book-এর পাখির নামের তালিকা থেকে নেওয়া হয়েছে।",
            difficulty: "easy",
            active: true,
            source: "naturesbook",
            generation_provider: "Nature's Book",
            fingerprint,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "fingerprint", ignoreDuplicates: true },
        );

      if (insertError) throw insertError;
      inserted++;
    }

    for (const row of matches) {
      if (exact && row.id === exact.id) continue;
      if (normalize(clean(row.bengali)) === normalize(bengali)) continue;

      if (row.active !== false) {
        const { error: retireError } = await admin
          .from("game_questions")
          .update({ active: false, updated_at: new Date().toISOString() })
          .eq("id", row.id);
        if (retireError) throw retireError;
        retired++;
      }
    }
  }

  const sourceKeys = new Set(
    birdNames.map(
      (bird) =>
        `${normalize(bird.english)}|${normalize(
          clean(bird.bengali).split(",")[0].split("/")[0].trim(),
        )}`,
    ),
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

async function cleanupInvalidActiveRows(admin: any): Promise<number> {
  const { data, error } = await admin
    .from("game_questions")
    .select(
      "id,category,species,bengali,question,options,hints,image_url,audio_url,source,generation_provider,active",
    )
    .eq("active", true);

  if (error) throw error;

  const wordPhrase = "বাংলা নামটি অক্ষর সাজিয়ে সম্পূর্ণ করুন";
  const invalidIds: string[] = [];

  for (const row of (data || []) as any[]) {
    const category = clean(row.category).toLowerCase();
    const species = clean(row.species);
    const bengali = clean(row.bengali);
    const question = clean(row.question);
    const options = Array.isArray(row.options)
      ? row.options.map(clean).filter(Boolean)
      : [];
    const hints = Array.isArray(row.hints)
      ? row.hints.map(clean).filter(Boolean)
      : [];
    const hasImage = clean(row.image_url).length > 0;
    const hasAudio = clean(row.audio_url).length > 0;
    const source = clean(row.source).toLowerCase();
    const provider = clean(row.generation_provider).toLowerCase();

    let invalid = false;
    if (category === "photo") {
      invalid = !hasImage || options.length !== 4 || question.includes(wordPhrase);
    } else if (category === "audio") {
      invalid = !hasAudio || options.length !== 4 || question.includes(wordPhrase);
    } else if (category === "hint") {
      invalid =
        options.length !== 4 ||
        hints.length !== 3 ||
        question.includes(wordPhrase) ||
        !hintsAreValid(hints, species, bengali);
    } else if (category === "scramble") {
      invalid = !hasImage;
    } else if (category === "word") {
      invalid =
        source !== "naturesbook" ||
        provider !== "nature's book" ||
        question !== wordPhrase;
    } else {
      invalid = true;
    }

    if (invalid && clean(row.id)) invalidIds.push(clean(row.id));
  }

  if (!invalidIds.length) return 0;

  const { error: updateError } = await admin
    .from("game_questions")
    .update({ active: false, updated_at: new Date().toISOString() })
    .in("id", invalidIds);

  if (updateError) throw updateError;
  return invalidIds.length;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return json({ ok: false, error: "POST required." }, 405);
  }

  let requestBody: any = {};
  try {
    const rawBody = await req.text();
    if (rawBody.trim()) requestBody = JSON.parse(rawBody);
  } catch (_) {
    requestBody = {};
  }

  const headerSecret = clean(req.headers.get("x-game-generator-secret"));
  const bodySecret = clean(requestBody?.secret);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!apiKey || !supabaseUrl || !serviceRoleKey) {
    return json(
      { ok: false, error: "Game generator server configuration is incomplete." },
      500,
    );
  }

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: config, error: configError } = await admin
      .from("game_generator_config")
      .select("secret")
      .eq("id", 1)
      .maybeSingle();

    if (configError) {
      return json(
        {
          ok: false,
          stage: "authorization_config",
          error: `Could not read game_generator_config: ${configError.message}`,
        },
        500,
      );
    }

    const configuredSecret = clean(config?.secret);
    const environmentSecret = clean(Deno.env.get("GAME_GENERATOR_SECRET"));
    const suppliedSecret = headerSecret || bodySecret;

    const authorized =
      suppliedSecret.length > 0 &&
      ((configuredSecret.length > 0 && suppliedSecret === configuredSecret) ||
        (environmentSecret.length > 0 && suppliedSecret === environmentSecret));

    if (!authorized) {
      return json(
        {
          ok: false,
          stage: "authorization",
          error:
            "Unauthorized. Provide the game generator secret using the x-game-generator-secret header or the JSON field 'secret'.",
          hasDatabaseSecret: configuredSecret.length > 0,
          hasEnvironmentSecret: environmentSecret.length > 0,
        },
        401,
      );
    }

    console.log("generate-game-bank: authorization successful");

    console.log("generate-game-bank: cleaning invalid rows");
    const cleanedInvalid = await cleanupInvalidActiveRows(admin);

    console.log("generate-game-bank: fetching Nature's Book bird names");
    const parsedBirdNames = await fetchNaturesBookBirdNames();

    console.log(
      `generate-game-bank: parsed ${parsedBirdNames.length} bird names`,
    );
    const birdValidation = await filterToVerifiedBirds(parsedBirdNames);
    const birdNames = birdValidation.birds;
    console.log(`generate-game-bank: verified ${birdNames.length} bird names`);

    const wordSync = await syncWordBank(admin, birdNames);
    console.log("generate-game-bank: word bank synchronized", wordSync);

    if (requestBody?.sync_words_only === true) {
      return json({
        ok: true,
        syncOnly: true,
        wordSync,
        cleanedInvalid,
        birdValidation: {
          parsed: parsedBirdNames.length,
          verified: birdNames.length,
          rejected: birdValidation.rejected,
        },
      });
    }

    console.log("generate-game-bank: repairing universal visual bank");
    const beforeRepair = await repairVisualBank(admin);
    console.log("generate-game-bank: visual bank repaired", beforeRepair);

    console.log("generate-game-bank: repairing universal bird-call bank");
    const audioRepair = await repairAudioBank(admin, birdNames);
    console.log("generate-game-bank: bird-call bank repaired", audioRepair);

    console.log(
      `generate-game-bank: generating ${GENERATION_COUNT} supplemental records with ${MODEL}`,
    );
    const generated = await geminiGenerate(apiKey);

    const { data: activePhotoRows, error: activePhotoError } = await admin
      .from("game_questions")
      .select("species,image_url")
      .eq("category", "photo")
      .eq("active", true);
    if (activePhotoError) throw activePhotoError;

    const usedPhotoImages = new Set<string>();
    const usedPhotoSpecies = new Set<string>();
    for (const row of (activePhotoRows || []) as any[]) {
      const image = clean(row.image_url);
      const species = normalize(clean(row.species));
      if (image) usedPhotoImages.add(image);
      if (species) usedPhotoSpecies.add(species);
    }

    const usedCategorySpecies = new Map<string, Set<string>>([
      ["photo", new Set(usedPhotoSpecies)],
      ["audio", new Set<string>()],
      ["hint", new Set<string>()],
    ]);

    // HINT records must be restricted to species already present in the
    // visual pool.  visualSpecies is populated below as photo records land.
    const visualSpecies = new Set<string>();

    let inserted = 0;
    let rejected = 0;
    let noMedia = 0;
    let duplicateMedia = 0;
    let duplicateSpecies = 0;
    let hintOutsideVisualSet = 0;
    let badHints = 0;

    for (const raw of generated) {
      if (!validRecord(raw)) {
        if (clean(raw?.category) === "hint") badHints++;
        rejected++;
        continue;
      }

      const category = clean(raw.category) as GeneratedCategory;
      const species = clean(raw.species);
      const bengali = clean(raw.bengali);
      const question = clean(raw.question);
      const speciesKey = normalize(species);

      if (!speciesKey) {
        rejected++;
        continue;
      }

      if (
        category === "hint" &&
        visualSpecies.size > 0 &&
        !visualSpecies.has(speciesKey)
      ) {
        hintOutsideVisualSet++;
        continue;
      }

      const categorySpecies = usedCategorySpecies.get(category)!;
      if (categorySpecies.has(speciesKey)) {
        duplicateSpecies++;
        continue;
      }

      let media: Record<string, string | null> | null = null;
      if (category === "photo") {
        media = await enrichMedia(category, species);
        if (!media) {
          noMedia++;
          continue;
        }
        const imageUrl = clean(media.image_url);
        if (!imageUrl) {
          noMedia++;
          continue;
        }
        if (usedPhotoImages.has(imageUrl)) {
          duplicateMedia++;
          continue;
        }
        usedPhotoImages.add(imageUrl);
        visualSpecies.add(speciesKey);
      } else if (category === "audio") {
        media = await enrichMedia(category, species);
        if (!media) {
          noMedia++;
          continue;
        }
      }

      categorySpecies.add(speciesKey);

      // Gemini supplied options; shuffle before persisting so the answer
      // is not always first.
      const rawOptions = Array.isArray(raw.options)
        ? raw.options.map(clean).filter(Boolean)
        : [];
      const answer = clean(raw.answer);
      const fingerprint = await sha256(
        `${category}|${normalize(question)}|${speciesKey}|${normalize(bengali)}`,
      );

      let options = rawOptions;
      if (
        (category === "photo" || category === "audio" || category === "hint") &&
        rawOptions.length === 4
      ) {
        options = deterministicShuffle(rawOptions, fingerprint);
        if (!options.includes(answer)) {
          // Answer string didn't survive the round-trip — reject rather
          // than silently insert a broken row.
          rejected++;
          continue;
        }
      }

      const row: any = {
        category,
        species,
        bengali,
        question,
        options,
        answer,
        hints: Array.isArray(raw.hints) ? raw.hints.map(clean) : [],
        syllables: Array.isArray(raw.syllables) ? raw.syllables.map(clean) : [],
        explanation: clean(raw.explanation) || null,
        difficulty: DIFFICULTIES.includes(clean(raw.difficulty) as any)
          ? clean(raw.difficulty)
          : "medium",
        active: true,
        source: "gemini",
        generation_provider: `Gemini ${MODEL} with retry/fallback`,
        fingerprint,
        ...(media || {}),
      };

      const { error } = await admin
        .from("game_questions")
        .upsert(row, { onConflict: "fingerprint", ignoreDuplicates: true });

      if (error) {
        throw new Error(`Game-bank insert failed: ${error.message}`);
      }

      inserted++;
    }

    console.log("generate-game-bank: final universal visual-bank repair");
    const afterRepair = await repairVisualBank(admin);

    // Single authoritative difficulty pass — replaces all previous
    // difficultyForIndex / difficultyFor / per-run labels.
    console.log("generate-game-bank: rebalancing difficulty across all categories");
    const difficultyBank = await rebalanceAllCategories(admin);
    console.log("generate-game-bank: difficulty bank", difficultyBank);

    return json({
      ok: true,
      model: MODEL,
      requested: GENERATION_COUNT,
      received: generated.length,
      inserted,
      rejected,
      badHints,
      noMedia,
      duplicateMedia,
      duplicateSpecies,
      hintOutsideVisualSet,
      visualBank: { before: beforeRepair, after: afterRepair },
      audioBank: audioRepair,
      difficultyBank,
      wordSync,
      cleanedInvalid,
      birdValidation: {
        parsed: parsedBirdNames.length,
        verified: birdNames.length,
        rejected: birdValidation.rejected,
      },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("generate-game-bank failed:", message, e);
    return json({ ok: false, stage: "generation", error: message }, 500);
  }
});