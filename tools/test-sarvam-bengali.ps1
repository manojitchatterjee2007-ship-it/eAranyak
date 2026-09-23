# =====================================================================
# eAranyak - STAGE 1.5 Sarvam Proof-of-Concept (ISOLATED TEST ONLY)
# =====================================================================
# Purpose : Test Sarvam English -> Bengali translation quality with the
#           EXACT SAME four English samples used in the Stage 1 Bhashini
#           test, for a direct apples-to-apples comparison.
# Security: The API key is read EXCLUSIVELY from the environment
#           variable SARVAM_TRANSLATION_API_KEY. It is never printed,
#           never hard-coded, never written to any file. The Supabase
#           secret (Sarvam_Bengali_Translation_Key) is NOT touched.
# Quota   : Exactly 5 requests (1 tiny probe + 4 samples, one request
#           per sample). One retry max for 5xx/timeout. No quota
#           exhaustion testing. No retries on 4xx.
# Delete  : This file and tools\sarvam-bengali-test-results.txt are safe
#           to delete after evaluation.
# =====================================================================

param(
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 0. Environment / key verification (never prints the key)
# ---------------------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$endpoint = 'https://api.sarvam.ai/translate'
$envVar   = 'SARVAM_TRANSLATION_API_KEY'
$apiKey   = [Environment]::GetEnvironmentVariable($envVar)

if (-not $apiKey -or -not $apiKey.Trim()) {
    Write-Host '====================================================================='
    Write-Host 'STOPPED: environment variable SARVAM_TRANSLATION_API_KEY is NOT set.'
    Write-Host '====================================================================='
    Write-Host ''
    Write-Host 'The Supabase Edge Function secret (Sarvam_Bengali_Translation_Key)'
    Write-Host 'is intentionally NOT read by this script. For this LOCAL test, set'
    Write-Host 'a temporary environment variable from your Sarvam dashboard key'
    Write-Host '(https://dashboard.sarvam.ai) in your CURRENT PowerShell session:'
    Write-Host ''
    Write-Host '    $env:SARVAM_TRANSLATION_API_KEY = "<paste your Sarvam API key here>"'
    Write-Host ''
    Write-Host 'Then re-run this script:'
    Write-Host ''
    Write-Host '    powershell -ExecutionPolicy Bypass -File tools\test-sarvam-bengali.ps1'
    Write-Host ''
    exit 2
}
Write-Host ("Key check: SARVAM_TRANSLATION_API_KEY present (length {0} characters, not displayed)." -f $apiKey.Length)

# ---------------------------------------------------------------------
# 1. Test data - EXACT SAME samples as tools\test-bhashini-bengali.ps1
#    (clearly labelled fixtures, NOT real published news)
# ---------------------------------------------------------------------
$probeText = 'Wild tigers need large forest areas to survive.'

# NEWS 1: Sundarbans tiger monitoring
$news1Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (NOT REAL PUBLISHED NEWS).',
    'Forest officials in the Sundarbans have recorded a significant increase in Royal Bengal Tiger (Panthera tigris tigris) movement along the forest fringe villages of Gosaba block during the past three months, according to camera-trap data reviewed this week.',
    'The monitoring exercise, carried out by the state forest department with support from a national conservation trust, deployed 240 camera traps across the mangrove landscape and generated more than 11,000 photographs. Researchers identified at least 38 individual tigers, including 12 cubs, a figure they describe as encouraging for the delta ecosystem.',
    'Conservationists say the findings underline the importance of protecting mangrove habitat, which shelters species such as the saltwater crocodile, the Gangetic river dolphin and the endangered northern river terrapin. The department has planned additional patrols during the winter tourist season and will expand community awareness programmes in villages adjoining the reserve.',
    'Officials added that the next full population estimate, due in two years, will follow the national protocol of the National Tiger Conservation Authority (NTCA) and the Wildlife Institute of India.'
)

