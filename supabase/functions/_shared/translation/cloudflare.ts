/**
 * Cloudflare Workers AI Bengali translation provider.
 *
 * Expected Supabase secret:
 *   CLOUDFLARE_BENGALI_TRANSLATOR_URL
 *
 * The URL should point to the deployed eআরণ্যক Cloudflare Worker:
 *   https://earanyak-bengali-ai-benchmark.manojitchatterjee2007.workers.dev
 *
 * The Worker uses:
 *   @cf/ai4bharat/indictrans2-en-indic-1B
 * with target_language = ben_Beng
 *
 * It performs sentence-aware chunking and deterministic Bengali validation.
 */

export type CloudflareTranslationResult =
  | {
      ok: true;
      text: string;
      raw?: unknown;
    }
  | {
      ok: false;
      failure: {
        reason: string;
      };
    };

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export async function translateCloudflare(
  text: string,
  timeoutMs = 60_000,
): Promise<CloudflareTranslationResult> {
  const endpoint = clean(
    Deno.env.get("CLOUDFLARE_BENGALI_TRANSLATOR_URL"),
  );

  if (!endpoint) {
    return {
      ok: false,
      failure: {
        reason: "CLOUDFLARE_BENGALI_TRANSLATOR_URL is not configured.",
      },
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({
        englishSummary: text,
      }),
      signal: controller.signal,
    });

    const rawText = await response.text();

    let payload: any;
    try {
      payload = JSON.parse(rawText);
    } catch {
      return {
        ok: false,
        failure: {
          reason:
            `Cloudflare returned invalid JSON (HTTP ${response.status}). ` +
            rawText.slice(0, 500),
        },
      };
    }

    if (!response.ok) {
      return {
        ok: false,
        failure: {
          reason:
            `Cloudflare HTTP ${response.status}: ` +
            (clean(payload?.error) || rawText.slice(0, 500)),
        },
      };
    }

    if (payload?.success !== true) {
      return {
        ok: false,
        failure: {
          reason:
            clean(payload?.error) ||
            "Cloudflare translation failed validation.",
        },
      };
    }

    const translated = clean(payload?.translation);

    if (!translated) {
      return {
        ok: false,
        failure: {
          reason: "Cloudflare returned an empty Bengali translation.",
        },
      };
    }

    if (payload?.validation?.valid !== true) {
      return {
        ok: false,
        failure: {
          reason:
            "Cloudflare returned text that failed its Bengali/number validation.",
        },
      };
    }

    return {
      ok: true,
      text: translated,
      raw: payload,
    };
  } catch (error) {
    return {
      ok: false,
      failure: {
        reason:
          error instanceof DOMException && error.name === "AbortError"
            ? `Cloudflare translation timed out after ${timeoutMs} ms.`
            : error instanceof Error
              ? error.message
              : String(error),
      },
    };
  } finally {
    clearTimeout(timeout);
  }
}
