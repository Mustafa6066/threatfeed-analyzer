<#
.SYNOPSIS
    Copy or rebuild dashboard JSON into dashboard/public/data for the hosted UI.

.DESCRIPTION
    After ThreatFeed-Analyzer.ps1 runs, dashboard.json is written to data\ and
    dashboard\public\data\. This script refreshes the dashboard app folder from
    the latest export (or builds a reduced bundle from articles.json + run-meta.json).

.EXAMPLE
    .\Sync-DashboardData.ps1
#>
[CmdletBinding()]
param(
    [string]$DataDir,
    [string]$DashboardDir
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $DataDir) { $DataDir = Join-Path $ScriptRoot 'data' }
if (-not $DashboardDir) { $DashboardDir = Join-Path $ScriptRoot 'dashboard' }

$publicData = Join-Path $DashboardDir 'public\data'
if (-not (Test-Path $publicData)) { New-Item -ItemType Directory -Path $publicData -Force | Out-Null }

$srcBundle = Join-Path $DataDir 'dashboard.json'
$destBundle = Join-Path $publicData 'dashboard.json'

if (Test-Path $srcBundle) {
    Copy-Item -Path $srcBundle -Destination $destBundle -Force
    foreach ($name in @('run-meta.json', 'shift-brief.json', 'articles.json', 'cves.json')) {
        $src = Join-Path $DataDir $name
        if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $publicData $name) -Force }
    }
    Write-Host "[+] Synced dashboard data from $srcBundle" -ForegroundColor Green
    exit 0
}

Write-Host "[*] No data\dashboard.json - building reduced bundle from articles + run-meta..." -ForegroundColor Cyan
. (Join-Path $ScriptRoot 'lib\ArticleKey.ps1')
. (Join-Path $ScriptRoot 'lib\Scoring.ps1')
. (Join-Path $ScriptRoot 'lib\DashboardExport.ps1')
. (Join-Path $ScriptRoot 'lib\TextEncoding.ps1')

$articlesPath = Join-Path $DataDir 'articles.json'
$runMetaPath = Join-Path $DataDir 'run-meta.json'
if (-not (Test-Path $articlesPath)) {
    Write-Host "[x] Missing data\articles.json - run .\ThreatFeed-Analyzer.ps1 first." -ForegroundColor Red
    exit 1
}

$articlesRaw = (Get-Content -Raw -Path $articlesPath -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
$runMeta = $null
if (Test-Path $runMetaPath) {
    $runMetaRaw = (Get-Content -Raw -Path $runMetaPath -Encoding UTF8).TrimStart([char]0xFEFF)
    if ($runMetaRaw) { $runMeta = $runMetaRaw | ConvertFrom-Json }
}

$display = New-Object System.Collections.Generic.List[object]
foreach ($item in @($articlesRaw)) {
    $pub = $null
    if ($item.published) {
        try { $pub = [datetime]$item.published } catch { }
    }
    $display.Add([pscustomobject]@{
        Title           = Normalize-FeedText ([string]$item.title)
        Link            = [string]$item.link
        Summary         = Normalize-FeedText ([string]$item.summary)
        Source          = [string]$item.source
        Category        = [string]$item.category
        Published       = $pub
        FirstSeen       = [string]$item.firstSeen
        MatchedKeywords = @($item.keywords)
        Mitre           = @($item.mitre)
    })
}

$kwTally = @{}
foreach ($a in $display) {
    foreach ($k in $a.MatchedKeywords) {
        if ($k) {
            if ($kwTally.ContainsKey($k)) { $kwTally[$k]++ } else { $kwTally[$k] = 1 }
        }
    }
}
$kwSorted = $kwTally.GetEnumerator() | Sort-Object Value -Descending
$keywordCounts = [pscustomobject]@{
    labels = @($kwSorted | ForEach-Object { $_.Key })
    values = @($kwSorted | ForEach-Object { $_.Value })
}

$mtTally = @{}
$mtName = @{}
foreach ($a in $display) {
    foreach ($t in $a.Mitre) {
        if (-not $t -or -not $t.id) { continue }
        $lab = [string]$t.id
        if ($mtTally.ContainsKey($lab)) { $mtTally[$lab]++ }
        else { $mtTally[$lab] = 1; $mtName[$lab] = $t.name }
    }
}
$mtSorted = $mtTally.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15
$mitreCounts = [pscustomobject]@{
    labels = @($mtSorted | ForEach-Object { "$($_.Key) $($mtName[$_.Key])" })
    values = @($mtSorted | ForEach-Object { $_.Value })
}

$seenKeys = @{}
$scored = New-Object System.Collections.Generic.List[object]
foreach ($a in $display) {
    $scored.Add((Add-ArticleScoring -Article $a -Tracking @() -SeenKeys $seenKeys -NoDedup))
}
$shiftBrief = @(Sort-ByPriorityScore -Articles ([object[]]$scored.ToArray()) | Select-Object -First 10)

$stats = [pscustomobject]@{
    GeneratedAt  = if ($runMeta -and $runMeta.generatedAt) { [string]$runMeta.generatedAt } else { (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    FeedsTotal   = if ($runMeta) { [int]$runMeta.feedsTotal } else { 0 }
    FeedsOk      = if ($runMeta) { [int]$runMeta.feedsOk } else { 0 }
    Fetched      = if ($runMeta) { [int]$runMeta.fetched } else { 0 }
    Matched      = if ($runMeta) { [int]$runMeta.matched } else { $display.Count }
    New          = if ($runMeta) { [int]$runMeta.newArticles } else { 0 }
    Duplicates   = 0
    CveCount     = if ($runMeta) { [int]$runMeta.cveCount } else { 0 }
    TotalTracked = $display.Count
    TopicCount   = $kwTally.Count
}

$path = Export-DashboardData -DashboardDir $DashboardDir -Stats $stats -ShiftBrief $shiftBrief `
    -DisplayArticles $display.ToArray() -KeywordCounts $keywordCounts -MitreCounts $mitreCounts `
    -Platform $null -Cves @() -RunMeta $runMeta -CveDays 7 -NvdBanner $null

Copy-Item -Path $path -Destination $srcBundle -Force
Write-Host "[+] Wrote reduced bundle: $path" -ForegroundColor Green