# NEWS 2: Snow leopard survey
$news2Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (NOT REAL PUBLISHED NEWS).',
    'A three-year survey of the snow leopard (Panthera uncia) in the high-altitude landscape of Ladakh has estimated a stable population of about 477 individuals, researchers announced on 20 January this year.',
    'The study, conducted between 2022 and 2025 across an area of nearly 59,000 square kilometres, used occupancy modelling based on camera traps and field signs at 94 sampling units. The average elevation of confirmed detections was 4,180 metres above sea level.',
    'The species remains listed as Vulnerable on the IUCN Red List, with an estimated global population of fewer than 6,000 mature individuals. Scientists noted that climate change, expansion of pastoral settlements and free-ranging dogs are among the emerging threats to the cat and to its principal wild prey, the blue sheep (Pseudois nayaur) and the Himalayan ibex (Capra sibirica).',
    'The research team recommended that future conservation planning should prioritise village-level insurance schemes for livestock losses and a landscape-level corridor network connecting protected areas of the trans-Himalayan region.'
)

# TUTORIAL 1: Camera trap setup guide
$tut1Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (TUTORIAL SAMPLE).',
    'How to Set Up a Camera Trap for Wildlife Monitoring',
    'Camera traps are motion-activated cameras that let researchers and citizen scientists observe animals without disturbing them. This tutorial explains the basic steps for deploying a camera trap safely and collecting reliable data.',
    'What You Will Need:',
    '- A weatherproof camera trap (IP66 rating or better)',
    '- 8 AA lithium batteries and a 32 GB memory card',
    '- A mounting strap and a small level',
    '- A field notebook or a data-collection app',
    'Step 1: Choose the Right Location. Place the camera on an animal trail, near a water source, or at a scent-marking site. Avoid south-facing slopes at midday, because direct sunlight can trigger false photographs.',
    'Step 2: Set the Height. Mount the camera about 45 to 60 centimetres above the ground, angled slightly downward. For large mammals such as gaur or elephants, raise it to roughly 1 metre.',
    'Step 3: Configure the Settings. Use three photographs per trigger, a 5-second delay, and medium sensitivity. Record the date, GPS coordinates, habitat type and camera ID in your notebook.',
    'Step 4: Check and Retrieve. Visit the camera every 3 to 4 weeks. Later, identify each species, note the timestamp, and upload the records to a recognised biodiversity platform for analysis.',
    'With patience and consistent method, camera traps can reveal a hidden world of nocturnal and shy species.'
)

# TUTORIAL 2: Beginner birdwatching guide
$tut2Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (TUTORIAL SAMPLE).',
    'Beginner Guide to Birdwatching in Indian Wetlands',
    'Wetlands are among the richest bird habitats in India, hosting resident species as well as thousands of migratory waterbirds that arrive from Central Asia every winter. This guide helps beginners start birdwatching responsibly.',
    'Step 1: Get Basic Equipment. A pair of 8x42 binoculars and a regional field guide are enough to begin. A notebook with a pencil works better than a phone on humid mornings.',
    'Step 2: Learn to Observe Slowly. Stand still near the water edge and watch for at least ten minutes. Note the size, bill shape, leg colour and flight pattern. Beginners often identify only herons and cormorants at first; with practice, you will separate the Purple Heron (Ardea purpurea) from the Grey Heron (Ardea cinerea) by its posture and neck shape.',
    'Step 3: Record What You See. Prepare a simple checklist: species name, number of individuals, time and habitat. Submit complete lists to a citizen-science database such as eBird so that your data supports real conservation research.',
    'Step 4: Follow Ethical Rules. Keep a minimum distance of 20 metres from nesting sites, never use recorded calls to attract rare birds, and avoid trampling aquatic vegetation that serves as nursery habitat for fish and amphibians.',
    'Recommended Reading: wetland ecology handbooks published by the Bombay Natural History Society (BNHS) offer excellent regional checklists for Indian wetlands.'
)

$tests = @(
    @{ Name = 'NEWS 1';     Blocks = $news1Blocks },
    @{ Name = 'NEWS 2';     Blocks = $news2Blocks },
    @{ Name = 'TUTORIAL 1'; Blocks = $tut1Blocks },
    @{ Name = 'TUTORIAL 2'; Blocks = $tut2Blocks }
)

