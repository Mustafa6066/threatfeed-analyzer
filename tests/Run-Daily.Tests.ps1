#Requires -Version 5.1
Describe 'Run-Daily exit code' {
    It 'exits non-zero when analyzer script is missing' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $fakeRoot = Join-Path $TestDrive 'run-daily-isolated'
        New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
        Copy-Item (Join-Path $repoRoot 'Run-Daily.ps1') -Destination $fakeRoot -Force

        Push-Location $fakeRoot
        try {
            & (Join-Path $fakeRoot 'Run-Daily.ps1') 2>&1 | Out-Null
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $code | Should BeGreaterThan 0
    }
}
