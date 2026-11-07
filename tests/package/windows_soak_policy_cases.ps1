$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '../../scripts/validate-windows-installer.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'MSI validator parse failed' }
# Execute the production soak block without installing an MSI or launching a GUI.
$soakBlock = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text.StartsWith('if ($SoakSeconds -gt 0)')
}, $true)
if (-not $soakBlock) { throw 'MSI soak block missing' }
$runSoak = [scriptblock]::Create($soakBlock.Extent.Text)
function Assert-Case($Condition, [string]$Name) {
    if (-not $Condition) { throw "Soak policy regression: $Name" }
}
function Invoke-Case([bool]$Advisory, [string]$Mode, [int]$Seconds = 600) {
    $SoakAdvisory = $Advisory
    $SoakSeconds = $Seconds
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gitlama-soak-policy-' + [guid]::NewGuid().ToString('N'))
    $SoakOutputPath = Join-Path $root 'report.json'
    $installedExe = 'unused fixture executable'
    $soakResult = 'not-run'
    $soakExitCode = $null
    $threw = $false
    $invoked = $false
    $measuredReport = '{"acceptance":{"passed":false,"failures":["rss_slope"]},"samples":[{"rssKiB":1234}]}'
    function powershell {
        Set-Variable -Name invoked -Value $true -Scope 1
        if ($Mode -eq 'throw') { throw 'fixture stderr failure' }
        if ($Mode -eq 'success') {
            [System.IO.File]::WriteAllText($SoakOutputPath, '{"acceptance":{"passed":true},"samples":[{}]}')
            $global:LASTEXITCODE = 0
        } elseif ($Mode -eq 'resource') {
            [System.IO.File]::WriteAllText($SoakOutputPath, $measuredReport)
            $global:LASTEXITCODE = 1
        } else {
            $global:LASTEXITCODE = $(if ($Mode -eq 'missing') { 0 } else { 1 })
        }
    }
    try {
        [System.IO.Directory]::CreateDirectory($root) | Out-Null
        # Must not accept an earlier candidate's successful report.
        [System.IO.File]::WriteAllText($SoakOutputPath, '{"stale":true}')
        try { . $runSoak } catch { $threw = $true }
        if ($Seconds -eq 0) {
            Assert-Case ($soakResult -eq 'not-run' -and -not $invoked -and -not $threw) 'disabled soak remains not-run'
            return
        }
        $reportText = Get-Content -Raw -LiteralPath $SoakOutputPath
        $report = $reportText | ConvertFrom-Json
        if ($Mode -eq 'success') {
            Assert-Case (-not $threw -and $soakResult -eq 'passed' -and $soakExitCode -eq 0) 'successful soak passes in either mode'
            Assert-Case $report.acceptance.passed 'successful report retained'
        } else {
            Assert-Case ($threw -eq (-not $Advisory)) 'only advisory soak failures continue'
            Assert-Case ($soakResult -eq 'failed') 'failure never reported as passed'
            Assert-Case (-not $report.acceptance.passed) 'failed report stays failed'
            if ($Mode -eq 'resource') {
                Assert-Case ($reportText -ceq $measuredReport) 'raw measurement report preserved byte for byte'
            } else {
                Assert-Case ($report.acceptance.failures -contains 'soak_incomplete') 'early failure has explicit incomplete report'
                Assert-Case ($report.samples.Count -eq 0) 'incomplete report invents no samples'
            }
        }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
foreach ($advisory in @($false, $true)) {
    foreach ($mode in @('success', 'resource', 'startup', 'throw', 'missing')) {
        Invoke-Case $advisory $mode
    }
}
Invoke-Case $true 'success' 0
Write-Output 'Windows soak policy regressions passed'