# ---------------------------------------------------------------------
# 2. Sarvam helpers
#    Model: sarvam-translate:v1 (current formal-style translation model;
#    the colloquial alternative is the separate mayura model - noted in
#    the report, NOT tested here per single-model test policy).
# ---------------------------------------------------------------------
$script:model   = 'sarvam-translate:v1'
$script:srcLang = 'en-IN'
$script:tgtLang = 'bn-IN'

function Split-IntoChunks {
    param([string[]]$Blocks, [int]$MaxChars = 1900)
    $chunks = @()
    $current = ''
    foreach ($b in $Blocks) {
        if ($current -eq '') {
            $current = $b
        } elseif (($current.Length + 1 + $b.Length) -le $MaxChars) {
            $current = $current + "`n" + $b
        } else {
            $chunks += $current
            $current = $b
        }
    }
    if ($current -ne '') { $chunks += $current }
    return $chunks
}

function Invoke-SarvamTranslation {
    param([string]$Text, [int]$Timeout = 60)

    $payload = @{
        input                = $Text
        source_language_code = $script:srcLang
        target_language_code = $script:tgtLang
        model                = $script:model
    }
    $json  = $payload | ConvertTo-Json -Depth 4
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds($Timeout)
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $endpoint)
        [void]$req.Headers.TryAddWithoutValidation('api-subscription-key', $apiKey)
        $req.Content = New-Object System.Net.Http.ByteArrayContent(,$bytes)
        $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/json')

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $sw.Stop()
        $code    = [int]$resp.StatusCode
        $bodyStr = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $redacted = $bodyStr -replace [regex]::Escape($apiKey), '***KEY REDACTED***'
        return @{ Ok = ($code -ge 200 -and $code -lt 300); Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; Body = $redacted; TimedOut = $false }
    } catch {
        $code = $null
        $msg  = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
        $timedOut = ($_.Exception -is [System.Threading.Tasks.TaskCanceledException])
        if ($timedOut) { $msg = "TIMEOUT after ${Timeout}s" }
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
        return @{ Ok = $false; Status = $code; Elapsed = 0.0; Body = ''; ErrorMessage = $msg; TimedOut = $timedOut }
    } finally {
        $client.Dispose()
    }
}

function Invoke-SarvamWithPolicy {
    # Max ONE retry, only for transient failures (5xx / timeout / network).
    # Never retries 400/401/403. On 429: record, do NOT retry.
    param([string]$Text, [int]$Timeout = 60)

    $r = Invoke-SarvamTranslation -Text $Text -Timeout $Timeout
    if (-not $r.Ok) {
        $transient = $false
        if ($r.TimedOut) { $transient = $true }
        elseif ($r.Status -and $r.Status -ge 500) { $transient = $true }
        elseif (-not $r.Status) { $transient = $true }   # network failure

        if ($transient) {
            $script:retryCount++
            Start-Sleep -Seconds 5
            $r = Invoke-SarvamTranslation -Text $Text -Timeout $Timeout
        }
    }
    return $r
}

function Get-TranslatedText {
    param([string]$JsonBody)
    # Handles both snake_case (REST) and camelCase (SDK-style) fields.
    $obj = $null
    try { $obj = $JsonBody | ConvertFrom-Json } catch { return $null }
    if ($obj -and $obj.PSObject.Properties['translated_text']) { return [string]$obj.translated_text }
    if ($obj -and $obj.PSObject.Properties['translatedText'])  { return [string]$obj.translatedText }
    return $null
}

