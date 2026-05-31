#Requires -Version 5.1
$script:LibRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:LibRoot 'lib\PromptLoader.ps1')
$script:PromptsDir = Join-Path $script:LibRoot 'prompts'

Describe 'Invoke-PromptSubstitution' {
    It 'replaces known variables' {
        $t = 'Hello {{date}} - {{keywords}}'
        $out = Invoke-PromptSubstitution -Template $t -Variables @{ date = '2026-05-31'; keywords = 'APT, CVE' }
        $out | Should Be 'Hello 2026-05-31 - APT, CVE'
    }

    It 'leaves unknown tokens unchanged' {
        $out = Invoke-PromptSubstitution -Template '{{missing}}' -Variables @{}
        $out | Should Be '{{missing}}'
    }
}

Describe 'Get-LoadedPrompt' {
    It 'loads shift-brief template from manifest' {
        $vars = @{
            date         = '2026-05-31'
            topArticles  = '1. Test article'
            keywords     = 'APT'
            mitreTop     = 'T1055'
            cveCount     = '10'
            cveDays      = '7'
        }
        $text = Get-LoadedPrompt -PromptsDir $script:PromptsDir -PromptId 'shift-brief' -Variables $vars
        $text | Should Not BeNullOrEmpty
        ($text -match '2026-05-31') | Should Be $true
        ($text -match '\{\{date\}\}') | Should Be $false
    }

    It 'HTML-escapes when requested' {
        $vars = @{
            articleTitle      = '<script>alert(1)</script>'
            articleLink       = 'https://example.com'
            articleSummary    = 'x'
            matchedKeywords   = 'APT'
            mitreTechniques   = 'T1055'
        }
        $text = Get-LoadedPrompt -PromptsDir $script:PromptsDir -PromptId 'article-analyst' -Variables $vars -HtmlEscape
        ($text -match '<script>') | Should Be $false
        ($text -match '&lt;script&gt;') | Should Be $true
    }
}

Describe 'Escape-PromptForHtml' {
    It 'escapes angle brackets' {
        Escape-PromptForHtml '<b>x</b>' | Should Be '&lt;b&gt;x&lt;/b&gt;'
    }
}
