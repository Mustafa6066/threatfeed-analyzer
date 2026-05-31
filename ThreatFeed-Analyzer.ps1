<#
.SYNOPSIS
    ThreatFeed-Analyzer - Aggregate, filter, and analyze cybersecurity news from RSS/Atom feeds.

.DESCRIPTION
    Pulls articles from many security RSS/Atom feeds, keeps only those that match YOUR
    keywords, maps each kept article to MITRE ATT&CK techniques (using your own keyword
    map), pulls the last N days of CVEs from NVD, de-duplicates across runs, and writes
    an interactive HTML dashboard + a CSV file. Each article in the report has one-click
    "Analyze with ChatGPT / Claude / Gemini" buttons that copy a ready-made analyst
    prompt and open the AI site.

    All feeds, keywords, and the MITRE map live in config.json so you edit them without
    touching code.

.PARAMETER OutputDir
    Folder for the HTML + CSV reports. Default: .\reports

.PARAMETER CveDays
    Lookback window (days) for the NVD CVE report. Default 7 (overrides config.json).

.PARAMETER MaxItemsPerFeed
    Cap on items parsed per feed. Default 40 (overrides config.json).

.PARAMETER MaxFeeds
    Process only the first N feeds (0 = all). Handy for a quick test run.

.PARAMETER ConfigPath
    Path to config.json. Default: .\config.json (next to this script).

.PARAMETER NoDedup
    Include matched articles even if they were already seen in a previous run.

.PARAMETER NoOpen
    Do not auto-open the HTML report when finished.

.PARAMETER NvdApiKey
    Optional NVD API key for higher rate limits (https://nvd.nist.gov/developers/request-an-api-key).

.EXAMPLE
    .\ThreatFeed-Analyzer.ps1

.EXAMPLE
    .\ThreatFeed-Analyzer.ps1 -CveDays 3 -OutputDir C:\Reports

.EXAMPLE
    .\ThreatFeed-Analyzer.ps1 -MaxFeeds 4 -CveDays 1   # quick smoke test
#>
[CmdletBinding()]
param(
    [string]$OutputDir,
    [int]$CveDays = 0,
    [int]$MaxItemsPerFeed = 0,
    [int]$MaxFeeds = 0,
    [string]$ConfigPath,
    [switch]$NoDedup,
    [switch]$NoOpen,
    [string]$NvdApiKey
)

# ----------------------------------------------------------------------------
# 0. Environment
# ----------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 } catch {}

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptRoot 'config.json' }
if (-not $OutputDir)  { $OutputDir  = Join-Path $ScriptRoot 'reports' }
$SeenPath = Join-Path $ScriptRoot '.threatfeed-seen.json'
$PromptsDir = Join-Path $ScriptRoot 'prompts'
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ThreatFeed-Analyzer/1.0'
$RunId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$NvdWarning = $null

. (Join-Path $ScriptRoot 'lib\ArticleKey.ps1')
. (Join-Path $ScriptRoot 'lib\Scoring.ps1')
. (Join-Path $ScriptRoot 'lib\PromptLoader.ps1')
. (Join-Path $ScriptRoot 'lib\DashboardExport.ps1')
. (Join-Path $ScriptRoot 'lib\TextEncoding.ps1')
Set-Utf8Environment

function Write-Step($msg)  { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-ErrLine($msg){ Write-Host "[x] $msg" -ForegroundColor Red }

# ----------------------------------------------------------------------------
# 1. Config
# ----------------------------------------------------------------------------
function Get-FallbackConfig {
    [pscustomobject]@{
        CveDays         = 7
        MaxItemsPerFeed = 40
        Keywords        = @('APT','Zero-day','CVE','Exploit','Ransomware','Phishing','Process Injection','Infostealer','Supply Chain','Fileless')
        Feeds           = @(
            [pscustomobject]@{ name='The Hacker News';   url='https://feeds.feedburner.com/TheHackersNews'; category='News' }
            [pscustomobject]@{ name='Bleeping Computer'; url='https://www.bleepingcomputer.com/feed/';      category='News' }
        )
        Mitre           = @(
            [pscustomobject]@{ pattern='ransomware';        id='T1486'; name='Data Encrypted for Impact' }
            [pscustomobject]@{ pattern='phishing';          id='T1566'; name='Phishing' }
            [pscustomobject]@{ pattern='process injection'; id='T1055'; name='Process Injection' }
        )
    }
}

Write-Step "Loading config: $ConfigPath"
if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Raw -Path $ConfigPath -Encoding UTF8 | ConvertFrom-Json
        Write-Ok "Config loaded ($($cfg.Feeds.Count) feeds, $($cfg.Keywords.Count) keywords, $($cfg.Mitre.Count) MITRE patterns)"
    } catch {
        Write-Warn2 "Could not parse config.json ($($_.Exception.Message)) - using built-in fallback."
        $cfg = Get-FallbackConfig
    }
} else {
    Write-Warn2 "config.json not found - using built-in fallback."
    $cfg = Get-FallbackConfig
}

# CLI params override config
if ($CveDays -le 0)         { $CveDays         = if ($cfg.CveDays)         { [int]$cfg.CveDays }         else { 7 } }
if ($MaxItemsPerFeed -le 0) { $MaxItemsPerFeed = if ($cfg.MaxItemsPerFeed) { [int]$cfg.MaxItemsPerFeed } else { 40 } }

$Feeds    = @($cfg.Feeds)
$Keywords = @($cfg.Keywords) | Where-Object { $_ -and $_.Trim() }
$Mitre    = @($cfg.Mitre)
if ($MaxFeeds -gt 0) { $Feeds = $Feeds | Select-Object -First $MaxFeeds }

# Pre-compile keyword regexes (word-boundary, case-insensitive) so "APT" does not
# match "adaptive" and "CVE" does not match arbitrary substrings.
$KeywordRegex = @{}
foreach ($k in $Keywords) {
    $KeywordRegex[$k] = [regex]::new('\b' + [regex]::Escape($k) + '\b', 'IgnoreCase')
}

# ----------------------------------------------------------------------------
# 2. Helpers
# ----------------------------------------------------------------------------
function Convert-HtmlToText {
    param([string]$html)
    if ([string]::IsNullOrWhiteSpace($html)) { return '' }
    $t = $html -replace '(?s)<script.*?</script>', ' '
    $t = $t   -replace '(?s)<style.*?</style>', ' '
    $t = $t   -replace '<[^>]+>', ' '
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-Child {
    param($node, [string]$name)
    if (-not $node) { return $null }
    return $node.SelectSingleNode("*[local-name()='$name']")
}

function ConvertTo-LocalDate {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, [ref]$d)) { return $d }
    return $null
}

# ----------------------------------------------------------------------------
# 3. Fetch + parse feeds
# ----------------------------------------------------------------------------
function Get-FeedRaw {
    param([string]$url)
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            return (Get-HttpText -Url $url -UserAgent $UserAgent)
        } catch {
            if ($attempt -eq 0) {
                Start-Sleep -Seconds 2
                continue
            }
            return $null
        }
    }
    return $null
}

function ConvertFrom-Feed {
    param([string]$raw, $feed, [int]$max)
    $items = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($raw)) { return $items }

    $xml = $null
    try { $xml = [xml]$raw } catch {
        # Strip anything before the first '<' (BOM / stray bytes) and retry once.
        try {
            $idx = $raw.IndexOf('<')
            if ($idx -ge 0) { $xml = [xml]($raw.Substring($idx)) }
        } catch { return $items }
    }
    if (-not $xml) { return $items }

    # local-name() XPath ignores RSS/Atom/RDF namespace differences entirely.
    $nodes = $xml.SelectNodes("//*[local-name()='item' or local-name()='entry']")
    if (-not $nodes) { return $items }

    $count = 0
    foreach ($n in $nodes) {
        if ($count -ge $max) { break }
        $count++

        $titleNode = Get-Child $n 'title'
        $title = if ($titleNode) { Normalize-FeedText $titleNode.InnerText.Trim() } else { '(no title)' }

        # Link: RSS keeps the URL as text; Atom keeps it in href on a <link> element.
        $link = ''
        $linkNodes = $n.SelectNodes("*[local-name()='link']")
        if ($linkNodes -and $linkNodes.Count -gt 0) {
            $alt = $null
            foreach ($ln in $linkNodes) {
                $rel = $ln.GetAttribute('rel')
                if (-not $rel -or $rel -eq 'alternate') { $alt = $ln; break }
            }
            if (-not $alt) { $alt = $linkNodes[0] }
            $href = $alt.GetAttribute('href')
            $link = if ($href) { $href } else { $alt.InnerText.Trim() }
        }

        $sumNode = Get-Child $n 'description'
        if (-not $sumNode) { $sumNode = Get-Child $n 'summary' }
        if (-not $sumNode) { $sumNode = Get-Child $n 'content' }
        $summaryText = if ($sumNode) { Normalize-FeedText (Convert-HtmlToText $sumNode.InnerText) } else { '' }

        $dateStr = $null
        foreach ($dn in @('pubDate','published','updated','date')) {
            $dNode = Get-Child $n $dn
            if ($dNode) { $dateStr = $dNode.InnerText; break }
        }

        $items.Add([pscustomobject]@{
            Title     = $title
            Link      = $link
            Summary   = $summaryText
            Published = ConvertTo-LocalDate $dateStr
            Source    = $feed.name
            Category  = $feed.category
        })
    }
    return $items
}

