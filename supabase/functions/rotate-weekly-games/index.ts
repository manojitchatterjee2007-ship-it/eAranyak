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

// ---------------------------------------------------------------------------
// Fisher-Yates shuffle. Used to randomize option order at the moment a
// question is selected for weekly play — this is what actually fixes
// "the correct answer is almost always the first option": nothing upstream
// (whatever originally generated the question) needs to change, because we
// re-shuffle right before publishing regardless of how it was stored.
// ---------------------------------------------------------------------------
function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
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

async function imageForSpecies(species:string){ try{ const r=await fetch(`https://api.inaturalist.org/v1/taxa?q=${encodeURIComponent(species)}&per_page=1`,{headers:{"User-Agent":"eAranyakGameRotator/1.0"}}); if(!r.ok)return null; const b=await r.json(); const p=b?.results?.[0]?.default_photo; const url=p?.medium_url||p?.url; if(!url)return null; return {image_url:String(url).replace("square","medium"),image_source:"iNaturalist",attribution:p?.attribution?String(p.attribution):null}; }catch(_){return null;} }
function audioRank(mime:string,url:string){const m=mime.toLowerCase(),u=url.toLowerCase(); if(m==='audio/mpeg'||u.endsWith('.mp3'))return 0;if(m==='audio/wav'||m==='audio/x-wav'||u.endsWith('.wav'))return 1;if(m.includes('ogg')||m.includes('opus')||u.endsWith('.ogg')||u.endsWith('.oga')||u.endsWith('.opus'))return 2;return m.startsWith('audio/')?3:99;}

async function audioFromWikimedia(species:string){ try{for(const term of [`"${species}" filetype:audio`,`${species} bird filetype:audio`]){const u=new URL('https://commons.wikimedia.org/w/api.php');u.search=new URLSearchParams({action:'query',format:'json',generator:'search',gsrnamespace:'6',gsrsearch:term,gsrlimit:'30',prop:'imageinfo',iiprop:'url|mime|extmetadata'}).toString();const r=await fetch(u,{headers:{'User-Agent':'eAranyakGameRotator/1.0'}});if(!r.ok)continue;const b=await r.json();const pages=b?.query?.pages;if(!pages)continue;const cs:any[]=[];for(const page of Object.values(pages) as any[]){const info=page?.imageinfo?.[0];const url=info?.url?.toString().trim(),mime=info?.mime?.toString().trim();if(!url||!mime?.startsWith('audio/'))continue;const title=page?.title?.toString().toLowerCase()||'';let relevance=title.includes(species.toLowerCase())?100:0;if(title.includes('call'))relevance+=20;if(title.includes('song'))relevance+=10;cs.push({url,mime,relevance,meta:info?.extmetadata});}cs.sort((a,b)=>b.relevance-a.relevance||audioRank(a.mime,a.url)-audioRank(b.mime,b.url));if(!cs.length)continue;const best=cs[0],m=best.meta||{};const artist=m.Artist?.value||m.Credit?.value||m.Creator?.value;const license=m.LicenseShortName?.value||m.UsageTerms?.value;return {audio_url:best.url,audio_source:'Wikimedia Commons',attribution:[artist&&`Recorded by ${artist}`,license,'Wikimedia Commons'].filter(Boolean).join(' • ')||null};}}catch(_){} return null; }

