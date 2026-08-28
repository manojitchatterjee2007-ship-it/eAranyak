import { createClient } from "npm:@supabase/supabase-js@2";

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

  // Lightweight shared-secret check (gateway JWT verify is disabled because
  // this project rejects legacy JWTs; this blocks casual abuse).
  if (req.headers.get("x-earanyak-key") !== "earanyak-notify-2026") {
    return new Response(JSON.stringify({ ok: false, reason: "forbidden" }), {
      status: 403,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const { title, body, data = {} } = await req.json();

    const sa = loadServiceAccount();
    if (!sa) {
      return new Response(
        JSON.stringify({
          ok: false,
          reason:
            "FCM_SERVICE_ACCOUNT_JSON secret not set — push skipped",
        }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: tokens, error } = await admin
      .from("device_tokens")
      .select("token");
    if (error) throw error;

    // FCM v1 data payload values must be strings.
    const strData: Record<string, string> = {};
    for (const [k, v] of Object.entries(data ?? {})) {
      strData[k] = typeof v === "string" ? v : JSON.stringify(v);
    }

    let sent = 0;
    let staleRemoved = 0;

    for (const row of tokens ?? []) {
      const res = await sendFcm(sa, row.token, title, body, strData);
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 410) {
        // Token no longer valid — clean it up.
        await admin.from("device_tokens").delete().eq("token", row.token);
        staleRemoved++;
      }
    }

    return new Response(JSON.stringify({ ok: true, sent, staleRemoved }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});