# ----------------------------------------------------------------------------
# 4. NVD CVE feed
# ----------------------------------------------------------------------------
function Get-NvdCves {
    param([int]$days, [string]$apiKey)
    $end   = (Get-Date).ToUniversalTime()
    $start = $end.AddDays(-$days)
    $fmt   = 'yyyy-MM-ddTHH:mm:ss.000'
    $startStr = $start.ToString($fmt)
    $endStr   = $end.ToString($fmt)
    $headers = @{ 'User-Agent' = $UserAgent }
    if ($apiKey) { $headers['apiKey'] = $apiKey }

    $list = New-Object System.Collections.Generic.List[object]
    $startIndex = 0
    $pageSize = 2000
    $gotAny = $false

    while ($true) {
        $url = "https://services.nvd.nist.gov/rest/json/cves/2.0?pubStartDate=$startStr&pubEndDate=$endStr&resultsPerPage=$pageSize&startIndex=$startIndex"
        $resp = $null
        $success = $false
        for ($retry = 0; $retry -lt 3; $retry++) {
            try {
                $resp = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 60
                $success = $true
                break
            } catch {
                $delaySec = [Math]::Pow(2, $retry)
                if ($retry -lt 2) { Start-Sleep -Seconds $delaySec }
            }
        }
        if (-not $success) {
            Write-Warn2 "NVD request failed after retries (startIndex=$startIndex) - CVE section may be empty or incomplete."
            $script:NvdWarning = 'NVD fetch failed after retries; CVE list may be incomplete.'
            if (-not $gotAny) { return @() }
            break
        }

        if (-not $resp.vulnerabilities -or $resp.vulnerabilities.Count -eq 0) { break }
        $gotAny = $true

        foreach ($v in $resp.vulnerabilities) {
            $cve  = $v.cve
            $desc = ($cve.descriptions | Where-Object { $_.lang -eq 'en' } | Select-Object -First 1).value
            $score = $null; $sev = $null
            if     ($cve.metrics.cvssMetricV31) { $m = $cve.metrics.cvssMetricV31[0].cvssData; $score = $m.baseScore; $sev = $m.baseSeverity }
            elseif ($cve.metrics.cvssMetricV30) { $m = $cve.metrics.cvssMetricV30[0].cvssData; $score = $m.baseScore; $sev = $m.baseSeverity }
            elseif ($cve.metrics.cvssMetricV2)  { $m = $cve.metrics.cvssMetricV2[0];           $score = $m.cvssData.baseScore; $sev = $m.baseSeverity }
            $list.Add([pscustomobject]@{
                Id          = $cve.id
                Published   = (ConvertTo-LocalDate $cve.published)
                Score       = $score
                Severity    = if ($sev) { $sev } else { 'UNKNOWN' }
                Description = if ($desc) { $desc } else { '' }
            })
        }

        $total = if ($null -ne $resp.totalResults) { [int]$resp.totalResults } else { $startIndex + $resp.vulnerabilities.Count }
        $startIndex += $resp.vulnerabilities.Count
        if ($startIndex -ge $total) { break }
    }

    return ($list | Sort-Object -Property @{Expression={ if ($_.Score) { [double]$_.Score } else { -1 } }; Descending=$true})
}

