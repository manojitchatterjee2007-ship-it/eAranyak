import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-significant-update-secret",
};

const VALID_CONTENT_TYPES = [
  "news",
  "gallery",
  "magazine",
  "quiz",
  "app_notification",
  "community_article",
  "podcast",
  "vlog",
  "tutorial",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const authHeader = req.headers.get("Authorization") ?? "";
  const providedSecret = req.headers.get("x-significant-update-secret");
  const expectedSecret = Deno.env.get("SIGNIFICANT_UPDATE_SECRET") ||
    Deno.env.get("NEWS_NOTIFICATION_SECRET");

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let isAuthorized = false;

  if (expectedSecret && providedSecret === expectedSecret) {
    isAuthorized = true;
  } else if (authHeader.startsWith("Bearer ")) {
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (!userError && userData?.user) {
      const { data: profile } = await admin
        .from("profiles")
        .select("role")
        .eq("id", userData.user.id)
        .maybeSingle();
      if (profile && (profile.role === "admin" || profile.role === "editor")) {
        isAuthorized = true;
      }
    }
  }

  if (!isAuthorized) {
    return new Response(JSON.stringify({ ok: false, error: "forbidden" }), {
      status: 403,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const contentType = String(body.content_type ?? "").trim();
    const contentId = String(body.content_id ?? "").trim();
    const title = String(body.title ?? "").trim();
    const bodyText = String(body.body ?? "").trim();
    const data = body.data && typeof body.data === "object" ? body.data : {};

    if (!VALID_CONTENT_TYPES.includes(contentType)) {
      return new Response(
        JSON.stringify({ ok: false, error: "invalid content_type" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }
    if (!contentId || !title || !bodyText) {
      return new Response(
        JSON.stringify({ ok: false, error: "missing required fields" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const { error } = await admin
      .from("significant_update_events")
      .upsert({
        content_type: contentType,
        content_id: contentId,
        title,
        body: bodyText,
        payload: data,
      }, { onConflict: "content_type,content_id" });

    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ ok: false, error: String(error) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});