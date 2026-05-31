<#
.SYNOPSIS
    Append analyst feedback for a ThreatFeed article to data/feedback.jsonl.

.DESCRIPTION
    B-Seed feedback capture via CLI. Actions: up, down, acted, skip.

.PARAMETER ArticleKey
    SHA1 hex from Get-ArticleKey (shown in Shift Brief / article cards).

.PARAMETER Action
    One of: up, down, acted, skip

.PARAMETER Shift
    Shift date (YYYY-MM-DD). Defaults to today.

.EXAMPLE
    .\Add-TfaFeedback.ps1 -ArticleKey abc123... -Action up
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArticleKey,

    [Parameter(Mandatory = $true)]
    [ValidateSet('up', 'down', 'acted', 'skip')]
    [string]$Action,

    [string]$Shift
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$DataDir = Join-Path $ScriptRoot 'data'
$FeedbackPath = Join-Path $DataDir 'feedback.jsonl'

if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
if (-not $Shift) { $Shift = (Get-Date).ToString('yyyy-MM-dd') }

$key = $ArticleKey.Trim().ToLowerInvariant()
if ($key -notmatch '^[a-f0-9]{40}$') {
    Write-Error "ArticleKey must be a 40-character SHA1 hex string."
}

$line = [ordered]@{
    ts         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    articleKey = $key
    action     = $Action
    shift      = $Shift
    source     = 'cli'
} | ConvertTo-Json -Compress

Add-Content -Path $FeedbackPath -Value $line -Encoding UTF8
Write-Host "[+] Feedback recorded: $Action for $key (shift $Shift)" -ForegroundColor Green
