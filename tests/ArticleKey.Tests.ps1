#Requires -Version 5.1
$script:LibRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:LibRoot 'lib\ArticleKey.ps1')

Describe 'Get-ArticleKey' {
    It 'returns same key for URL with and without UTM params' {
        $base = 'https://Example.COM/path/article?utm_source=twitter&utm_medium=social&id=42'
        $clean = 'https://example.com/path/article?id=42'
        $k1 = Get-ArticleKey -Link $base -Source 'Test' -Title 'Title A'
        $k2 = Get-ArticleKey -Link $clean -Source 'Test' -Title 'Title B'
        $k1 | Should Be $k2
    }

    It 'strips fbclid from canonical URL' {
        $with = 'https://news.example.com/story?fbclid=abc123'
        $without = 'https://news.example.com/story'
        Get-ArticleKey -Link $with -Source 'S' -Title 'T' |
            Should Be (Get-ArticleKey -Link $without -Source 'S' -Title 'T')
    }

    It 'lowercases host and removes www prefix' {
        $a = Get-ArticleKey -Link 'https://WWW.Example.com/Path/' -Source 'S' -Title 'T'
        $b = Get-ArticleKey -Link 'https://example.com/Path/' -Source 'S' -Title 'T'
        $a | Should Be $b
    }

    It 'falls back to source|title when link is empty' {
        $k = Get-ArticleKey -Link '' -Source 'FeedName' -Title 'Some Title'
        $k | Should Match '^[a-f0-9]{40}$'
        Get-ArticleKey -Link '' -Source 'FeedName' -Title 'Some Title' | Should Be $k
    }

    It 'produces different keys for different titles when link empty' {
        $a = Get-ArticleKey -Link '' -Source 'Feed' -Title 'Alpha'
        $b = Get-ArticleKey -Link '' -Source 'Feed' -Title 'Beta'
        $a | Should Not Be $b
    }

    It 'returns 40-char hex SHA1' {
        $k = Get-ArticleKey -Link 'https://example.com/x' -Source 'S' -Title 'T'
        $k.Length | Should Be 40
        $k | Should Match '^[a-f0-9]{40}$'
    }
}

Describe 'Get-CanonicalUrl' {
    It 'preserves non-tracking query params' {
        Get-CanonicalUrl 'https://example.com/a?foo=bar&utm_campaign=x' |
            Should Be 'https://example.com/a?foo=bar'
    }
}
