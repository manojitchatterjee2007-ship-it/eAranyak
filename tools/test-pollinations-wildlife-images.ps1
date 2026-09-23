# =====================================================================
# eAranyak - STAGE 1 Pollinations Image Proof-of-Concept (TEST ONLY)
# =====================================================================
# Purpose : Determine which CURRENT Pollinations image model gives the
#           best REALISTIC NATURAL-HISTORY WATERCOLOUR illustrations
#           for eAranyak wildlife News/Tutorial article imagery when
#           no usable source photo exists.
# Security: Key read EXCLUSIVELY from env POLLINATIONS_API_KEY.
#           The Supabase secret (Pollination_image_API) is NOT touched.
#           The key is never printed, never saved, never committed.
# Cost    : 2 candidate models x 6 subjects = 12 images max.
#           (Third candidate only as full-failure fallback, cap 18.)
#           Fixed seeds, no aggressive retries, no quota exhaustion.
# Delete  : tools\test-pollinations-wildlife-images.ps1,
#           tools\pollinations-test-output\ and the report file are all
#           safe to delete after evaluation.
# =====================================================================

param(
    [int]$TimeoutSec = 180,
    [int]$Seed = 42
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 0. Environment / key verification (never prints the key)
# ---------------------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$baseUri = 'https://gen.pollinations.ai'
$modelsUri = "$baseUri/image/models"
$envVar  = 'POLLINATIONS_API_KEY'
$apiKey  = [Environment]::GetEnvironmentVariable($envVar)

if (-not $apiKey -or -not $apiKey.Trim()) {
    Write-Host '====================================================================='
    Write-Host 'STOPPED: environment variable POLLINATIONS_API_KEY is NOT set.'
    Write-Host '====================================================================='
    Write-Host ''
    Write-Host 'The Supabase Edge Function secret (Pollination_image_API) is'
    Write-Host 'intentionally NOT read by this script. For this LOCAL test, copy'
    Write-Host 'your Pollinations key (https://enter.pollinations.ai/keys) into a'
    Write-Host 'temporary environment variable in your CURRENT PowerShell session:'
    Write-Host ''
    Write-Host '    $env:POLLINATIONS_API_KEY = "<paste your Pollinations API key here>"'
    Write-Host ''
    Write-Host 'Then re-run this script:'
    Write-Host ''
    Write-Host '    powershell -ExecutionPolicy Bypass -File tools\test-pollinations-wildlife-images.ps1'
    Write-Host ''
    exit 2
}
Write-Host ("Key check: POLLINATIONS_API_KEY present (length {0} characters, not displayed)." -f $apiKey.Length)

# ---------------------------------------------------------------------
# 1. Shared style + avoidance blocks (the required visual language)
# ---------------------------------------------------------------------
$styleBlock = 'scientifically accurate natural-history wildlife illustration, realistic hand-painted watercolour, detailed natural anatomy, realistic fur and feathers, authentic habitat, subtle pigment variation, visible cold-press watercolour paper texture, delicate transparent washes, controlled pigment granulation, natural earthy colour palette, realistic atmospheric perspective, restrained editorial composition, high-detail wildlife field illustration, museum-quality natural-history artwork, Indian wildlife conservation editorial illustration'

$avoidBlock = 'strictly avoid: cartoon, anime, comic, children book illustration, fantasy art, surrealism, glossy generic digital painting, 3D render, CGI, game artwork, exaggerated eyes, incorrect anatomy, extra limbs, duplicate animals, malformed paws, malformed wings, distorted faces, plastic-looking animals, oversaturated colours, artificial neon lighting, any text, captions, labels, typography, logos, watermarks, borders, frames'

# ---------------------------------------------------------------------
# 2. Six test subjects - structured article-derived information
#    (mirrors the future pipeline: subject extraction -> facts -> prompt)
# ---------------------------------------------------------------------
$subjects = @(
    @{ File='01_tiger_sundarbans';
       Name='TEST 1 - ROYAL BENGAL TIGER / SUNDARBANS';
       Subject='Royal Bengal Tiger'; SciName='Panthera tigris tigris';
       Location='Sundarbans, West Bengal, India'; Habitat='mangrove forest';
       Elements='tiger, mangrove vegetation, tidal mud, stilt roots, brackish water channel';
       Scene='A Royal Bengal Tiger moving naturally through a Sundarbans mangrove landscape, walking across muddy tidal ground between tangled stilt roots and mangrove trunks, a brackish water channel behind it, dense green mangrove foliage with atmospheric depth, wildlife-documentary composition, side-full-body view' }
    @{ File='02_snow_leopard_ladakh';
       Name='TEST 2 - SNOW LEOPARD / LADAKH';
       Subject='Snow Leopard'; SciName='Panthera uncia';
       Location='high-altitude Ladakh, trans-Himalaya, India'; Habitat='rocky alpine steppe';
       Elements='snow leopard, rocky Himalayan terrain, sparse alpine vegetation, cold clear light';
       Scene='A snow leopard resting on rocky Himalayan terrain in high-altitude Ladakh, thick pale smoky-grey rosetted fur, long balanced tail, sparse alpine cushion plants and scattered boulders, distant barren trans-Himalayan ridges with realistic atmospheric perspective, cold natural morning light, documentary natural-history composition, full-body three-quarter view' }
    @{ File='03_purple_heron_wetland';
       Name='TEST 3 - INDIAN WETLAND BIRD';
       Subject='Purple Heron'; SciName='Ardea purpurea';
       Location='Indian freshwater wetland'; Habitat='reed-bed wetland edge';
       Elements='purple heron, reeds, aquatic plants, still water, reflections';
       Scene='A Purple Heron standing in natural hunting posture at the edge of an Indian freshwater wetland, slender chestnut and slate plumage, snake-like neck in slight S-curve, among dense reeds and aquatic plants, calm still water with subtle reflections, soft overcast daylight, natural-history composition' }
    @{ File='04_camera_trap';
       Name='TEST 4 - CAMERA TRAP / WILDLIFE MONITORING';
       Subject='Wildlife camera trap field setup'; SciName='';
       Location='Indian deciduous forest'; Habitat='forest trail at dusk';
       Elements='camera trap strapped to tree, forest trail, chital deer passing, low light';
       Scene='A realistic camouflaged camera trap strapped to a tree trunk beside a forest trail in an Indian deciduous forest at dusk, a chital deer walking naturally past in the background, subtle low-light evening atmosphere, scientifically plausible field equipment, educational editorial composition' }
    @{ File='05_indian_forest';
       Name='TEST 5 - INDIAN FOREST ECOSYSTEM';
       Subject='Indian forest ecosystem and biodiversity'; SciName='';
       Location='Indian subcontinent'; Habitat='moist deciduous forest';
       Elements='sal trees, bamboo, layered undergrowth, dappled light, distant deer and bird life';
       Scene='A rich but scientifically plausible Indian moist deciduous forest ecosystem, tall sal trees with straight trunks, bamboo clumps and layered green undergrowth, dappled golden forest light, a distant chital deer and small bird life as subtle signs of biodiversity, believable Indian ecology, natural-history illustration composition' }
    @{ File='06_birdwatching_wetland';
       Name='TEST 6 - TUTORIAL IMAGE / BIRDWATCHING';
       Subject='Beginner birdwatching in Indian wetlands'; SciName='';
       Location='Indian wetland'; Habitat='wetland observation point';
       Elements='birder with binoculars at respectful distance, wetland birds, reeds, morning light';
       Scene='An educational natural-history illustration of a beginner birder quietly observing wetland birds through binoculars from a respectful distance at an Indian wetland, herons and waterfowl feeding undisturbed among reeds, soft morning light, calm responsible birdwatching behaviour, natural restrained composition' }
)

# ---------------------------------------------------------------------
# 3. Prompt construction (structured facts -> controlled visual prompt)
#    and request helpers
# ---------------------------------------------------------------------
function Build-Prompt {
    param($Subject)
    $sci = ''
    if ($Subject.SciName) { $sci = " (scientific name {0})" -f $Subject.SciName }
    $p = '{0}{1} in its authentic habitat: {2}. Location context: {3}. Habitat: {4}. Visual elements: {5}. Style: {6}. {7}' -f `
        $Subject.Subject, $sci, $Subject.Scene, $Subject.Location, $Subject.Habitat, $Subject.Elements, $styleBlock, $avoidBlock
    return $p
}

$outDir = Join-Path $PSScriptRoot 'pollinations-test-output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$reportPath = Join-Path $PSScriptRoot 'pollinations-image-test-results.txt'
Set-Content -Path $reportPath -Value 'POLLINATIONS IMAGE TEST' -Encoding UTF8
Add-Content -Path $reportPath -Value '========================' -Encoding UTF8
Add-Content -Path $reportPath -Value ("Date/time    : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
Add-Content -Path $reportPath -Value ("API endpoint : $baseUri/image/{{prompt}} (GET), auth: Authorization Bearer (key NOT stored here)") -Encoding UTF8

function Write-Both {
    param([string]$Text = '')
    Write-Host $Text
    Add-Content -Path $reportPath -Value $Text -Encoding UTF8
}

$script:okCount = 0; $script:failCount = 0
$script:statusCounts = @{}
$script:totalElapsed = 0.0; $script:okElapsed = 0.0
$script:httpErrors = 0

# ---------------------------------------------------------------------
# 4. Model discovery (no auth needed) + candidate selection
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '======================== MODEL DISCOVERY ========================'
$models = $null
try {
    $models = Invoke-RestMethod -Uri $modelsUri -TimeoutSec 60
    Write-Host ("Model discovery: SUCCESS ({0} total models returned)" -f $models.Count)
    Add-Content -Path $reportPath -Value 'Model discovery: SUCCESS' -Encoding UTF8
} catch {
    Write-Host ("Model discovery FAILED: {0}" -f $_.Exception.Message)
    Add-Content -Path $reportPath -Value 'Model discovery: FAILED' -Encoding UTF8
    exit 3
}

$imageModels = @($models | Where-Object { $_.category -eq 'image' -and -not $_.paid_only })
Write-Host ''
Write-Host 'Currently available FREE image models (name | rpm | description):'
foreach ($im in $imageModels) {
    $rpm = if ($im.per_user_rpm) { $im.per_user_rpm } else { 'n/a' }
    Write-Host ("  {0} | rpm={1} | {2}" -f $im.name, $rpm, $im.description)
}

# Preference order for realistic natural-history watercolour work:
# 1) gpt-image-2: premium prompt adherence (crucial for a long style prompt)
# 2) mai-image-2.5-flash: photorealistic quality
# 3) z-image-turbo: fast budget fallback
$candidatePrefs = @('openai/gpt-image-2', 'microsoft/mai-image-2.5-flash', 'tongyi-mai/z-image-turbo')
$availableNames = $imageModels | ForEach-Object { $_.name }
$candidates = @($candidatePrefs | Where-Object { $availableNames -contains $_ } | Select-Object -First 2)
$fallback   = @($candidatePrefs | Where-Object { $availableNames -contains $_ } | Select-Object -First 3) | Select-Object -Last 1

if ($candidates.Count -eq 0) {
    Write-Host 'No preferred candidate models are currently available. Stopping.'
    exit 3
}
Write-Host ''
Write-Host ("Selected candidate models (2): {0}" -f ($candidates -join ', '))
if ($fallback -and ($candidates -notcontains $fallback)) {
    Write-Host ("Fallback (only if one candidate fails completely): {0}" -f $fallback)
}

# ---------------------------------------------------------------------
# 5. Generation function + per-model loop
# ---------------------------------------------------------------------
function Invoke-ImageGeneration {
    param([string]$Model, [string]$Prompt)

    $enc = [System.Uri]::EscapeDataString($Prompt)
    $uri = "{0}/image/{1}?model={2}&width=1280&height=720&seed={3}" -f $baseUri, $enc, [System.Uri]::EscapeDataString($Model), $Seed

    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $uri)
        [void]$req.Headers.TryAddWithoutValidation('Authorization', "Bearer $apiKey")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $sw.Stop()
        $code = [int]$resp.StatusCode
        $ctype = ''
        if ($resp.Content.Headers.ContentType) { $ctype = $resp.Content.Headers.ContentType.MediaType }
        if ($code -ge 200 -and $code -lt 300 -and $ctype -like 'image/*') {
            $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            return @{ Ok = $true; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; Bytes = $bytes; ContentType = $ctype }
        }
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $body = $body -replace [regex]::Escape($apiKey), '***KEY REDACTED***'
        return @{ Ok = $false; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; ErrorMessage = "HTTP $code ($ctype)"; Body = $body }
    } catch {
        $code = $null; $msg = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
        if ($_.Exception -is [System.Threading.Tasks.TaskCanceledException]) { $msg = "TIMEOUT after ${TimeoutSec}s" }
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
        return @{ Ok = $false; Status = $code; Elapsed = 0.0; ErrorMessage = $msg; Body = '' }
    } finally {
        $client.Dispose()
    }
}

function Test-ModelGeneration {
    param([string]$Model)
    # Run all 6 subjects for one model. Returns $true if ALL succeed.
    $allOk = $true
    $rpmForModel = 6
    $mm = $imageModels | Where-Object { $_.name -eq $Model }
    if ($mm -and $mm.per_user_rpm) { $rpmForModel = [int]$mm.per_user_rpm }
    $delaySec = [Math]::Max(2, [Math]::Ceiling(60.0 / $rpmForModel) + 1)

    $modelDir = Join-Path $outDir ($Model -replace '/', '_')
    if (-not (Test-Path $modelDir)) { New-Item -ItemType Directory -Path $modelDir | Out-Null }

    foreach ($s in $subjects) {
        Write-Both ''
        Write-Both ("-------------------------------------------------------------")
        Write-Both ("[POLLINATIONS TEST - {0} | model: {1}]" -f $s.Name, $Model)
        Write-Both '-------------------------------------------------------------'
        Write-Both 'Structured article-derived information:'
        Write-Both ("  Subject        : {0}" -f $s.Subject)
        Write-Both ("  Scientific name: {0}" -f $(if ($s.SciName) { $s.SciName } else { '(not applicable)' }))
        Write-Both ("  Location       : {0}" -f $s.Location)
        Write-Both ("  Habitat        : {0}" -f $s.Habitat)
        Write-Both ("  Visual elements: {0}" -f $s.Elements)
        $prompt = Build-Prompt $s
        Write-Both 'Final image prompt:'
        Write-Both ("  {0}" -f $prompt)
        Write-Both ("Parameters: width=1280 height=720 (16:9 landscape) seed=$Seed")

        $r = Invoke-ImageGeneration -Model $Model -Prompt $prompt
        $script:totalElapsed += $r.Elapsed
        $sc = if ($r.Status) { $r.Status } else { 'network' }
        if ($script:statusCounts.ContainsKey([string]$sc)) { $script:statusCounts[[string]$sc]++ } else { $script:statusCounts[[string]$sc] = 1 }

        if ($r.Ok) {
            $ext = if ($r.ContentType -eq 'image/png') { 'png' } elseif ($r.ContentType -eq 'image/svg+xml') { 'svg' } else { 'jpg' }
            $filePath = Join-Path $modelDir ("{0}.{1}" -f $s.File, $ext)
            [System.IO.File]::WriteAllBytes($filePath, $r.Bytes)
            $script:okCount++; $script:okElapsed += $r.Elapsed
            Write-Both ("HTTP status   : {0}" -f $r.Status)
            Write-Both ("Response time : {0:N2} seconds" -f $r.Elapsed)
            Write-Both ("Output file   : {0} ({1}, {2} bytes)" -f $filePath, $r.ContentType, $r.Bytes.Length)
            Write-Both 'Result        : SUCCESS'
        } else {
            $script:failCount++; $script:httpErrors++
            Write-Both ("HTTP status   : {0}" -f $r.Status)
            Write-Both ("Response time : {0:N2} seconds" -f $r.Elapsed)
            Write-Both ("Result        : FAILED | {0}" -f $r.ErrorMessage)
            if ($r.Body) { Write-Both ("Server message: {0}" -f $r.Body) }
            $allOk = $false
        }
        Start-Sleep -Seconds $delaySec
    }
    return $allOk
}

# ---------------------------------------------------------------------
# 6. Run candidates (fallback third model ONLY if one fails completely)
# ---------------------------------------------------------------------
Write-Both ''
Write-Both '==================== GENERATION RESULTS ===================='
$modelsTested = @()
foreach ($m in $candidates) {
    $modelsTested += $m
    $ok = Test-ModelGeneration -Model $m
    if (-not $ok -and $fallback -and ($modelsTested -notcontains $fallback)) {
        Write-Both ''
        Write-Both ("Model {0} had failures - running fallback model {1} (cost cap respected)." -f $m, $fallback)
        $modelsTested += $fallback
        $null = Test-ModelGeneration -Model $fallback
        break
    }
}

# ---------------------------------------------------------------------
# 7. Technical summary
# ---------------------------------------------------------------------
$avgOk = 0.0
if ($script:okCount -gt 0) { $avgOk = $script:okElapsed / $script:okCount }

Write-Both ''
Write-Both '==================== TECHNICAL METRICS ===================='
Write-Both ("Endpoint               : {0}/image/{{prompt}} (GET, Bearer auth)" -f $baseUri)
Write-Both ("Parameters             : width=1280, height=720 (16:9), fixed seed=$Seed")
Write-Both ("Models tested          : {0}" -f ($modelsTested -join ', '))
Write-Both ''
Write-Both ("Total generations      : {0}" -f ($script:okCount + $script:failCount))
Write-Both ("Successful             : {0}" -f $script:okCount)
Write-Both ("Failed                 : {0}" -f $script:failCount)
Write-Both ("HTTP errors            : {0}" -f $script:httpErrors)
$scLine = ($script:statusCounts.GetEnumerator() | ForEach-Object { '{0} x{1}' -f $_.Key, $_.Value }) -join ', '
Write-Both ("HTTP status breakdown  : {0}" -f $scLine)
Write-Both ("Average generation time: {0:N2} seconds" -f $avgOk)
Write-Both ("Total elapsed time     : {0:N2} seconds" -f $script:totalElapsed)
Write-Both ''
Write-Both 'IMPORTANT: HTTP 200 only proves technical success. Visual quality'
Write-Both '(anatomy, habitat accuracy, watercolour character, AI artefacts)'
Write-Both 'requires human inspection of the saved images in:'
Write-Both ("  {0}" -f $outDir)
Write-Both 'Quality scoring table and model recommendation are added after human review.'
Write-Both ''
Write-Both 'These images are AI-GENERATED ILLUSTRATIONS - never documentary photographs.'
Write-Both 'Future production UI must label them as illustration generated from article subject.'

Write-Host ''
Write-Host ("Images saved under: {0}" -f $outDir)
Write-Host ("Report saved to   : {0}" -f $reportPath)
Write-Host 'Delete after review: tools\test-pollinations-wildlife-images.ps1, tools\pollinations-test-output\, tools\pollinations-image-test-results.txt'



