# TextEncoding.ps1 — UTF-8 HTTP/text helpers for RSS ingest and JSON I/O

function Set-Utf8Environment {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    } catch { }
    try {
        $OutputEncoding = [System.Text.Encoding]::UTF8
    } catch { }
}

function Get-HttpText {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$UserAgent = 'ThreatFeed-Analyzer/1.0'
    )

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', $UserAgent)
    $bytes = $wc.DownloadData($Url)

    $encoding = [System.Text.Encoding]::UTF8
    $probeLen = [Math]::Min(1024, $bytes.Length)
    if ($probeLen -gt 0) {
        $head = $encoding.GetString($bytes, 0, $probeLen)
        if ($head -match '(?i)encoding\s*=\s*["'']([^"'']+)["'']') {
            try { $encoding = [System.Text.Encoding]::GetEncoding($Matches[1].Trim()) } catch { }
        }
    }

    return $encoding.GetString($bytes)
}

function Repair-MojibakeText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    if ($Text -notmatch '\u00c3|\u00e2|\u0192|\u00c6') { return $Text }

    $latin1 = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
    $utf8 = [System.Text.Encoding]::UTF8
    $cur = $Text

    for ($i = 0; $i -lt 4; $i++) {
        try {
            $next = $utf8.GetString($latin1.GetBytes($cur))
        } catch {
            break
        }
        if ($next -eq $cur) { break }
        if ($next -match '\u00c3|\u00e2|\u0192|\u00c6' -and $next.Length -ge $cur.Length) { break }
        $cur = $next
    }

    return $cur
}

function Normalize-FeedText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = [System.Net.WebUtility]::HtmlDecode([string]$Text)
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    return (Repair-MojibakeText -Text $t)
}
