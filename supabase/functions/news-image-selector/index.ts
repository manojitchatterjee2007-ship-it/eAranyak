import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ImageCandidate = {
  url: string;
  score: number;
  reason: string;
};

type Result = {
  success: boolean;
  selectedImage: string | null;
  candidates: ImageCandidate[];
  error?: string;
};

const SYSTEM_INSTRUCTIONS = `
You are the visual image editor for eআরণ্যক.

You must select the BEST photograph from a set of images taken
from the ORIGINAL SOURCE ARTICLE.

The photograph will later be transformed into a watercolor
editorial illustration.

IMPORTANT:

1. Select only from the supplied source image URLs.
2. Never invent an image URL.
3. Prefer an image that directly depicts one or more of the
   specific subjects identified by the visual analysis.
4. Prefer the actual habitat/ecosystem described by the article.
5. Prefer a photograph that visually communicates the core story.
6. A generic wildlife image is inferior to a specific species image.
7. A beautiful image that is unrelated to the story is inferior
   to a less dramatic but highly relevant image.
8. Avoid logos, portraits, screenshots, advertisements and unrelated
   images.
9. If several images are relevant, prefer the clearest photograph
   with the best subject visibility and useful composition.
10. If the article is fundamentally about habitat change, prefer
    an image showing the habitat or ecological contrast when
    available.
11. Do not select an image merely because it is the first image.
12. Return an ordered ranking.

Output exactly:

BEST:
<exact URL>

RANKING:
<URL> | <score 0-100> | <short reason>
<URL> | <score 0-100> | <short reason>

Use only the supplied URLs.
`;

function clean(text: string): string {
  return text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

function extractBest(text: string): string {
  const match = text.match(
    /BEST:\s*([\s\S]*?)(?:\n\s*RANKING:|$)/i,
  );

  return match?.[1]?.trim() ?? "";
}

function extractRanking(text: string): ImageCandidate[] {
  const result: ImageCandidate[] = [];

  const rankingStart = text
    .toUpperCase()
    .indexOf("RANKING:");

  if (rankingStart === -1) {
    return result;
  }

  const rankingText =
    text.substring(rankingStart + "RANKING:".length);

  for (const line of rankingText.split("\n")) {
    const trimmed = line.trim();

    if (!trimmed || !trimmed.includes("|")) {
      continue;
    }

    const parts = trimmed
      .split("|")
      .map((part) => part.trim());

    if (parts.length < 3) {
      continue;
    }

    const url = parts[0];

    const score = Number(
      parts[1].replace(/[^\d]/g, ""),
    );

    const reason = parts
      .slice(2)
      .join(" | ");

    if (
      url.startsWith("http://") ||
      url.startsWith("https://")
    ) {
      result.push({
        url,
        score: Number.isFinite(score)
          ? score
          : 0,
        reason,
      });
    }
  }

  return result;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    const requestBody = await req.json();

    const sourceTitle =
      typeof requestBody?.sourceTitle === "string"
        ? requestBody.sourceTitle.trim()
        : "";

    const sourceUrl =
      typeof requestBody?.sourceUrl === "string"
        ? requestBody.sourceUrl.trim()
        : "";

    const subjects =
      Array.isArray(requestBody?.subjects)
        ? requestBody.subjects
            .map((value: unknown) => String(value))
            .filter(Boolean)
        : [];

    const habitat =
      typeof requestBody?.habitat === "string"
        ? requestBody.habitat.trim()
        : "";

    const scene =
      typeof requestBody?.scene === "string"
        ? requestBody.scene.trim()
        : "";

    const visualPriority =
      typeof requestBody?.visualPriority === "string"
        ? requestBody.visualPriority.trim()
        : "";

    const imageUrls =
      Array.isArray(requestBody?.imageUrls)
        ? requestBody.imageUrls
            .map((value: unknown) => String(value))
            .filter(
              (value: string) =>
                value.startsWith("http://") ||
                value.startsWith("https://"),
            )
        : [];

    if (imageUrls.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "No source images were supplied.",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json; charset=utf-8",
          },
        },
      );
    }

    const apiKey =
      Deno.env.get("OPENROUTER_API_KEY");

    if (!apiKey) {
      throw new Error(
        "OPENROUTER_API_KEY is not configured in Supabase secrets.",
      );
    }

    const imageList = imageUrls
      .map(
        (url: string, index: number) =>
          `${index + 1}. ${url}`,
      )
      .join("\n");

    const userPrompt = `
SOURCE TITLE:
${sourceTitle || "(not available)"}

SOURCE URL:
${sourceUrl || "(not available)"}

SPECIFIC VISUAL SUBJECTS:
${subjects.join(", ")}

HABITAT:
${habitat || "(not available)"}

IDEAL SCENE:
${scene || "(not available)"}

VISUAL PRIORITY:
${visualPriority || "(not available)"}

SOURCE ARTICLE IMAGES:
${imageList}

Select the best image from ONLY the supplied URLs.

The chosen image must be the closest visual match to the article
and the visual analysis.

Do not create or modify URLs.
`;

    const aiResponse = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",

        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },

        body: JSON.stringify({
          model: "google/gemini-2.0-flash-exp:free",

          messages: [
            {
              role: "system",
              content: SYSTEM_INSTRUCTIONS,
            },
            {
              role: "user",
              content: userPrompt,
            },
          ],

          temperature: 0.1,
          max_tokens: 1400,
        }),
      },
    );

    const responseText =
      await aiResponse.text();

    if (!aiResponse.ok) {
      throw new Error(
        `OpenRouter request failed (${aiResponse.status}): ${responseText}`,
      );
    }

    let aiJson: Record<string, unknown>;

    try {
      aiJson = JSON.parse(responseText);
    } catch (_) {
      throw new Error(
        "OpenRouter returned invalid JSON.",
      );
    }

    const choices =
      aiJson["choices"];

    if (
      !Array.isArray(choices) ||
      choices.length === 0
    ) {
      throw new Error(
        "OpenRouter returned no choices.",
      );
    }

    const firstChoice =
      choices[0] as Record<string, unknown>;

    const message =
      firstChoice["message"] as
        | Record<string, unknown>
        | undefined;

    const generatedContent =
      typeof message?.["content"] === "string"
        ? clean(message["content"])
        : "";

    if (!generatedContent) {
      throw new Error(
        "OpenRouter returned no image-selection result.",
      );
    }

    const selectedImage =
      extractBest(generatedContent);

    const ranking =
      extractRanking(generatedContent);

    /*
     * Safety check:
     * never allow the model to return an image that was not
     * actually supplied to it.
     */
    if (
      selectedImage &&
      !imageUrls.includes(selectedImage)
    ) {
      throw new Error(
        "The selected image URL was not present in the source image list.",
      );
    }

    const finalImage =
      selectedImage ||
      ranking[0]?.url ||
      imageUrls[0];

    const result: Result = {
      success: true,
      selectedImage: finalImage,
      candidates: ranking,
    };

    return new Response(
      JSON.stringify(result),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type":
            "application/json; charset=utf-8",
        },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error:
          error instanceof Error
            ? error.message
            : "Unknown image selection error.",
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          "Content-Type":
            "application/json; charset=utf-8",
        },
      },
    );
  }
});