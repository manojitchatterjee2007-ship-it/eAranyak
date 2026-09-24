// eআরণ্যক — Wildlife Bird Call Proxy (failsafe)
// Server-side Xeno-canto search + audio proxy.
// XENO_CANTO_API_KEY must remain in Supabase secrets.

const MAX_AUDIO_BYTES = 16 * 1024 * 1024;
// Keep the interactive dashboard call fast. The previous implementation could
// try up to 10 recordings x 2 URLs x 20 seconds, which explains the 45-second
// Flutter timeout seen on Windows.
const SEARCH_TIMEOUT_MS = 6_000;
const AUDIO_TIMEOUT_MS = 8_000;
const MAX_CANDIDATES = 2;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function normalize(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

function exactSpecies(
  recording: Record<string, unknown>,
  genus: string,
  species: string,
  scientific: string,
): boolean {
  const recGenus = normalize(recording.gen);
  const recSpecies = normalize(recording.sp);
  if (recGenus === normalize(genus) && recSpecies === normalize(species)) return true;

  const sci = normalize(recording.sci_name)
    .replace(/_/g, ' ')
    .replace(/\s+/g, ' ');
  return sci === normalize(scientific);
}

function scoreRecording(recording: Record<string, unknown>): number {
  const type = normalize(recording.type);
  const quality = normalize(recording.q).toUpperCase();
  let score = 0;

  if (type.includes('song')) score += 30;
  if (type.includes('call')) score += 20;
  if (type.includes('flight')) score += 4;

  if (quality === 'A') score += 20;
  else if (quality === 'B') score += 14;
  else if (quality === 'C') score += 7;

  if (normalize(recording.bird_seen) === 'yes') score += 5;

  // Prefer shorter recordings because they are less likely to hit proxy limits
  // and are usually sufficient for a bird-call button.
  const length = Number(recording.length ?? 0);
  if (Number.isFinite(length) && length > 0) {
    if (length <= 60) score += 8;
    else if (length <= 120) score += 4;
  }

  return score;
}

function resolveUrl(value: unknown): string | null {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  try {
    if (raw.startsWith('//')) return `https:${raw}`;
    return new URL(raw, 'https://xeno-canto.org').toString();
  } catch (_) {
    return null;
  }
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

async function searchXenoV3(
  query: string,
  apiKey: string,
): Promise<Record<string, unknown>[]> {
  const url = new URL('https://xeno-canto.org/api/3/recordings');
  url.searchParams.set('query', query);
  url.searchParams.set('key', apiKey);

  const response = await fetchWithTimeout(
    url.toString(),
    {
      headers: {
        accept: 'application/json',
        'user-agent': 'eAranyak/1.0 wildlife bird call',
      },
    },
    SEARCH_TIMEOUT_MS,
  );

  if (!response.ok) {
    console.error('Xeno v3 search HTTP', response.status, query);
    return [];
  }

  const data = await response.json();
  const recordings = Array.isArray(data?.recordings) ? data.recordings : [];
  return recordings.filter((r: unknown): r is Record<string, unknown> =>
    !!r && typeof r === 'object'
  );
}

// Compatibility fallback. Some species/search combinations may still be
// returned more reliably by the legacy endpoint. This is search-only; the
// secret is never sent to Flutter.
async function searchXenoV2(query: string): Promise<Record<string, unknown>[]> {
  const url = new URL('https://xeno-canto.org/api/2/recordings');
  url.searchParams.set('query', query);

  const response = await fetchWithTimeout(
    url.toString(),
    {
      headers: {
        accept: 'application/json',
        'user-agent': 'eAranyak/1.0 wildlife bird call',
      },
    },
    SEARCH_TIMEOUT_MS,
  );

  if (!response.ok) return [];

  const data = await response.json();
  const recordings = Array.isArray(data?.recordings) ? data.recordings : [];
  return recordings.filter((r: unknown): r is Record<string, unknown> =>
    !!r && typeof r === 'object'
  );
}

function audioLooksValid(bytes: Uint8Array, contentType: string): boolean {
  if (bytes.length < 1024 || bytes.length > MAX_AUDIO_BYTES) return false;

  const type = contentType.toLowerCase();
  if (type.includes('text/html') || type.includes('application/json')) return false;

  // Common audio signatures. We deliberately allow unknown audio/* types
  // because Xeno-canto may serve different encodings/container headers.
  if (type.startsWith('audio/')) return true;

  if (bytes.length >= 3 &&
      bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
    return true; // ID3 / MP3
  }

  if (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0) {
    return true; // MPEG audio frame
  }

  if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x41 &&
      bytes[10] === 0x56 && bytes[11] === 0x45) {
    return true; // WAV
  }

  if (bytes.length >= 4 &&
      bytes[0] === 0x4f && bytes[1] === 0x67 &&
      bytes[2] === 0x67 && bytes[3] === 0x53) {
    return true; // OGG
  }

  return false;
}

async function downloadAudio(
  recording: Record<string, unknown>,
  apiKey: string,
): Promise<Uint8Array | null> {
  const raw = resolveUrl(recording.file);
  if (!raw) return null;

  // Xeno-canto API authentication belongs on the server. Try the authenticated
  // media URL first. Only retry the plain URL when the host explicitly rejects
  // the authenticated request; do not perform two full downloads routinely.
  const urls: string[] = [];
  try {
    const authenticated = new URL(raw);
    authenticated.searchParams.set('key', apiKey);
    urls.push(authenticated.toString());
  } catch (_) {}

  for (const url of [...new Set(urls)]) {
    try {
      const response = await fetchWithTimeout(
        url,
        {
          headers: {
            accept: 'audio/*,application/octet-stream;q=0.9,*/*;q=0.1',
            'user-agent': 'eAranyak/1.0 wildlife bird call',
            referer: 'https://xeno-canto.org/',
          },
        },
        AUDIO_TIMEOUT_MS,
      );

      if (!response.ok) continue;

      const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
      const contentLength = Number(response.headers.get('content-length') ?? '0');
      if (Number.isFinite(contentLength) && contentLength > MAX_AUDIO_BYTES) continue;

      const bytes = new Uint8Array(await response.arrayBuffer());
      if (!audioLooksValid(bytes, contentType)) continue;
      return bytes;
    } catch (error) {
      console.error('Xeno audio attempt failed', recording.id, error);
    }
  }

  return null;
}

async function searchINaturalistSounds(
  scientific: string,
): Promise<Record<string, unknown>[]> {
  const url = new URL('https://api.inaturalist.org/v2/observations');
  url.searchParams.set('taxon_name', scientific);
  url.searchParams.set('sounds', 'true');
  url.searchParams.set('per_page', '30');
  url.searchParams.set('order_by', 'observed_on');
  url.searchParams.set('order', 'desc');
  url.searchParams.set(
    'fields',
    'id,taxon.name,taxon.rank,sounds',
  );

  const response = await fetchWithTimeout(
    url.toString(),
    {
      headers: {
        accept: 'application/json',
        'user-agent': 'eAranyak/1.0 wildlife bird call',
      },
    },
    SEARCH_TIMEOUT_MS,
  );

  if (!response.ok) {
    console.error('iNaturalist sound search HTTP', response.status);
    return [];
  }

  const data = await response.json();
  const observations = Array.isArray(data?.results) ? data.results : [];
  return observations.filter((o: unknown): o is Record<string, unknown> =>
    !!o && typeof o === 'object'
  );
}

function exactINaturalistSoundUrl(
  observation: Record<string, unknown>,
  scientific: string,
): string | null {
  const taxon = observation.taxon;
  if (!taxon || typeof taxon !== 'object') return null;

  const taxonName = normalize((taxon as Record<string, unknown>).name)
    .replace(/_/g, ' ')
    .replace(/\s+/g, ' ');
  if (taxonName !== normalize(scientific)) return null;

  const sounds = observation.sounds;
  if (!Array.isArray(sounds)) return null;

  for (const sound of sounds) {
    if (!sound || typeof sound !== 'object') continue;
    const url = resolveUrl((sound as Record<string, unknown>).file_url);
    if (url) return url;
  }

  return null;
}

async function downloadRemoteAudio(url: string): Promise<Uint8Array | null> {
  try {
    const response = await fetchWithTimeout(
      url,
      {
        headers: {
          accept: 'audio/*,application/octet-stream;q=0.9,*/*;q=0.1',
          'user-agent': 'eAranyak/1.0 wildlife bird call',
        },
      },
      AUDIO_TIMEOUT_MS,
    );

    if (!response.ok) return null;

    const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
    const contentLength = Number(response.headers.get('content-length') ?? '0');
    if (Number.isFinite(contentLength) && contentLength > MAX_AUDIO_BYTES) return null;

    const bytes = new Uint8Array(await response.arrayBuffer());
    return audioLooksValid(bytes, contentType) ? bytes : null;
  } catch (error) {
    console.error('Remote audio download failed', url, error);
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return json({ error: 'POST required' }, 405);
  }

  const apiKey = Deno.env.get('XENO_CANTO_API_KEY')?.trim() || '';


  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const scientific = String(body.scientific_name ?? '').trim();
  const commonName = String(body.common_name ?? '').trim();
  const parts = scientific.split(/\s+/).filter(Boolean);

  if (parts.length < 2) {
    return json({ error: 'A valid binomial scientific name is required' }, 400);
  }

  const genus = parts[0];
  const species = parts[1];
  const exactScientific = `${genus} ${species}`;

  if (apiKey) {
    const candidates = new Map<string, Record<string, unknown>>();
    let searchSucceeded = false;

    const addCandidates = (results: Record<string, unknown>[]) => {
      searchSucceeded = true;
      for (const recording of results) {
        if (!exactSpecies(recording, genus, species, exactScientific)) continue;
        const id = String(recording.id ?? recording.file ?? '');
        if (id && !candidates.has(id)) candidates.set(id, recording);
      }
    };

    const primaryQuery = `gen:${genus} sp:${species} grp:birds`;
    try {
      addCandidates(await searchXenoV3(primaryQuery, apiKey));
    } catch (error) {
      console.error('Xeno v3 search failed', primaryQuery, error);
    }

    if (candidates.size === 0) {
      try {
        addCandidates(await searchXenoV2(exactScientific));
      } catch (error) {
        console.error('Xeno v2 fallback search failed', error);
      }
    }

    const sorted = [...candidates.values()]
      .sort((a, b) => scoreRecording(b) - scoreRecording(a))
      .slice(0, MAX_CANDIDATES);

    for (const recording of sorted) {
      try {
        const audio = await downloadAudio(recording, apiKey);
        if (!audio) continue;

        return new Response(audio, {
          status: 200,
          headers: {
            'content-type': 'application/octet-stream',
            'cache-control': 'no-store',
            'x-bird-species': exactScientific,
            'x-audio-source': 'xeno-canto',
            'x-xenocanto-recording': String(recording.id ?? ''),
          },
        });
      } catch (error) {
        console.error('Xeno audio download failed', recording.id, error);
      }
    }

    if (!searchSucceeded) {
      console.warn('Xeno-canto unavailable; trying iNaturalist sound fallback');
    }
  }

  // Secondary source: iNaturalist observation sounds. iNaturalist officially
  // exposes observations filtered by sounds=true, and sound records provide
  // file_url. We only accept an observation whose resolved taxon name is the
  // exact requested species, so this cannot silently become another species.
  try {
    const observations = await searchINaturalistSounds(exactScientific);
    for (const observation of observations) {
      const soundUrl = exactINaturalistSoundUrl(observation, exactScientific);
      if (!soundUrl) continue;

      const audio = await downloadRemoteAudio(soundUrl);
      if (!audio) continue;

      return new Response(audio, {
        status: 200,
        headers: {
          'content-type': 'application/octet-stream',
          'cache-control': 'no-store',
          'x-bird-species': exactScientific,
          'x-audio-source': 'iNaturalist',
        },
      });
    }
  } catch (error) {
    console.error('iNaturalist sound fallback failed', error);
  }

  return json({
    error: 'No playable exact-species recording is currently available from the supported bird-call sources.',
    scientific_name: exactScientific,
    common_name: commonName,
    code: 'NO_PLAYABLE_RECORDING',
  }, 503);
});
