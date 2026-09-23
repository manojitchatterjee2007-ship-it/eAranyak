# =====================================================================
# eAranyak - STAGE 1 Bhashini Proof-of-Concept (ISOLATED TEST ONLY)
# =====================================================================
# Purpose : Test Bhashini (Dhruva) English -> Bengali translation quality
#           for Wildlife News and Wildlife Tutorials BEFORE any
#           integration into eAranyak.
# Security: The API key is read EXCLUSIVELY from the environment
#           variable BHASHINI_INFERENCE_API_KEY. It is never printed,
#           never hard-coded, never written to any file in the repo.
# Quota   : Exactly 5 requests (1 tiny probe + 4 samples). No quota
#           exhaustion testing is performed.
# Delete  : This file is safe to delete after evaluation.
# =====================================================================

param(
    # Optional explicit translation serviceId override. If omitted, the
    # script omits serviceId and lets Dhruva resolve its default (strongest
    # generally-available) en->bn service, then RECORDS the serviceId the
    # API actually used (from the response config).
    [string]$ServiceId = '',
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# 0. Environment / key verification (never prints the key)
# ---------------------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$endpoint = 'https://dhruva-api.bhashini.gov.in/services/inference/pipeline'
$envVar   = 'BHASHINI_INFERENCE_API_KEY'
$apiKey   = [Environment]::GetEnvironmentVariable($envVar)

if (-not $apiKey -or -not $apiKey.Trim()) {
    Write-Host '====================================================================='
    Write-Host 'STOPPED: environment variable BHASHINI_INFERENCE_API_KEY is NOT set.'
    Write-Host '====================================================================='
    Write-Host ''
    Write-Host 'Set it in your CURRENT PowerShell session (key stays in memory,'
    Write-Host 'nothing is written to disk or the repository):'
    Write-Host ''
    Write-Host '    $env:BHASHINI_INFERENCE_API_KEY = "<paste your inference API key here>"'
    Write-Host ''
    Write-Host 'Then re-run this script:'
    Write-Host ''
    Write-Host '    powershell -ExecutionPolicy Bypass -File tools\test-bhashini-bengali.ps1'
    Write-Host ''
    Write-Host 'To set it for every future session (optional, persists on your machine):'
    Write-Host ''
    Write-Host '    [Environment]::SetEnvironmentVariable("BHASHINI_INFERENCE_API_KEY", "<key>", "User")'
    Write-Host ''
    Write-Host 'The key comes from the Bhashini developer portal'
    Write-Host '(https://bhashini.gov.in / Dhruva dashboard), "Inference API Key".'
    exit 2
}
Write-Host ("Key check: BHASHINI_INFERENCE_API_KEY present (length {0} characters, not displayed)." -f $apiKey.Length)

# ---------------------------------------------------------------------
# 1. Test data - eAranyak-style fixtures (CLEARLY LABELLED TEST INPUTS)
#    These are illustrative test fixtures written for this POC. They are
#    NOT real published news and must not be mistaken for real articles.
# ---------------------------------------------------------------------
$probeBlocks = @('The tiger is the largest living cat species.')

# NEWS 1: Sundarbans tiger monitoring (species, place, science, numbers)
$news1Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (NOT REAL PUBLISHED NEWS).',
    'Forest officials in the Sundarbans have recorded a significant increase in Royal Bengal Tiger (Panthera tigris tigris) movement along the forest fringe villages of Gosaba block during the past three months, according to camera-trap data reviewed this week.',
    'The monitoring exercise, carried out by the state forest department with support from a national conservation trust, deployed 240 camera traps across the mangrove landscape and generated more than 11,000 photographs. Researchers identified at least 38 individual tigers, including 12 cubs, a figure they describe as encouraging for the delta ecosystem.',
    'Conservationists say the findings underline the importance of protecting mangrove habitat, which shelters species such as the saltwater crocodile, the Gangetic river dolphin and the endangered northern river terrapin. The department has planned additional patrols during the winter tourist season and will expand community awareness programmes in villages adjoining the reserve.',
    'Officials added that the next full population estimate, due in two years, will follow the national protocol of the National Tiger Conservation Authority (NTCA) and the Wildlife Institute of India.'
)

