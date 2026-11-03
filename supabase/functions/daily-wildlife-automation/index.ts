import { createClient } from "npm:@supabase/supabase-js@2";
import {
  isAnimalType,
  isEditoriallyEligibleCandidate,
  isExistingRecordEditoriallyEligible,
  isReuseCompatibleLicense,
  isImageProvenanceValidForSpecies,
  getCandidateRejectionReason,
  KNOWN_RETAINED_CONSERVATION_SPECIES,
} from "./editorial_guardrails.ts";

export {
  isAnimalType,
  isEditoriallyEligibleCandidate,
  isExistingRecordEditoriallyEligible,
  isReuseCompatibleLicense,
  isImageProvenanceValidForSpecies,
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, x-daily-wildlife-secret, content-type',
};

const GEMINI_MODELS = [
  "gemini-3.1-flash-lite",
  "gemini-2.5-flash",
  "gemini-1.5-flash",
];

async function callGemini(
  geminiKey: string,
  prompt: string,
  options: {
    temperature?: number;
    responseMimeType?: string;
  } = {}
): Promise<{ ok: true; text: string; model: string } | { ok: false; error: string; status?: number }> {
  let lastError = 'No model attempted';
  let lastStatus = 500;

  for (const model of GEMINI_MODELS) {
    const endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent?key=" + encodeURIComponent(geminiKey);
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: options.temperature ?? 0.7,
            ...(options.responseMimeType ? { responseMimeType: options.responseMimeType } : {})
          }
        })
      });

      if (res.ok) {
        const json = await res.json();
        const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
        if (typeof text === 'string' && text.trim().length > 0) {
          return { ok: true, text, model };
        }
        lastError = "Model " + model + " returned empty content parts";
        lastStatus = 200;
        console.warn("[Daily Wildlife] " + lastError);
      } else {
        const errBody = await res.text();
        lastError = "Model " + model + " HTTP " + res.status + ": " + errBody.slice(0, 500);
        lastStatus = res.status;
        console.warn("[Daily Wildlife] " + lastError);
      }
    } catch (e: any) {
      lastError = "Model " + model + " fetch exception: " + e.message;
      console.warn("[Daily Wildlife] " + lastError);
    }
  }

  return { ok: false, error: lastError, status: lastStatus };
}

function extractJsonArray(rawText: string): any[] | null {
  if (!rawText) return null;
  let cleaned = rawText.trim();
  cleaned = cleaned.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();

  try {
    const parsed = JSON.parse(cleaned);
    if (Array.isArray(parsed)) return parsed;
    if (parsed && Array.isArray(parsed.candidates)) return parsed.candidates;
    if (parsed && Array.isArray(parsed.species)) return parsed.species;
  } catch (_) {
    const startIdx = cleaned.indexOf('[');
    const endIdx = cleaned.lastIndexOf(']');
    if (startIdx !== -1 && endIdx > startIdx) {
      try {
        const substring = cleaned.substring(startIdx, endIdx + 1);
        const parsed = JSON.parse(substring);
        if (Array.isArray(parsed)) return parsed;
      } catch (_) {}
    }
  }
  return null;
}

function extractJsonObject(rawText: string): any | null {
  if (!rawText) return null;
  let cleaned = rawText.trim();
  cleaned = cleaned.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();

  try {
    const parsed = JSON.parse(cleaned);
    if (parsed && typeof parsed === 'object') return parsed;
  } catch (_) {
    const startIdx = cleaned.indexOf('{');
    const endIdx = cleaned.lastIndexOf('}');
    if (startIdx !== -1 && endIdx > startIdx) {
      try {
        const substring = cleaned.substring(startIdx, endIdx + 1);
        const parsed = JSON.parse(substring);
        if (parsed && typeof parsed === 'object') return parsed;
      } catch (_) {}
    }
  }
  return null;
}

async function authenticateRequest(
  req: Request,
  supabaseUrl: string,
  serviceRoleKey: string
): Promise<{ ok: true; caller: 'internal' | 'admin'; userId?: string } | { ok: false; response: Response }> {
  const json = (body: Record<string, unknown>, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  const internalSecret = Deno.env.get('DAILY_WILDLIFE_INTERNAL_SECRET')?.trim();

  const secretHeader = req.headers.get('x-daily-wildlife-secret')?.trim();
  if (secretHeader) {
    if (!internalSecret) {
      return {
        ok: false,
        response: json({ error: 'DAILY_WILDLIFE_INTERNAL_SECRET is not configured' }, 500),
      };
    }
    if (secretHeader === internalSecret) {
      return { ok: true, caller: 'internal' };
    }
    return {
      ok: false,
      response: json({ error: 'Invalid internal automation secret' }, 403),
    };
  }

  const authHeader = req.headers.get('authorization')?.trim();
  if (!authHeader) {
    return {
      ok: false,
      response: json({ error: 'Authentication required' }, 401),
    };
  }

  const tokenMatch = /^Bearer\s+(.+)$/i.exec(authHeader);
  if (!tokenMatch || !tokenMatch[1]) {
    return {
      ok: false,
      response: json({ error: 'Authentication required' }, 401),
    };
  }

  const token = tokenMatch[1].trim();

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  let authenticatedUser: { id: string; email?: string | null } | null = null;
  try {
    const userResponse = await fetch(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/user`, {
      method: 'GET',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${token}`,
      },
    });
    if (userResponse.ok) {
      const userJson = await userResponse.json();
      if (typeof userJson?.id === 'string') {
        authenticatedUser = { id: userJson.id, email: userJson.email ?? null };
      }
    }
  } catch (error) {
    console.error('[Daily Wildlife] Supabase Auth user validation failed:', error);
  }

  if (!authenticatedUser) {
    return {
      ok: false,
      response: json({ error: 'Invalid or expired Supabase session' }, 401),
    };
  }

  const userId = authenticatedUser.id;
  const userEmail = authenticatedUser.email;

  let isAdmin = false;

  const { data: profile } = await adminClient
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .maybeSingle();

  if (profile?.role === 'admin') {
    isAdmin = true;
  } else if (userEmail) {
    const { data: adminRow } = await adminClient
      .from('admins')
      .select('email')
      .eq('email', userEmail)
      .maybeSingle();

    if (adminRow) {
      isAdmin = true;
    }
  }

  if (!isAdmin) {
    return {
      ok: false,
      response: json({ error: 'Administrator access required' }, 403),
    };
  }

  return { ok: true, caller: 'admin', userId };
}

