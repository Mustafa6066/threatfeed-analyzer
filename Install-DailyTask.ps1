<#
.SYNOPSIS
    Register (or remove) a Windows Scheduled Task that runs ThreatFeed-Analyzer daily.

.DESCRIPTION
    Creates a per-user scheduled task that runs Run-Daily.ps1 every day at a set time.
    The task runs only while you are logged on (LogonType Interactive), so it needs
    no admin rights and no stored password. If the machine was off at the scheduled
    time, the task runs as soon as it next becomes available (StartWhenAvailable).

.PARAMETER At
    Time of day to run, HH:mm (24h). Default 09:00.

.PARAMETER TaskName
    Scheduled task name. Default "ThreatFeed-Analyzer Daily".

.PARAMETER CveDays
    Forwarded to the analyzer (NVD lookback window). Default uses config.json.

.PARAMETER Uninstall
    Remove the scheduled task instead of creating it.

.EXAMPLE
    .\Install-DailyTask.ps1                 # daily at 09:00
    .\Install-DailyTask.ps1 -At 07:30
    .\Install-DailyTask.ps1 -CveDays 3 -At 08:00
    .\Install-DailyTask.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$At = '09:00',
    [string]$TaskName = 'ThreatFeed-Analyzer Daily',
    [int]$CveDays = 0,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Wrapper    = Join-Path $ScriptRoot 'Run-Daily.ps1'

function Write-Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Write-Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Err($m)  { Write-Host "[x] $m" -ForegroundColor Red }

# --- Uninstall path ---
if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Ok "Removed scheduled task '$TaskName'."
    } else {
        Write-Info "No scheduled task named '$TaskName' found - nothing to remove."
    }
    return
}

# --- Validate ---
if (-not (Test-Path $Wrapper)) { Write-Err "Run-Daily.ps1 not found next to this script."; exit 1 }
$parsedTime = [datetime]::MinValue
if (-not [datetime]::TryParseExact($At, 'HH:mm', $null, [System.Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
    Write-Err "Invalid -At value '$At'. Use 24h HH:mm, e.g. 09:00 or 07:30."; exit 1
}

# --- Build the task definition ---
# Quote the wrapper path; forward optional analyzer args.
$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$Wrapper`""
if ($CveDays -gt 0) { $psArgs += " -CveDays $CveDays" }

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs -WorkingDirectory $ScriptRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $parsedTime
$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Write-Info "Registering '$TaskName' to run daily at $At ..."
try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Runs ThreatFeed-Analyzer daily and writes an HTML/CSV report.' -Force | Out-Null
}
catch {
    # Fallback: schtasks.exe (still per-user, runs only when logged on).
    Write-Info "Register-ScheduledTask failed ($($_.Exception.Message)); falling back to schtasks.exe ..."
    $tr = "powershell.exe $psArgs"
    schtasks.exe /Create /TN $TaskName /TR $tr /SC DAILY /ST $At /F | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err "schtasks fallback also failed (exit $LASTEXITCODE)."; exit 1 }
}

$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
Write-Ok "Scheduled task '$TaskName' is installed."
Write-Host "    Runs daily at : $At (only while you are logged on)" -ForegroundColor White
if ($info -and $info.NextRunTime) { Write-Host "    Next run      : $($info.NextRunTime)" -ForegroundColor White }
Write-Host "    Wrapper       : $Wrapper" -ForegroundColor White
Write-Host "    Logs          : $(Join-Path $ScriptRoot 'logs')" -ForegroundColor White
Write-Host ""
Write-Host "Run now to test : Start-ScheduledTask -TaskName `"$TaskName`"" -ForegroundColor DarkGray
Write-Host "Change the time : .\Install-DailyTask.ps1 -At 07:30" -ForegroundColor DarkGray
Write-Host "Remove it       : .\Install-DailyTask.ps1 -Uninstall" -ForegroundColor DarkGray
