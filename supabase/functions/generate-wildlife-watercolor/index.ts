@
import { createClient } from npm:@supabase/supabase-js@2;
import { generateIllustration, storeIllustration, buildIllustrationPrompt } from ../_shared/image/pollinations.ts;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Auth Check
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing auth header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid user' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const { data: roleData } = await supabase.from('user_roles').select('role').eq('user_id', user.id).single();
    if (!roleData || (roleData.role !== 'admin' && roleData.role !== 'editor')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const body = await req.json();
    const { featureId, speciesInfo, manualPrompt } = body;

    if (!featureId) {
      return new Response(JSON.stringify({ error: 'Missing featureId' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const { data: feature, error: fetchError } = await supabase
      .from('daily_wildlife_features')
      .select('*')
      .eq('id', featureId)
      .single();

    if (fetchError || !feature) {
      return new Response(JSON.stringify({ error: 'Feature not found' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    let prompt = manualPrompt;
    if (!prompt) {
      const facts = {
         subject: speciesInfo?.commonName || feature.common_name || feature.title,
         scientificName: speciesInfo?.scientificName || feature.scientific_name,
         habitat: speciesInfo?.habitat || feature.habitat,
      };
      prompt = buildIllustrationPrompt(facts);
    }

    // Fallback seed
    const seed = Math.floor(Math.random() * 1000000);

    const generated = await generateIllustration(prompt, seed);
    if (!generated.ok || !generated.bytes || !generated.mime) {
      // Record failure
      await supabase.from('daily_wildlife_features').update({
        image_generation_status: 'failed',
        image_generation_error: generated.reason || 'Generation failed without reason'
      }).eq('id', featureId);

      return new Response(JSON.stringify({ error: 'Generation failed', details: generated.reason }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const stored = await storeIllustration({ storage: supabase.storage } as any, generated.bytes, generated.mime, daily-feature-${featureId});

    if (!stored.ok || !stored.publicUrl) {
      await supabase.from('daily_wildlife_features').update({
        image_generation_status: 'failed',
        image_generation_error: stored.reason || 'Storage upload failed'
      }).eq('id', featureId);

      return new Response(JSON.stringify({ error: 'Storage failed', details: stored.reason }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Success! Update DB
    await supabase.from('daily_wildlife_features').update({
      watercolour_image_url: stored.publicUrl,
      watercolour_prompt: prompt,
      image_generation_status: 'completed',
      image_generation_provider: generated.model || 'pollinations',
      image_generation_error: null
    }).eq('id', featureId);

    return new Response(JSON.stringify({
      success: true,
      imageUrl: stored.publicUrl,
      prompt: prompt
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
@
