# DashboardExport.ps1 — write dashboard/public/data for the hosted React app
# Dot-source from ThreatFeed-Analyzer.ps1 or Sync-DashboardData.ps1

function ConvertTo-DashboardArticle {
    param($Article, [hashtable]$ScoreByKey = @{})
    $key = $null
    if ($Article.ArticleKey) { $key = [string]$Article.ArticleKey }
    elseif ($Article.key) { $key = [string]$Article.key }
    else { $key = Get-ArticleKey -Link $Article.Link -Source $Article.Source -Title $Article.Title }

    $pub = ''
    if ($Article.Published -is [datetime]) { $pub = $Article.Published.ToString('yyyy-MM-ddTHH:mm:ss') }
    elseif ($Article.published) { $pub = [string]$Article.published }

    $mitre = @()
    $src = if ($Article.Mitre) { $Article.Mitre } else { $Article.mitre }
    foreach ($t in @($src)) {
        if ($t -and $t.id) { $mitre += @{ id = [string]$t.id; name = [string]$t.name } }
    }

    $kw = @()
    $kwSrc = if ($Article.MatchedKeywords) { $Article.MatchedKeywords } else { $Article.keywords }
    foreach ($k in @($kwSrc)) { if ($k) { $kw += [string]$k } }

    $out = [ordered]@{
        key       = $key
        title     = if ($Article.Title) { [string]$Article.Title } else { [string]$Article.title }
        link      = if ($Article.Link) { [string]$Article.Link } else { [string]$Article.link }
        summary   = if ($Article.Summary) { [string]$Article.Summary } else { [string]$Article.summary }
        source    = if ($Article.Source) { [string]$Article.Source } else { [string]$Article.source }
        category  = if ($Article.Category) { [string]$Article.Category } else { [string]$Article.category }
        published = $pub
        firstSeen = if ($Article.FirstSeen) { [string]$Article.FirstSeen } elseif ($Article.firstSeen) { [string]$Article.firstSeen } else { '' }
        keywords  = $kw
        mitre     = $mitre
    }

    if ($ScoreByKey.ContainsKey($key)) {
        $s = $ScoreByKey[$key]
        $out['priorityScore'] = [int]$s.PriorityScore
        $out['reasonChips']   = @($s.ReasonChips)
        $out['isNew']         = [bool]$s.IsNewArticle
    } elseif ($null -ne $Article.PriorityScore) {
        $out['priorityScore'] = [int]$Article.PriorityScore
        $out['reasonChips']   = @($Article.ReasonChips)
        $out['isNew']         = [bool]$Article.IsNewArticle
    }

    return [pscustomobject]$out
}

function Export-DashboardData {
    param(
        [string]$DashboardDir,
        $Stats,
        $ShiftBrief,
        $DisplayArticles,
        $KeywordCounts,
        $MitreCounts,
        $Platform,
        $Cves,
        $RunMeta,
        [int]$CveDays = 7,
        [string]$NvdBanner,
        [int]$MaxCves = 150,
        [int]$MaxArticles = 500
    )

    if (-not $DashboardDir) { throw 'DashboardDir is required.' }
    $publicData = Join-Path $DashboardDir 'public\data'
    if (-not (Test-Path $publicData)) { New-Item -ItemType Directory -Path $publicData -Force | Out-Null }

    $scoreByKey = @{}
    foreach ($a in @($ShiftBrief)) {
        if ($a -and $a.ArticleKey) { $scoreByKey[[string]$a.ArticleKey] = $a }
    }

    $shiftOut = @($ShiftBrief | ForEach-Object { ConvertTo-DashboardArticle -Article $_ })
    $articlesOut = @($DisplayArticles | Select-Object -First $MaxArticles | ForEach-Object {
        ConvertTo-DashboardArticle -Article $_ -ScoreByKey $scoreByKey
    })

    $cveSlice = @($Cves | Select-Object -First $MaxCves | ForEach-Object {
        [ordered]@{
            id          = [string]$_.Id
            published   = if ($_.Published -is [datetime]) { $_.Published.ToString('yyyy-MM-dd') } else { [string]$_.Published }
            score       = if ($null -ne $_.Score) { [double]$_.Score } else { $null }
            severity    = [string]$_.Severity
            description = if ($_.Description.Length -gt 280) { $_.Description.Substring(0, 280) } else { [string]$_.Description }
        }
    })

    $tracking = @()
    if ($Platform -and $Platform.Tracking) {
        foreach ($row in @($Platform.Tracking)) {
            $tracking += [ordered]@{
                topic    = [string]$row.topic
                total    = [int]$row.total
                last7    = [int]$row.last7
                prev7    = [int]$row.prev7
                trend    = [string]$row.trend
                lastSeen = [string]$row.lastSeen
                spark    = @($row.spark)
            }
        }
    }

    $trendSeries = @()
    if ($Platform -and $Platform.TrendSeries) {
        foreach ($ts in @($Platform.TrendSeries)) {
            $trendSeries += [ordered]@{ topic = [string]$ts.topic; values = @($ts.values) }
        }
    }

    $bundle = [ordered]@{
        version     = 1
        generatedAt = if ($RunMeta -and $RunMeta.generatedAt) { [string]$RunMeta.generatedAt } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
        runMeta     = $RunMeta
        stats       = [ordered]@{
            generatedAt  = [string]$Stats.GeneratedAt
            feedsTotal   = [int]$Stats.FeedsTotal
            feedsOk      = [int]$Stats.FeedsOk
            fetched      = [int]$Stats.Fetched
            matched      = [int]$Stats.Matched
            new          = [int]$Stats.New
            duplicates   = [int]$Stats.Duplicates
            cveCount     = [int]$Stats.CveCount
            totalTracked = [int]$Stats.TotalTracked
            topicCount   = [int]$Stats.TopicCount
            cveDays      = [int]$CveDays
            nvdWarning   = $NvdBanner
        }
        shiftBrief  = $shiftOut
        articles    = $articlesOut
        aggregates  = [ordered]@{
            keywords = [ordered]@{ labels = @($KeywordCounts.labels); values = @($KeywordCounts.values) }
            mitre    = [ordered]@{ labels = @($MitreCounts.labels); values = @($MitreCounts.values) }
        }
        tracking    = [ordered]@{
            rows        = $tracking
            trendDays   = if ($Platform -and $Platform.TrendDays) { @($Platform.TrendDays) } else { @() }
            trendSeries = $trendSeries
        }
        cves        = $cveSlice
    }

    $bundlePath = Join-Path $publicData 'dashboard.json'
    $json = $bundle | ConvertTo-Json -Depth 8 -Compress
    [System.IO.File]::WriteAllText($bundlePath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Mirror split files for debugging / partial reloads
    $mirrors = @{
        'run-meta.json'    = $RunMeta
        'shift-brief.json' = $shiftOut
        'articles.json'    = $articlesOut
        'cves.json'        = $cveSlice
    }
    foreach ($kv in $mirrors.GetEnumerator()) {
        $j = $kv.Value | ConvertTo-Json -Depth 8 -Compress
        [System.IO.File]::WriteAllText((Join-Path $publicData $kv.Key), $j, (New-Object System.Text.UTF8Encoding($false)))
    }

    return $bundlePath
}