// Xeno-canto is THE dedicated bird-call archive — far broader species
// coverage than Wikimedia Commons, which is why audio was consistently
// scarcer than the other categories. Requires a free API key (register at
// xeno-canto.org -> verify email -> Account page -> API key) set as the
// XENO_CANTO_API_KEY secret. Tried first; falls back to Wikimedia Commons.
async function audioFromXenoCanto(species:string){
  const key = Deno.env.get('XENO_CANTO_API_KEY');
  if (!key) return null;
  try {
    const u = new URL('https://xeno-canto.org/api/3/recordings');
    u.search = new URLSearchParams({ query: `en:"${species}"`, key }).toString();
    const r = await fetch(u, { headers: { 'User-Agent': 'eAranyakGameRotator/1.0' } });
    if (!r.ok) return null;
    const b = await r.json();
    const recordings: any[] = Array.isArray(b?.recordings) ? b.recordings : [];
    if (!recordings.length) return null;

    // Prefer higher-quality ("A"/"B" rated), shorter (quicker to load in-app) recordings.
    recordings.sort((a, b) => {
      const qa = String(a?.q ?? 'E'), qb = String(b?.q ?? 'E');
      if (qa !== qb) return qa.localeCompare(qb); // 'A' < 'B' < ... < 'E'
      return (parseFloat(a?.length) || 999) - (parseFloat(b?.length) || 999);
    });

    const best = recordings[0];
    const fileUrl = best?.file ? String(best.file) : null;
    if (!fileUrl) return null;

    const recordist = best?.rec ? String(best.rec) : null;
    const license = best?.lic ? String(best.lic).replace(/^\/\//, 'https://') : null;

    return {
      audio_url: fileUrl.startsWith('http') ? fileUrl : `https:${fileUrl}`,
      audio_source: 'Xeno-canto',
      attribution: [recordist && `Recorded by ${recordist}`, 'Xeno-canto', license].filter(Boolean).join(' • ') || null,
    };
  } catch (_) {
    return null;
  }
}

async function audioForSpecies(species:string){
  return (await audioFromXenoCanto(species)) ?? (await audioFromWikimedia(species));
}

async function ensureMedia(admin:any,row:any){ if(row.category==='hint')return true; if(row.category==='audio'){ if(row.audio_url)return true; const media=await audioForSpecies(row.species); if(!media)return false; const {error}=await admin.from('game_questions').update(media).eq('id',row.id); if(!error){row.audio_url=media.audio_url;row.audio_source=media.audio_source;row.attribution=media.attribution;} return !error; } if(row.image_url)return true; const media=await imageForSpecies(row.species); if(!media)return false; const {error}=await admin.from('game_questions').update(media).eq('id',row.id); if(!error){row.image_url=media.image_url;row.image_source=media.image_source;row.attribution=media.attribution;} return !error; }


async function rebalanceActiveDifficulties(admin:any) {
  const result:Record<string,Record<string,number>>={};
  for (const category of Object.keys(COUNTS)) {
    if (category === "word") continue;
    const {data,error}=await admin.from("game_questions")
      .select("id")
      .eq("category",category)
      .eq("active",true)
      .order("created_at",{ascending:true})
      .order("id",{ascending:true});
    if(error) throw error;
    const rows=data??[];
    const base=Math.floor(rows.length/3);
    const rem=rows.length%3;
    const sizes=[base+(rem>0?1:0),base+(rem>1?1:0),base];
    const difficulties=["easy","medium","hard"] as const;
    result[category]={};
    let cursor=0;
    for(let i=0;i<3;i++){
      const ids=rows.slice(cursor,cursor+sizes[i]).map((r:any)=>r.id).filter(Boolean);
      cursor+=sizes[i];
      if(ids.length){
        const {error:updateError}=await admin.from("game_questions")
          .update({difficulty:difficulties[i],updated_at:new Date().toISOString()})
          .in("id",ids);
        if(updateError) throw updateError;
      }
      result[category][difficulties[i]]=ids.length;
    }
  }
  return result;
}

Deno.serve(async(req:Request)=>{ if(req.method==='OPTIONS')return new Response('ok',{headers:cors}); try{const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);const weekStart=mondayUtc();const {data:existing}=await admin.from('weekly_challenges').select('id').eq('week_start',weekStart).limit(1);if(existing&&existing.length)return new Response(JSON.stringify({ok:true,message:'already generated',weekStart}),{headers:{...cors,'Content-Type':'application/json'}});

const bankBefore = await topUpGameBankIfNeeded(admin);

// Rebalance BEFORE this week's selection, not just after. Previously this
// only ran at the very end of the run, which meant any category that had
// just been topped up (audio, most often, since it was chronically short)
// was drawn from using whatever raw/arbitrary difficulty the generator
// originally assigned — a full week out of date. Rebalancing here first
// means this week's own picks come from freshly-fair thirds.
const difficultyBalanceBefore = await rebalanceActiveDifficulties(admin);

const selected: any[] = [];
const selectedRows: Record<string, any> = {};
const usageCutoff = new Date(Date.now() - 21 * 24 * 60 * 60 * 1000).toISOString();

for (const category of CATEGORIES) {
  const need = COUNTS[category];

  const { data, error } = await admin
    .from("game_questions")
    .select("id,category,species,bengali,question,options,answer,hints,syllables,image_url,audio_url,image_source,audio_source,attribution,last_used_at,times_used,difficulty")
    .eq("category", category)
    .eq("active", true)
    .order("last_used_at", { ascending: true, nullsFirst: true })
    .order("times_used", { ascending: true })
    .order("created_at", { ascending: true })
    .limit(MAX_ACTIVE_BANK);

  if (error) throw error;

  const eligible = (data ?? []).filter((row: any) => !row.last_used_at || String(row.last_used_at) < usageCutoff);
  const pool = eligible.length >= need ? eligible : (data ?? []);

  if (category === "word") {
    let got = 0;
    for (const row of pool) {
      if (got >= need) break;
      if (await ensureMedia(admin, row)) { selected.push({ category, id: row.id }); selectedRows[row.id] = row; got++; }
    }
    if (got < need) throw new Error(`Not enough playable ${category} questions. Need ${need}, found ${got}.`);
    continue;
  }

  // Weekly play should itself expose an approximately even difficulty mix:
  // 8 questions => 3/3/2; 4 questions => 2/1/1. (Not a strict requirement —
  // if one bucket runs short, the fill-in pass below just pulls from
  // whatever's left, so it degrades to "close enough" rather than failing.)
  const base = Math.floor(need / 3);
  const rem = need % 3;
  const targets = { easy: base + (rem > 0 ? 1 : 0), medium: base + (rem > 1 ? 1 : 0), hard: base };
  const chosenIds = new Set<string>();
  let got = 0;

  for (const difficulty of ["easy", "medium", "hard"] as const) {
    let taken = 0;
    for (const row of pool) {
      if (taken >= targets[difficulty]) break;
      if (chosenIds.has(row.id) || row.difficulty !== difficulty) continue;
      if (await ensureMedia(admin, row)) {
        selected.push({ category, id: row.id });
        selectedRows[row.id] = row;
        chosenIds.add(row.id);
        taken++;
        got++;
      }
    }
  }

  // If a particular difficulty bucket is temporarily short, fill the remaining
  // slots from the best unused playable questions rather than failing the week.
  if (got < need) {
    for (const row of pool) {
      if (got >= need) break;
      if (chosenIds.has(row.id)) continue;
      if (await ensureMedia(admin, row)) {
        selected.push({ category, id: row.id });
        selectedRows[row.id] = row;
        chosenIds.add(row.id);
        got++;
      }
    }
  }

  if (got < need) throw new Error(`Not enough playable ${category} questions. Need ${need}, found ${got}.`);
}

for(const s of selected){await admin.from('game_questions').update({times_used:((await admin.from('game_questions').select('times_used').eq('id',s.id).single()).data?.times_used??0)+1,last_used_at:new Date().toISOString()}).eq('id',s.id);}

const grouped:Record<string,string[]>={};
const groupedQuestions:Record<string,any[]>={};
for(const s of selected){
  (grouped[s.category]??=[]).push(s.id);
  const row = selectedRows[s.id];
  // Shuffle options HERE, once, at publish time — this is what fixes the
  // "correct answer is almost always first" bug, regardless of what order
  // whatever generated the row originally wrote them in. The correct
  // answer is tracked by its actual text value, not by array position, so
  // shuffling never breaks correctness-checking on the client.
  const shuffledOptions = Array.isArray(row?.options) ? shuffle(row.options) : row?.options;
  const snapshot = {
    id: row.id,
    category: row.category,
    species: row.species,
    bengali: row.bengali,
    question: row.question,
    options: shuffledOptions,
    answer: row.answer,
    hints: row.hints,
    syllables: row.syllables,
    image_url: row.image_url,
    audio_url: row.audio_url,
    image_source: row.image_source,
    audio_source: row.audio_source,
    attribution: row.attribution,
    difficulty: row.difficulty,
  };
  (groupedQuestions[s.category]??=[]).push(snapshot);
}

// payload now carries the fully-shuffled, frozen question content for the
// week (not just IDs) — this also makes an in-progress week immune to any
// later rebalance/trim touching the same rows mid-week.
const rows=CATEGORIES.map(category=>({week_start:weekStart,category,payload:{version:3,question_ids:grouped[category]||[],questions:groupedQuestions[category]||[]},question_ids:grouped[category]||[],generated_at:new Date().toISOString(),selection_version:3}));
const {error:upsertError}=await admin.from('weekly_challenges').upsert(rows,{onConflict:'week_start,category'});if(upsertError)throw upsertError;
await admin.from('weekly_challenges').delete().neq('week_start',weekStart);
const retired = await trimActiveBank(admin);
const difficultyBalanceAfter = await rebalanceActiveDifficulties(admin);
let notified=0;const sa=loadServiceAccount();if(sa){const {data:tokens}=await admin.from('device_tokens').select('token');for(const row of tokens||[]){try{const res=await sendFcm(sa,row.token,'নতুন সাপ্তাহিক চ্যালেঞ্জ! (New Weekly Challenges)','এই সপ্তাহের প্রকৃতি-খেলা এসেছে — খেলতে ট্যাপ করুন।',{type:'game'});if(res.ok)notified++;}catch(_){}}}
return new Response(JSON.stringify({ok:true,weekStart,selected:grouped,bankBefore,retired,difficultyBalanceBefore,difficultyBalanceAfter,notified}),{headers:{...cors,'Content-Type':'application/json'}});
}catch(e){return new Response(JSON.stringify({ok:false,error:e instanceof Error?e.message:String(e)}),{status:500,headers:{...cors,'Content-Type':'application/json'}});}});
