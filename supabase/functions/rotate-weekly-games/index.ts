import { createClient } from "npm:@supabase/supabase-js@2";

// Mirrors WildlifeGameData in lib/main.dart. Update both together.
const PHOTO_SPECIES = [
  "Bengal Tiger",
  "Asian Elephant",
  "One-horned Rhinoceros",
  "Himalayan Monal",
  "Great Indian Bustard",
  "Indian Skimmer",
  "Snow Leopard",
  "Batagur baska",
  "Gharial",
  "Great Hornbill",
  "Red Panda",
  "Indian Pangolin",
  "Barasingha",
];

const AUDIO_SPECIES = [
  "Oriental Magpie-Robin",
  "Common Myna",
  "Asian Koel",
  "Greater Coucal",
  "Black Drongo",
  "Spotted Dove",
  "Jungle Babbler",
  "White-throated Kingfisher",
  "Coppersmith Barbet",
];

const PUZZLE_SPECIES = [
  "Indian Skimmer",
  "Great Indian Bustard",
  "Lesser Adjutant",
  "Red Panda",
  "Indian Pangolin",
  "Himalayan Monal",
  "Snow Leopard",
  "Barasingha",
];

const HINT_BANK_SIZE = 8;

function mondayUtc(date = new Date()): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const diff = (d.getUTCDay() + 6) % 7; // days since Monday
  d.setUTCDate(d.getUTCDate() - diff);
  return d.toISOString().slice(0, 10);
}

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle<T>(arr: T[], rnd: () => number): T[] {
  const out = [...arr];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// -------------------------------------------------------------
// FCM HTTP v1 authentication (service account -> OAuth2 token)
// The service account JSON is stored base64-encoded in the
// FCM_SERVICE_ACCOUNT_JSON secret.
// -------------------------------------------------------------
let cachedToken: { token: string; exp: number } | null = null;

function base64UrlEncode(data: Uint8Array): string {
  let bin = "";
  for (const b of data) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function loadServiceAccount(): any | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;
  let json = raw;
  try {
    json = atob(raw);
  } catch (_) {
    // not base64 — use as-is
  }
  try {
    return JSON.parse(json);
  } catch (_) {
    return null;
  }
}

async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token;

  const enc = new TextEncoder();
  const header = base64UrlEncode(
    enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64UrlEncode(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64UrlEncode(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth failed: ${await res.text()}`);
  const json = await res.json();
  cachedToken = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cachedToken.token;
}

async function sendFcm(
  sa: any,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<Response> {
  const accessToken = await getAccessToken(sa);
  return fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            notification: { sound: "default", channel_id: "earanyak_push_channel" },
          },
        },
      }),
    },
  );
}


Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const weekStart = mondayUtc();
    const seed = parseInt(weekStart.replace(/-/g, ""), 10);
    const rnd = mulberry32(seed);

    const { data: existing } = await admin
      .from("weekly_challenges")
      .select("id")
      .eq("week_start", weekStart)
      .limit(1);

    if (existing && existing.length > 0) {
      return new Response(
        JSON.stringify({ ok: true, message: "already generated", weekStart }),
        { headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const rows = [
      {
        week_start: weekStart,
        category: "photo",
        payload: { seed, species: shuffle(PHOTO_SPECIES, rnd).slice(0, 8) },
      },
      {
        week_start: weekStart,
        category: "audio",
        payload: { seed, species: shuffle(AUDIO_SPECIES, rnd).slice(0, 8) },
      },
      {
        week_start: weekStart,
        category: "hint",
        payload: {
          seed,
          indices: shuffle(
            [...Array(HINT_BANK_SIZE).keys()],
            rnd,
          ).slice(0, 4),
        },
      },
      {
        week_start: weekStart,
        category: "scramble",
        payload: { seed, species: shuffle(PUZZLE_SPECIES, rnd).slice(0, 4) },
      },
    ];

    // Old challenges are deleted at the same moment the new ones land.
    await admin.from("weekly_challenges").delete().neq("week_start", weekStart);

    const { error } = await admin
      .from("weekly_challenges")
      .upsert(rows, { onConflict: "week_start,category" });
    if (error) throw error;

    // Notify all users about the fresh challenges.
    const sa = loadServiceAccount();
    let notified = 0;
    if (sa) {
      const { data: tokens } = await admin
        .from("device_tokens")
        .select("token");
      for (const row of tokens ?? []) {
        const res = await sendFcm(
          sa,
          row.token,
          "নতুন সাপ্তাহিক চ্যালেঞ্জ! (New Weekly Challenges)",
          "এই সপ্তাহের প্রকৃতি-খেলা এসেছে — খেলতে ট্যাপ করুন।",
          { type: "game" },
        );
        if (res.ok) notified++;
      }
    }

    return new Response(
      JSON.stringify({ ok: true, weekStart, notified }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
