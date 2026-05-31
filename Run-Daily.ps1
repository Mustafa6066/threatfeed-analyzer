<#
.SYNOPSIS
    Unattended wrapper for ThreatFeed-Analyzer - run by the daily scheduled task.

.DESCRIPTION
    Runs ThreatFeed-Analyzer.ps1 with -NoOpen (no browser pop-up on an unattended
    machine), writes a full transcript to .\logs\, and prunes logs older than the
    retention window. Knobs are explicit, typed parameters and are forwarded to the
    analyzer via hashtable splatting (robust on Windows PowerShell 5.1, unlike
    ValueFromRemainingArguments which reorders -Name value pairs).

.PARAMETER CveDays
    NVD CVE lookback window in days. 0 = use config.json default.

.PARAMETER MaxFeeds
    Process only the first N feeds (0 = all). Mainly for quick tests.

.PARAMETER OutputDir
    Report output folder. Defaults to the analyzer's own default (.\reports).

.PARAMETER NvdApiKey
    Optional NVD API key for higher CVE rate limits.

.PARAMETER NoDedup
    Forward -NoDedup to the analyzer (show already-seen articles too).

.PARAMETER KeepLogs
    How many daily log files to keep. Default 30.

.EXAMPLE
    .\Run-Daily.ps1
    .\Run-Daily.ps1 -CveDays 3
#>
[CmdletBinding()]
param(
    [int]$CveDays = 0,
    [int]$MaxFeeds = 0,
    [string]$OutputDir,
    [string]$NvdApiKey,
    [switch]$NoDedup,
    [int]$KeepLogs = 30
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Analyzer   = Join-Path $ScriptRoot 'ThreatFeed-Analyzer.ps1'
$LogDir     = Join-Path $ScriptRoot 'logs'
$exitCode   = 0

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logFile = Join-Path $LogDir ("threatfeed-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

Start-Transcript -Path $logFile -Force | Out-Null
try {
    Write-Host "ThreatFeed daily run started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if (-not (Test-Path $Analyzer)) { throw "Analyzer not found at $Analyzer" }

    $params = @{ NoOpen = $true }
    if ($CveDays  -gt 0) { $params['CveDays']  = $CveDays }
    if ($MaxFeeds -gt 0) { $params['MaxFeeds'] = $MaxFeeds }
    if ($OutputDir)      { $params['OutputDir'] = $OutputDir }
    if ($NvdApiKey)      { $params['NvdApiKey'] = $NvdApiKey }
    if ($NoDedup)        { $params['NoDedup']   = $true }

    & $Analyzer @params
    if ($LASTEXITCODE -ne 0) {
        $exitCode = [int]$LASTEXITCODE
        Write-Host "Analyzer exited with code $exitCode"
    } else {
        Write-Host "ThreatFeed daily run finished $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Stop-Transcript | Out-Null
    Get-ChildItem -Path $LogDir -Filter 'threatfeed-*.log' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepLogs |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

exit $exitCode
