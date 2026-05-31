# ArticleKey.ps1 — canonical article identity for dedup + feedback
# Dot-source from ThreatFeed-Analyzer.ps1

function Get-CanonicalUrl {
    param([string]$Link)
    if ([string]::IsNullOrWhiteSpace($Link)) { return '' }
    $uri = $null
    if (-not [System.Uri]::TryCreate($Link.Trim(), [System.UriKind]::Absolute, [ref]$uri)) {
        return $Link.Trim().ToLowerInvariant()
    }
    $hostPart = $uri.Host.ToLowerInvariant()
    if ($hostPart.StartsWith('www.')) { $hostPart = $hostPart.Substring(4) }
    $path = $uri.AbsolutePath
    if ([string]::IsNullOrEmpty($path)) { $path = '/' }

    $keep = New-Object System.Collections.Generic.List[string]
    if ($uri.Query) {
        $qs = $uri.Query.TrimStart('?')
        foreach ($pair in ($qs -split '&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) { continue }
            $name = ($pair -split '=', 2)[0]
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $lower = $name.ToLowerInvariant()
            if ($lower.StartsWith('utm_') -or $lower -eq 'fbclid' -or $lower -eq 'gclid' -or $lower -eq 'mc_eid') { continue }
            $keep.Add($pair)
        }
    }
    $query = if ($keep.Count -gt 0) { '?' + ($keep -join '&') } else { '' }
    return "$($uri.Scheme.ToLowerInvariant())://$hostPart$path$query"
}

function Get-Sha1Hex {
    param([string]$s)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))
        return (-join ($bytes | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

function Get-ArticleKey {
    param(
        [string]$Link,
        [string]$Source,
        [string]$Title
    )
    if (-not [string]::IsNullOrWhiteSpace($Link)) {
        $canonical = Get-CanonicalUrl -Link $Link
        if ($canonical) { return Get-Sha1Hex $canonical }
    }
    $fallback = ([string]$Source + '|' + [string]$Title).Trim()
    return Get-Sha1Hex $fallback
}