async function fetchINatTaxon(scientificName: string) {
    try {
        const res = await fetch(`https://api.inaturalist.org/v1/taxa?q=${encodeURIComponent(scientificName)}&rank=species`);
        if (res.ok) {
            const json = await res.json();
            const results = json.results || [];
            const sciLower = scientificName.toLowerCase().trim();
            for (const item of results) {
                const nameLower = (item.name || '').toLowerCase().trim();
                const matchedLower = (item.matched_term || '').toLowerCase().trim();
                if (nameLower === sciLower || matchedLower === sciLower || nameLower.startsWith(sciLower.split(' ')[0])) {
                    return item;
                }
            }
            return results[0] || null;
        }
        console.error(`[Daily Wildlife] iNat fetch failed: ${res.status}`);
    } catch (e: any) {
        console.error(`[Daily Wildlife] iNat error: ${e.message}`);
    }
    return null;
}

async function fetchEBirdData(scientificName: string) {
    const apiKey = Deno.env.get('eBird_API') ?? Deno.env.get('EBIRD_API_KEY') ?? '';
    if (!apiKey) {
        console.warn('[Daily Wildlife] EBIRD_API_KEY is not configured; eBird data unavailable.');
        return null;
    }
    try {
        const res = await fetch(`https://api.ebird.org/v2/ref/taxonomy/ebird?sciName=${encodeURIComponent(scientificName)}&fmt=json`, {
            headers: { 'X-eBirdApiToken': apiKey, 'Accept': 'application/json' }
        });
        if (res.ok) {
            const json = await res.json();
            return json?.[0] || null;
        }
        console.error(`[Daily Wildlife] eBird fetch failed: ${res.status}: ${await res.text()}`);
    } catch (e: any) {
        console.error(`[Daily Wildlife] eBird error: ${e.message}`);
    }
    return null;
}

type ImageCandidate = {
    provider: string;
    source_id: string | null;
    source_url: string;
    image_url: string;
    creator: string | null;
    license: string | null;
    license_url: string | null;
    attribution: string | null;
    retrieved_at: string;
};

async function findWikimediaCommonsImage(scientificName: string, commonName: string): Promise<ImageCandidate | null> {
    const queries = [scientificName, commonName].filter(Boolean);
    const EXCLUDED_TITLE_PATTERNS = /(map|distmap|distribution|range|skull|fossil|skeleton|diagram|taxobox|museum|specimen|drawing|illustration|stamp|coin)/i;
    const GENERIC_LOCATION_WORDS = new Set(['gangetic', 'ganges', 'indian', 'bengal', 'river', 'common', 'asian', 'great', 'white', 'small', 'lesser', 'southern', 'northern', 'eastern', 'western']);

    const sciWords = scientificName.toLowerCase().split(/\s+/).filter(w => w.length > 3 && !GENERIC_LOCATION_WORDS.has(w));
    const commonWords = commonName.toLowerCase().split(/\s+/).filter(w => w.length > 3 && !GENERIC_LOCATION_WORDS.has(w));

    for (const query of queries) {
        try {
            const params = new URLSearchParams({
                action: 'query',
                generator: 'search',
                gsrsearch: query,
                gsrnamespace: '6',
                gsrlimit: '20',
                prop: 'imageinfo',
                iiprop: 'url|mime|size|extmetadata|canonicaltitle',
                iiurlwidth: '1600',
                format: 'json',
                origin: '*'
            });
            const res = await fetch(`https://commons.wikimedia.org/w/api.php?${params.toString()}`, {
                headers: { 'User-Agent': 'eAranyak/1.0 DailyWildlife/1.0' }
            });
            if (!res.ok) {
                console.error(`[Daily Wildlife] Wikimedia Commons search failed: ${res.status}`);
                continue;
            }
            const json = await res.json();
            const pages = Object.values(json?.query?.pages ?? {}) as any[];
            for (const page of pages) {
                const info = page?.imageinfo?.[0];
                if (!info?.url || !String(info.mime || '').startsWith('image/')) continue;
                if ((Number(info.width) || 0) < 600 || (Number(info.height) || 0) < 400) continue;

                const title = String(page.title || '');
                if (EXCLUDED_TITLE_PATTERNS.test(title)) {
                    continue;
                }

                const titleNormalized = title.replace(/^File:/i, '').replace(/[_-]+/g, ' ').toLowerCase();

                // Strict title match check to prevent cross-species mismatch
                const matchesSci = sciWords.some(w => titleNormalized.includes(w));
                const matchesCommon = commonWords.some(w => titleNormalized.includes(w));
                if (!matchesSci && !matchesCommon) {
                    console.warn(`[Daily Wildlife] Rejected Wikimedia result with weak taxon/title match for ${commonName}: ${page.title}`);
                    continue;
                }

                // Contradicting taxon check: if searching for non-tiger species, reject titles with tiger/panthera
                if (!scientificName.toLowerCase().includes('panthera tigris')) {
                    const tigerKeywords = ['panthera tigris', 'panthera_tigris', 'bengal tiger', 'bengal_tiger', 'tiger in', 'tiger_in'];
                    if (tigerKeywords.some(kw => titleNormalized.includes(kw))) {
                        console.warn(`[Daily Wildlife] Rejected cross-species tiger image for ${commonName}: ${page.title}`);
                        continue;
                    }
                }

                const meta = info.extmetadata ?? {};
                const value = (key: string) => meta[key]?.value ? String(meta[key].value).replace(/<[^>]+>/g, '').trim() : null;
                const creator = value('Artist') || value('Credit') || info.user || null;
                const license = value('LicenseShortName') || value('UsageTerms') || null;
                const licenseUrl = value('LicenseUrl') || null;
                if (!isReuseCompatibleLicense(license)) {
                    console.warn(`[Daily Wildlife] Rejected Wikimedia image with missing or incompatible licence: ${page.title}`);
                    continue;
                }

                if (scientificName.toLowerCase().includes('panthera tigris')) {
                   const OtherTigerSubspecies = ['sumatran', 'sumatrae', 'altaica', 'siberian', 'sibirischer', 'amur', 'sondaica', 'balica', 'virgata', 'corbetti', 'jacksoni', 'indochinese', 'malayan', 'caspian'];
                   if (OtherTigerSubspecies.some(sub => titleNormalized.includes(sub))) {
                      console.warn(`[Daily Wildlife] Rejected Wikimedia tiger subspecies mismatch: ${page.title}`);
                      continue;
                   }
                }

                const sourceUrl = `https://commons.wikimedia.org/wiki/${encodeURIComponent(title.replace(/ /g, '_'))}`;
                const attribution = creator && license ? `© ${creator}; ${license}; Wikimedia Commons` : `Wikimedia Commons; ${creator || 'creator unavailable'}; ${license || 'license unavailable'}`;
                return {
                    provider: 'Wikimedia Commons',
                    source_id: page.pageid?.toString() || page.title || null,
                    source_url: sourceUrl,
                    image_url: info.url,
                    creator,
                    license,
                    license_url: licenseUrl,
                    attribution,
                    retrieved_at: new Date().toISOString()
                };
            }
        } catch (e: any) {
            console.error(`[Daily Wildlife] Wikimedia Commons error: ${e.message}`);
        }
    }
    return null;
}

