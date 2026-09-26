@
import { createClient } from npm:@supabase/supabase-js@2;

// For daily automation, this will be invoked via pg_cron.

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

    // Verify it's a trusted internal request or has admin token
    const authHeader = req.headers.get('Authorization');
    if (authHeader) {
        const token = authHeader.replace('Bearer ', '');
        if (token !== supabaseKey) {
            const { data: { user }, error: userError } = await supabase.auth.getUser(token);
            if (userError || !user) {
              return new Response(JSON.stringify({ error: 'Invalid user' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
            }
            const { data: roleData } = await supabase.from('user_roles').select('role').eq('user_id', user.id).single();
            if (!roleData || (roleData.role !== 'admin' && roleData.role !== 'editor')) {
              return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
            }
        }
    } else {
         return new Response(JSON.stringify({ error: 'Missing auth header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Determine target date (e.g. 7 days from now)
    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 7);
    const dateStr = targetDate.toISOString().split('T')[0];

    // Check if feature already exists for that date
    const { data: existing } = await supabase
      .from('daily_wildlife_features')
      .select('id')
      .eq('feature_date', dateStr)
      .maybeSingle();

    if (existing) {
       return new Response(JSON.stringify({ message: 'Feature already prepared for ' + dateStr }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Select a random wildlife item from the gallery that hasn't been featured recently
    const { data: candidates, error: candidateError } = await supabase
      .from('wildlife_gallery')
      .select('*')
      .eq('is_published', true)
      .not('common_name', 'is', null)
      .limit(50);

    if (candidateError || !candidates || candidates.length === 0) {
       return new Response(JSON.stringify({ error: 'No candidates available' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Get recently featured to avoid repetition
    const { data: recent } = await supabase
      .from('daily_wildlife_features')
      .select('common_name, scientific_name')
      .order('feature_date', { ascending: false })
      .limit(30);

    const recentNames = (recent || []).map(r => r.common_name).filter(Boolean);
    const recentSciNames = (recent || []).map(r => r.scientific_name).filter(Boolean);

    let selected = candidates[0];
    for (const c of candidates) {
        if (!recentNames.includes(c.common_name) && !recentSciNames.includes(c.scientific_name)) {
            selected = c;
            break;
        }
    }

    // Create the feature draft
    const { data: feature, error: insertError } = await supabase
      .from('daily_wildlife_features')
      .insert({
        feature_date: dateStr,
        status: 'draft',
        title: selected.common_name || selected.title,
        title_bn: selected.bengali_description, // Optional mapping
        common_name: selected.common_name,
        scientific_name: selected.scientific_name,
        bengali_name: selected.title, // Just using title if it's bengali
        species_description: selected.species_description,
        habitat: selected.location, // Approximate
        original_image_url: selected.storage_path,
        is_published: false,
        scheduled_publish_at: dateStr + 'T00:00:00Z', // Schedule to publish at midnight UTC
      })
      .select()
      .single();

    if (insertError || !feature) {
       return new Response(JSON.stringify({ error: 'Failed to insert feature', details: insertError }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Call generate edge function (using our own API to avoid duplicating pollinations logic)
    // We pass the auth header along to be authorized
    const genRes = await fetch(supabaseUrl + '/functions/v1/generate-wildlife-watercolor', {
        method: 'POST',
        headers: {
            'Authorization': 'Bearer ' + supabaseKey,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            featureId: feature.id,
            speciesInfo: {
                commonName: feature.common_name,
                scientificName: feature.scientific_name,
                habitat: feature.habitat
            }
        })
    });

    const genData = await genRes.json();

    return new Response(JSON.stringify({
      success: true,
      feature: feature,
      generation: genData
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
@