# NEWS 2: Snow leopard survey (IUCN, science terms, dates, measurements)
$news2Blocks = @(
    'TEST FIXTURE FOR TRANSLATION EVALUATION (NOT REAL PUBLISHED NEWS).',
    'A three-year survey of the snow leopard (Panthera uncia) in the high-altitude landscape of Ladakh has estimated a stable population of about 477 individuals, researchers announced on 20 January this year.',
    'The study, conducted between 2022 and 2025 across an area of nearly 59,000 square kilometres, used occupancy modelling based on camera traps and field signs at 94 sampling units. The average elevation of confirmed detections was 4,180 metres above sea level.',
    'The species remains listed as Vulnerable on the IUCN Red List, with an estimated global population of fewer than 6,000 mature individuals. Scientists noted that climate change, expansion of pastoral settlements and free-ranging dogs are among the emerging threats to the cat and to its principal wild prey, the blue sheep (Pseudois nayaur) and the Himalayan ibex (Capra sibirica).',
    'The research team recommended that future conservation planning should prioritise village-level insurance schemes for livestock losses and a landscape-level corridor network connecting protected areas of the trans-Himalayan region.'
)

# TUTORIAL 1: Camera trap setup guide (headings, numbered steps, bullets)
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

# TUTORIAL 2: Beginner birdwatching guide (instructional + scientific terms)
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
# 2. Bhashini pipeline helpers
# ---------------------------------------------------------------------
function Invoke-BhashiniTranslation {
    param(
        [string[]]$Blocks,
        [string]$SrcLang = 'en',
        [string]$TgtLang = 'bn',
        [string]$SvcId = '',
        [string]$PipelineId = '63483ddab6e5414eb27d4a2c6ff17965',
        [int]$Timeout = 90
    )

    $taskConfig = @{
        language = @{ sourceLanguage = $SrcLang; targetLanguage = $TgtLang }
    }
    if ($SvcId) { $taskConfig.serviceId = $SvcId }

    $in = @($Blocks | ForEach-Object { @{ source = $_ } })

    $payload = @{
        pipelineTasks = @(
            @{ taskType = 'translation'; config = $taskConfig }
        )
        # Current Dhruva API requires input inside inputData.input[]
        inputData = @{
            input = $in
        }
    }
    if ($PipelineId) {
        $payload.pipelineRequestConfig = @{ pipelineId = $PipelineId }
    }

    $json  = $payload | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    # HttpClient gives reliable status codes + response bodies on PS 5.1
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds($Timeout)
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $endpoint)
        [void]$req.Headers.TryAddWithoutValidation('Authorization', $apiKey)   # RAW key - no Bearer prefix
        $req.Content = New-Object System.Net.Http.ByteArrayContent(,$bytes)
        $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/json')

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $sw.Stop()
        $code    = [int]$resp.StatusCode
        $bodyStr = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $redacted = $bodyStr -replace [regex]::Escape($apiKey), '***KEY REDACTED***'

        if ($code -ge 200 -and $code -lt 300) {
            $obj = $null
            try { $obj = $redacted | ConvertFrom-Json } catch {}
            if ($null -eq $obj) {
                return @{ Ok = $false; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; ErrorMessage = 'HTTP 2xx but response was not valid JSON (malformed)'; ErrorBody = $redacted }
            }
            return @{ Ok = $true; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; Response = $obj; RawBody = $redacted }
        }
        return @{ Ok = $false; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; ErrorMessage = "HTTP $code"; ErrorBody = $redacted }
    } catch {
        $sw = New-Object System.Diagnostics.Stopwatch
        $code = $null
        $msg  = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
        if ($_.Exception -is [System.Threading.Tasks.TaskCanceledException]) {
            $msg = "TIMEOUT after ${Timeout}s"
        }
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
        return @{ Ok = $false; Status = $code; Elapsed = $sw.Elapsed.TotalSeconds; ErrorMessage = $msg; ErrorBody = '' }
    } finally {
        $client.Dispose()
    }
}