async function downloadAndStoreSourceImage(
    supabase: any,
    candidate: ImageCandidate,
    featureId: string
): Promise<{ candidate: ImageCandidate; storagePath: string; storageUrl: string } | null> {
    try {
        const res = await fetch(candidate.image_url, {
            headers: { 'User-Agent': 'eAranyak/1.0 DailyWildlife/1.0', 'Accept': 'image/*' },
            redirect: 'follow'
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const mime = (res.headers.get('content-type') || 'image/jpeg').split(';')[0];
        if (!mime.startsWith('image/')) throw new Error(`Unexpected content type ${mime}`);
        const bytes = new Uint8Array(await res.arrayBuffer());
        if (bytes.length < 2048) throw new Error('Image response too small');
        const ext = mime === 'image/png' ? 'png' : mime === 'image/webp' ? 'webp' : 'jpg';
        const storagePath = `daily_sources/${featureId}-${Date.now()}.${ext}`;
        const { error } = await supabase.storage.from('wildlife_gallery').upload(storagePath, bytes, { contentType: mime, upsert: false });
        if (error) throw new Error(`Storage upload failed: ${error.message}`);

        const { data, error: signedError } = await supabase.storage
            .from('wildlife_gallery')
            .createSignedUrl(storagePath, 60 * 60 * 24 * 365);
        if (signedError || !data?.signedUrl) {
            throw new Error(`Storage signed URL unavailable: ${signedError?.message || 'unknown error'}`);
        }
        return {
            candidate: { ...candidate, image_url: data.signedUrl },
            storagePath,
            storageUrl: data.signedUrl
        };
    } catch (e: any) {
        console.error(`[Daily Wildlife] Source image download/store failed for ${candidate.provider}: ${e.message}`);
        return null;
    }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? '';

    if (!supabaseUrl || !serviceRoleKey) {
        return new Response(JSON.stringify({ error: 'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const authCheck = await authenticateRequest(req, supabaseUrl, serviceRoleKey);
    if (!authCheck.ok) return authCheck.response;

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const failures: Array<{ stage: string; message: string; featureId?: string }> = [];
    const recordFailure = (stage: string, message: string, featureId?: string) => {
      console.error(`[Daily Wildlife] ${stage}: ${message}`);
      failures.push({ stage, message, ...(featureId ? { featureId } : {}) });
    };

    if (!geminiKey) {
      return new Response(JSON.stringify({ error: 'GEMINI_API_KEY is not configured.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const istOffset = 5.5 * 60 * 60 * 1000;
    const nowUtc = new Date();
    const istTime = new Date(nowUtc.getTime() + istOffset);
    const todayStr = istTime.toISOString().split('T')[0];

    console.log(`[Daily Wildlife] Current IST date: ${todayStr}`);

    // --- STEP 1: PUBLISH TODAY'S FEATURE ---
    const { data: publishedFeatures, error: pubError } = await supabase
        .from('daily_wildlife_features')
        .update({
            status: 'published',
            is_published: true,
            published_at: nowUtc.toISOString()
        })
        .lte('feature_date', todayStr)
        .eq('status', 'scheduled')
        .eq('image_generation_status', 'completed')
        .eq('is_published', false)
        .lte('scheduled_publish_at', nowUtc.toISOString())
        .select('id');

    if (pubError) {
        recordFailure('publish', pubError.message || String(pubError));
    } else if (publishedFeatures && publishedFeatures.length > 0) {
        console.log(`[Daily Wildlife] Successfully published feature(s) for today (${todayStr}):`, publishedFeatures.map((f: { id: string }) => f.id));
    }

    // --- STEP 2: MAINTAIN & RECONCILE 7 DAYS QUEUE ---
    const next7Days: string[] = [];
    for (let i = 0; i <= 6; i++) {
        const d = new Date(istTime.getTime());
        d.setDate(d.getDate() + i);
        next7Days.push(d.toISOString().split('T')[0]);
    }

    const { data: upcomingFeatures, error: upcomingError } = await supabase
        .from('daily_wildlife_features')
        .select('*')
        .in('feature_date', next7Days)
        .order('feature_date', { ascending: true });

    if (upcomingError) recordFailure('planning_lookup', upcomingError.message);

    const existingByDate = new Map<string, any>();
    for (const f of (upcomingFeatures || [])) {
      existingByDate.set(f.feature_date, f);
    }

    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const { data: recentSpecies, error: recentSpeciesError } = await supabase
        .from('daily_wildlife_features')
        .select('scientific_name')
        .gte('feature_date', ninetyDaysAgo);
    if (recentSpeciesError) recordFailure('planning_duplicate_lookup', recentSpeciesError.message);

    const seenScientificNames = new Set<string>(
        (recentSpecies || []).map((row: { scientific_name: string | null }) =>
            (row.scientific_name || '').trim().toLowerCase()
        ).filter(Boolean)
    );

    const datesNeedingCandidate: string[] = [];
    const invalidRowIdsToClear: Map<string, any> = new Map();

    for (const dateStr of next7Days) {
      const existing = existingByDate.get(dateStr);
      if (!existing) {
        datesNeedingCandidate.push(dateStr);
        continue;
      }

      if (existing.editor_override === true || existing.is_published === true) {
        if (existing.scientific_name) {
          seenScientificNames.add(existing.scientific_name.trim().toLowerCase());
        }
        continue;
      }

      if (!isAnimalType(existing.animal_type)) {
        console.warn(`[Daily Wildlife Audit] Date ${dateStr} entry '${existing.common_name}' (${existing.scientific_name || existing.animal_type}) is non-animal/ineligible. Flagged for replacement.`);
        invalidRowIdsToClear.set(dateStr, existing);
        datesNeedingCandidate.push(dateStr);
        continue;
      }

      if (!isExistingRecordEditoriallyEligible(existing)) {
        console.warn(`[Daily Wildlife Audit] Date ${dateStr} entry '${existing.common_name}' lacks required conservation/ecological rationale or reference. Flagged for candidate replacement.`);
        invalidRowIdsToClear.set(dateStr, existing);
        datesNeedingCandidate.push(dateStr);
        continue;
      }

      if (existing.original_image_url || existing.image_provenance) {
        const provValid = isImageProvenanceValidForSpecies(existing.scientific_name, existing.image_provenance);
        if (!provValid) {
          console.warn(`[Daily Wildlife Audit] Date ${dateStr} entry '${existing.common_name}' has invalid/mismatched image provenance. Resetting image to re-fetch.`);
          await supabase.from('daily_wildlife_features').update({
            original_image_url: null,
            image_provenance: null,
            image_generation_status: 'pending',
            image_generation_error: 'Image provenance failed audit (subspecies or license mismatch). Re-resolving source image.',
            status: 'planned'
          }).eq('id', existing.id);
        }
      }

      if (existing.scientific_name) {
        seenScientificNames.add(existing.scientific_name.trim().toLowerCase());
      }
    }

    if (datesNeedingCandidate.length > 0) {
      console.log(`[Daily Wildlife] Queue reconciliation: ${datesNeedingCandidate.length} dates need candidates:`, datesNeedingCandidate);

      let replacementCandidates: any[] = [];

      const numRequested = Math.max(datesNeedingCandidate.length + 5, 12);

      const planningPrompt = `You are the conservation editor for eআরণ্যক, a Bengali wildlife education app.
Generate exactly ${numRequested} DISTINCT, scientifically valid ANIMAL species native to India, prioritising Bengal and nearby Indian ecosystems.

EDITORIAL MISSION (strict):
- Feature rare, threatened, endangered, ecologically significant and/or economically significant ANIMALS ONLY.
- Strongly prioritise IUCN Critically Endangered, Endangered, and Vulnerable species.
- Include mammals, birds, reptiles, amphibians, fish, or invertebrates where genuinely justified.
- DO NOT select plants, trees, mangroves, fungi, or other non-animals.
- DO NOT select familiar/common species solely because they are popular, colourful, or national symbols without a critical conservation priority.
- Do not assert a conservation category or ecological claim without a credible reference.
- Avoid duplicate species. Use valid Latin binomials.

VALIDATION CONSTRAINTS (each field is machine-validated — do not deviate):
- "commonName": non-empty English string (e.g. "Fishing Cat")
- "scientificName": valid Latin binomial, non-empty (e.g. "Prionailurus viverrinus")
- "type": must be one of: mammal, bird, reptile, amphibian, fish, insect, arachnid, crustacean, mollusc, invertebrate, animal
- "conservationStatus": must be one of: Critically Endangered, Endangered, Vulnerable, Near Threatened, Data Deficient (or abbreviations CR, EN, VU, NT, DD)
- "ecologicalSignificance": string at least 20 chars describing ecological role
- "economicSignificance": string at least 20 chars describing economic value
- "reason": string at least 30 chars explaining why this species deserves featuring
- "referenceUrl": must be a valid HTTPS URL to a credible source (IUCN Red List, ZSI, WII, MoEFCC, WWF, etc.) — must start with "https://"

Respond ONLY with a valid JSON array of objects matching the fields above. Do not wrap in Markdown code fences.`;

      const planningRes = await callGemini(geminiKey, planningPrompt, {
        temperature: 0.7,
        responseMimeType: "application/json"
      });

      if (planningRes.ok) {
        const generated = extractJsonArray(planningRes.text);
        if (Array.isArray(generated)) {
          for (const spec of generated) {
            const guardrailReason = getCandidateRejectionReason(spec);
            if (!guardrailReason) {
              const sciKey = (spec.scientificName || '').trim().toLowerCase();
              if (!seenScientificNames.has(sciKey)) {
                seenScientificNames.add(sciKey);
                replacementCandidates.push(spec);
              } else {
                console.warn("[Daily Wildlife] Candidate " + spec.commonName + " (" + spec.scientificName + ") already in 90-day history; skipping.");
              }
            } else {
              console.warn("[Daily Wildlife] Candidate " + (spec?.commonName || spec?.scientificName || 'unknown') + " rejected by guardrails: " + guardrailReason);
            }
          }
        } else {
          recordFailure('planning_json_parse', "Failed to parse JSON array from Gemini planning response. Raw: " + planningRes.text.slice(0, 300));
        }
      } else {
        recordFailure('planning_gemini_api', planningRes.error);
      }

      if (replacementCandidates.length < datesNeedingCandidate.length) {
        console.log("[Daily Wildlife] Planning attempt 1 found " + replacementCandidates.length + "/" + datesNeedingCandidate.length + " candidates. Retrying Gemini...");
        const retryRes = await callGemini(geminiKey, planningPrompt, {
          temperature: 0.2,
          responseMimeType: "application/json"
        });

        if (retryRes.ok) {
          const retryGenerated = extractJsonArray(retryRes.text);
          if (Array.isArray(retryGenerated)) {
            for (const spec of retryGenerated) {
              if (replacementCandidates.length >= datesNeedingCandidate.length) break;
              const guardrailReason = getCandidateRejectionReason(spec);
              if (!guardrailReason) {
                const sciKey = (spec.scientificName || '').trim().toLowerCase();
                if (!seenScientificNames.has(sciKey)) {
                  seenScientificNames.add(sciKey);
                  replacementCandidates.push(spec);
                }
              }
            }
          }
        } else {
          console.warn("[Daily Wildlife] Gemini planning retry failed: " + retryRes.error);
        }
      }

      // Safety net: If external AI API encountered an outage or deficit,
      // draw verified, compliant Indian conservation species from the curated pool
      if (replacementCandidates.length < datesNeedingCandidate.length) {
        console.warn("[Daily Wildlife] Gemini generated " + replacementCandidates.length + "/" + datesNeedingCandidate.length + " candidates. Drawing remaining from verified conservation species pool...");
        for (const [sciKey, verifiedSpec] of KNOWN_RETAINED_CONSERVATION_SPECIES.entries()) {
          if (replacementCandidates.length >= datesNeedingCandidate.length) break;
          if (!seenScientificNames.has(sciKey)) {
            seenScientificNames.add(sciKey);
            replacementCandidates.push(verifiedSpec);
            console.log("[Daily Wildlife] Added verified conservation fallback candidate: " + verifiedSpec.commonName + " (" + verifiedSpec.scientificName + ")");
          }
        }
      }

      for (let i = 0; i < datesNeedingCandidate.length; i++) {
        const targetDate = datesNeedingCandidate[i];
        const spec = replacementCandidates[i];
        if (!spec) {
          recordFailure('planning_validation', `Could not find an eligible candidate for date ${targetDate}`);
          continue;
        }

        const selectionReason = [
          `Editorial rationale: ${spec.reason.trim()}`,
          `Conservation status: ${spec.conservationStatus.trim()}`,
          `Ecological significance: ${spec.ecologicalSignificance.trim()}`,
          `Economic significance: ${spec.economicSignificance.trim()}`,
          `Reference: ${spec.referenceUrl.trim()}`
        ].join('\n');

        const existingRow = invalidRowIdsToClear.get(targetDate) || existingByDate.get(targetDate);
        if (existingRow) {
          console.log(`[Daily Wildlife] Replacing invalid entry on ${targetDate} (${existingRow.common_name}) with ${spec.commonName} (${spec.scientificName})`);
          const { error: updateError } = await supabase.from('daily_wildlife_features').update({
            title: spec.commonName.trim(),
            common_name: spec.commonName.trim(),
            scientific_name: spec.scientificName.trim(),
            animal_type: spec.type.trim(),
            selection_reason: selectionReason,
            status: 'planned',
            image_generation_status: 'pending',
            image_generation_error: null,
            original_image_url: null,
            image_provenance: null,
            title_bn: null,
            bengali_name: null,
            species_description: null,
            description_bn: null,
            habitat: null,
            distribution: null,
            diet: null,
            behaviour: null,
            ecological_role: null,
            conservation_status: null,
            iucn_status: null,
            interesting_facts: null,
            did_you_know: null,
            source_urls: null,
            source_attributions: null,
            audio_url: null,
            audio_provider: null,
            audio_id: null,
            audio_recordist: null,
            audio_license: null,
            audio_attribution: null,
            is_published: false
          }).eq('id', existingRow.id);

          if (updateError) recordFailure('candidate_replace_update', updateError.message, existingRow.id);
        } else {
          console.log(`[Daily Wildlife] Inserting candidate for missing date ${targetDate}: ${spec.commonName} (${spec.scientificName})`);
          const { error: insertError } = await supabase.from('daily_wildlife_features').insert({
            feature_date: targetDate,
            status: 'planned',
            title: spec.commonName.trim(),
            common_name: spec.commonName.trim(),
            scientific_name: spec.scientificName.trim(),
            animal_type: spec.type.trim(),
            selection_reason: selectionReason,
            is_published: false,
            image_generation_status: 'pending'
          });

          if (insertError) recordFailure('candidate_insert', insertError.message);
        }
      }
    }

    // --- STEP 3: PROCESS 'PLANNED' ITEMS ---
    const { data: plannedFeatures, error: plannedError } = await supabase
      .from('daily_wildlife_features')
      .select('*')
      .eq('status', 'planned')
      .in('feature_date', next7Days)
      .order('feature_date', { ascending: true })
      .limit(7);
    if (plannedError) recordFailure('planned_lookup', plannedError.message);

    if (plannedFeatures && plannedFeatures.length > 0) {
        for (const feature of plannedFeatures) {
            console.log(`[Daily Wildlife] Processing planned feature: ${feature.common_name} (${feature.feature_date})`);

            if (feature.editor_override) {
               console.log(`[Daily Wildlife] Skipping synthesis for ${feature.id} due to editor override`);
               continue;
            }

            if (!isExistingRecordEditoriallyEligible(feature)) {
                const reviewMessage = 'Held for editorial review: this planned entry lacks a qualifying conservation/significance rationale and an HTTPS reference recorded in selection_reason. Add verified evidence before re-queueing.';
                const { error: editorialReviewError } = await supabase
                    .from('daily_wildlife_features')
                    .update({
                        status: 'draft',
                        image_generation_error: reviewMessage
                    })
                    .eq('id', feature.id)
                    .eq('status', 'planned');
                if (editorialReviewError) {
                    recordFailure('editorial_review_hold', editorialReviewError.message, feature.id);
                } else {
                    console.warn(`[Daily Wildlife] Held weak/unsupported planned entry for editorial review: ${feature.common_name}`);
                }
                continue;
            }

            if (!isAnimalType(feature.animal_type)) {
                const reviewMessage = `Excluded from the Daily Wildlife animal series: animal_type is missing or non-animal (${String(feature.animal_type || 'not specified')}). Review manually or move to a separate flora series.`;
                const { error: editorialHoldError } = await supabase
                    .from('daily_wildlife_features')
                    .update({
                        status: 'draft',
                        image_generation_status: 'failed',
                        image_generation_error: reviewMessage
                    })
                    .eq('id', feature.id)
                    .eq('status', 'planned');
                if (editorialHoldError) {
                    recordFailure('editorial_hold', editorialHoldError.message, feature.id);
                } else {
                    console.warn(`[Daily Wildlife] Moved non-animal entry to draft for editorial review: ${feature.common_name}`);
                }
                continue;
            }

            const inatData = await fetchINatTaxon(feature.scientific_name);
            const ebirdData = await fetchEBirdData(feature.scientific_name);

            let originalImageUrl = feature.original_image_url;
            let imageProvenance: any = null;
            if (feature.image_provenance) {
                try { imageProvenance = typeof feature.image_provenance === 'string' ? JSON.parse(feature.image_provenance) : feature.image_provenance; }
                catch (e: any) { recordFailure('image_provenance_parse', e?.message || String(e), feature.id); }
            }

            if (!originalImageUrl) {
                const candidates: ImageCandidate[] = [];
                if (inatData?.default_photo?.url || inatData?.default_photo?.medium_url) {
                    const photo = inatData.default_photo;
                    if (isReuseCompatibleLicense(photo.license_code)) {
                        // Prefer full-size over the 75px square thumb: the row
                        // must never store square/small — that is what renders
                        // pixelated in the editorial Edit preview.
                        const rawInatUrl = (photo.original_url || photo.large_url || photo.medium_url || photo.url);
                        const hiResInatUrl = String(rawInatUrl || '').replace(
                          /\/(square|small|thumb|medium)(\.\w+)(\s*)?$/,
                          '/large$2',
                        );
                        candidates.push({
                            provider: 'iNaturalist',
                            source_id: photo.id?.toString() || null,
                            source_url: photo.id ? `https://www.inaturalist.org/photos/${photo.id}` : `https://www.inaturalist.org/taxa/${inatData.id}`,
                            image_url: hiResInatUrl,
                            creator: photo.attribution_name || null,
                            license: photo.license_code || null,
                            license_url: photo.license_code ? `https://creativecommons.org/licenses/${photo.license_code}/` : null,
                            attribution: photo.attribution || null,
                            retrieved_at: new Date().toISOString()
                        });
                    } else {
                        console.warn(`[Daily Wildlife] Rejected iNaturalist image with missing or incompatible licence for ${feature.common_name}.`);
                    }
                }

                const ebirdPhoto = (ebirdData as any)?.photo || (ebirdData as any)?.photoUrl || (ebirdData as any)?.imageUrl;
                if (ebirdPhoto && isReuseCompatibleLicense((ebirdData as any)?.license)) {
                    candidates.push({
                        provider: 'eBird', source_id: (ebirdData as any)?.speciesCode || null,
                        source_url: `https://ebird.org/species/${(ebirdData as any)?.speciesCode || ''}`,
                        image_url: ebirdPhoto, creator: (ebirdData as any)?.photoCredit || null,
                        license: (ebirdData as any)?.license || null, license_url: null,
                        attribution: (ebirdData as any)?.photoCredit || 'eBird', retrieved_at: new Date().toISOString()
                    });
                }

                const commons = await findWikimediaCommonsImage(feature.scientific_name, feature.common_name);
                if (commons) candidates.push(commons);

                for (const candidate of candidates) {
                    const stored = await downloadAndStoreSourceImage(supabase, candidate, feature.id);
                    if (stored) {
                        originalImageUrl = stored.storageUrl;
                        imageProvenance = {
                            provider: candidate.provider, source_id: candidate.source_id, source_url: candidate.source_url,
                            original_image_url: candidate.image_url, storage_bucket: 'wildlife_gallery',
                            storage_path: stored.storagePath, creator: candidate.creator, license: candidate.license,
                            license_url: candidate.license_url, attribution: candidate.attribution, retrieved_at: candidate.retrieved_at
                        };
                        break;
                    }
                }
            }

            if (originalImageUrl) {
                const { error: imageReadyError } = await supabase.from('daily_wildlife_features').update({
                    image_generation_status: 'completed',
                    image_generation_error: null,
                    original_image_url: originalImageUrl,
                    image_provenance: imageProvenance ? JSON.stringify(imageProvenance) : null
                }).eq('id', feature.id);
                if (imageReadyError) { recordFailure('image_status_update', imageReadyError.message, feature.id); continue; }
            }

            if (!originalImageUrl) {
                const imageFailureMessage = 'No usable source photograph was found from iNaturalist, eBird, or Wikimedia Commons. The feature remains planned and will retry on the next automation run.';
                const { error: imageFailureUpdateError } = await supabase.from('daily_wildlife_features').update({
                    image_generation_status: 'failed',
                    image_generation_error: imageFailureMessage
                }).eq('id', feature.id);
                if (imageFailureUpdateError) recordFailure('image_failure_update', imageFailureUpdateError.message, feature.id);
                recordFailure('image_resolution', imageFailureMessage, feature.id);
                continue;
            }

            let xenoCantoUrl = feature.audio_url;
            let audioRecordist = feature.audio_recordist;
            let audioLicense = feature.audio_license;
            let audioId = feature.audio_id;
            let audioProvider = feature.audio_provider;
            let audioAttribution = feature.audio_attribution;

            if (!xenoCantoUrl) {
                try {
                    const xcKey = Deno.env.get('XENO_CANTO_API_KEY');
                    const xcUrl = xcKey
                        ? `https://xeno-canto.org/api/3/recordings?query=${encodeURIComponent(feature.scientific_name)}&key=${xcKey}`
                        : `https://xeno-canto.org/api/2/recordings?query=${encodeURIComponent(feature.scientific_name)}`;
                    const xcRes = await fetch(xcUrl);
                    if (xcRes.ok) {
                        const xcJson = await xcRes.json();
                        if (xcJson.recordings && xcJson.recordings.length > 0) {
                            const rec = xcJson.recordings[0];
                            xenoCantoUrl = rec.file?.startsWith('http') ? rec.file : `https:${rec.file}`;
                            audioId = rec.id;
                            audioRecordist = rec.rec;
                            audioLicense = rec.lic;
                            audioProvider = "Xeno-canto";
                            audioAttribution = `Recorded by ${audioRecordist}, via Xeno-canto, ${audioLicense}`;
                        }
                    } else if (!xcKey) {
                        console.warn('[Daily Wildlife] Xeno-canto v2 (keyless) request failed; consider setting XENO_CANTO_API_KEY to use v3.');
                    }
                } catch (e) {
                    console.error("[Daily Wildlife] Xeno-canto fetch error", e);
                }
            }

            const prompt = `
Generate a comprehensive, scientifically accurate daily wildlife feature in JSON format.
INFORMATION-ONLY ROLE: Gemini produces ONLY the factual/informational text
fields below (taxonomy, Bengali names/presentation, habitat, behaviour,
IUCN status, facts). Do NOT invent, select, or describe any image; the
verified source photograph is fetched separately (iNaturalist/eBird/
Wikimedia Commons) and the client renders the oil-painted derivative.
The scheduled wildlife candidate is: ${feature.common_name} (Scientific name: ${feature.scientific_name}).

Reference Data (integrate this knowledge):
eBird: ${ebirdData ? JSON.stringify(ebirdData) : "Not available"}
iNaturalist: ${inatData ? JSON.stringify({
  observations_count: inatData.observations_count,
  conservation_status: inatData.conservation_status,
  wikipedia_url: inatData.wikipedia_url
}) : "Not available"}
Audio Context: ${xenoCantoUrl ? "Audio available at " + xenoCantoUrl : "No audio"}

Do not invent missing source data. If a field cannot be reliably established, use null or "Not available".
Respond ONLY with valid JSON matching exactly this structure:
{
  "title": "...",
  "title_bn": "...",
  "common_name": "...",
  "scientific_name": "...",
  "bengali_name": "...",
  "species_description": "...",
  "description_bn": "...",
  "habitat": "...",
  "distribution": "...",
  "diet": "...",
  "behaviour": "...",
  "ecological_role": "...",
  "conservation_status": "...",
  "iucn_status": "...",
  "interesting_facts": "Fact 1\\nFact 2\\nFact 3",
  "did_you_know": "..."
}

Rules:
- CRITICAL SPECIES FIDELITY: every text field MUST describe ONLY
  ${feature.common_name} (${feature.scientific_name}). Never mix in another
  species' title, Bengali name, habitat, diet, behaviour, or description
  (e.g. never put a dolphin title over tiger details).
- 'scientific_name' MUST exactly equal "${feature.scientific_name}".
- 'common_name' MUST equal "${feature.common_name}".
- The PRIMARY language for this content must be natural, readable INDIAN BENGALI (West Bengal standard).
- STRICT REGIONAL VOCABULARY DIRECTIVE: DO NOT use Bangladeshi Bengali vocabulary anywhere in the app content. For example, ALWAYS translate "water" as "জল" (Jol), NEVER as "পানি" (Pani). Ensure all terminology and spelling strictly aligns with Indian Bengali usage.
- Write the following fields entirely in INDIAN BENGALI: title_bn, bengali_name, description_bn, species_description, habitat, distribution, diet, behaviour, ecological_role, conservation_status, interesting_facts, did_you_know.
- For 'title' and 'common_name', you may use English or standard English common names.
- 'scientific_name' MUST remain in Latin script (e.g., Panthera tigris tigris).
- iucn_status must be a real IUCN Red List status (in English). If unknown, use "Not Evaluated".
- Keep useful bilingual scientific terminology when educationally appropriate, but do not use English as the default narrative language for the Bengali fields.
- Ensure proper JSON formatting. Do not wrap in Markdown code blocks like \`\`\`json.
`;
            const geminiRes = await callGemini(geminiKey, prompt, {
              temperature: 0.2,
              responseMimeType: "application/json"
            });

            if (geminiRes.ok) {
                const contentText = geminiRes.text;
                if (contentText) {
                    try {
                        const featureData = extractJsonObject(contentText);
                        if (!featureData || typeof featureData !== 'object') {
                          throw new Error("Invalid JSON object returned by Gemini: " + contentText.slice(0, 200));
                        }
                        // Species-fidelity gate: Gemini is information-only and
                        // must not drift to another species. Never persist
                        // cross-species text (dolphin/tiger overlap).
                        const wantSci = String(feature.scientific_name || '')
                          .trim()
                          .toLowerCase();
                        const gotSci = String(featureData.scientific_name || '')
                          .trim()
                          .toLowerCase();
                        const wantCommon = String(feature.common_name || '')
                          .trim()
                          .toLowerCase();
                        const gotCommon = String(featureData.common_name || '')
                          .trim()
                          .toLowerCase();
                        const sciDrifted = wantSci.length > 0 &&
                            gotSci.length > 0 &&
                            gotSci !== wantSci;
                        const commonDrifted = wantCommon.length > 0 &&
                            gotCommon.length > 0 &&
                            gotCommon !== wantCommon;
                        if (sciDrifted || commonDrifted) {
                          const driftMsg =
                            `Species fidelity failed: scheduled ${feature.common_name} (${feature.scientific_name}) but Gemini returned ${featureData.common_name || '?'} (${featureData.scientific_name || '?'})`;
                          recordFailure('species_fidelity', driftMsg, feature.id);
                          const { error: driftUpdateError } = await supabase
                            .from('daily_wildlife_features')
                            .update({ image_generation_error: driftMsg })
                            .eq('id', feature.id);
                          if (driftUpdateError) {
                            recordFailure('species_fidelity_update', driftUpdateError.message, feature.id);
                          }
                          continue;
                        }
                        const requiredBengaliFields = [
                          'title_bn', 'bengali_name', 'species_description', 'description_bn',
                          'habitat', 'distribution', 'diet', 'behaviour', 'ecological_role',
                          'conservation_status', 'interesting_facts', 'did_you_know'
                        ];
                        const missingFields = requiredBengaliFields.filter((key) =>
                          typeof featureData[key] !== 'string' || !featureData[key].trim()
                        );
                        const bengaliFields = ['title_bn', 'bengali_name', 'species_description', 'description_bn', 'habitat', 'distribution', 'diet', 'behaviour', 'ecological_role', 'conservation_status', 'interesting_facts', 'did_you_know'];
                        const nonBengaliFields = bengaliFields.filter((key) =>
                          typeof featureData[key] === 'string' && featureData[key].trim() && !/[\u0980-\u09FF]/.test(featureData[key])
                        );
                        if (missingFields.length || nonBengaliFields.length) {
                          const validationMessage = `Content validation failed; missing/empty: ${missingFields.join(', ') || 'none'}; no Bengali script: ${nonBengaliFields.join(', ') || 'none'}`;
                          recordFailure('content_validation', validationMessage, feature.id);
                          const { error: validationUpdateError } = await supabase.from('daily_wildlife_features').update({
                            image_generation_error: validationMessage
                          }).eq('id', feature.id);
                          if (validationUpdateError) recordFailure('content_validation_update', validationUpdateError.message, feature.id);
                          continue;
                        }
                        const sourceUrls = [
                            ebirdData ? `https://ebird.org/species/${(ebirdData as any).speciesCode || ''}` : null,
                            inatData?.id ? `https://www.inaturalist.org/taxa/${inatData.id}` : null,
                            xenoCantoUrl || null,
                            imageProvenance?.source_url || null
                        ].filter(Boolean);
                        const sourceAttributionsStr = JSON.stringify({
                            ebird: ebirdData ? { provider: 'eBird', source_id: (ebirdData as any).speciesCode || null } : null,
                            inaturalist: inatData ? { provider: 'iNaturalist', source_id: inatData.id?.toString() || null } : null,
                            image: imageProvenance,
                            audio: xenoCantoUrl ? { provider: audioProvider, id: audioId, recordist: audioRecordist, license: audioLicense, attribution: audioAttribution, url: xenoCantoUrl } : null
                        });

                        const { error: scheduleUpdateError } = await supabase
                          .from('daily_wildlife_features')
                          .update({
                            status: 'scheduled',
                            title: featureData.title || feature.common_name,
                            common_name: featureData.common_name || feature.common_name,
                            scientific_name: featureData.scientific_name || feature.scientific_name,
                            title_bn: featureData.title_bn,
                            bengali_name: featureData.bengali_name,
                            species_description: featureData.species_description,
                            description_bn: featureData.description_bn,
                            habitat: featureData.habitat,
                            distribution: featureData.distribution,
                            diet: featureData.diet,
                            behaviour: featureData.behaviour,
                            ecological_role: featureData.ecological_role,
                            conservation_status: featureData.conservation_status,
                            iucn_status: featureData.iucn_status,
                            interesting_facts: featureData.interesting_facts,
                            did_you_know: featureData.did_you_know,
                            source_urls: sourceUrls.join(','),
                            source_attributions: sourceAttributionsStr,
                            original_image_url: originalImageUrl,
                            image_provenance: imageProvenance ? JSON.stringify(imageProvenance) : null,
                            audio_url: xenoCantoUrl,
                            audio_provider: audioProvider,
                            audio_id: audioId,
                            audio_recordist: audioRecordist,
                            audio_license: audioLicense,
                            audio_attribution: audioAttribution,
                            scheduled_publish_at: new Date(`${feature.feature_date}T00:00:00+05:30`).toISOString()
                          })
                          .eq('id', feature.id);
                        if (scheduleUpdateError) recordFailure('feature_schedule_update', scheduleUpdateError.message, feature.id);
                    } catch (e: any) {
                        recordFailure('feature_json_parse', e?.message || String(e), feature.id);
                    }
                } else {
                    recordFailure('synthesis_empty_response', 'Gemini returned no content text.', feature.id);
                }
            } else {
                 recordFailure('synthesis_request', geminiRes.error, feature.id);
            }
        }
    }

    const result = { success: failures.length === 0, message: failures.length === 0 ? 'Automation run completed' : 'Automation completed with errors', failureCount: failures.length, failures };
    return new Response(JSON.stringify(result), { status: failures.length === 0 ? 200 : 207, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (e: any) {
    console.error(`[Daily Wildlife] Unhandled error: ${e.message}`);
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
