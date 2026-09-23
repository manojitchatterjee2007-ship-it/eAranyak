import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const EBIRD_BASE = "https://api.ebird.org/v2";
const INAT_BASE = "https://api.inaturalist.org/v2";
const INDIA_PLACE_ID = "6681";

const DEFAULT_LIMIT = 12;
const MIN_LIMIT = 4;
const MAX_LIMIT = 20;
const FETCH_TIMEOUT_MS = 15000;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function text(value: unknown): string {
  return value == null ? "" : String(value).trim();
}

function firstPhotoUrl(observation: any): string | null {
  const photos = Array.isArray(observation?.photos)
    ? observation.photos
    : [];

  for (const photo of photos) {
    if (!photo || typeof photo !== "object") continue;

    const url =
      text(photo.url) ||
      text(photo.medium_url) ||
      text(photo.original_url);

    if (url) return url;
  }

  const defaultPhoto = observation?.taxon?.default_photo;

  if (defaultPhoto && typeof defaultPhoto === "object") {
    const url =
      text(defaultPhoto.medium_url) ||
      text(defaultPhoto.square_url) ||
      text(defaultPhoto.original_url);

    if (url) return url;
  }

  return null;
}

function normalizeEbird(obs: any, bengaliName = "") {
  return {
    id:
      `ebird-${text(obs.speciesCode)}-` +
      `${text(obs.locId)}-${text(obs.obsDt)}`,
    source: "eBird",
    common_name: text(obs.comName),
    bengali_name: text(bengaliName) || null,
    scientific_name: text(obs.sciName),
    location: text(obs.locName),
    latitude: Number.isFinite(Number(obs.lat)) ? Number(obs.lat) : null,
    longitude: Number.isFinite(Number(obs.lng)) ? Number(obs.lng) : null,
    observed_at: text(obs.obsDt),
    count: obs.howMany ?? null,
    observer: null,
    quality:
      obs.obsReviewed === true
        ? "Reviewed"
        : "Unreviewed",
    attribution: null,
    observation_url: text(obs.subId)
      ? `https://ebird.org/checklist/${text(obs.subId)}`
      : null,
    description: null,
    image_url: null,
  };
}

