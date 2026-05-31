# Scoring.ps1 — deterministic PriorityScore for B-Seed (pure PowerShell)
# Dot-source from ThreatFeed-Analyzer.ps1

function Get-SourceTierPoints {
    param([string]$Category)
    switch -Regex ($Category) {
        '^Research$' { return 12 }
        '^Official$' { return 8 }
        default      { return 4 }
    }
}

function Get-TopicTrendForKeywords {
    param(
        $Tracking,
        [string[]]$MatchedKeywords
    )
    if (-not $Tracking -or -not $MatchedKeywords -or $MatchedKeywords.Count -eq 0) { return 'flat' }
    $byTopic = @{}
    foreach ($row in @($Tracking)) {
        if ($row -and $row.topic) { $byTopic[[string]$row.topic.ToLowerInvariant()] = [string]$row.trend }
    }
    $best = 'flat'
    foreach ($kw in $MatchedKeywords) {
        $k = [string]$kw
        if (-not $k) { continue }
        $t = $null
        if ($byTopic.ContainsKey($k.ToLowerInvariant())) { $t = $byTopic[$k.ToLowerInvariant()] }
        if ($t -eq 'up')   { return 'up' }
        if ($t -eq 'down' -and $best -ne 'up') { $best = 'down' }
    }
    return $best
}

function Get-PriorityScore {
    param(
        [string]$Category,
        [string[]]$MatchedKeywords,
        $Mitre,
        [bool]$IsNew = $false,
        [string]$TopicTrend = 'flat'
    )
    $score = 0
    $score += Get-SourceTierPoints -Category $Category

    $kwHits = @($MatchedKeywords | Where-Object { $_ -and $_.Trim() }).Count
    $score += [Math]::Min($kwHits * 3, 15)

    $mitreCount = @($Mitre | Where-Object { $_ -and $_.id }).Count
    $score += [Math]::Min($mitreCount * 4, 12)

    if ($IsNew) { $score += 10 }

    switch ($TopicTrend) {
        'up'   { $score += 6 }
        'down' { $score += 3 }
        default { }
    }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    return [int]$score
}

function Get-ReasonChips {
    param(
        [string]$Category,
        [string[]]$MatchedKeywords,
        $Mitre,
        [bool]$IsNew = $false,
        [string]$TopicTrend = 'flat'
    )
    $chips = New-Object System.Collections.Generic.List[string]

    if ($IsNew) { $chips.Add('NEW') }
    if ($TopicTrend -eq 'up')   { $chips.Add('TREND-UP') }
    if ($TopicTrend -eq 'down') { $chips.Add('TREND-DOWN') }
    if ($Category -eq 'Research') { $chips.Add('RESEARCH') }
    elseif ($Category -eq 'Official') { $chips.Add('OFFICIAL') }

    $mitreCount = @($Mitre | Where-Object { $_ -and $_.id }).Count
    if ($mitreCount -ge 3) { $chips.Add(("{0}xMITRE" -f $mitreCount)) }

    return @($chips | Select-Object -First 4)
}

function Add-ArticleScoring {
    param(
        $Article,
        $Tracking,
        [hashtable]$SeenKeys,
        [switch]$NoDedup
    )
    $key = Get-ArticleKey -Link $Article.Link -Source $Article.Source -Title $Article.Title
    $isNew = $true
    if (-not $NoDedup -and $SeenKeys -and $SeenKeys.ContainsKey($key)) { $isNew = $false }

    $trend = Get-TopicTrendForKeywords -Tracking $Tracking -MatchedKeywords @($Article.MatchedKeywords)
    $score = Get-PriorityScore -Category $Article.Category -MatchedKeywords @($Article.MatchedKeywords) `
        -Mitre $Article.Mitre -IsNew $isNew -TopicTrend $trend
    $reasons = @(Get-ReasonChips -Category $Article.Category -MatchedKeywords @($Article.MatchedKeywords) `
        -Mitre $Article.Mitre -IsNew $isNew -TopicTrend $trend)

    # Return a fresh record — Add-Member with collection values throws on PS 5.1.
    return [pscustomobject]@{
        Title           = [string]$Article.Title
        Link            = [string]$Article.Link
        Summary         = [string]$Article.Summary
        Published       = $Article.Published
        Source          = [string]$Article.Source
        Category        = [string]$Article.Category
        MatchedKeywords = @($Article.MatchedKeywords)
        Mitre           = @($Article.Mitre)
        ArticleKey      = $key
        PriorityScore   = $score
        ReasonChips     = $reasons
        IsNewArticle    = $isNew
    }
}

function Get-SortPublishedTicks {
    param($Article)
    $p = $Article.Published
    if ($p -is [datetime]) { return $p.Ticks }
    if ($null -eq $p -or [string]::IsNullOrWhiteSpace([string]$p)) { return [datetime]::MinValue.Ticks }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse([string]$p, [ref]$d)) { return $d.Ticks }
    return [datetime]::MinValue.Ticks
}

function Sort-ByPriorityScore {
    param($Articles)
    # Stable multi-pass sort — PS 5.1 multi-key Sort-Object fails on mixed property types.
    $a = @($Articles)
    $a = @($a | Sort-Object { [string]$_.Title })
    $a = @($a | Sort-Object @{ Expression = { Get-SortPublishedTicks $_ }; Descending = $true })
    $a = @($a | Sort-Object @{ Expression = { [int](@($_.Mitre | Where-Object { $_ -and $_.id }).Count) }; Descending = $true })
    $a = @($a | Sort-Object @{ Expression = { [int]$_.PriorityScore }; Descending = $true })
    return @($a)
}
