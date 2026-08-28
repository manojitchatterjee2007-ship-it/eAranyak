import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type WatercolorResult = {
  success: boolean;
  sourceImage: string | null;
  watercolorImage: string | null;
  mimeType: string | null;
  error?: string;
};

function isHttpUrl(value: string): boolean {
  return (
    value.startsWith("http://") ||
    value.startsWith("https://")
  );
}

function detectMimeType(
  url: string,
  contentType: string | null,
): string {
  if (contentType) {
    const cleanType = contentType
      .split(";")[0]
      .trim()
      .toLowerCase();

    if (cleanType.startsWith("image/")) {
      return cleanType;
    }
  }

  const lower = url.toLowerCase();

  if (lower.includes(".png")) {
    return "image/png";
  }

  if (lower.includes(".webp")) {
    return "image/webp";
  }

  if (lower.includes(".gif")) {
    return "image/gif";
  }

  return "image/jpeg";
}

async function fetchSourceImage(
  url: string,
): Promise<{
  bytes: Uint8Array;
  mimeType: string;
}> {
  const response = await fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (compatible; eAranyakNewsReader/1.0)",
      "Accept":
        "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    },
    redirect: "follow",
  });

  if (!response.ok) {
    throw new Error(
      `Source image request failed with HTTP ${response.status}.`,
    );
  }

  const contentType =
    response.headers.get("content-type");

  const buffer = await response.arrayBuffer();

  const bytes = new Uint8Array(buffer);

  if (bytes.length === 0) {
    throw new Error(
      "The source image returned zero bytes.",
    );
  }

  return {
    bytes,
    mimeType: detectMimeType(
      url,
      contentType,
    ),
  };
}

function bytesToBase64(
  bytes: Uint8Array,
): string {
  let binary = "";

  const chunkSize = 8192;

  for (
    let i = 0;
    i < bytes.length;
    i += chunkSize
  ) {
    const end = Math.min(
      i + chunkSize,
      bytes.length,
    );

    const chunk = bytes.subarray(
      i,
      end,
    );

    binary += String.fromCharCode(
      ...chunk,
    );
  }

  return btoa(binary);
}