# ----------------------------------------------------------------------------
# 5. HTML report
# ----------------------------------------------------------------------------
function New-HtmlReport {
    param($Articles, $Cves, $KeywordCounts, $MitreCounts, $Stats, $Platform, $ShiftBrief, [string]$Path, [string]$ShiftPrompt, [string]$NvdBanner)

    $css = @'
:root{
 --oxford:#002147;--oxford-2:#0a3a6b;--accent:#1e5fbf;--accent-soft:rgba(30,95,191,.12);
 --bg:#f4f7fb;--bg2:#eaf0f8;
 --surface:rgba(255,255,255,.72);--surface-2:rgba(255,255,255,.55);--surface-solid:#ffffff;
 --text:#0a1a2f;--muted:#5b6b82;--border:rgba(10,33,71,.10);
 --crit:#d12c4e;--high:#c2660a;--med:#9a7d0a;--low:#1f9d6b;
 --shadow:0 12px 34px -14px rgba(10,33,71,.22);--blob:.34;--glass:16px;
}
[data-theme='dark']{
 --oxford:#9ec1ff;--oxford-2:#5b8cff;--accent:#5b8cff;--accent-soft:rgba(91,140,255,.14);
 --bg:#070e1a;--bg2:#0a1424;
 --surface:rgba(18,30,52,.60);--surface-2:rgba(18,30,52,.40);--surface-solid:#10203a;
 --text:#e8eef7;--muted:#8aa0bd;--border:rgba(158,193,255,.13);
 --crit:#ff5c7a;--high:#ff9b4a;--med:#ffd23f;--low:#52d6a0;
 --shadow:0 16px 44px -16px rgba(0,0,0,.62);--blob:.52;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;color:var(--text);font-family:Inter,'Segoe UI',system-ui,Arial,sans-serif;font-size:15px;line-height:1.55;-webkit-font-smoothing:antialiased;transition:color .4s}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
.liquid-bg{position:fixed;inset:0;z-index:-1;overflow:hidden;background:linear-gradient(180deg,var(--bg),var(--bg2));transition:background .5s}
.blob{position:absolute;width:48vmax;height:48vmax;border-radius:50%;filter:blur(64px);opacity:var(--blob);will-change:transform}
.b1{background:radial-gradient(circle at 30% 30%,var(--accent),transparent 60%);top:-14vmax;left:-8vmax;animation:float1 20s ease-in-out infinite}
.b2{background:radial-gradient(circle at 60% 40%,var(--oxford-2),transparent 60%);bottom:-16vmax;right:-10vmax;animation:float2 24s ease-in-out infinite}
.b3{background:radial-gradient(circle at 50% 50%,#6aa6ff,transparent 60%);top:34%;left:42%;opacity:calc(var(--blob) * .6);animation:float3 28s ease-in-out infinite}
@keyframes float1{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(6vmax,5vmax) scale(1.14)}}
@keyframes float2{0%,100%{transform:translate(0,0) scale(1.05)}50%{transform:translate(-5vmax,-4vmax) scale(.92)}}
@keyframes float3{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-4vmax,3vmax) scale(1.1)}}
.progress{position:fixed;top:0;left:0;height:3px;width:0;background:linear-gradient(90deg,var(--accent),var(--oxford-2));z-index:1001;border-radius:0 3px 3px 0;transition:width .08s linear}
.wrap{max-width:1200px;margin:0 auto;padding:22px;animation:fadein .6s ease-out}
@keyframes fadein{from{opacity:0}to{opacity:1}}
header{display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin-bottom:20px}
.brand{display:flex;align-items:center;gap:11px}
.brand svg{width:30px;height:30px;color:var(--accent);flex:none}
header h1{font-size:21px;margin:0;font-weight:650;letter-spacing:-.2px}
header .gen{color:var(--muted);font-size:13px;margin-left:auto}
.theme-toggle{width:42px;height:42px;border-radius:50%;border:1px solid var(--border);background:var(--surface);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));color:var(--text);cursor:pointer;display:grid;place-items:center;transition:transform .25s,box-shadow .25s}
.theme-toggle:hover{transform:rotate(18deg) scale(1.06);box-shadow:var(--shadow)}
.theme-toggle svg{width:19px;height:19px}
.theme-toggle .moon{display:none}
[data-theme='dark'] .theme-toggle .sun{display:none}
[data-theme='dark'] .theme-toggle .moon{display:block}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:13px;margin:16px 0 26px}
.stat{background:var(--surface);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));border:1px solid var(--border);border-radius:16px;padding:15px 17px;box-shadow:var(--shadow);transition:transform .3s cubic-bezier(.2,.8,.2,1),box-shadow .3s}
.stat:hover{transform:translateY(-3px)}
.stat .n{font-size:27px;font-weight:750;letter-spacing:-.5px;background:linear-gradient(135deg,var(--oxford),var(--accent));-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .l{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.6px;margin-top:2px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:26px}
@media(max-width:860px){.grid2{grid-template-columns:1fr}}
.panel{background:var(--surface);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));border:1px solid var(--border);border-radius:18px;padding:18px;box-shadow:var(--shadow)}
.panel h2{font-size:13px;margin:0 0 14px;color:var(--muted);text-transform:uppercase;letter-spacing:.7px;font-weight:650}
.section-title{color:var(--muted);text-transform:uppercase;letter-spacing:.7px;font-size:13px;font-weight:650;margin:8px 0}
.toolbar{display:flex;gap:10px;align-items:center;margin:12px 0 18px;flex-wrap:wrap}
.toolbar input{flex:1;min-width:220px;background:var(--surface-2);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));border:1px solid var(--border);color:var(--text);padding:11px 14px;border-radius:12px;font-size:14px;outline:none;transition:border-color .2s,box-shadow .2s}
.toolbar input:focus{border-color:var(--accent);box-shadow:0 0 0 4px var(--accent-soft)}
.cards{display:grid;gap:14px}
.card{background:var(--surface);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));border:1px solid var(--border);border-radius:18px;padding:17px;box-shadow:var(--shadow);position:relative;overflow:hidden;opacity:0;transform:translateY(14px);transition:transform .35s cubic-bezier(.2,.8,.2,1),box-shadow .35s,opacity .5s}
.card.in{opacity:1;transform:none}
.card:hover{transform:translateY(-4px) scale(1.006);box-shadow:0 20px 46px -18px var(--accent)}
.card::before{content:'';position:absolute;inset:0;border-radius:18px;padding:1px;background:linear-gradient(120deg,transparent,var(--accent-soft),transparent);-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;opacity:0;transition:opacity .35s;pointer-events:none}
.card:hover::before{opacity:1}
.card .meta{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:9px}
.badge{background:var(--accent-soft);color:var(--muted);border-radius:999px;padding:3px 11px;font-size:12px}
.badge.cat-Research{color:var(--accent)}.badge.cat-Official{color:var(--high)}.badge.cat-News{color:var(--low)}
.card h3{margin:2px 0 8px;font-size:17px;line-height:1.35;font-weight:620}
.card h3 a{color:var(--text)}
.card .summary{color:var(--muted);font-size:14px;line-height:1.55;margin-bottom:11px}
.chips{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:11px}
.chip{font-size:12px;border-radius:9px;padding:3px 10px;border:1px solid var(--border)}
.chip.kw{background:var(--accent-soft);color:var(--accent)}
.chip.tt{background:transparent;color:var(--oxford-2)}
.aibtns{display:flex;gap:8px;flex-wrap:wrap}
.aibtn{cursor:pointer;border:1px solid var(--border);border-radius:11px;padding:8px 15px;font-size:13px;font-weight:600;color:var(--text);background:var(--surface-2);transition:transform .18s,box-shadow .25s,border-color .2s}
.aibtn:hover{transform:translateY(-2px);box-shadow:var(--shadow)}
.aibtn:active{transform:scale(.96)}
.aibtn.gpt:hover{border-color:#10a37f}.aibtn.claude:hover{border-color:#d97757}.aibtn.gemini:hover{border-color:#4285f4}
.aibtn .dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:7px;vertical-align:middle}
.aibtn.gpt .dot{background:#10a37f}.aibtn.claude .dot{background:#d97757}.aibtn.gemini .dot{background:#4285f4}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{text-align:left;padding:9px 11px;border-bottom:1px solid var(--border);vertical-align:top}
th{color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:.5px;font-weight:650}
td{font-variant-numeric:tabular-nums}
tbody tr{transition:background .2s}
tbody tr:hover{background:var(--accent-soft)}
.sev{font-weight:700;border-radius:7px;padding:2px 9px;font-size:12px;display:inline-block}
.sev.CRITICAL{background:rgba(209,44,78,.16);color:var(--crit)}
.sev.HIGH{background:rgba(194,102,10,.16);color:var(--high)}
.sev.MEDIUM{background:rgba(154,125,10,.16);color:var(--med)}
.sev.LOW{background:rgba(31,157,107,.16);color:var(--low)}
.sev.UNKNOWN{background:var(--accent-soft);color:var(--muted)}
.empty{color:var(--muted);padding:20px;text-align:center}
canvas{max-height:290px}
footer{color:var(--muted);font-size:12px;text-align:center;margin:34px 0 90px}
#toast{position:fixed;bottom:26px;left:50%;transform:translateX(-50%) translateY(8px);background:var(--surface-solid);border:1px solid var(--accent);color:var(--text);padding:12px 18px;border-radius:13px;box-shadow:var(--shadow);opacity:0;transition:opacity .3s,transform .3s;pointer-events:none;z-index:1100}
#toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
.assistant{position:fixed;right:22px;bottom:22px;z-index:1000;display:flex;flex-direction:column;align-items:flex-end;gap:12px}
.assistant-orb{width:62px;height:62px;border-radius:50%;border:none;cursor:pointer;position:relative;background:radial-gradient(circle at 35% 28%,var(--oxford-2),var(--oxford));display:grid;place-items:center;color:#fff;animation:breathe 4.2s ease-in-out infinite}
.assistant-orb svg{width:30px;height:30px;animation:spin 14s linear infinite}
.assistant-orb:hover{filter:brightness(1.08)}
.assistant-orb:active{transform:scale(.94)}
@keyframes breathe{0%,100%{box-shadow:0 12px 30px -8px var(--accent),0 0 0 0 rgba(30,95,191,.42)}50%{box-shadow:0 16px 38px -8px var(--accent),0 0 0 15px rgba(30,95,191,0)}}
@keyframes spin{to{transform:rotate(360deg)}}
.assistant-panel{width:250px;background:var(--surface);backdrop-filter:blur(var(--glass));-webkit-backdrop-filter:blur(var(--glass));border:1px solid var(--border);border-radius:18px;box-shadow:var(--shadow);padding:14px;transform-origin:bottom right;transform:scale(.9) translateY(8px);opacity:0;pointer-events:none;transition:transform .26s cubic-bezier(.2,.9,.2,1),opacity .26s}
.assistant-panel.open{transform:scale(1) translateY(0);opacity:1;pointer-events:auto}
.assistant-panel .ah{display:flex;align-items:center;gap:9px;margin-bottom:11px}
.assistant-panel .ah .av{width:26px;height:26px;border-radius:50%;background:radial-gradient(circle at 35% 28%,var(--oxford-2),var(--oxford));display:grid;place-items:center;color:#fff;flex:none}
.assistant-panel .ah .av svg{width:15px;height:15px}
.assistant-panel .ah b{font-size:14px}
.assistant-panel .ah span{font-size:11px;color:var(--muted);display:block}
.aopt{display:flex;align-items:center;gap:9px;width:100%;text-align:left;background:transparent;border:1px solid transparent;border-radius:11px;padding:9px 10px;color:var(--text);font-size:13px;cursor:pointer;transition:background .18s,border-color .18s}
.aopt:hover{background:var(--accent-soft);border-color:var(--border)}
.aopt svg{width:16px;height:16px;color:var(--accent);flex:none}
.aopt.primary{background:linear-gradient(135deg,var(--oxford-2),var(--accent));color:#fff;margin-bottom:4px}
.aopt.primary svg{color:#fff}
.aopt.primary:hover{filter:brightness(1.06)}
.tracker{display:grid;grid-template-columns:repeat(auto-fill,minmax(208px,1fr));gap:12px}
.topic{background:var(--surface-2);border:1px solid var(--border);border-radius:14px;padding:12px 13px;position:relative;transition:transform .25s,box-shadow .25s,border-color .2s}
.topic:hover{transform:translateY(-2px);box-shadow:var(--shadow)}
.topic.prio{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent) inset}
.topic .th{display:flex;align-items:center;gap:8px;margin-bottom:6px}
.topic .name{font-weight:620;font-size:14px;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.star{cursor:pointer;border:none;background:transparent;color:var(--muted);padding:0;width:24px;height:24px;flex:none;display:grid;place-items:center;transition:transform .2s,color .2s}
.star:hover{transform:scale(1.18)}
.star svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linejoin:round}
.star.on{color:#f5b301}
.star.on svg{fill:currentColor}
.topic .stat-row{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}
.topic .cnt{font-size:22px;font-weight:730;color:var(--text);font-variant-numeric:tabular-nums}
.topic .trend{font-size:12px;font-weight:650}
.trend.up{color:var(--crit)}.trend.down{color:var(--low)}.trend.flat{color:var(--muted)}
.topic .last{font-size:11px;color:var(--muted);margin-top:4px}
.spark{margin-top:8px;width:100%;height:28px;display:block}
.spark polyline{fill:none;stroke:var(--accent);stroke-width:1.6}
.spark .area{fill:var(--accent-soft);stroke:none}
.filterbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:2px 0 12px}
.chip-btn{cursor:pointer;border:1px solid var(--border);background:var(--surface-2);color:var(--text);border-radius:999px;padding:6px 14px;font-size:13px;font-weight:550;transition:background .2s,border-color .2s,color .2s}
.chip-btn:hover{border-color:var(--accent)}
.chip-btn.active{background:var(--accent);border-color:var(--accent);color:#fff}
.card.prio{border-color:var(--accent)}
.card.prio::after{content:'\2605';position:absolute;top:14px;right:15px;font-size:13px;color:var(--accent)}
.prio-hint{color:var(--muted);font-size:13px;margin:0 0 12px;line-height:1.5}
.shift-brief{margin-bottom:26px}
.shift-row{display:grid;gap:10px}
.shift-item{display:flex;gap:12px;align-items:flex-start;padding:12px 14px;background:var(--surface-2);border:1px solid var(--border);border-radius:14px;transition:transform .25s,box-shadow .25s}
.shift-item:hover{transform:translateY(-2px);box-shadow:var(--shadow)}
.shift-rank{font-size:20px;font-weight:750;color:var(--accent);min-width:28px;line-height:1.2}
.shift-body{flex:1;min-width:0}
.shift-title{font-size:15px;font-weight:620;margin:0 0 6px;line-height:1.35}
.shift-title a{color:var(--text)}
.shift-meta{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-bottom:6px}
.shift-score{font-size:12px;font-weight:650;color:var(--oxford-2);background:var(--accent-soft);border-radius:999px;padding:2px 9px}
.chip.reason{background:rgba(30,95,191,.08);color:var(--accent);font-size:11px}
.shift-key{font-size:10px;color:var(--muted);font-family:Consolas,monospace;margin-top:4px;word-break:break-all}
@media(prefers-reduced-motion:reduce){*{animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important;scroll-behavior:auto!important}.card{opacity:1;transform:none}.blob{animation:none}}
'@

    $js = @'
function $(s){return document.querySelector(s);}
function cssVar(n){return getComputedStyle(document.documentElement).getPropertyValue(n).trim();}
function reduceMotion(){return window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches;}
var charts={};

function showToast(t){var e=$("#toast");e.textContent=t;e.classList.add("show");clearTimeout(window._tt);window._tt=setTimeout(function(){e.classList.remove("show");},2800);}

function aiAnalyze(btn,provider){
  var prompt=btn.getAttribute("data-prompt");
  if(navigator.clipboard){navigator.clipboard.writeText(prompt).then(function(){showToast("Prompt copied - paste it into "+provider);},function(){showToast("Opening "+provider+" (copy manually)");});}
  var urls={ChatGPT:"https://chatgpt.com/?q="+encodeURIComponent(prompt),Claude:"https://claude.ai/new?q="+encodeURIComponent(prompt),Gemini:"https://gemini.google.com/app"};
  window.open(urls[provider],"_blank");
}

var FLT="all";
function filterCards(){
  var q=$("#search").value.toLowerCase();
  var cards=document.querySelectorAll(".card");var shown=0;
  cards.forEach(function(c){
    var txt=c.getAttribute("data-text").indexOf(q)>=0;
    var pOk=(FLT==="all")||c.classList.contains("prio");
    var vis=txt&&pOk;c.style.display=vis?"":"none";if(vis)shown++;
  });
  $("#shownCount").textContent=shown;
}
function setFilter(m){FLT=m;var a=$("#fltAll"),p=$("#fltPrio");if(a)a.classList.toggle("active",m==="all");if(p)p.classList.toggle("active",m==="prio");filterCards();}

// --- Priority topics (saved per browser) ---
function getPriority(){try{return JSON.parse(localStorage.getItem("tfa-priority")||"[]");}catch(e){return [];}}
function setPriorityList(a){try{localStorage.setItem("tfa-priority",JSON.stringify(a));}catch(e){}}
function toggleStar(btn){var t=btn.getAttribute("data-topic");var a=getPriority();var i=a.indexOf(t);if(i>=0)a.splice(i,1);else a.push(t);setPriorityList(a);applyPriority();}
function applyPriority(){
  var prio=getPriority().map(function(s){return s.toLowerCase();});
  document.querySelectorAll(".star").forEach(function(b){
    var on=prio.indexOf((b.getAttribute("data-topic")||"").toLowerCase())>=0;
    b.classList.toggle("on",on);var row=b.closest(".topic");if(row)row.classList.toggle("prio",on);
  });
  var cards=document.querySelectorAll(".card");var pc=0;
  cards.forEach(function(c){
    var tops=(c.getAttribute("data-topics")||"").split(" ");
    var hit=prio.length>0&&tops.some(function(x){return x&&prio.indexOf(x)>=0;});
    c.classList.toggle("prio",hit);if(hit)pc++;
  });
  var wrap=$(".cards");
  if(wrap){var arr=Array.prototype.slice.call(wrap.querySelectorAll(".card"));
    arr.sort(function(a,b){return (b.classList.contains("prio")?1:0)-(a.classList.contains("prio")?1:0);});
    arr.forEach(function(c){wrap.appendChild(c);});}
  var pcnt=$("#prioCount");if(pcnt)pcnt.textContent=getPriority().length;
  var pf=$("#prioFilterCount");if(pf)pf.textContent=pc;
  filterCards();
}

function applyTheme(t){document.documentElement.setAttribute("data-theme",t);try{localStorage.setItem("tfa-theme",t);}catch(e){}renderCharts();}
function toggleTheme(){var cur=document.documentElement.getAttribute("data-theme");applyTheme(cur==="dark"?"light":"dark");}
function initTheme(){var s=null;try{s=localStorage.getItem("tfa-theme");}catch(e){}if(!s){s=(window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)").matches)?"dark":"light";}document.documentElement.setAttribute("data-theme",s);}

function renderCharts(){
  if(typeof Chart==="undefined")return;
  var muted=cssVar("--muted"),grid=cssVar("--border"),accent=cssVar("--accent"),oxford=cssVar("--oxford-2");
  Chart.defaults.color=muted;Chart.defaults.borderColor=grid;Chart.defaults.font.family="Inter, Segoe UI, system-ui, sans-serif";
  var anim=reduceMotion()?false:{duration:700,easing:"easeOutQuart"};
  var kw=window.KEYWORD_DATA,mt=window.MITRE_DATA;
  if(charts.kw){charts.kw.destroy();}if(charts.mt){charts.mt.destroy();}
  if(kw&&kw.labels.length){charts.kw=new Chart($("#kwChart"),{type:"bar",data:{labels:kw.labels,datasets:[{label:"Articles",data:kw.values,backgroundColor:accent,borderRadius:6,maxBarThickness:36}]},options:{animation:anim,plugins:{legend:{display:false}},scales:{x:{grid:{display:false},ticks:{autoSkip:false,maxRotation:60,minRotation:0}},y:{grid:{color:grid},beginAtZero:true,ticks:{precision:0}}}}});}
  if(mt&&mt.labels.length){charts.mt=new Chart($("#mtChart"),{type:"bar",data:{labels:mt.labels,datasets:[{label:"Articles",data:mt.values,backgroundColor:oxford,borderRadius:6}]},options:{animation:anim,indexAxis:"y",plugins:{legend:{display:false}},scales:{x:{grid:{color:grid},beginAtZero:true,ticks:{precision:0}},y:{grid:{display:false}}}}});}
  var tr=window.TREND;
  if(tr&&tr.series&&tr.series.length&&$("#trendChart")){
    var palette=["#1e5fbf","#7b3fe4","#0f9d6b","#c2660a","#d12c4e","#2aa9c0"];
    var ds=tr.series.map(function(s,i){return {label:s.topic,data:s.values,borderColor:palette[i%palette.length],backgroundColor:"transparent",tension:.35,borderWidth:2,pointRadius:0,pointHoverRadius:4};});
    if(charts.trend){charts.trend.destroy();}
    charts.trend=new Chart($("#trendChart"),{type:"line",data:{labels:tr.days.map(function(d){return d.slice(5);}),datasets:ds},options:{animation:anim,interaction:{mode:"index",intersect:false},plugins:{legend:{position:"bottom",labels:{boxWidth:10,boxHeight:10,usePointStyle:true,padding:14}}},scales:{x:{grid:{display:false}},y:{grid:{color:grid},beginAtZero:true,ticks:{precision:0}}}}});
  }
}

function revealCards(){
  var cards=document.querySelectorAll(".card");
  if(reduceMotion()){cards.forEach(function(c){c.classList.add("in");});return;}
  // Staggered on-load reveal so above-the-fold cards animate in immediately and
  // nothing ever stays stuck at opacity:0. Cap the stagger so long lists finish fast.
  cards.forEach(function(c,i){setTimeout(function(){c.classList.add("in");},Math.min(i*45,900));});
  // Hard safety net: guarantee every card is visible shortly after load.
  setTimeout(function(){cards.forEach(function(c){c.classList.add("in");});},1400);
}

function initProgress(){
  var bar=$("#progress");if(!bar)return;var ticking=false;
  function upd(){var h=document.documentElement;var max=h.scrollHeight-h.clientHeight;var p=max>0?(h.scrollTop/max)*100:0;bar.style.width=p+"%";ticking=false;}
  window.addEventListener("scroll",function(){if(!ticking){requestAnimationFrame(upd);ticking=true;}},{passive:true});upd();
}

function toggleAsst(){$("#asstPanel").classList.toggle("open");}
function asstNav(sel){var el=$(sel);if(el){el.scrollIntoView({behavior:reduceMotion()?"auto":"smooth",block:"start"});}$("#asstPanel").classList.remove("open");}
function asstSummary(){
  var p=window.SHIFT_PROMPT||"";
  if(!p){
    var s=window.SUMMARY||{};
    var kw=(s.keywords||[]).slice(0,8).join(", ");
    var mt=(s.mitre||[]).slice(0,6).join(", ");
    p="You are a senior threat intelligence analyst. Give me a concise executive threat briefing for "+(s.date||"today")+" based on this aggregated feed.\n\n"
      +"Articles matched: "+(s.articles||0)+"\nTop keywords: "+(kw||"n/a")+"\nTop MITRE ATT&CK techniques: "+(mt||"n/a")+"\nNew CVEs (last "+(s.cveDays||7)+" days): "+(s.cves||0)+"\n\n"
      +"Provide:\n1. Top 5 things a SOC analyst should prioritise today\n2. Notable threat actors or campaigns if implied\n3. The most relevant MITRE techniques to hunt for\n4. Quick recommended mitigations";
  }
  if(navigator.clipboard){navigator.clipboard.writeText(p).then(function(){showToast("Briefing prompt copied - opening Claude");},function(){});}
  window.open("https://claude.ai/new?q="+encodeURIComponent(p),"_blank");
  $("#asstPanel").classList.remove("open");
}

window.addEventListener("DOMContentLoaded",function(){
  renderCharts();revealCards();initProgress();applyPriority();
  var tt=$("#themeToggle");if(tt)tt.addEventListener("click",toggleTheme);
  var orb=$("#asstOrb");if(orb)orb.addEventListener("click",toggleAsst);
  document.addEventListener("click",function(e){var a=$(".assistant");if(a&&!a.contains(e.target)){$("#asstPanel").classList.remove("open");}});
});
'@

    $kwJson = ($KeywordCounts | ConvertTo-Json -Compress)
    $mtJson = ($MitreCounts   | ConvertTo-Json -Compress)
    if (-not $kwJson) { $kwJson = '{"labels":[],"values":[]}' }
    if (-not $mtJson) { $mtJson = '{"labels":[],"values":[]}' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<!DOCTYPE html><html lang='en' data-theme='light'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>")
    [void]$sb.Append("<title>ThreatFeed Analyzer - $($Stats.GeneratedAt)</title>")
    [void]$sb.Append("<link rel='preconnect' href='https://fonts.googleapis.com'><link rel='preconnect' href='https://fonts.gstatic.com' crossorigin><link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap' rel='stylesheet'>")
    # Set theme before first paint to avoid a flash of the wrong mode.
    [void]$sb.Append("<script>(function(){try{var s=localStorage.getItem('tfa-theme');if(!s){s=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';}document.documentElement.setAttribute('data-theme',s);}catch(e){}})();</script>")
    [void]$sb.Append("<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js'></script>")
    [void]$sb.Append("<style>$css</style></head><body>")
    [void]$sb.Append("<div class='liquid-bg'><span class='blob b1'></span><span class='blob b2'></span><span class='blob b3'></span></div>")
    [void]$sb.Append("<div class='progress' id='progress'></div>")
    [void]$sb.Append("<div class='wrap'>")
    $shieldSvg = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><path d='M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6l7-3z'/><path d='M9 12l2 2 4-4'/></svg>"
    [void]$sb.Append("<header><div class='brand'>$shieldSvg<h1>ThreatFeed Analyzer</h1></div><span class='gen'>Generated $($Stats.GeneratedAt)</span>")
    [void]$sb.Append("<button class='theme-toggle' id='themeToggle' aria-label='Toggle light or dark mode'><svg class='sun' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='4'/><path d='M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4'/></svg><svg class='moon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><path d='M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z'/></svg></button></header>")

    # Stat cards
    [void]$sb.Append("<div class='stats'>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.FeedsOk)/$($Stats.FeedsTotal)</div><div class='l'>Feeds OK</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.Fetched)</div><div class='l'>Articles fetched</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.Matched)</div><div class='l'>Keyword matches</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.New)</div><div class='l'>New today</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.TotalTracked)</div><div class='l'>Tracked (45d)</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.TopicCount)</div><div class='l'>Topics tracked</div></div>")
    [void]$sb.Append("<div class='stat'><div class='n'>$($Stats.CveCount)</div><div class='l'>CVEs (last $CveDays d)</div></div>")
    [void]$sb.Append("</div>")

    # --- Shift Brief Top-10 (today's keyword matches, scored) ---
    [void]$sb.Append("<div class='panel shift-brief' id='shift-brief'>")
    [void]$sb.Append("<h2>Shift Brief &middot; Top 10 priority today</h2>")
    [void]$sb.Append("<p class='prio-hint'>Ranked by local PriorityScore (zero API tokens). Reason chips explain why each item surfaced. Log feedback with <code>Add-TfaFeedback.ps1 -ArticleKey &lt;key&gt; -Action up|down|acted|skip</code>.</p>")
    if ($ShiftBrief -and $ShiftBrief.Count -gt 0) {
        [void]$sb.Append("<div class='shift-row'>")
        $rank = 1
        foreach ($a in $ShiftBrief) {
            $titleEnc = [System.Net.WebUtility]::HtmlEncode($a.Title)
            $linkEnc  = [System.Net.WebUtility]::HtmlEncode($a.Link)
            $pub = if ($a.Published) { $a.Published.ToString('yyyy-MM-dd HH:mm') } else { '' }
            $cat = if ($a.Category) { $a.Category } else { 'News' }
            $reasonHtml = ''
            foreach ($r in @($a.ReasonChips)) {
                if ($r) { $reasonHtml += "<span class='chip reason'>$([System.Net.WebUtility]::HtmlEncode($r))</span>" }
            }
            $keyEnc = [System.Net.WebUtility]::HtmlEncode([string]$a.ArticleKey)
            [void]$sb.Append("<div class='shift-item'>")
            [void]$sb.Append("<div class='shift-rank'>$rank</div>")
            [void]$sb.Append("<div class='shift-body'>")
            [void]$sb.Append("<div class='shift-meta'><span class='shift-score'>$($a.PriorityScore)</span><span class='badge cat-$cat'>$cat</span><span class='badge'>$([System.Net.WebUtility]::HtmlEncode($a.Source))</span>")
            if ($pub) { [void]$sb.Append("<span class='badge'>$pub</span>") }
            [void]$sb.Append("</div>")
            [void]$sb.Append("<div class='shift-title'><a href='$linkEnc' target='_blank'>$titleEnc</a></div>")
            if ($reasonHtml) { [void]$sb.Append("<div class='chips'>$reasonHtml</div>") }
            if ($keyEnc) { [void]$sb.Append("<div class='shift-key' title='Article key for feedback CLI'>key: $keyEnc</div>") }
            [void]$sb.Append("</div></div>")
            $rank++
        }
        [void]$sb.Append("</div>")
    } else {
        [void]$sb.Append('<div class=''empty''>No keyword matches this run - Shift Brief will populate when articles match your config.</div>')
    }
    [void]$sb.Append("</div>")

    # --- Topic trend + tracker (the platform's tracking layer) ---
    if ($Platform) {
        $starSvg = "<svg viewBox='0 0 24 24'><path d='M12 3.2l2.6 5.3 5.8.8-4.2 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L6.4 9.3l5.8-.8z'/></svg>"
        $mkSpark = {
            param($vals)
            $arr = @($vals)
            $n = $arr.Count
            if ($n -lt 2) { return "<svg class='spark' viewBox='0 0 100 28' preserveAspectRatio='none'></svg>" }
            $max = ($arr | Measure-Object -Maximum).Maximum; if ($max -lt 1) { $max = 1 }
            $pts = for ($i = 0; $i -lt $n; $i++) {
                $x = [math]::Round($i / ($n - 1) * 100, 2)
                $y = [math]::Round(27 - ($arr[$i] / $max) * 25, 2)
                "$x,$y"
            }
            $line = ($pts -join ' ')
            $area = "0,28 $line 100,28"
            return "<svg class='spark' viewBox='0 0 100 28' preserveAspectRatio='none'><polygon class='area' points='$area'/><polyline points='$line'/></svg>"
        }

        [void]$sb.Append("<div class='panel' id='trend' style='margin-bottom:26px'><h2>Topic trend - last 14 days</h2><canvas id='trendChart'></canvas></div>")

        [void]$sb.Append("<div class='panel' id='tracker' style='margin-bottom:26px'>")
        [void]$sb.Append("<h2>Topic tracker &middot; <span id='prioCount'>0</span> priority</h2>")
        [void]$sb.Append("<p class='prio-hint'>&#9733; Star the topics that matter to you. Priority topics get highlighted, jump to the top of the feed, and can be isolated with the Priority filter below. Your picks are saved in this browser.</p>")
        $tracking = @($Platform.Tracking)
        if ($tracking.Count -gt 0) {
            [void]$sb.Append("<div class='tracker'>")
            foreach ($row in $tracking) {
                $tn = [System.Net.WebUtility]::HtmlEncode($row.topic)
                $arrow = if ($row.trend -eq 'up') { '&#9650;' } elseif ($row.trend -eq 'down') { '&#9660;' } else { '&#8211;' }
                $delta = [int]$row.last7 - [int]$row.prev7
                $deltaTxt = if ($delta -gt 0) { "+$delta" } else { "$delta" }
                $spark = & $mkSpark $row.spark
                [void]$sb.Append("<div class='topic'>")
                [void]$sb.Append("<div class='th'><span class='name' title='$tn'>$tn</span><button class='star' data-topic='$tn' onclick='toggleStar(this)' aria-label='Prioritise $tn'>$starSvg</button></div>")
                [void]$sb.Append("<div class='stat-row'><span class='cnt'>$($row.total)</span><span class='trend $($row.trend)'>$arrow $deltaTxt/7d</span></div>")
                [void]$sb.Append("<div class='last'>last seen $($row.lastSeen)</div>")
                [void]$sb.Append($spark)
                [void]$sb.Append("</div>")
            }
            [void]$sb.Append("</div>")
        } else {
            [void]$sb.Append("<div class='empty'>No topics tracked yet - run the analyzer to start building history.</div>")
        }
        [void]$sb.Append("</div>")
    }

    # Charts
    [void]$sb.Append("<div class='grid2' id='charts'>")
    [void]$sb.Append("<div class='panel'><h2>Keyword distribution</h2><canvas id='kwChart'></canvas></div>")
    [void]$sb.Append("<div class='panel'><h2>MITRE ATT&amp;CK techniques</h2><canvas id='mtChart'></canvas></div>")
    [void]$sb.Append("</div>")

    # CVE table
    [void]$sb.Append("<div class='panel cve' id='cves' style='margin-bottom:26px'><h2>Live CVE report - NVD, last $CveDays days</h2>")
    if ($NvdBanner) {
        [void]$sb.Append("<div class='empty' style='text-align:left;margin-bottom:12px'>$([System.Net.WebUtility]::HtmlEncode($NvdBanner))</div>")
    }
    if ($Cves -and $Cves.Count -gt 0) {
        [void]$sb.Append("<table><thead><tr><th>CVE</th><th>Severity</th><th>Score</th><th>Published</th><th>Description</th></tr></thead><tbody>")
        foreach ($c in ($Cves | Select-Object -First 60)) {
            $sev = $c.Severity.ToUpper()
            $pub = if ($c.Published) { $c.Published.ToString('yyyy-MM-dd') } else { '' }
            $d   = [System.Net.WebUtility]::HtmlEncode((($c.Description) -as [string]))
            if ($d.Length -gt 220) { $d = $d.Substring(0,220) + '...' }
            $score = if ($null -ne $c.Score) { $c.Score } else { '-' }
            [void]$sb.Append("<tr><td><a href='https://nvd.nist.gov/vuln/detail/$($c.Id)' target='_blank'>$($c.Id)</a></td><td><span class='sev $sev'>$sev</span></td><td>$score</td><td>$pub</td><td>$d</td></tr>")
        }
        [void]$sb.Append("</tbody></table>")
        if ($Cves.Count -gt 60) { [void]$sb.Append("<div class='empty'>Showing top 60 of $($Cves.Count) CVEs by score.</div>") }
    } else {
        [void]$sb.Append("<div class='empty'>No CVE data available (NVD unreachable or no CVEs in window).</div>")
    }
    [void]$sb.Append("</div>")

    # Articles
    [void]$sb.Append("<h2 class='section-title' id='articles'>Articles ($($Articles.Count))</h2>")
    [void]$sb.Append("<div class='filterbar'><button class='chip-btn active' id='fltAll' onclick=`"setFilter('all')`">All</button><button class='chip-btn' id='fltPrio' onclick=`"setFilter('prio')`">&#9733; Priority (<span id='prioFilterCount'>0</span>)</button></div>")
    [void]$sb.Append("<div class='toolbar'><input id='search' type='text' placeholder='Filter articles...' oninput='filterCards()'><span class='badge'>Showing <span id='shownCount'>$($Articles.Count)</span></span></div>")

    if ($Articles -and $Articles.Count -gt 0) {
        [void]$sb.Append("<div class='cards'>")
        foreach ($a in $Articles) {
            $titleEnc = [System.Net.WebUtility]::HtmlEncode($a.Title)
            $sumEnc   = [System.Net.WebUtility]::HtmlEncode($a.Summary)
            if ($sumEnc.Length -gt 280) { $sumEnc = $sumEnc.Substring(0,280) + '...' }
            $pub = if ($a.Published) { $a.Published.ToString('yyyy-MM-dd HH:mm') } else { '' }
            $cat = if ($a.Category) { $a.Category } else { 'News' }

            $mitreStr = (($a.Mitre | ForEach-Object { "$($_.id) $($_.name)" }) -join '; ')
            $prompt = Get-LoadedPrompt -PromptsDir $PromptsDir -PromptId 'article-analyst' -Variables @{
                articleTitle      = [string]$a.Title
                articleLink       = [string]$a.Link
                articleSummary    = [string]$a.Summary
                matchedKeywords   = ($a.MatchedKeywords -join ', ')
                mitreTechniques   = $mitreStr
            }
            if (-not $prompt) {
                $prompt = "You are a senior threat intelligence analyst. Analyze this security article and produce a structured report.`n`nArticle: $($a.Title)`nLink: $($a.Link)`n`nProvide these sections:`n1. Executive Summary`n2. Key Technical Details`n3. Threat Actor Information (if any)`n4. Impact & Risk Assessment`n5. MITRE ATT&CK Techniques (with IDs)`n6. Recommended Mitigations"
            }
            $promptAttr = [System.Net.WebUtility]::HtmlEncode($prompt)

            $kwChips = ''
            foreach ($k in $a.MatchedKeywords) { $kwChips += "<span class='chip kw'>$([System.Net.WebUtility]::HtmlEncode($k))</span>" }
            $ttChips = ''
            foreach ($t in $a.Mitre) { $ttChips += "<span class='chip tt' title='$([System.Net.WebUtility]::HtmlEncode($t.name))'>$($t.id) $([System.Net.WebUtility]::HtmlEncode($t.name))</span>" }

            $dataText = (($a.Title + ' ' + $a.Summary + ' ' + ($a.MatchedKeywords -join ' ') + ' ' + (($a.Mitre | ForEach-Object { $_.id + ' ' + $_.name }) -join ' ')).ToLower())
            $dataTextEnc = [System.Net.WebUtility]::HtmlEncode($dataText)
            $topicsAttr  = [System.Net.WebUtility]::HtmlEncode(((@($a.MatchedKeywords) | ForEach-Object { ([string]$_).ToLower() }) -join ' '))

            [void]$sb.Append("<div class='card' data-text='$dataTextEnc' data-topics='$topicsAttr'>")
            [void]$sb.Append("<div class='meta'><span class='badge cat-$cat'>$cat</span><span class='badge'>$([System.Net.WebUtility]::HtmlEncode($a.Source))</span><span class='badge'>$pub</span></div>")
            [void]$sb.Append("<h3><a href='$([System.Net.WebUtility]::HtmlEncode($a.Link))' target='_blank'>$titleEnc</a></h3>")
            if ($sumEnc) { [void]$sb.Append("<div class='summary'>$sumEnc</div>") }
            if ($kwChips) { [void]$sb.Append("<div class='chips'>$kwChips</div>") }
            if ($ttChips) { [void]$sb.Append("<div class='chips'>$ttChips</div>") }
            [void]$sb.Append("<div class='aibtns'>")
            [void]$sb.Append("<button class='aibtn gpt' data-prompt='$promptAttr' onclick='aiAnalyze(this,&quot;ChatGPT&quot;)'><span class='dot'></span>ChatGPT</button>")
            [void]$sb.Append("<button class='aibtn claude' data-prompt='$promptAttr' onclick='aiAnalyze(this,&quot;Claude&quot;)'><span class='dot'></span>Claude</button>")
            [void]$sb.Append("<button class='aibtn gemini' data-prompt='$promptAttr' onclick='aiAnalyze(this,&quot;Gemini&quot;)'><span class='dot'></span>Gemini</button>")
            [void]$sb.Append("</div></div>")
        }
        [void]$sb.Append("</div>")
    } else {
        [void]$sb.Append("<div class='empty'>No new matching articles this run. Try -NoDedup, broaden your keywords, or check feed connectivity.</div>")
    }

    [void]$sb.Append("<footer>ThreatFeed Analyzer - keywords come to you. Edit config.json to tune feeds, keywords, and the MITRE map.</footer>")
    [void]$sb.Append("</div>")

    # Floating Claude-style assistant avatar with quick actions
    $sparkSvg = "<svg viewBox='0 0 24 24' fill='currentColor'><path d='M12 2c.35 4 1.65 5.65 5.65 6C13.65 8.35 12 9.65 12 14c0-4.35-1.65-5.65-5.65-6C10.35 7.65 11.65 6 12 2z'/><path d='M18.5 13c.2 2 .8 2.8 2.8 3-2 .2-2.6 1-2.8 3-.2-2-.8-2.8-2.8-3 2-.2 2.6-1 2.8-3z' opacity='.65'/></svg>"
    $cIcon = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><path d='M3 3v18h18'/><path d='M7 14l3-3 3 3 4-5'/></svg>"
    $vIcon = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><path d='M12 3l8 4v5c0 4.5-3 8-8 9-5-1-8-4.5-8-9V7z'/></svg>"
    $aIcon = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><path d='M4 6h16M4 12h16M4 18h10'/></svg>"
    $tIcon = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='4'/><path d='M12 2v2M12 20v2M2 12h2M20 12h2'/></svg>"
    [void]$sb.Append("<div class='assistant'>")
    [void]$sb.Append("<div class='assistant-panel' id='asstPanel'><div class='ah'><span class='av'>$sparkSvg</span><div><b>Assistant</b><span>Quick actions</span></div></div>")
    [void]$sb.Append("<button class='aopt' onclick=`"asstNav('#shift-brief')`">$sparkSvg Shift Brief</button>")
    [void]$sb.Append("<button class='aopt primary' onclick='asstSummary()'>$sparkSvg Summarise today's threats</button>")
    [void]$sb.Append("<button class='aopt' onclick=`"asstNav('#charts')`">$cIcon Go to charts</button>")
    [void]$sb.Append("<button class='aopt' onclick=`"asstNav('#cves')`">$vIcon Latest CVEs</button>")
    [void]$sb.Append("<button class='aopt' onclick=`"asstNav('#articles')`">$aIcon Jump to articles</button>")
    [void]$sb.Append("<button class='aopt' onclick='toggleTheme()'>$tIcon Toggle light / dark</button>")
    [void]$sb.Append("</div>")
    [void]$sb.Append("<button class='assistant-orb' id='asstOrb' aria-label='Open assistant'>$sparkSvg</button>")
    [void]$sb.Append("</div>")

    [void]$sb.Append("<div id='toast'></div>")

    $summary = [pscustomobject]@{
        date     = $Stats.GeneratedAt
        articles = $Stats.New
        cves     = $Stats.CveCount
        cveDays  = $CveDays
        keywords = @($KeywordCounts.labels)
        mitre    = @($MitreCounts.labels)
    }
    $summaryJson = ($summary | ConvertTo-Json -Compress)
    if (-not $summaryJson) { $summaryJson = '{}' }

    $shiftPromptJs = 'null'
    if ($ShiftPrompt) {
        $shiftPromptJs = '"' + (Escape-PromptForJs $ShiftPrompt) + '"'
    }

    $trendJson = '{"days":[],"series":[]}'
    if ($Platform) {
        $trendObj = [pscustomobject]@{
            days   = @($Platform.TrendDays)
            series = @($Platform.TrendSeries | ForEach-Object { [pscustomobject]@{ topic = $_.topic; values = @($_.values) } })
        }
        $tj = $trendObj | ConvertTo-Json -Depth 5 -Compress
        if ($tj) { $trendJson = $tj }
    }

    [void]$sb.Append("<script>window.KEYWORD_DATA=$kwJson;window.MITRE_DATA=$mtJson;window.SUMMARY=$summaryJson;window.TREND=$trendJson;window.SHIFT_PROMPT=$shiftPromptJs;</script>")
    [void]$sb.Append("<script>$js</script>")
    [void]$sb.Append("</body></html>")

    [System.IO.File]::WriteAllText($Path, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

# ----------------------------------------------------------------------------
# 6. Platform data store (tracking over time)
# ----------------------------------------------------------------------------
# The platform accumulates state across runs in two JSON files under data/:
#   articles.json - rolling window of tracked articles (dedup + the live feed)
#   topics.json   - per-topic daily counts -> powers trends and the tracker
function Read-JsonFile {
    param([string]$path)
    if (-not (Test-Path $path)) { return $null }
    try {
        $raw = (Get-Content -Raw -Path $path -Encoding UTF8).TrimStart([char]0xFEFF, ' ', "`t", "`r", "`n")
        if (-not $raw) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch { return $null }
}

function Write-JsonFile {
    param([string]$path, $obj, [int]$depth = 8)
    $json = $obj | ConvertTo-Json -Depth $depth -Compress
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# Merge this run's matched articles into the rolling store, bump per-topic daily
# counts, prune anything older than the window, and return everything the live
# page needs: tracked articles, topic tracking rows, and a daily trend series.
function Update-Platform {
    param(
        [string]$DataDir,
        $Matched,
        [string[]]$Keywords,
        [int]$WindowDays = 45,
        [int]$MaxArticles = 1500
    )
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    $articlesPath = Join-Path $DataDir 'articles.json'
    $topicsPath   = Join-Path $DataDir 'topics.json'

    $now      = Get-Date
    $today    = $now.ToString('yyyy-MM-dd')
    $cutoffDt = $now.AddDays(-1.0 * $WindowDays)
    $cutStr   = $cutoffDt.ToString('yyyy-MM-dd')

    # Precompute the 14-day date strings once.
    $dayStr = New-Object System.Collections.Generic.List[string]   # 0=today .. 13=13d ago
    for ($i = 0; $i -lt 14; $i++) { $dayStr.Add($now.AddDays(-1.0 * $i).ToString('yyyy-MM-dd')) }
    $last14 = New-Object System.Collections.Generic.List[string]   # oldest -> newest
    for ($i = 13; $i -ge 0; $i--) { $last14.Add($dayStr[$i]) }

    # --- Load existing article store ---
    $byKey = [ordered]@{}
    $existing = Read-JsonFile $articlesPath
    if ($existing) {
        foreach ($a in @($existing)) {
            if (-not $a -or -not $a.key) { continue }
            $a.title = Normalize-FeedText ([string]$a.title)
            $a.summary = Normalize-FeedText ([string]$a.summary)
            $byKey[[string]$a.key] = $a
        }
    }

    # --- Load topic daily counts -> hashtable topic => (hashtable date => int) ---
    $topicDaily = @{}
    $topicsObj = Read-JsonFile $topicsPath
    if ($topicsObj) {
        foreach ($p in $topicsObj.PSObject.Properties) {
            $inner = @{}
            if ($p.Value) { foreach ($d in $p.Value.PSObject.Properties) { $inner[[string]$d.Name] = [int]$d.Value } }
            $topicDaily[[string]$p.Name] = $inner
        }
    }

    # --- Merge this run's matched articles + bump today's per-topic counts ---
    $newCount = 0
    foreach ($m in $Matched) {
        $key = Get-ArticleKey -Link $m.Link -Source $m.Source -Title $m.Title
        $sum = Normalize-FeedText ([string]$m.Summary)
        if ($sum.Length -gt 320) { $sum = $sum.Substring(0, 320) }
        $pub = ''
        if ($m.Published) { try { $pub = ([datetime]$m.Published).ToString('yyyy-MM-ddTHH:mm:ss') } catch { $pub = '' } }
        $title = Normalize-FeedText ([string]$m.Title)

        if ($byKey.Contains($key)) {
            $prev = $byKey[$key]
            $byKey[$key] = [pscustomobject]@{
                key       = $key
                title     = $title
                link      = [string]$m.Link
                summary   = $sum
                source    = [string]$m.Source
                category  = [string]$m.Category
                published = if ($pub) { $pub } else { [string]$prev.published }
                firstSeen = [string]$prev.firstSeen
                keywords  = @($m.MatchedKeywords | ForEach-Object { [string]$_ })
                mitre     = @($m.Mitre)
            }
            continue
        }

        $newCount++
        $byKey[$key] = [pscustomobject]@{
            key       = $key
            title     = $title
            link      = [string]$m.Link
            summary   = $sum
            source    = [string]$m.Source
            category  = [string]$m.Category
            published = $pub
            firstSeen = $today
            keywords  = @($m.MatchedKeywords | ForEach-Object { [string]$_ })
            mitre     = @($m.Mitre)
        }
        foreach ($kw in $m.MatchedKeywords) {
            $kws = [string]$kw
            if (-not $topicDaily.ContainsKey($kws)) { $topicDaily[$kws] = @{} }
            $cur = 0; if ($topicDaily[$kws].ContainsKey($today)) { $cur = [int]$topicDaily[$kws][$today] }
            $topicDaily[$kws][$today] = $cur + 1
        }
    }

    # --- Prune articles by window + cap (newest firstSeen first) ---
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $byKey.Values) {
        $fs = [datetime]::MinValue
        $ok = $true
        if ([datetime]::TryParse([string]$rec.firstSeen, [ref]$fs)) { $ok = ($fs -ge $cutoffDt) }
        if ($ok) { $kept.Add($rec) }
    }
    $allArticles = @($kept | Sort-Object -Property @{Expression={ [string]$_.firstSeen }; Descending=$true} | Select-Object -First $MaxArticles)

    # --- Prune old topic-day entries ---
    foreach ($t in @($topicDaily.Keys)) {
        $inner = $topicDaily[$t]
        foreach ($d in @($inner.Keys)) { if ([string]$d -lt $cutStr) { $inner.Remove($d) } }
        if ($inner.Count -eq 0) { $topicDaily.Remove($t) }
    }

    # --- Build topic tracking rows (config order first, then any extras) ---
    $orderedTopics = New-Object System.Collections.Generic.List[string]
    foreach ($k in $Keywords) { $ks=[string]$k; if (-not $orderedTopics.Contains($ks)) { $orderedTopics.Add($ks) } }
    foreach ($k in $topicDaily.Keys) { $ks=[string]$k; if (-not $orderedTopics.Contains($ks)) { $orderedTopics.Add($ks) } }

    $trackRows = New-Object System.Collections.Generic.List[object]
    foreach ($t in $orderedTopics) {
        $inner = if ($topicDaily.ContainsKey($t)) { $topicDaily[$t] } else { @{} }
        $total = 0; foreach ($v in $inner.Values) { $total += [int]$v }
        if ($total -le 0) { continue }
        $last7 = 0; $prev7 = 0
        for ($i = 0; $i -lt 7;  $i++) { if ($inner.ContainsKey($dayStr[$i])) { $last7 += [int]$inner[$dayStr[$i]] } }
        for ($i = 7; $i -lt 14; $i++) { if ($inner.ContainsKey($dayStr[$i])) { $prev7 += [int]$inner[$dayStr[$i]] } }
        $lastSeen = ''
        foreach ($d in (@($inner.Keys) | Sort-Object -Descending)) { if ([int]$inner[$d] -gt 0) { $lastSeen = [string]$d; break } }
        $spark = New-Object System.Collections.Generic.List[int]
        foreach ($d in $last14) { if ($inner.ContainsKey($d)) { $spark.Add([int]$inner[$d]) } else { $spark.Add(0) } }
        $dir = if ($last7 -gt $prev7) { 'up' } elseif ($last7 -lt $prev7) { 'down' } else { 'flat' }
        $trackRows.Add([pscustomobject]@{
            topic = [string]$t; total = [int]$total; last7 = [int]$last7; prev7 = [int]$prev7
            trend = $dir; lastSeen = $lastSeen; spark = $spark.ToArray()
        })
    }
    $trackRows = @($trackRows | Sort-Object -Property @{Expression={ [int]$_.total }; Descending=$true})

    # --- Daily trend series: top 6 topics over 14 days ---
    $trendSeriesArr = @()
    foreach ($row in ($trackRows | Select-Object -First 6)) {
        $t = [string]$row.topic
        $inner = if ($topicDaily.ContainsKey($t)) { $topicDaily[$t] } else { @{} }
        $vals = New-Object System.Collections.Generic.List[int]
        foreach ($d in $last14) { if ($inner.ContainsKey($d)) { $vals.Add([int]$inner[$d]) } else { $vals.Add(0) } }
        $trendSeriesArr += [pscustomobject]@{ topic = $t; values = $vals.ToArray() }
    }

    # --- Persist store ---
    try { Write-JsonFile -path $articlesPath -obj $allArticles -depth 6 } catch { Write-Warn2 "Could not save articles store: $($_.Exception.Message)" }
    try {
        $topicsOut = [ordered]@{}
        foreach ($t in (@($topicDaily.Keys) | Sort-Object)) {
            $dayObj = [ordered]@{}
            foreach ($d in (@($topicDaily[$t].Keys) | Sort-Object)) { $dayObj[[string]$d] = [int]$topicDaily[$t][$d] }
            $topicsOut[[string]$t] = $dayObj
        }
        Write-JsonFile -path $topicsPath -obj $topicsOut -depth 5
    } catch { Write-Warn2 "Could not save topics store: $($_.Exception.Message)" }

    $out = [ordered]@{}
    $out['Articles']     = $allArticles
    $out['Tracking']     = @($trackRows)
    $out['TrendDays']    = @($last14.ToArray())
    $out['TrendSeries']  = $trendSeriesArr
    $out['NewCount']     = [int]$newCount
    $out['TotalTracked'] = @($allArticles).Count
    return [pscustomobject]$out
}

# ============================================================================
# MAIN
# ============================================================================
$startTime = Get-Date
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# --- Fetch + parse all feeds ---
Write-Step "Fetching $($Feeds.Count) feeds..."
$allItems = New-Object System.Collections.Generic.List[object]
$feedsOk = 0
foreach ($feed in $Feeds) {
    $raw = Get-FeedRaw -url $feed.url
    if (-not $raw) { Write-Warn2 "  FAIL  $($feed.name)"; continue }
    $parsed = ConvertFrom-Feed -raw $raw -feed $feed -max $MaxItemsPerFeed
    if ($parsed.Count -gt 0) {
        $feedsOk++
        Write-Ok "  $($parsed.Count.ToString().PadLeft(3)) items  $($feed.name)"
        foreach ($p in $parsed) { $allItems.Add($p) }
    } else {
        Write-Warn2 "  EMPTY $($feed.name)"
    }
}
Write-Ok "Fetched $($allItems.Count) items from $feedsOk/$($Feeds.Count) feeds."
if ($feedsOk -eq 0 -and $Feeds.Count -gt 0) {
    Write-ErrLine "All feeds failed - no articles fetched."
    exit 1
}

# --- Filter by keywords + map MITRE ---
Write-Step "Filtering by $($Keywords.Count) keywords + mapping MITRE ATT&CK..."
$matched = New-Object System.Collections.Generic.List[object]
foreach ($item in $allItems) {
    # Force scalar strings - a few feeds expose multi-valued title/content nodes,
    # which would otherwise make Regex.IsMatch() throw "Argument types do not match".
    $text = [string]$item.Title + ' ' + [string]$item.Summary
    if ([string]::IsNullOrWhiteSpace($text)) { continue }

    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($k in $Keywords) {
        if ($KeywordRegex[$k].IsMatch($text)) { $hits.Add($k) }
    }
    if ($hits.Count -eq 0) { continue }

    # MITRE mapping
    $tt = New-Object System.Collections.Generic.List[object]
    $seenTt = @{}
    foreach ($m in $Mitre) {
        if ([string]::IsNullOrWhiteSpace($m.pattern)) { continue }
        if ($text -imatch ('\b' + [regex]::Escape($m.pattern) + '\b')) {
            if (-not $seenTt.ContainsKey($m.id)) {
                $seenTt[$m.id] = $true
                $tt.Add([pscustomobject]@{ id = $m.id; name = $m.name })
            }
        }
    }

    # Build a fresh record rather than Add-Member onto the parsed item; -Force
    # Add-Member with a collection value is what was throwing on PS 5.1.
    $matched.Add([pscustomobject]@{
        Title           = Normalize-FeedText ([string]$item.Title)
        Link            = [string]$item.Link
        Summary         = Normalize-FeedText ([string]$item.Summary)
        Published       = $item.Published
        Source          = $item.Source
        Category        = $item.Category
        MatchedKeywords = $hits.ToArray()
        Mitre           = $tt.ToArray()
    })
}
Write-Ok "$($matched.Count) articles matched your keywords."

# --- Dedup across runs ---
$seenKeys = @{}
if (-not $NoDedup -and (Test-Path $SeenPath)) {
    try {
        # PS 5.1: a UTF-8 BOM in the file breaks ConvertFrom-Json, so strip it first.
        $rawSeen = (Get-Content -Raw -Path $SeenPath -Encoding UTF8).TrimStart([char]0xFEFF, ' ', "`t", "`r", "`n")
        if ($rawSeen) {
            $prev = $rawSeen | ConvertFrom-Json
            foreach ($k in @($prev)) { if ($k) { $seenKeys[$k] = $true } }
        }
    } catch { Write-Warn2 "Could not read dedup state ($($_.Exception.Message)) - treating all as new." }
}
$new = New-Object System.Collections.Generic.List[object]
$dupCount = 0
$updatedKeys = New-Object System.Collections.Generic.List[string]
foreach ($k in $seenKeys.Keys) { $updatedKeys.Add($k) }
foreach ($item in $matched) {
    $key = Get-ArticleKey -Link $item.Link -Source $item.Source -Title $item.Title
    if (-not $NoDedup -and $seenKeys.ContainsKey($key)) { $dupCount++; continue }
    $new.Add($item)
    if (-not $seenKeys.ContainsKey($key)) { $updatedKeys.Add($key); $seenKeys[$key] = $true }
}
# Sort newest first (nulls last)
$new = $new | Sort-Object -Property @{Expression={ if ($_.Published) { $_.Published } else { [datetime]::MinValue } }; Descending=$true}
Write-Ok "$($new.Count) new article(s); $dupCount duplicate(s) skipped."

# --- Platform store: track topics over time ---
Write-Step "Updating platform store (tracking topics over time)..."
$DataDir  = Join-Path $ScriptRoot 'data'
try {
    $platform = Update-Platform -DataDir $DataDir -Matched $matched -Keywords $Keywords
} catch {
    $diag = "MSG: $($_.Exception.Message)`nTYPE: $($_.Exception.GetType().FullName)`nSTACK:`n$($_.ScriptStackTrace)"
    [System.IO.File]::WriteAllText((Join-Path $ScriptRoot '_err.txt'), $diag, (New-Object System.Text.UTF8Encoding($false)))
    throw
}
Write-Ok "$($platform.TotalTracked) articles tracked in the rolling window ($($platform.Tracking.Count) topics)."

# Score today's keyword matches for Shift Brief (uses $matched, not rolling $display)
Write-Step "Scoring $($matched.Count) matched articles for Shift Brief..."
$scoredMatched = New-Object System.Collections.Generic.List[object]
foreach ($item in $matched) {
    $scoredMatched.Add((Add-ArticleScoring -Article $item -Tracking $platform.Tracking -SeenKeys $seenKeys -NoDedup:$NoDedup))
}
$matched = $scoredMatched
$sortedAll = Sort-ByPriorityScore -Articles ([object[]]($matched.ToArray()))
$shiftBrief = @($sortedAll | Select-Object -First 10)
Write-Ok "Shift Brief Top-$($shiftBrief.Count) ready (highest score: $(if ($shiftBrief.Count -gt 0) { $shiftBrief[0].PriorityScore } else { 0 }))."

# Build the article list the live page shows: rehydrate tracked records into the
# same shape the renderer expects (.Title/.MatchedKeywords/.Mitre/.Published).
$display = @($platform.Articles | ForEach-Object {
    $pub = $null
    if ($_.published) { $p = [datetime]::MinValue; if ([datetime]::TryParse($_.published, [ref]$p)) { $pub = $p } }
    [pscustomobject]@{
        Title = $_.title; Link = $_.link; Summary = $_.summary; Source = $_.source
        Category = $_.category; Published = $pub; FirstSeen = $_.firstSeen
        MatchedKeywords = @($_.keywords); Mitre = @($_.mitre)
    }
} | Sort-Object -Property @{Expression={ if ($_.Published) { $_.Published } else { [datetime]::MinValue } }; Descending=$true})

# --- Aggregates for charts (from the tracked window, so the page always has data) ---
$kwTally = @{}
foreach ($a in $display) { foreach ($k in $a.MatchedKeywords) { if ($k) { if ($kwTally.ContainsKey($k)) { $kwTally[$k]++ } else { $kwTally[$k] = 1 } } } }
$kwSorted = $kwTally.GetEnumerator() | Sort-Object Value -Descending
$keywordCounts = [pscustomobject]@{ labels = @($kwSorted | ForEach-Object { $_.Key }); values = @($kwSorted | ForEach-Object { $_.Value }) }

$mtTally = @{}
$mtName  = @{}
foreach ($a in $display) {
    foreach ($t in $a.Mitre) {
        if (-not $t -or -not $t.id) { continue }
        $lab = "$($t.id)"
        if ($mtTally.ContainsKey($lab)) { $mtTally[$lab]++ } else { $mtTally[$lab] = 1; $mtName[$lab] = $t.name }
    }
}
$mtSorted = $mtTally.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15
$mitreCounts = [pscustomobject]@{ labels = @($mtSorted | ForEach-Object { "$($_.Key) $($mtName[$_.Key])" }); values = @($mtSorted | ForEach-Object { $_.Value }) }

# --- CVEs ---
Write-Step "Querying NVD for CVEs (last $CveDays days)..."
$cves = Get-NvdCves -days $CveDays -apiKey $NvdApiKey
Write-Ok "$($cves.Count) CVEs retrieved."

# --- Stats ---
$stats = [pscustomobject]@{
    GeneratedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    FeedsTotal   = $Feeds.Count
    FeedsOk      = $feedsOk
    Fetched      = $allItems.Count
    Matched      = $matched.Count
    New          = $new.Count
    Duplicates   = $dupCount
    CveCount     = $cves.Count
    TotalTracked = $platform.TotalTracked
    TopicCount   = $platform.Tracking.Count
}

# --- Write the live platform page (stable index.html) + a timestamped archive ---
$stamp     = (Get-Date).ToString('yyyyMMdd-HHmmss')
$indexPath = Join-Path $OutputDir 'index.html'
$htmlPath  = Join-Path $OutputDir "threatfeed-report-$stamp.html"
$csvPath   = Join-Path $OutputDir 'index.csv'

# Shift brief prompt from template
$topLines = New-Object System.Collections.Generic.List[string]
$si = 1
foreach ($a in $shiftBrief) {
    $pub = if ($a.Published) { $a.Published.ToString('yyyy-MM-dd') } else { 'n/a' }
    [void]$topLines.Add("$si. [$($a.PriorityScore)] $($a.Title) ($($a.Source), $pub)")
    $si++
}
$shiftPrompt = Get-LoadedPrompt -PromptsDir $PromptsDir -PromptId 'shift-brief' -Variables @{
    date        = $stats.GeneratedAt
    topArticles = ($topLines -join "`n")
    keywords    = (($keywordCounts.labels | Select-Object -First 8) -join ', ')
    mitreTop    = (($mitreCounts.labels | Select-Object -First 6) -join ', ')
    cveCount    = [string]$stats.CveCount
    cveDays     = [string]$CveDays
}

Write-Step "Writing live platform page..."
New-HtmlReport -Articles $display -Cves $cves -KeywordCounts $keywordCounts -MitreCounts $mitreCounts `
    -Stats $stats -Platform $platform -ShiftBrief $shiftBrief -Path $indexPath `
    -ShiftPrompt $shiftPrompt -NvdBanner $NvdWarning
Copy-Item -Path $indexPath -Destination $htmlPath -Force

Write-Step "Writing CSV..."
$display | ForEach-Object {
    [pscustomobject]@{
        Source          = $_.Source
        Category        = $_.Category
        FirstSeen       = $_.FirstSeen
        Published       = if ($_.Published) { $_.Published.ToString('yyyy-MM-dd HH:mm') } else { '' }
        Title           = $_.Title
        Link            = $_.Link
        MatchedKeywords = ($_.MatchedKeywords -join '; ')
        MitreTechniques = (($_.Mitre | ForEach-Object { "$($_.id) $($_.name)" }) -join '; ')
    }
} | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# --- Run metadata (observability) ---
$runMeta = [ordered]@{
    runId          = $RunId
    generatedAt    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    engine         = 'powershell'
    fallbackReason = $null
    feedsTotal     = $stats.FeedsTotal
    feedsOk        = $stats.FeedsOk
    fetched        = $stats.Fetched
    matched        = $stats.Matched
    newArticles    = $stats.New
    shiftBriefSize = @($shiftBrief).Count
    cveCount       = $stats.CveCount
    nvdWarning     = $NvdWarning
}
try {
    Write-JsonFile -path (Join-Path $DataDir 'run-meta.json') -obj $runMeta -depth 4
} catch { Write-Warn2 "Could not save run-meta.json: $($_.Exception.Message)" }

# --- Hosted dashboard data (Vite/React static app) ---
Write-Step "Exporting dashboard data..."
try {
    $dashboardDir = Join-Path $ScriptRoot 'dashboard'
    $dashPath = Export-DashboardData -DashboardDir $dashboardDir -Stats $stats -ShiftBrief $shiftBrief `
        -DisplayArticles $display -KeywordCounts $keywordCounts -MitreCounts $mitreCounts `
        -Platform $platform -Cves $cves -RunMeta $runMeta -CveDays $CveDays -NvdBanner $NvdWarning
    Copy-Item -Path $dashPath -Destination (Join-Path $DataDir 'dashboard.json') -Force
    Write-Ok "Dashboard bundle: $dashPath"
} catch {
    Write-Warn2 "Dashboard export skipped: $($_.Exception.Message)"
}

# --- Persist dedup state ---
if (-not $NoDedup) {
    try {
        $seenJson = ConvertTo-Json -InputObject @($updatedKeys) -Compress
        [System.IO.File]::WriteAllText($SeenPath, $seenJson, (New-Object System.Text.UTF8Encoding($false)))
    } catch { Write-Warn2 "Could not save dedup state: $($_.Exception.Message)" }
}

$elapsed = [int]((Get-Date) - $startTime).TotalSeconds
Write-Host ""
Write-Ok "Done in ${elapsed}s."
Write-Host "    LIVE   : $indexPath" -ForegroundColor White
Write-Host "    Archive: $htmlPath" -ForegroundColor White
Write-Host "    CSV    : $csvPath"  -ForegroundColor White
Write-Host "    Data   : $DataDir" -ForegroundColor White
Write-Host "    Dash   : $(Join-Path $ScriptRoot 'dashboard')" -ForegroundColor White

if (-not $NoOpen) {
    try { Invoke-Item $indexPath } catch {}
}