function normalizeInat(obs: any, bengaliName = "") {
  const taxon = obs?.taxon ?? {};
  const user = obs?.user ?? {};

  const commonName =
    text(obs.preferred_common_name) ||
    text(taxon.preferred_common_name) ||
    text(obs.species_guess) ||
    text(taxon.name);

  const scientificName =
    text(taxon.name) ||
    text(obs.species_guess) ||
    commonName;

  return {
    id:
      `inaturalist-${text(obs.uuid) || text(obs.id)}`,
    source: "iNaturalist",
    common_name: commonName || scientificName,
    bengali_name: text(bengaliName) || null,
    scientific_name: scientificName,
    location:
      text(obs.place_guess) ||
      "Location not disclosed",
    latitude:
      Array.isArray(obs.geojson?.coordinates) &&
          Number.isFinite(Number(obs.geojson.coordinates[1]))
        ? Number(obs.geojson.coordinates[1])
        : null,
    longitude:
      Array.isArray(obs.geojson?.coordinates) &&
          Number.isFinite(Number(obs.geojson.coordinates[0]))
        ? Number(obs.geojson.coordinates[0])
        : null,
    observed_at:
      text(obs.observed_on_string) ||
      text(obs.observed_on) ||
      text(obs.time_observed_at),
    count: null,
    observer:
      text(user.login) ||
      text(user.name) ||
      null,
    quality:
      text(obs.quality_grade) ||
      null,
    attribution:
      text(user.login) ||
      null,
    observation_url:
      text(obs.uri) ||
      (obs.id
        ? `https://www.inaturalist.org/observations/${obs.id}`
        : null),
    description:
      text(obs.description) ||
      text(obs.short_description) ||
      null,
    image_url: firstPhotoUrl(obs),
  };
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  timeoutMs = FETCH_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();

  const timeoutId = setTimeout(
    () => controller.abort(),
    timeoutMs,
  );

  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function fetchJson(
  url: string,
  init: RequestInit = {},
): Promise<{
  data: any;
  status: number;
}> {
  const response = await fetchWithTimeout(url, init);
  const bodyText = await response.text();

  if (!response.ok) {
    const safeBody = bodyText
      ? bodyText
          .slice(0, 300)
          .replace(/\s+/g, " ")
      : "";

    throw new Error(
      `${response.status} ${response.statusText}` +
      `${safeBody ? `: ${safeBody}` : ""}`,
    );
  }

  let data: any;

  try {
    data = bodyText
      ? JSON.parse(bodyText)
      : null;
  } catch (_) {
    throw new Error(
      "Provider returned a non-JSON response.",
    );
  }

  return {
    data,
    status: response.status,
  };
}

function providerError(error: unknown): string {
  if (
    error instanceof DOMException &&
    error.name === "AbortError"
  ) {
    return "Request timed out.";
  }

  if (error instanceof Error) {
    return error.message.slice(0, 400);
  }

  return String(error).slice(0, 400);
}

function getRequestedLimit(body: any): number {
  const requested = Number(
    body?.limit ?? DEFAULT_LIMIT,
  );

  if (!Number.isFinite(requested)) {
    return DEFAULT_LIMIT;
  }

  return Math.min(
    MAX_LIMIT,
    Math.max(
      MIN_LIMIT,
      Math.floor(requested),
    ),
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (
    req.method !== "GET" &&
    req.method !== "POST"
  ) {
    return json(
      {
        ok: false,
        error: "Method not allowed.",
      },
      405,
    );
  }

  try {
    let body: any = {};

    if (req.method === "POST") {
      try {
        body = await req.json();
      } catch (_) {
        body = {};
      }
    }

    const limit = getRequestedLimit(body);

    // The eBird API key is server-side only.
    const eBirdApiKey =
      Deno.env.get("eBird_API")?.trim() || "";

    // ------------------------------------------------------------
    // eBird
    // ------------------------------------------------------------

    const ebirdEnglishUrl =
      `${EBIRD_BASE}/data/obs/IN/recent` +
      `?back=7` +
      `&maxResults=${Math.min(30, limit)}` +
      `&sppLocale=en`;

    const ebirds: any[] = [];

    const ebirdStatus = {
      configured: Boolean(eBirdApiKey),
      status: null as number | null,
      taxonomy_status: null as number | null,
      raw_count: 0,
      normalized_count: 0,
      bengali_matches: 0,
      error: null as string | null,
      taxonomy_error: null as string | null,
    };

    if (!eBirdApiKey) {
      ebirdStatus.error =
        "eBird_API secret is not configured.";
    } else {
      try {
        const headers = {
          "X-eBirdApiToken": eBirdApiKey,
          Accept: "application/json",
          "User-Agent": "eAranyak-Wildlife-Dashboard/1.0",
        };

        const result = await fetchJson(ebirdEnglishUrl, { headers });
        ebirdStatus.status = result.status;

        if (Array.isArray(result.data)) {
          ebirdStatus.raw_count = result.data.length;

          const rawEbirds = result.data
            .filter((item: any) => item?.comName && item?.sciName)
            .slice(0, limit);

          // Resolve Bengali names in ONE taxonomy request using species codes.
          // This keeps the eBird API key server-side and avoids one request per bird.
          const speciesCodes = Array.from(
            new Set(
              rawEbirds
                .map((item: any) => text(item.speciesCode))
                .filter(Boolean),
            ),
          );

          const bengaliBySpeciesCode = new Map<string, string>();
          if (speciesCodes.length > 0) {
            const taxonomyUrl =
              `${EBIRD_BASE}/ref/taxonomy/ebird` +
              `?cat=species` +
              `&fmt=json` +
              `&locale=bn_IN` +
              `&species=${encodeURIComponent(speciesCodes.join(","))}`;

            try {
              const taxonomy = await fetchJson(taxonomyUrl, { headers });
              ebirdStatus.taxonomy_status = taxonomy.status;
              if (Array.isArray(taxonomy.data)) {
                for (const item of taxonomy.data) {
                  const code = text(item?.speciesCode);
                  const name = text(item?.comName);
                  if (code && name && /[\u0980-\u09FF]/.test(name)) {
                    bengaliBySpeciesCode.set(code, name);
                  }
                }
              }
            } catch (error) {
              ebirdStatus.taxonomy_error = providerError(error);
            }
          }

          for (const item of rawEbirds) {
            const code = text(item.speciesCode);
            const bengaliName = bengaliBySpeciesCode.get(code) ?? "";
            if (bengaliName) ebirdStatus.bengali_matches++;
            ebirds.push(normalizeEbird(item, bengaliName));
          }

          ebirdStatus.normalized_count = ebirds.length;
        } else {
          ebirdStatus.error =
            "eBird returned an unexpected response format.";
        }
      } catch (error) {
        ebirdStatus.error = providerError(error);
      }
    }

    // ------------------------------------------------------------
    // iNaturalist
    //
    // API v2 uses a customizable fields parameter.
    // Without fields, observations can return only uuid.
    // Request the exact fields required by the dashboard.
    // ------------------------------------------------------------

    const inatFields = [
      "id",
      "uuid",
      "species_guess",
      "preferred_common_name",
      "observed_on",
      "observed_on_string",
      "time_observed_at",
      "place_guess",
      "quality_grade",
      "uri",
      "description",
      "taxon.id",
      "taxon.name",
      "taxon.preferred_common_name",
      "user.id",
      "user.login",
      "user.name",
      "photos.url",
      "photos.medium_url",
      "photos.original_url",
      "taxon.default_photo.medium_url",
      "taxon.default_photo.square_url",
      "geojson",
    ].join(",");

    const inatEnglishUrl =
      `${INAT_BASE}/observations` +
      `?place_id=${INDIA_PLACE_ID}` +
      `&per_page=${Math.min(20, limit)}` +
      `&order_by=observed_on` +
      `&order=desc` +
      `&fields=${encodeURIComponent(inatFields)}`;

    // iNaturalist supports locale-based common-name selection. Use the
    // Bengali lexicon with an India place preference, while keeping the
    // English observation response as the canonical observation payload.
    const inatBengaliUrl =
      `${INAT_BASE}/observations` +
      `?place_id=${INDIA_PLACE_ID}` +
      `&preferred_place_id=${INDIA_PLACE_ID}` +
      `&locale=bn` +
      `&per_page=${Math.min(20, limit)}` +
      `&order_by=observed_on` +
      `&order=desc` +
      `&fields=${encodeURIComponent(inatFields)}`;

    const inats: any[] = [];

    const inatStatus = {
      configured: true,
      status: null as number | null,
      bengali_status: null as number | null,
      raw_count: 0,
      normalized_count: 0,
      bengali_matches: 0,
      error: null as string | null,
      bengali_error: null as string | null,
    };

    try {
      const headers = {
        Accept: "application/json",
        "User-Agent": "eAranyak-Wildlife-Dashboard/1.0",
      };

      const [englishResult, bengaliResult] = await Promise.allSettled([
        fetchJson(inatEnglishUrl, { headers }),
        fetchJson(inatBengaliUrl, { headers }),
      ]);

      const bengaliByObservation = new Map<string, string>();
      const bengaliByScientificName = new Map<string, string>();

      if (bengaliResult.status === "fulfilled") {
        inatStatus.bengali_status = bengaliResult.value.status;
        const bengaliResults = Array.isArray(bengaliResult.value.data?.results)
          ? bengaliResult.value.data.results
          : [];

        for (const item of bengaliResults) {
          const name = text(item?.preferred_common_name) ||
              text(item?.taxon?.preferred_common_name);
          if (!name || !/[\u0980-\u09FF]/.test(name)) continue;

          const observationKey = text(item?.uuid) || text(item?.id);
          const scientificName = text(item?.taxon?.name);
          if (observationKey) bengaliByObservation.set(observationKey, name);
          if (scientificName) bengaliByScientificName.set(scientificName.toLowerCase(), name);
        }
      } else {
        inatStatus.bengali_error = providerError(bengaliResult.reason);
      }

      if (englishResult.status === "fulfilled") {
        inatStatus.status = englishResult.value.status;
        const results = Array.isArray(englishResult.value.data?.results)
            ? englishResult.value.data.results
            : [];

        inatStatus.raw_count = results.length;

        for (const item of results) {
          const observationKey = text(item?.uuid) || text(item?.id);
          const scientificName = text(item?.taxon?.name);
          const bengaliName =
              bengaliByObservation.get(observationKey) ??
              bengaliByScientificName.get(scientificName.toLowerCase()) ??
              "";

          const normalized = normalizeInat(item, bengaliName);
          if (!normalized.common_name && !normalized.scientific_name) continue;

          if (bengaliName) inatStatus.bengali_matches++;
          inats.push(normalized);
          if (inats.length >= limit) break;
        }

        inatStatus.normalized_count = inats.length;

        if (!Array.isArray(englishResult.value.data?.results)) {
          inatStatus.error =
            "iNaturalist returned an unexpected response format.";
        }
      } else {
        inatStatus.error = providerError(englishResult.reason);
      }
    } catch (error) {
      inatStatus.error = providerError(error);
    }

    // ------------------------------------------------------------
    // Merge both providers.
    // ------------------------------------------------------------

    const merged: any[] = [];

    let ebirdIndex = 0;
    let inatIndex = 0;

    while (
      merged.length < limit &&
      (
        ebirdIndex < ebirds.length ||
        inatIndex < inats.length
      )
    ) {
      if (
        ebirdIndex < ebirds.length
      ) {
        merged.push(
          ebirds[ebirdIndex++],
        );
      }

      if (
        merged.length >= limit
      ) {
        break;
      }

      if (
        inatIndex < inats.length
      ) {
        merged.push(
          inats[inatIndex++],
        );
      }
    }

    // ------------------------------------------------------------
    // Response.
    //
    // Existing Flutter fields remain unchanged:
    // ok, generated_at, observations, sources
    // ------------------------------------------------------------

    return json({
      ok: true,
      generated_at:
        new Date().toISOString(),

      observations: merged,

      sources: {
        ebird: ebirds.length,
        inaturalist: inats.length,
      },

      source_status: {
        ebird: ebirdStatus,
        inaturalist: inatStatus,
      },

      diagnostics: {
        requested_limit: limit,
        total_observations:
          merged.length,
        ebird_url_region: "IN",
        inaturalist_place_id:
          INDIA_PLACE_ID,
      },
    });
  } catch (error) {
    return json(
      {
        ok: false,
        generated_at:
          new Date().toISOString(),
        error:
          providerError(error),
      },
      500,
    );
  }
});
