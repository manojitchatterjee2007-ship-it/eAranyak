<#
    trigger_codemagic.ps1 - Trigger a Codemagic build from the command line.

    PURPOSE:
      This machine is Windows and CANNOT compile iOS/iPadOS (needs macOS/Xcode).
      Instead we ask Cobey/CodeMagic-cloud to build for us. This script talks to
      the Codemagic REST API and starts one of the workflows defined in
      codemagic.yaml (e.g. ios-workflow) on the current git branch.

    PREREQUISITES:
      1) Install the Codemagic CLI tools (optional, not required for this script):
             pip3 install codemagic-cli-tools
         OR just authenticate with an API token as described below.

      2) Provide your API token securely via ONE of these (in order of precedence):
             - environment variable  CODEMAGIC_API_TOKEN
             - a local file `.codemagic_token` in the repo root (gitignored)

      3) The repo must be committed & pushed; Codemagic builds from your repo,
         not these local working files. Workflows run on your latest pushed commit.

    USAGE:
        powershell -ExecutionPolicy Bypass -File .\scripts\trigger_codemagic.ps1 -Workflow ios-workflow
        powershell -ExecutionPolicy Bypass -File .\scripts\trigger_codemagic.ps1 -Workflow android-workflow -Branch main

    SECURITY NOTE:
      NEVER paste your token into a chat window or commit it. Only set it as an
      env var or drop it into the gitignored `.codemagic_token` file (touch it,
      then write only your token to it, e.g. `Set-Content .codemagic_token <token>`).
#>
param(
    [string]$Workflow = "ios-workflow",
    [string]$Branch = ""
)

$ErrorActionPreference = "Stop"

function Get-EnvOrFile([string]$Name, [string]$Path) {
    $v = [System.Environment]::GetEnvironmentVariable($Name)
    if ($v) { return $v }
    $full = Join-Path (Get-Location) $Path
    if (Test-Path $full) {
        $line = (Get-Content $full -Raw).Trim()
        if ($line) { return $line }
    }
    return $null
}

$token = Get-EnvOrFile "CODEMAGIC_API_TOKEN" ".codemagic_token"
if ([string]::IsNullOrEmpty($token)) {
    Write-Error "No API token found. Set CODEMAGIC_API_TOKEN env var OR create a .codemagic_token file (gitignored) containing only your token."
    exit 1
}

# Resolve branch if not given (current branch via git)
if ([string]::IsNullOrEmpty($Branch)) {
    $Branch = git rev-parse --abbrev-ref HEAD
    if (-not $Branch) { $Branch = "main" }
}

$headers = @{ "x-auth-token" = $token; "Content-Type" = "application/json" }
$base = "https://api.codemagic.io"

Write-Host "Fetching Codemagic apps..." -ForegroundColor Cyan
$appsResp = Invoke-RestMethod -Method Get -Uri "$base/apps" -Headers $headers
$appId = $null
if ($appsResp.applications) {
    foreach ($app in $appsResp.applications) {
        # Match by the repo unique id or fall back to first app
        if (-not $appId) { $appId = $app.id }
        Write-Host ("  appId=" + $app.id + "  " + $app.repository.url) -ForegroundColor Gray
    }
}
if (-not $appId) {
    Write-Error "Could not find any applications on this Codemagic account. Are you authenticated?"
    exit 1
}

Write-Host "Triggering workflow '$Workflow' on branch '$Branch' (appId=$appId)..." -ForegroundColor Cyan
$body = @{
    appId      = $appId
    workflowId = $Workflow
    branch     = $Branch
} | ConvertTo-Json

$buildResp = Invoke-RestMethod -Method Post -Uri "$base/builds" -Headers $headers -Body $body
$buildId = $buildResp.buildId
if (-not $buildId) {
    Write-Host "Response:"; $buildResp | ConvertTo-Json -Depth 5
    Write-Error "No buildId returned. Check the workflow name matches a workflow in codemagic.yaml."
    exit 1
}

Write-Host "Build triggered! buildId=$buildId" -ForegroundColor Green
Write-Host "Track it at: https://codemagic.io/app/$appId/build/$buildId" -ForegroundColor Green

# Export for scripting use
Set-Content -Path ".last_codemagic_build" -Value $buildId
Write-Host "Saved buildId to .last_codemagic_build"