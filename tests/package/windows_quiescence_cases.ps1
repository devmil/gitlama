$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../scripts/lib/soak-windows-quiescence.ps1')
$policy = @{ minimumQuiescentSamples = 5; requiredQuiescentChildren = 0; maximumQuiescentThreadGrowth = 4; maximumQuiescentOpenFileGrowth = 4 }
function Assert-Case($Condition, [string]$Name) {
    if (-not $Condition) { throw "Quiescence regression: $Name" }
}
function Measure-Case([object[]]$Samples, $Baseline, [int]$Deadline = 10) {
    $state = [pscustomobject]@{ now = 0; index = 0 }
    $sample = {
        $at = [Math]::Min($state.index, $Samples.Count - 1)
        $state.index += 1
        return $Samples[$at]
    }.GetNewClosure()
    $clock = { return $state.now }.GetNewClosure()
    $pause = { $state.now += 1 }.GetNewClosure()
    return Wait-GitLamaQuiescentWindow -Sample $sample -Policy $policy -Baseline $Baseline -DeadlineSeconds $Deadline -Clock $clock -Pause $pause
}
$normal = [pscustomobject]@{ threads = 10; openFiles = 20; children = 0 }
$busy = [pscustomobject]@{ threads = 30; openFiles = 40; children = 1 }
$growth = [pscustomobject]@{ threads = 30; openFiles = 40; children = 0 }
$recovered = Measure-Case @($busy, $busy, $busy, $normal, $normal, $normal, $normal, $normal) $normal
Assert-Case $recovered.accepted 'trailing workload can drain'
Assert-Case ($recovered.settlingSamples.Count -eq 8) 'every attempted sample retained'
Assert-Case (@($recovered.samples | Where-Object { $_.children -ne 0 }).Count -eq 0) 'entire admitted window child-free'
$persistentChild = Measure-Case @($busy) $normal
Assert-Case (-not $persistentChild.accepted) 'persistent child stays fatal'
Assert-Case ($persistentChild.settlingSamples.Count -eq 11) 'deadline bounds settling'
$persistentGrowth = Measure-Case @($growth) $normal
Assert-Case (-not $persistentGrowth.accepted) 'persistent resource growth stays fatal'
Assert-Case ($persistentGrowth.samples.Count -eq 5) 'failed final window retained'
$short = Measure-Case @($normal) $null 2
Assert-Case (-not $short.accepted) 'insufficient samples refuse acceptance'
$boundary = Measure-Case @([pscustomobject]@{ threads = 14; openFiles = 24; children = 0 }) $normal
Assert-Case $boundary.accepted 'original inclusive growth budget retained'
$overBoundary = Measure-Case @([pscustomobject]@{ threads = 15; openFiles = 25; children = 0 }) $normal
Assert-Case (-not $overBoundary.accepted) 'one above growth budget refused'
$recordedEndpoint = Measure-Case @([pscustomobject]@{ threads = 99; openFiles = 472; children = 0 }) ([pscustomobject]@{ threads = 72; openFiles = 468 })
Assert-Case (-not $recordedEndpoint.accepted) 'recorded thread growth stays fatal if it never drains'
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '../../scripts/soak-windows.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-Case ($parseErrors.Count -eq 0) 'main soak script parses'
Write-Output 'Windows quiescence regressions passed'
