import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-news-notification-secret",
};

let cachedAccessToken: { token: string; exp: number } | null = null;

function base64UrlEncode(data: Uint8Array): string {
  let value = "";
  for (const byte of data) value += String.fromCharCode(byte);
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function loadServiceAccount(): Record<string, string> | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;
  try {
    const decoded = (() => {
      try {
        return atob(raw);
      } catch (_) {
        return raw;
      }
    })();
    const value = JSON.parse(decoded);
    return value && typeof value === "object" ? value : null;
  } catch (_) {
    return null;
  }
}

async function fcmAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.exp > now + 60) return cachedAccessToken.token;

  const encoder = new TextEncoder();
  const header = base64UrlEncode(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64UrlEncode(encoder.encode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64UrlEncode(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`FCM OAuth failed: ${await response.text()}`);
  const json = await response.json();
  cachedAccessToken = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cachedAccessToken.token;
}

async function sendFcm(
  serviceAccount: Record<string, string>,
  token: string,
  event: Record<string, unknown>,
): Promise<{ ok: boolean; status: number; messageId?: string; error?: string }> {
  const accessToken = await fcmAccessToken(serviceAccount);
  const payload = (event.payload ?? {}) as Record<string, unknown>;
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(payload)) {
    data[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  const newsId = String(event.news_id ?? "");
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: String(event.title), body: String(event.body) },
          data,
          android: {
            priority: "HIGH",
            collapse_key: `news_${newsId}`,
            notification: {
              channel_id: "earanyak_news_v2",
              tag: `news_${newsId}`,
              sound: "elephant_trumpet",
            },
          },
        },
      }),
    },
  );
  const text = await response.text();
  if (!response.ok) return { ok: false, status: response.status, error: text.slice(0, 800) };
  let messageId: string | undefined;
  try {
    messageId = JSON.parse(text).name;
  } catch (_) {}
  return { ok: true, status: response.status, messageId };
}

async function claimEvent(admin: ReturnType<typeof createClient>, eventId: string) {
  const { data, error } = await admin
    .from("news_notification_events")
    .update({ status: "sending", attempt_count: 1, last_error: null })
    .eq("id", eventId)
    .in("status", ["pending", "failed"])
    .select()
    .maybeSingle();
  if (error) throw error;
  return data as Record<string, unknown> | null;
}

async function deliverEvent(
  admin: ReturnType<typeof createClient>,
  serviceAccount: Record<string, string>,
  eventId: string,
): Promise<{ sent: number; invalid: number; failed: number }> {
  const event = await claimEvent(admin, eventId);
  if (!event) return { sent: 0, invalid: 0, failed: 0 };

  try {
    const { data: tokens, error: tokenError } = await admin.from("device_tokens").select("token");
    if (tokenError) throw tokenError;
    const { data: delivered, error: deliveredError } = await admin
      .from("news_notification_deliveries")
      .select("token")
      .eq("event_id", eventId)
      .eq("status", "sent");
    if (deliveredError) throw deliveredError;
    const alreadySent = new Set((delivered ?? []).map((row) => String(row.token)));

    let sent = 0;
    let invalid = 0;
    let failed = 0;
    for (const row of tokens ?? []) {
      const token = String(row.token ?? "");
      if (!token || alreadySent.has(token)) continue;
      const result = await sendFcm(serviceAccount, token, event);
      const now = new Date().toISOString();
      if (result.ok) {
        sent++;
        await admin.from("news_notification_deliveries").upsert({
          event_id: eventId, token, status: "sent", attempted_at: now,
          delivered_at: now, fcm_message_id: result.messageId ?? null, last_error: null,
        }, { onConflict: "event_id,token" });
      } else if (result.status === 404 || result.status === 410) {
        invalid++;
        await admin.from("news_notification_deliveries").upsert({
          event_id: eventId, token, status: "invalid", attempted_at: now,
          last_error: result.error ?? "FCM token is invalid",
        }, { onConflict: "event_id,token" });
        await admin.from("device_tokens").delete().eq("token", token);
      } else {
        failed++;
        await admin.from("news_notification_deliveries").upsert({
          event_id: eventId, token, status: "failed", attempted_at: now,
          last_error: result.error ?? `FCM HTTP ${result.status}`,
        }, { onConflict: "event_id,token" });
      }
    }

    await admin.from("news_notification_events").update(
      failed > 0
        ? { status: "failed", last_error: `${failed} token delivery attempt(s) failed` }
        : { status: "sent", sent_at: new Date().toISOString(), last_error: null },
    ).eq("id", eventId);
    return { sent, invalid, failed };
  } catch (error) {
    await admin.from("news_notification_events").update({
      status: "failed",
      last_error: String(error).slice(0, 1000),
    }).eq("id", eventId);
    throw error;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.headers.get("x-news-notification-secret") !== Deno.env.get("NEWS_NOTIFICATION_SECRET")) {
    return new Response(JSON.stringify({ ok: false, error: "forbidden" }), {
      status: 403, headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const serviceAccount = loadServiceAccount();
    if (!serviceAccount) throw new Error("FCM_SERVICE_ACCOUNT_JSON is not configured.");
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const eventIds: string[] = body.eventId
      ? [String(body.eventId)]
      : (await admin.from("news_notification_events")
          .select("id")
          .in("status", ["pending", "failed"])
          .order("created_at", { ascending: true })
          .limit(25)).data?.map((row) => String(row.id)) ?? [];

    let sent = 0;
    let invalid = 0;
    let failed = 0;
    for (const eventId of eventIds) {
      const result = await deliverEvent(admin, serviceAccount, eventId);
      sent += result.sent;
      invalid += result.invalid;
      failed += result.failed;
    }
    return new Response(JSON.stringify({ ok: true, events: eventIds.length, sent, invalid, failed }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ ok: false, error: String(error) }), {
      status: 500, headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