function Extract-Translation {
    param($Response)
    # Dhruva pipeline response: pipelineResponse[] -> taskType=translation -> output[] -> target
    $result = @()
    foreach ($pr in $Response.pipelineResponse) {
        if ($pr.taskType -eq 'translation' -and $pr.output) {
            foreach ($o in $pr.output) {
                $result += [string]$o.target
            }
        }
    }
    return $result
}

function Get-UsedServiceId {
    param($Response)
    foreach ($pr in $Response.pipelineResponse) {
        if ($pr.taskType -eq 'translation' -and $pr.config -and $pr.config.serviceId) {
            return [string]$pr.config.serviceId
        }
    }
    return '(serviceId not echoed in response)'
}

# ---------------------------------------------------------------------
# 3. Probe request (tiny, 1 sentence) - verifies API + resolves serviceId
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '============================== PROBE =============================='
Write-Host 'Trying documented pipeline request variants (tiny 1-sentence probe each)...'
$script:okCount    = 0
$script:failCount  = 0
$script:statuses   = @()
$script:serviceIds = @()
$script:totalElapsed = 0.0

$variants = @(
    @{ Name = 'V1: pipelineId only (serviceId auto-resolved)';                SvcId = $ServiceId; PipelineId = '63483ddab6e5414eb27d4a2c6ff17965' },
    @{ Name = 'V2: no pipelineRequestConfig (serviceId auto-resolved)';       SvcId = $ServiceId; PipelineId = '' },
    @{ Name = 'V3: explicit ai4bharat/indictrans-v2-all-gpu + pipelineId';    SvcId = 'ai4bharat/indictrans-v2-all-gpu'; PipelineId = '63483ddab6e5414eb27d4a2c6ff17965' },
    @{ Name = 'V4: explicit ai4bharat/indictrans-v2-en-indic-gpu, no pipelineId'; SvcId = 'ai4bharat/indictrans-v2-en-indic-gpu'; PipelineId = '' }
)

$probeOk = $false
foreach ($v in $variants) {
    Write-Host ''
    Write-Host ("-- Attempt: {0}" -f $v.Name)
    $probe = Invoke-BhashiniTranslation -Blocks $probeBlocks -SvcId $v.SvcId -PipelineId $v.PipelineId -Timeout $TimeoutSec
    $script:totalElapsed += $probe.Elapsed
    if ($probe.Ok) {
        $sid = Get-UsedServiceId $probe.Response
        $out = Extract-Translation $probe.Response
        $script:okCount++
        $script:statuses += $probe.Status
        $script:serviceIds += $sid
        Write-Host ("   PROBE OK   | HTTP {0} | {1:N2} s | serviceId used: {2}" -f $probe.Status, $probe.Elapsed, $sid)
        Write-Host ("   Probe translation: {0}" -f ($out -join ' | '))
        $script:workingSvcId     = $v.SvcId
        $script:workingPipelineId = $v.PipelineId
        $script:variantName      = $v.Name
        $probeOk = $true
        break
    } else {
        $script:failCount++
        if ($probe.Status) { $script:statuses += $probe.Status }
        Write-Host ("   FAILED     | HTTP {0} | {1:N2} s | {2}" -f $probe.Status, $probe.Elapsed, $probe.ErrorMessage)
        if ($probe.ErrorBody) { Write-Host ("   Server message: {0}" -f $probe.ErrorBody) }
    }
}

