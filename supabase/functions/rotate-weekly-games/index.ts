import { createClient } from "npm:@supabase/supabase-js@2";

const COUNTS: Record<string, number> = { photo: 8, audio: 8, hint: 4, scramble: 4, word: 4 };
const MIN_ACTIVE_BANK = 20;
const MAX_ACTIVE_BANK = 24;
const GENERATOR_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/generate-game-bank`;
const CATEGORIES = Object.keys(COUNTS);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

function mondayUtc(date = new Date()): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const diff = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - diff);
  return d.toISOString().slice(0, 10);
}

async function topUpGameBankIfNeeded(admin: any) {
  const counts: Record<string, number> = {};
  for (const category of CATEGORIES) {
    const { count, error } = await admin
      .from("game_questions")
      .select("id", { count: "exact", head: true })
      .eq("category", category)
      .eq("active", true);
    if (error) throw error;
    counts[category] = count ?? 0;
  }

  const shortages = CATEGORIES.filter((c) => counts[c] < MIN_ACTIVE_BANK);
  if (shortages.length === 0) return { triggered: false, counts };

  const { data: config, error: configError } = await admin
    .from("game_generator_config")
    .select("secret")
    .eq("id", 1)
    .maybeSingle();

  if (configError) throw configError;
  if (!config?.secret) {
    throw new Error(`Game bank below ${MIN_ACTIVE_BANK} but generator secret is unavailable.`);
  }

  const response = await fetch(GENERATOR_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-game-generator-secret": String(config.secret),
    },
    body: "{}",
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Game-bank top-up failed (${response.status}): ${body.slice(0, 500)}`);
  }

  return { triggered: true, shortages, generator: body };
}

async function trimActiveBank(admin: any) {
  const result: Record<string, number> = {};

  for (const category of CATEGORIES) {
    const { data, error } = await admin
      .from("game_questions")
      .select("id,last_used_at,times_used,created_at")
      .eq("category", category)
      .eq("active", true)
      .order("last_used_at", { ascending: true, nullsFirst: true })
      .order("times_used", { ascending: true })
      .order("created_at", { ascending: true });

    if (error) throw error;

    const rows = data ?? [];
    const excess = Math.max(0, rows.length - MAX_ACTIVE_BANK);
    if (!excess) {
      result[category] = 0;
      continue;
    }

    // Keep the permanent records in the table; retire only their active status.
    const retireIds = rows.slice(0, excess).map((row: any) => row.id);
    const { error: updateError } = await admin
      .from("game_questions")
      .update({ active: false })
      .in("id", retireIds);

    if (updateError) throw updateError;
    result[category] = retireIds.length;
  }

  return result;
}

function base64UrlEncode(data: Uint8Array): string { let bin = ""; for (const b of data) bin += String.fromCharCode(b); return btoa(bin).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,""); }
function pemToArrayBuffer(pem: string): Uint8Array { const b64=pem.replace(/-----BEGIN PRIVATE KEY-----/,"").replace(/-----END PRIVATE KEY-----/,"").replace(/\s+/g,""); const bin=atob(b64); const bytes=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i); return bytes; }
function loadServiceAccount(): any | null { const raw=Deno.env.get("FCM_SERVICE_ACCOUNT_JSON"); if(!raw)return null; let json=raw; try{json=atob(raw);}catch(_){} try{return JSON.parse(json);}catch(_){return null;} }
let cachedToken:{token:string;exp:number}|null=null;
async function getAccessToken(sa:any):Promise<string>{ const now=Math.floor(Date.now()/1000); if(cachedToken&&cachedToken.exp>now+60)return cachedToken.token; const enc=new TextEncoder(); const header=base64UrlEncode(enc.encode(JSON.stringify({alg:"RS256",typ:"JWT"}))); const claims=base64UrlEncode(enc.encode(JSON.stringify({iss:sa.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3600}))); const key=await crypto.subtle.importKey("pkcs8",pemToArrayBuffer(sa.private_key),{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]); const sig=await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,enc.encode(`${header}.${claims}`)); const jwt=`${header}.${claims}.${base64UrlEncode(new Uint8Array(sig))}`; const res=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:jwt})}); if(!res.ok)throw new Error(`OAuth failed: ${await res.text()}`); const j=await res.json(); cachedToken={token:j.access_token,exp:now+(j.expires_in??3600)}; return cachedToken.token; }
async function sendFcm(sa:any,token:string,title:string,body:string,data:Record<string,string>):Promise<Response>{ const accessToken=await getAccessToken(sa); return fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,{method:"POST",headers:{Authorization:`Bearer ${accessToken}`,"Content-Type":"application/json"},body:JSON.stringify({message:{token,notification:{title,body},data,android:{priority:"HIGH",notification:{sound:"default",channel_id:"earanyak_push_channel"}}}})}); }

