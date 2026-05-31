#Requires -Version 5.1
$script:LibRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:LibRoot 'lib\ArticleKey.ps1')
. (Join-Path $script:LibRoot 'lib\Scoring.ps1')

Describe 'Get-PriorityScore' {
    It 'returns 4 for minimal News article' {
        Get-PriorityScore -Category 'News' -MatchedKeywords @() -Mitre @() -IsNew:$false -TopicTrend 'flat' |
            Should Be 4
    }

    It 'adds Research tier +12' {
        Get-PriorityScore -Category 'Research' -MatchedKeywords @() -Mitre @() |
            Should Be 12
    }

    It 'caps keyword hits at +15' {
        $kws = 1..10 | ForEach-Object { "kw$_" }
        $s = Get-PriorityScore -Category 'News' -MatchedKeywords $kws -Mitre @()
        $s | Should Be 19
    }

    It 'caps MITRE at +12' {
        $mitre = 1..5 | ForEach-Object { [pscustomobject]@{ id = "T10$_"; name = 'X' } }
        $s = Get-PriorityScore -Category 'News' -MatchedKeywords @() -Mitre $mitre
        $s | Should Be 16
    }

    It 'adds +10 for novelty' {
        $base = Get-PriorityScore -Category 'News' -MatchedKeywords @('APT') -Mitre @() -IsNew:$false
        $novel = Get-PriorityScore -Category 'News' -MatchedKeywords @('APT') -Mitre @() -IsNew:$true
        ($novel - $base) | Should Be 10
    }

    It 'adds trend points up=6 down=3' {
        $up = Get-PriorityScore -Category 'News' -MatchedKeywords @() -Mitre @() -TopicTrend 'up'
        $down = Get-PriorityScore -Category 'News' -MatchedKeywords @() -Mitre @() -TopicTrend 'down'
        $flat = Get-PriorityScore -Category 'News' -MatchedKeywords @() -Mitre @() -TopicTrend 'flat'
        ($up - $flat) | Should Be 6
        ($down - $flat) | Should Be 3
    }

    It 'maxes out at 55 for fully-loaded Research article' {
        $kws = 1..10 | ForEach-Object { "k$_" }
        $mitre = 1..10 | ForEach-Object { [pscustomobject]@{ id = "T$_"; name = 'M' } }
        Get-PriorityScore -Category 'Research' -MatchedKeywords $kws -Mitre $mitre -IsNew:$true -TopicTrend 'up' |
            Should Be 55
    }

    It 'never exceeds 100' {
        $s = Get-PriorityScore -Category 'Research' -MatchedKeywords @('APT','CVE') -Mitre @() -IsNew:$true -TopicTrend 'up'
        ($s -le 100) | Should Be $true
    }
}

Describe 'Get-ReasonChips' {
    It 'returns max 4 chips' {
        $chips = Get-ReasonChips -Category 'Research' -MatchedKeywords @('a','b','c') `
            -Mitre @(
                [pscustomobject]@{ id='T1'; name='A' },
                [pscustomobject]@{ id='T2'; name='B' },
                [pscustomobject]@{ id='T3'; name='C' }
            ) -IsNew:$true -TopicTrend 'up'
        ($chips.Count -le 4) | Should Be $true
    }

    It 'includes NEW and RESEARCH when applicable' {
        $chips = Get-ReasonChips -Category 'Research' -MatchedKeywords @() -Mitre @() -IsNew:$true
        ($chips -contains 'NEW') | Should Be $true
        ($chips -contains 'RESEARCH') | Should Be $true
    }

    It 'emits NxMITRE chip when 3+ techniques' {
        $mitre = 1..3 | ForEach-Object { [pscustomobject]@{ id = "T10$_"; name = 'X' } }
        $chips = Get-ReasonChips -Category 'News' -MatchedKeywords @() -Mitre $mitre
        ($chips -contains '3xMITRE') | Should Be $true
    }
}

Describe 'Sort-ByPriorityScore' {
    It 'sorts by score then published then title' {
        $articles = @(
            [pscustomobject]@{ Title='B'; PriorityScore=50; Published=[datetime]'2026-05-30'; Mitre=@() },
            [pscustomobject]@{ Title='A'; PriorityScore=50; Published=[datetime]'2026-05-31'; Mitre=@() },
            [pscustomobject]@{ Title='C'; PriorityScore=80; Published=$null; Mitre=@() }
        )
        $sorted = Sort-ByPriorityScore -Articles $articles
        $sorted[0].Title | Should Be 'C'
        $sorted[1].Title | Should Be 'A'
        $sorted[2].Title | Should Be 'B'
    }
}
