export async function onRequestGet(context) {
  const { params, env } = context;
  const id = params.id;

  // Supabase config
  const SUPABASE_URL = 'https://btbcojfuipogpsarjcdw.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng';

  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/wildlife_news?article_id=eq.${id}&select=title,snippet,image_url,bengali_headline,bengali_dek`,
      {
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        },
      }
    );

    const articles = await response.json();
    const article = articles[0];

    // Get the base response (index.html)
    const originResponse = await context.next();

    if (!article) {
      return originResponse;
    }

    let html = await originResponse.text();

    const title = article.bengali_headline || article.title || 'eআরণ্যক Wildlife Update';
    const description = article.bengali_dek || article.snippet || 'Read the latest wildlife happenings on eআরণ্যক.';
    const imageUrl = article.image_url || 'https://earanyak.pages.dev/icons/Icon-512.png';
    const articleUrl = `https://earanyak.pages.dev/social/article/${id}`;

    // Construct Open Graph and Twitter meta tags
    const ogTags = `
  <!-- Social Preview Tags -->
  <title>${title}</title>
  <meta name="description" content="${description}">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:image" content="${imageUrl}">
  <meta property="og:url" content="${articleUrl}">
  <meta property="og:type" content="article">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${description}">
  <meta name="twitter:image" content="${imageUrl}">
`;

    // Inject tags into the head of index.html
    // We replace the first <head> tag with <head> + our tags
    html = html.replace('<head>', `<head>${ogTags}`);

    return new Response(html, {
      headers: {
        'content-type': 'text/html;charset=UTF-8',
      },
    });
  } catch (e) {
    // If anything fails, just return the standard index.html
    return context.next();
  }
}