async function imageForSpecies(species:string){
  try {
    const url = new URL("https://api.inaturalist.org/v1/taxa");
    url.search = new URLSearchParams({ q: species, rank: "species", per_page: "20" }).toString();
    const r = await fetch(url, { headers: { "User-Agent": "eAranyakGameRotator/1.0" } });
    if (!r.ok) return null;
    const body = await r.json();
    const target = species.toLowerCase().replace(/[^a-z0-9]/g, "");
    const taxon = (body?.results ?? []).find((t:any) => {
      const name = String(t?.name ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
      const common = String(t?.preferred_common_name ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
      return name === target || common === target;
    });
    const photo = taxon?.default_photo;
    const image = photo?.medium_url || photo?.url;
    if (!image) return null;
    return { image_url: String(image).replace("square", "medium"), image_source: "iNaturalist", attribution: photo?.attribution ? String(photo.attribution) : null };
  } catch (_) { return null; }
}

function audioRank(mime:string,url:string){const m=mime.toLowerCase(),u=url.toLowerCase(); if(m==='audio/mpeg'||u.endsWith('.mp3'))return 0;if(m==='audio/wav'||m==='audio/x-wav'||u.endsWith('.wav'))return 1;if(m.includes('ogg')||m.includes('opus')||u.endsWith('.ogg')||u.endsWith('.oga')||u.endsWith('.opus'))return 2;return m.startsWith('audio/')?3:99;}
async function audioForSpecies(species:string){ try{for(const term of [`"${species}" filetype:audio`,`${species} bird filetype:audio`]){const u=new URL('https://commons.wikimedia.org/w/api.php');u.search=new URLSearchParams({action:'query',format:'json',generator:'search',gsrnamespace:'6',gsrsearch:term,gsrlimit:'30',prop:'imageinfo',iiprop:'url|mime|extmetadata'}).toString();const r=await fetch(u,{headers:{'User-Agent':'eAranyakGameRotator/1.0'}});if(!r.ok)continue;const b=await r.json();const pages=b?.query?.pages;if(!pages)continue;const cs:any[]=[];for(const page of Object.values(pages) as any[]){const info=page?.imageinfo?.[0];const url=info?.url?.toString().trim(),mime=info?.mime?.toString().trim();if(!url||!mime?.startsWith('audio/'))continue;const title=page?.title?.toString().toLowerCase()||'';let relevance=title.includes(species.toLowerCase())?100:0;if(title.includes('call'))relevance+=20;if(title.includes('song'))relevance+=10;cs.push({url,mime,relevance,meta:info?.extmetadata});}cs.sort((a,b)=>b.relevance-a.relevance||audioRank(a.mime,a.url)-audioRank(b.mime,b.url));if(!cs.length || cs[0].relevance < 100)continue;const best=cs[0],m=best.meta||{};const artist=m.Artist?.value||m.Credit?.value||m.Creator?.value;const license=m.LicenseShortName?.value||m.UsageTerms?.value;return {audio_url:best.url,audio_source:'Wikimedia Commons',attribution:[artist&&`Recorded by ${artist}`,license,'Wikimedia Commons'].filter(Boolean).join(' • ')||null};}}catch(_){return null;} }

async function ensureMedia(admin:any,row:any){
  if(row.category==='hint' || row.category==='word') return true;
  if(row.category==='audio'){
    const media=await audioForSpecies(row.species);
    if(media){
      const {error}=await admin.from('game_questions').update(media).eq('id',row.id);
      return !error;
    }
    return Boolean(row.audio_url);
  }
  const media=await imageForSpecies(row.species);
  if(media){
    const {error}=await admin.from('game_questions').update(media).eq('id',row.id);
    return !error;
  }
  return Boolean(row.image_url);
}

Deno.serve(async(req:Request)=>{ if(req.method==='OPTIONS')return new Response('ok',{headers:cors}); try{const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);const weekStart=mondayUtc();const {data:existingRows}=await admin.from('weekly_challenges').select('id,category,question_ids').eq('week_start',weekStart);

const bankBefore = await topUpGameBankIfNeeded(admin);

const selected: any[] = [];
const usageCutoff = new Date(Date.now() - 21 * 24 * 60 * 60 * 1000).toISOString();

for (const category of CATEGORIES) {
  const need = COUNTS[category];

  const { data, error } = await admin
    .from("game_questions")
    .select("id,category,species,bengali,question,options,answer,hints,syllables,image_url,audio_url,image_source,audio_source,attribution,last_used_at,times_used")
    .eq("category", category)
    .eq("active", true)
    .order("last_used_at", { ascending: true, nullsFirst: true })
    .order("times_used", { ascending: true })
    .limit(MAX_ACTIVE_BANK);

  if (error) throw error;

  const eligible = (data ?? []).filter(
    (row: any) => !row.last_used_at || String(row.last_used_at) < usageCutoff,
  );
  const pool = eligible.length >= need ? eligible : (data ?? []);

  let got = 0;
  const seenWordAnswers = new Set<string>();
  for (const row of pool) {
    if (got >= need) break;
    if (category === "word") {
      const key = String(row.bengali ?? "").replace(/\s+/g, "").toLowerCase();
      if (!key || seenWordAnswers.has(key)) continue;
      seenWordAnswers.add(key);
    }
    if (await ensureMedia(admin, row)) {
      selected.push({ category, id: row.id });
      got++;
    }
  }

  if (got < need) {
    throw new Error(`Not enough playable ${category} questions. Need ${need}, found ${got}.`);
  }
}

for(const s of selected){await admin.from('game_questions').update({times_used:((await admin.from('game_questions').select('times_used').eq('id',s.id).single()).data?.times_used??0)+1,last_used_at:new Date().toISOString()}).eq('id',s.id);}
const grouped:Record<string,string[]>={};for(const s of selected)(grouped[s.category]??=[]).push(s.id);
const rows=CATEGORIES.map(category=>({week_start:weekStart,category,payload:{version:2,question_ids:grouped[category]||[]},question_ids:grouped[category]||[],generated_at:new Date().toISOString(),selection_version:2}));
const {error:upsertError}=await admin.from('weekly_challenges').upsert(rows,{onConflict:'week_start,category'});if(upsertError)throw upsertError;
await admin.from('weekly_challenges').delete().neq('week_start',weekStart);
const retired = await trimActiveBank(admin);
let notified=0;const sa=loadServiceAccount();if(sa){const {data:tokens}=await admin.from('device_tokens').select('token');for(const row of tokens||[]){try{const res=await sendFcm(sa,row.token,'নতুন সাপ্তাহিক চ্যালেঞ্জ! (New Weekly Challenges)','এই সপ্তাহের প্রকৃতি-খেলা এসেছে — খেলতে ট্যাপ করুন।',{type:'game'});if(res.ok)notified++;}catch(_){}}}
return new Response(JSON.stringify({ok:true,weekStart,repairedExistingWeek:Array.isArray(existingRows)&&existingRows.length>0,selected:grouped,bankBefore,retired,notified}),{headers:{...cors,'Content-Type':'application/json'}});
}catch(e){return new Response(JSON.stringify({ok:false,error:e instanceof Error?e.message:String(e)}),{status:500,headers:{...cors,'Content-Type':'application/json'}});}});
