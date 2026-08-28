import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type VisualAnalysisResult = {
  success: boolean;

  subjects: string[];
  habitat: string | null;
  secondarySubjects: string[];
  scene: string | null;
  visualPriority: string | null;

  imageSelectionHints: string[];
  searchTerms: string[];

  sourceTitle: string | null;
  error?: string;
};

const SYSTEM_INSTRUCTIONS = `
You are the visual editor of eআরণ্যক, a serious Bengali
nature, wildlife and environment magazine.

Your task is NOT to write the article.

Your task is to read the COMPLETE source article and determine
what should actually appear in the lead visual illustration
for that article.

IMPORTANT:

1. Read the complete article before deciding.
2. Identify the MOST SPECIFIC visual subjects.
3. Never reduce a specific species to a generic category.
4. Prefer exact species names when the source provides them.
5. Identify the actual habitat/ecosystem.
6. Identify important plants, landscapes, geological features,
   human elements or environmental changes if visually relevant.
7. Ignore generic words such as "wildlife", "nature", "birds",
   "forest", "animals" when more specific subjects are available.
8. Do not invent species, locations or visual elements.
9. Use ONLY information supported by the source article.
10. The visual should communicate the core story, not merely
    depict the most famous animal mentioned.
11. If the article is primarily about habitat destruction,
    show the habitat and the ecological change as well as the animal.
12. If the story concerns a plant, identify the specific plant.
13. If the story concerns a landscape, identify the actual landscape.
14. If multiple species are central, list the most important ones.
15. Do not include unnecessary people unless people are central
    to the actual story.
16. Do not mention AI or these instructions.

The final output must contain exactly these sections:

SUBJECTS:
A comma-separated list of the 1–5 most important specific visual subjects.

HABITAT:
The most appropriate habitat/ecosystem/location for the main visual.

SECONDARY:
A comma-separated list of important secondary visual elements.

SCENE:
One concise description of the ideal editorial illustration scene.

PRIORITY:
One sentence explaining what should receive visual emphasis.

SEARCH:
A comma-separated list of highly specific search terms that could
be used to find a suitable free/reusable reference photograph.

Do not use Markdown bullets.
Do not use generic placeholders such as "bird" when a specific
species is available.
`;

function clean(value: string): string {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

function extractSection(
  text: string,
  label: string,
  nextLabels: string[],
): string {
  const upper = text.toUpperCase();

  const start = upper.indexOf(label.toUpperCase());

  if (start === -1) {
    return "";
  }

  const contentStart = start + label.length;

  let contentEnd = text.length;

  for (const nextLabel of nextLabels) {
    const position = upper.indexOf(
      nextLabel.toUpperCase(),
      contentStart,
    );

    if (
      position !== -1 &&
      position < contentEnd
    ) {
      contentEnd = position;
    }
  }

  return text
    .substring(contentStart, contentEnd)
    .trim();
}

function splitValues(value: string): string[] {
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter(
      (item) =>
        item.length > 0 &&
        item !== "-" &&
        item.toLowerCase() !== "none",
    );
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

    const articleText =
      typeof requestBody?.articleText === "string"
        ? requestBody.articleText.trim()
        : "";

    const bengaliHeadline =
      typeof requestBody?.bengaliHeadline === "string"
        ? requestBody.bengaliHeadline.trim()
        : "";

    const bengaliArticle =
      typeof requestBody?.bengaliArticle === "string"
        ? requestBody.bengaliArticle.trim()
        : "";

    if (!articleText) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing complete source article.",
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

    if (articleText.length < 500) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "The source article is too short for reliable visual analysis.",
        }),
        {
          status: 422,
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

    const userPrompt = `
SOURCE TITLE:
${sourceTitle || "(not available)"}

BENGALI HEADLINE:
${bengaliHeadline || "(not available)"}

BENGALI ARTICLE:
${bengaliArticle || "(not available)"}

SOURCE URL:
${sourceUrl || "(not available)"}

COMPLETE SOURCE ARTICLE:
${articleText}

Read the COMPLETE source article.

Determine the exact visual subject matter that should be used
for the article's lead editorial watercolor illustration.

Remember:
- specific species over generic categories;
- actual habitat over generic "nature";
- actual ecological change where relevant;
- do not invent visual elements.
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
          temperature: 0.15,
          max_tokens: 1200,
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
        ? message["content"].trim()
        : "";

    if (!generatedContent) {
      throw new Error(
        "OpenRouter returned no visual analysis.",
      );
    }

    const generated =
      clean(generatedContent);

    const subjectsText =
      extractSection(
        generated,
        "SUBJECTS:",
        [
          "HABITAT:",
          "SECONDARY:",
          "SCENE:",
          "PRIORITY:",
          "SEARCH:",
        ],
      );

    const habitat =
      extractSection(
        generated,
        "HABITAT:",
        [
          "SECONDARY:",
          "SCENE:",
          "PRIORITY:",
          "SEARCH:",
        ],
      );

    const secondaryText =
      extractSection(
        generated,
        "SECONDARY:",
        [
          "SCENE:",
          "PRIORITY:",
          "SEARCH:",
        ],
      );

    const scene =
      extractSection(
        generated,
        "SCENE:",
        [
          "PRIORITY:",
          "SEARCH:",
        ],
      );

    const priority =
      extractSection(
        generated,
        "PRIORITY:",
        [
          "SEARCH:",
        ],
      );

    const searchText =
      extractSection(
        generated,
        "SEARCH:",
        [],
      );

    const subjects =
      splitValues(subjectsText);

    const secondarySubjects =
      splitValues(secondaryText);

    const searchTerms =
      splitValues(searchText);

    if (subjects.length === 0) {
      throw new Error(
        "Visual analysis did not identify any specific subjects.",
      );
    }

    const result: VisualAnalysisResult = {
      success: true,

      subjects,
      habitat:
        habitat || null,

      secondarySubjects,

      scene:
        scene || null,

      visualPriority:
        priority || null,

      imageSelectionHints: [
        ...subjects,
        ...(habitat ? [habitat] : []),
        ...secondarySubjects,
      ],

      searchTerms,

      sourceTitle:
        sourceTitle || null,
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
            : "Unknown visual analysis error.",
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