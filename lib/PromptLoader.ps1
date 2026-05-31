# PromptLoader.ps1 — load versioned prompt templates from prompts/
# Dot-source from ThreatFeed-Analyzer.ps1

function Escape-PromptForHtml {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Escape-PromptForJs {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = [string]$Text
    $t = $t -replace '\\', '\\\\'
    $t = $t -replace "`r", ''
    $t = $t -replace "`n", '\n'
    $t = $t -replace "'", "\'"
    return $t
}

function Invoke-PromptSubstitution {
    param(
        [string]$Template,
        [hashtable]$Variables
    )
    if ([string]::IsNullOrEmpty($Template)) { return '' }
    $out = $Template
    foreach ($key in $Variables.Keys) {
        $token = '{{' + $key + '}}'
        $val = if ($null -eq $Variables[$key]) { '' } else { [string]$Variables[$key] }
        $out = $out.Replace($token, $val)
    }
    return $out
}

function Get-PromptManifest {
    param([string]$PromptsDir)
    $manifestPath = Join-Path $PromptsDir 'prompt-manifest.json'
    if (-not (Test-Path $manifestPath)) { return $null }
    try {
        return (Get-Content -Raw -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json)
    } catch { return $null }
}

function Get-PromptTemplate {
    param(
        [string]$PromptsDir,
        [string]$PromptId
    )
    $manifest = Get-PromptManifest -PromptsDir $PromptsDir
    if (-not $manifest) { return $null }
    $entry = @($manifest.prompts | Where-Object { $_.id -eq $PromptId } | Select-Object -First 1)
    if (-not $entry) { return $null }
    $filePath = Join-Path $PromptsDir $entry.file
    if (-not (Test-Path $filePath)) { return $null }
    try {
        return (Get-Content -Raw -Path $filePath -Encoding UTF8)
    } catch { return $null }
}

function Get-LoadedPrompt {
    param(
        [string]$PromptsDir,
        [string]$PromptId,
        [hashtable]$Variables,
        [switch]$HtmlEscape
    )
    $template = Get-PromptTemplate -PromptsDir $PromptsDir -PromptId $PromptId
    if (-not $template) { return $null }
    $text = Invoke-PromptSubstitution -Template $template -Variables $Variables
    if ($HtmlEscape) { return Escape-PromptForHtml $text }
    return $text
}