function extractGeneratedImage(
  json: Record<string, unknown>,
): {
  data: string;
  mimeType: string;
} | null {
  const candidates = json["candidates"];

  if (!Array.isArray(candidates)) {
    return null;
  }

  for (const candidate of candidates) {
    if (
      typeof candidate !== "object" ||
      candidate === null
    ) {
      continue;
    }

    const candidateObject =
      candidate as Record<string, unknown>;

    const content =
      candidateObject["content"];

    if (
      typeof content !== "object" ||
      content === null
    ) {
      continue;
    }

    const contentObject =
      content as Record<string, unknown>;

    const parts =
      contentObject["parts"];

    if (!Array.isArray(parts)) {
      continue;
    }

    for (const part of parts) {
      if (
        typeof part !== "object" ||
        part === null
      ) {
        continue;
      }

      const partObject =
        part as Record<string, unknown>;

      const inlineData =
        partObject["inlineData"] ??
        partObject["inline_data"];

      if (
        typeof inlineData !== "object" ||
        inlineData === null
      ) {
        continue;
      }

      const imageData =
        inlineData as Record<string, unknown>;

      const data =
        typeof imageData["data"] === "string"
          ? imageData["data"]
          : "";

      const mimeType =
        typeof imageData["mimeType"] === "string"
          ? imageData["mimeType"]
          : typeof imageData["mime_type"] === "string"
          ? imageData["mime_type"]
          : "image/png";

      if (data) {
        return {
          data,
          mimeType,
        };
      }
    }
  }

  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    const requestBody = await req.json();

    const sourceImage =
      typeof requestBody?.sourceImage === "string"
        ? requestBody.sourceImage.trim()
        : "";

    const headline =
      typeof requestBody?.headline === "string"
        ? requestBody.headline.trim()
        : "";

    const visualScene =
      typeof requestBody?.visualScene === "string"
        ? requestBody.visualScene.trim()
        : "";

    const habitat =
      typeof requestBody?.habitat === "string"
        ? requestBody.habitat.trim()
        : "";

    const subjects =
      Array.isArray(requestBody?.subjects)
        ? requestBody.subjects
            .map((value: unknown) =>
              String(value).trim(),
            )
            .filter(Boolean)
        : [];

    if (
      !sourceImage ||
      !isHttpUrl(sourceImage)
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "A valid source image URL is required.",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type":
              "application/json; charset=utf-8",
          },
        },
      );
    }

    const apiKey =
      Deno.env.get("GEMINI_API_KEY");

    if (!apiKey) {
      throw new Error(
        "GEMINI_API_KEY is not configured in Supabase secrets.",
      );
    }

    /*
     * Download the actual photograph selected from
     * the source article.
     */
    const source =
      await fetchSourceImage(
        sourceImage,
      );

    const sourceBase64 =
      bytesToBase64(
        source.bytes,
      );

    const prompt = `
Transform the supplied source photograph into a refined,
naturalistic editorial watercolor painting for a serious
Bengali nature and wildlife magazine.

THIS IS A FAITHFUL IMAGE-TO-IMAGE TRANSFORMATION.

The supplied photograph is the primary factual visual reference.

Preserve:
- the actual species identity
- the actual anatomy
- natural proportions
- the pose and important composition
- the habitat
- the ecological relationships visible in the photograph

Do not replace the subject with a generic animal.
Do not invent a different species.
Do not create an unrelated new scene.

ARTICLE HEADLINE:
${headline || "(not available)"}

SPECIFIC SUBJECTS:
${
  subjects.length > 0
    ? subjects.join(", ")
    : "The specific subjects visible in the photograph"
}

HABITAT:
${habitat || "The natural habitat visible in the photograph"}

EDITORIAL SCENE:
${
  visualScene ||
  "A natural-history editorial illustration faithful to the source photograph"
}

WATERCOLOR STYLE:

Make it look like a genuinely hand-painted watercolor
on high-quality cold-pressed natural paper.

Use:
- transparent layered pigment
- visible paper texture
- watercolor granulation
- subtle pigment pooling
- soft wet-on-wet transitions
- irregular watercolor blooms
- delicate feathered edges
- selective dry-brush texture
- uneven natural pigment density
- luminous areas where paper remains visible
- restrained earthy greens
- muted olive
- ochre
- umber
- soft grey-blue
- understated natural browns

The painting should feel like a sophisticated
natural-history illustration prepared by a skilled
watercolor artist.

Keep the subject realistic and observational.

IMPORTANT:
Preserve the source photograph's recognizable subject,
species characteristics, habitat and composition while
changing the medium from photography to watercolor.

DO NOT create:
- cartoon animals
- vector art
- flat digital illustration
- glossy CGI
- 3D rendering
- plastic textures
- fantasy landscapes
- neon colours
- excessive saturation
- artificial dramatic effects
- text
- captions
- logos
- borders
- watermarks
`;

    const geminiResponse = await fetch(
      "https://generativelanguage.googleapis.com/v1/models/gemini-3.1-flash-image:generateContent",
      {
        method: "POST",
        headers: {
          "Content-Type":
            "application/json",
          "x-goog-api-key":
            apiKey,
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: prompt,
                },
                {
                  inline_data: {
                    mime_type:
                      source.mimeType,
                    data:
                      sourceBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseModalities: [
              "IMAGE",
            ],
          },
        }),
      },
    );

    const responseText =
      await geminiResponse.text();

    if (!geminiResponse.ok) {
      throw new Error(
        `Gemini image request failed (${geminiResponse.status}): ${responseText}`,
      );
    }

    let geminiJson:
      Record<string, unknown>;

    try {
      geminiJson =
        JSON.parse(responseText);
    } catch (_) {
      throw new Error(
        "Gemini returned invalid JSON.",
      );
    }

    const generated =
      extractGeneratedImage(
        geminiJson,
      );

    if (!generated) {
      throw new Error(
        "Gemini returned no generated image data.",
      );
    }

    /*
     * Return a data URL for the first visual-quality test.
     * Later we'll upload this to Supabase Storage.
     */
    const watercolorImage =
      `data:${generated.mimeType};base64,${generated.data}`;

    const result:
      WatercolorResult = {
      success: true,
      sourceImage,
      watercolorImage,
      mimeType:
        generated.mimeType,
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
            : "Unknown Gemini watercolor transformation error.",
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