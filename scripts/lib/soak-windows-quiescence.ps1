function Get-Median([object[]]$Values) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { throw "Median requires samples" }
    $middle = [Math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}


function Wait-GitLamaQuiescentWindow {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Sample,
        [Parameter(Mandatory = $true)]$Policy,
        $Baseline = $null,
        [int]$DeadlineSeconds = 60,
        [scriptblock]$Clock = { [Diagnostics.Stopwatch]::GetTimestamp() / [double][Diagnostics.Stopwatch]::Frequency },
        [scriptblock]$Pause = { Start-Sleep -Seconds 1 }
    )
    $deadline = (& $Clock) + $DeadlineSeconds
    $all = [Collections.Generic.List[object]]::new()
    $window = @()
    do {
        $all.Add((& $Sample))
        $first = [Math]::Max(0, $all.Count - $Policy.minimumQuiescentSamples)
        $window = @($all.ToArray()[$first..($all.Count - 1)])
        $accepted = $window.Count -ge $Policy.minimumQuiescentSamples -and
            @($window | Where-Object { $_.children -ne $Policy.requiredQuiescentChildren }).Count -eq 0
        if ($accepted -and $null -ne $Baseline) {
            $threads = Get-Median @($window | ForEach-Object { $_.threads })
            $handles = Get-Median @($window | ForEach-Object { $_.openFiles })
            $accepted = ($threads - $Baseline.threads) -le $Policy.maximumQuiescentThreadGrowth -and
                ($handles - $Baseline.openFiles) -le $Policy.maximumQuiescentOpenFileGrowth
        }
        if ($accepted -or (& $Clock) -ge $deadline) { break }
        & $Pause
    } while ($true)
    return [pscustomobject]@{
        accepted = $accepted
        samples = $window
        settlingSamples = $all.ToArray()
    }
}
