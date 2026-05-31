#Requires -Version 5.1
$script:LibRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:LibRoot 'lib\TextEncoding.ps1')

Describe 'Normalize-FeedText' {
    It 'decodes HTML entities' {
        Normalize-FeedText 'Foo &amp; Bar' | Should Be 'Foo & Bar'
    }

    It 'leaves plain ASCII unchanged' {
        Normalize-FeedText 'GTIG AI Threat Tracker' | Should Be 'GTIG AI Threat Tracker'
    }

    It 'preserves UTF-8 umlauts' {
        $umlaut = [char]0x00DC
        $title = "The German Cyber Criminal ${umlaut}berfall: Shifts in Europe's Data Leak Landscape"
        Normalize-FeedText $title | Should Be $title
    }
}

Describe 'Get-HttpText' {
    It 'returns UTF-8 RSS from Mandiant feed' {
        $xml = Get-HttpText -Url 'https://www.mandiant.com/resources/blog/rss.xml' -UserAgent 'ThreatFeed-Analyzer-Test/1.0'
        $xml | Should Match 'German Cyber Criminal'
        $xml | Should Not Match '\u00c3\u00a6'
    }
}