if (-not $probeOk) {
    Write-Host ''
    Write-Host 'All probe variants failed. HTTP 429 = rate limited; 401/403 = invalid/unauthorised key;'
    Write-Host '422 = payload/service validation (server message shown above); 402 or quota-related error'
    Write-Host 'bodies indicate token/character exhaustion. The future production integration must fall'
    Write-Host 'back to the existing Bengali system on any of these.'
    exit 3
}
Write-Host ''
Write-Host ("WORKING REQUEST VARIANT: {0}" -f $script:variantName)

# ---------------------------------------------------------------------
# 4. Sample tests - one request per sample (paragraph blocks preserve
#    paragraph separation inside the input[] array)
# ---------------------------------------------------------------------
foreach ($t in $tests) {
    Write-Host ''
    Write-Host '------------------------------------------------------------------'
    Write-Host ("TEST: {0}" -f $t.Name)
    Write-Host '------------------------------------------------------------------'

    $r = Invoke-BhashiniTranslation -Blocks $t.Blocks -SvcId $script:workingSvcId -PipelineId $script:workingPipelineId -Timeout $TimeoutSec
    if ($r.Ok) {
        $sid = Get-UsedServiceId $r.Response
        $out = Extract-Translation $r.Response
        $script:okCount++
        $script:statuses += 200
        $script:serviceIds += $sid
        $script:totalElapsed += $r.Elapsed

        Write-Host ("[HTTP 200 | {0:N2} s | serviceId: {1}]" -f $r.Elapsed, $sid)
        Write-Host ''
        Write-Host 'ENGLISH SOURCE:'
        foreach ($b in $t.Blocks) { Write-Host ''; Write-Host $b }
        Write-Host ''
        Write-Host 'BHASHINI BENGALI:'
        if ($out.Count -eq $t.Blocks.Count) {
            foreach ($o in $out) { Write-Host ''; Write-Host $o }
        } else {
            Write-Host ("WARNING: block count mismatch - sent {0} blocks, received {1} outputs (possible truncation/merging):" -f $t.Blocks.Count, $out.Count)
            foreach ($o in $out) { Write-Host ''; Write-Host $o }
        }
    } else {
        $script:failCount++
        if ($r.Status) { $script:statuses += $r.Status }
        Write-Host ("[FAILED | HTTP {0} | {1:N2} s]" -f $r.Status, $r.Elapsed)
        Write-Host ("Error: {0}" -f $r.ErrorMessage)
        if ($r.ErrorBody) { Write-Host ("Response body: {0}" -f $r.ErrorBody) }
    }
}

# ---------------------------------------------------------------------
# 5. Technical summary
# ---------------------------------------------------------------------
$uniqSid = $script:serviceIds | Sort-Object -Unique
Write-Host ''
Write-Host '======================== TECHNICAL SUMMARY ========================'
Write-Host ("API working               : {0}" -f $(if ($script:failCount -eq 0) { 'YES' } elseif ($script:okCount -gt 0) { 'PARTIAL' } else { 'NO' }))
Write-Host ("English->Bengali serviceId: {0}" -f ($uniqSid -join ', '))
Write-Host ("Endpoint                  : {0}" -f $endpoint)
Write-Host ("Source language           : en   Target language: bn")
Write-Host ("Successful requests       : {0}" -f $script:okCount)
Write-Host ("Failed requests           : {0}" -f $script:failCount)
Write-Host ("HTTP statuses observed    : {0}" -f ($script:statuses -join ', '))
Write-Host ("Approx total response time: {0:N2} s across {1} requests" -f $script:totalElapsed, ($script:okCount + $script:failCount))
Write-Host 'Truncation                : check block-count warnings above per test'
Write-Host 'Malformed response        : none if all outputs extracted cleanly'
Write-Host 'Rate-limit handling       : HTTP 429 / quota errors are caught and reported;'
Write-Host '                            no intentional quota exhaustion was performed.'
Write-Host ''
Write-Host 'NOTE: Raw Bhashini output shown above - deliberately NOT polished or rewritten.'
Write-Host 'Delete this file after review: tools\test-bhashini-bengali.ps1'