# ---------------------------------------------------------------------
# 3. Report file setup (never contains the API key)
# ---------------------------------------------------------------------
$reportPath = Join-Path $PSScriptRoot 'sarvam-bengali-test-results.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
Set-Content -Path $reportPath -Value ('SARVAM STAGE 1.5 BENGALI TRANSLATION TEST REPORT') -Encoding UTF8
Add-Content -Path $reportPath -Value ("Test date/time : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
Add-Content -Path $reportPath -Value ("Endpoint       : " + $endpoint) -Encoding UTF8
Add-Content -Path $reportPath -Value ("Model          : " + $script:model + "  (mode: formal - the only mode this model supports)") -Encoding UTF8
Add-Content -Path $reportPath -Value ("Language pair  : " + $script:srcLang + " -> " + $script:tgtLang) -Encoding UTF8
Add-Content -Path $reportPath -Value "(API key is NOT included in this report)" -Encoding UTF8

function Write-Both {
    param([string]$Text = '')
    Write-Host $Text
    Add-Content -Path $reportPath -Value $Text -Encoding UTF8
}

$script:okCount    = 0
$script:failCount  = 0
$script:count200   = 0
$script:count429   = 0
$script:otherErr   = 0
$script:statuses   = @()
$script:totalElapsed = 0.0
$script:okElapsed  = 0.0
$script:retryCount = 0

# ---------------------------------------------------------------------
# 4. Probe (1 tiny request) - confirms endpoint, auth, language config
# ---------------------------------------------------------------------
Write-Both ''
Write-Both '============================== PROBE =============================='
$pr = Invoke-SarvamWithPolicy -Text $probeText -Timeout $TimeoutSec
$script:totalElapsed += $pr.Elapsed
if ($pr.Ok) { $script:okElapsed += $pr.Elapsed }
$probeTextOut = Get-TranslatedText $pr.Body

if ($pr.Ok) {
    $script:okCount++; $script:count200++; $script:statuses += $pr.Status
    Write-Both ("Probe HTTP status : {0}" -f $pr.Status)
    Write-Both ("Response time     : {0:N2} seconds" -f $pr.Elapsed)
    Write-Both ("Expected response field found : {0}" -f $(if ($null -ne $probeTextOut) { 'YES (translated_text)' } else { 'NO - malformed response' }))
    if ($null -ne $probeTextOut) {
        Write-Both ("Raw probe translation : {0}" -f $probeTextOut)
    } else {
        Write-Both ("Raw response body     : {0}" -f $pr.Body)
    }
    Write-Both 'Probe result: SUCCESS'
} else {
    if     ($pr.Status -eq 429) { $script:count429++; $script:failCount++ }
    elseif ($pr.Status)         { $script:otherErr++; $script:failCount++ }
    else                        { $script:otherErr++; $script:failCount++ }
    if ($pr.Status) { $script:statuses += $pr.Status }
    Write-Both ("Probe FAILED | HTTP {0} | {1}" -f $pr.Status, $pr.ErrorMessage)
    if ($pr.Body)     { Write-Both ("Server message : {0}" -f $pr.Body) }
    if ($pr.ErrorMessage -and -not $pr.Status) { Write-Both ("Network error  : {0}" -f $pr.ErrorMessage) }
    Write-Both 'Probe result: FAILED'
    Write-Both '401/403 = bad key; 429 = rate limit/credits; 400 = bad request; timeouts and 5xx were retried once.'
    exit 3
}

# ---------------------------------------------------------------------
# 5. Sample tests - EXACT SAME four English sources as the Bhashini test
#    (each sample = 1 request; blocks joined by newlines into <=1900-char
#    chunks to respect the 2000-char API input limit)
# ---------------------------------------------------------------------
foreach ($t in $tests) {
    Write-Both ''
    Write-Both '------------------------------------------------------------------'
    Write-Both ("[SARVAM TEST - {0}]" -f $t.Name)
    Write-Both '------------------------------------------------------------------'
    Write-Both ''
    Write-Both 'English source:'
    foreach ($b in $t.Blocks) { Write-Both ''; Write-Both $b }
    Write-Both ''

    $chunks  = Split-IntoChunks -Blocks $t.Blocks -MaxChars 1900
    $outputs = @()
    $sampleOk = $true
    $sampleStatus = $null
    $sampleElapsed = 0.0
    $lineMismatch = $false
    $chunkIndex = 0

    foreach ($c in $chunks) {
        $chunkIndex++
        $r = Invoke-SarvamWithPolicy -Text $c -Timeout $TimeoutSec
        $script:totalElapsed += $r.Elapsed
        $sampleElapsed += $r.Elapsed
        if ($r.Ok) { $script:okElapsed += $r.Elapsed }

        if ($r.Ok) {
            $txt = Get-TranslatedText $r.Body
            if ($null -eq $txt) {
                $sampleOk = $false
                Write-Both ("(chunk {0}: HTTP 200 but 'translated_text' field missing - malformed response)" -f $chunkIndex)
                Write-Both ("Raw body: {0}" -f $r.Body)
            } else {
                $inLines  = @($c -split "`n").Count
                $outLines = @($txt -split "`n").Count
                if ($outLines -ne $inLines) {
                    $lineMismatch = $true
                    Write-Both ("(note: chunk {0} line count mismatch - sent {1} lines, received {2}; raw output kept unsplit below)" -f $chunkIndex, $inLines, $outLines)
                }
                $outputs += $txt
            }
            if ($null -eq $sampleStatus) { $sampleStatus = $r.Status }
        } else {
            $sampleOk = $false
            $sampleStatus = $r.Status
            if ($r.Status -eq 429) { $script:count429++ } else { $script:otherErr++ }
            Write-Both ("(chunk {0} FAILED | HTTP {1} | {2})" -f $chunkIndex, $r.Status, $r.ErrorMessage)
            if ($r.Body) { Write-Both ("Server message : {0}" -f $r.Body) }
            Write-Both 'Continuing to next sample (429 recorded, not retried).'
            break
        }
    }

    Write-Both ''
    Write-Both 'Sarvam Bengali (RAW - no polishing, no corrections):'
    foreach ($o in $outputs) { Write-Both ''; Write-Both $o }
    Write-Both ''
    Write-Both ("HTTP status   : {0}" -f $sampleStatus)
    Write-Both ("Response time : {0:N2} seconds" -f $sampleElapsed)
    Write-Both ("Result        : {0}" -f $(if ($sampleOk) { 'SUCCESS' } else { 'FAILED' }))
    if ($lineMismatch) { Write-Both 'Structure note: line-count mismatch above - verify heading/step structure manually.' }

    if ($sampleOk) { $script:okCount++; $script:count200++; $script:statuses += $sampleStatus }
    else           { $script:failCount++ }
    Start-Sleep -Seconds 2
}

# ---------------------------------------------------------------------
# 6. Technical summary (also appended to the report)
# ---------------------------------------------------------------------
$avgOk = 0.0
if ($script:okCount -gt 0) { $avgOk = $script:okElapsed / $script:okCount }

Write-Both ''
Write-Both '==================== SARVAM API TEST - TECHNICAL SUMMARY ===================='
Write-Both ("API reachable              : {0}" -f $(if ($script:okCount -gt 0) { 'YES' } else { 'NO' }))
Write-Both ("Authentication             : {0}" -f $(if ($script:okCount -gt 0) { 'SUCCESS' } else { 'FAILED' }))
Write-Both ("Language pair              : {0} -> {1}" -f $script:srcLang, $script:tgtLang)
Write-Both ("Model                      : {0} (mode: formal)" -f $script:model)
Write-Both ("Successful requests        : {0}/5" -f $script:okCount)
Write-Both ("Failed requests            : {0}/5" -f $script:failCount)
Write-Both ("HTTP 200 count             : {0}" -f $script:count200)
Write-Both ("HTTP 429 count             : {0}" -f $script:count429)
Write-Both ("Other errors               : {0}" -f $script:otherErr)
Write-Both ("Retries used (5xx/timeout) : {0}" -f $script:retryCount)
Write-Both ("HTTP statuses observed     : {0}" -f ($script:statuses -join ', '))
Write-Both ("Total elapsed time         : {0:N2} seconds" -f $script:totalElapsed)
Write-Both ("Average success resp. time : {0:N2} seconds" -f $avgOk)
Write-Both ''
Write-Both 'NOTE: All Bengali output above is RAW Sarvam API output - no LLM polishing,'
Write-Both 'no manual corrections. Quality assessment and Bhashini comparison are added'
Write-Both 'separately after human review of this raw output.'
Write-Both ''
Write-Host ''
Write-Host ("Report saved to: {0}" -f $reportPath)
Write-Host 'Delete after review: tools\test-sarvam-bengali.ps1 and tools\sarvam-bengali-test-results.txt'





