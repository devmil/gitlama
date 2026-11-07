param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [int]$DurationSeconds = 600,
    [Parameter(Mandatory = $true)][string]$ReportPath
)

$ErrorActionPreference = "Stop"
if ($DurationSeconds -lt 60) { throw "Windows soak requires at least 60 seconds" }
$executablePath = [System.IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Packaged Windows executable does not exist"
}

$policy = [ordered]@{
    maximumSteadyRssSlopeKiBPerSecond = 48.0
    maximumQuiescentThreadGrowth = 4
    maximumQuiescentOpenFileGrowth = 4
    requiredQuiescentChildren = 0
    minimumQuiescentSamples = 5
    maximumQuiescentSettleSeconds = 60
}

. (Join-Path $PSScriptRoot "lib/soak-windows-quiescence.ps1")

function Get-Percentile([object[]]$Values, [double]$Fraction) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { throw "Percentile requires samples" }
    $index = [int][Math]::Round(($ordered.Count - 1) * $Fraction)
    return [double]$ordered[$index]
}

function Get-Slope([object[]]$Samples) {
    if ($Samples.Count -eq 0) { throw "Slope requires samples" }
    $xMean = ($Samples | Measure-Object -Property elapsedSeconds -Average).Average
    $yMean = ($Samples | Measure-Object -Property rssKiB -Average).Average
    $numerator = 0.0
    $denominator = 0.0
    foreach ($sample in $Samples) {
        $x = [double]$sample.elapsedSeconds - [double]$xMean
        $y = [double]$sample.rssKiB - [double]$yMean
        $numerator += $x * $y
        $denominator += $x * $x
    }
    if ($denominator -eq 0.0) { return 0.0 }
    return $numerator / $denominator
}

function Get-ResourceSample([int]$ApplicationProcessId, [Diagnostics.Stopwatch]$Timer) {
    try {
        $process = Get-Process -Id $ApplicationProcessId -ErrorAction Stop
        if ($process.HasExited) { throw "Packaged Windows application exited" }
        $childProcesses = @(
            Get-CimInstance Win32_Process -Filter "ParentProcessId = $ApplicationProcessId" `
                -ErrorAction Stop -OperationTimeoutSec 5
        )
        $childKinds = @($childProcesses | ForEach-Object {
            switch -Regex ($_.Name) {
                '^git(?:-[a-z-]+)?\.exe$' { "git"; break }
                '^conhost\.exe$' { "console-host"; break }
                default { "other" }
            }
        })
        return [pscustomobject][ordered]@{
            elapsedSeconds = [Math]::Round($Timer.Elapsed.TotalSeconds, 3)
            rssKiB = [int64][Math]::Round($process.WorkingSet64 / 1KB)
            threads = @($process.Threads).Count
            openFiles = [int]$process.HandleCount
            children = [int]$childProcesses.Count
            childKinds = $childKinds
        }
    } catch {
        throw "Packaged Windows process metrics are unavailable"
    }
}

function New-StartInfo([string]$Arguments, [string]$ProfileRoot, [string]$WorkingDirectory) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executablePath
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.Environment["GITLAMA_PROFILE_ROOT"] = $ProfileRoot
    return $start
}

function Invoke-Forwarded([string]$Arguments, [string]$ProfileRoot, [string]$WorkingDirectory, [string]$Phase) {
    $process = [Diagnostics.Process]::new()
    $started = $false
    $process.StartInfo = New-StartInfo $Arguments $ProfileRoot $WorkingDirectory
    $process.StartInfo.Environment["GITLAMA_FORWARDING_DIAGNOSTICS"] = "1"
    $process.StartInfo.RedirectStandardError = $true
    try {
        if (-not $process.Start()) { throw "Forwarded Windows invocation did not start" }
        $started = $true
        if (-not $process.WaitForExit(20000)) {
            $process.Kill()
            throw "Forwarded Windows $Phase invocation timed out"
        }
        if ($process.ExitCode -ne 0) {
            $diagnostic = $process.StandardError.ReadToEnd()
            $failure = "unknown"
            $detail = "unknown"
            if ($diagnostic -match '(?m)^gitlama_forwarding_failure=(unsupportedPlatform|invalidArguments|notRunning|authentication|versionSkew|invalidPath|notRepository|busy|precondition|transport|unknown)\r?$') {
                $failure = $Matches[1]
            }
            if ($diagnostic -match '(?m)^gitlama_windows_ipc=(load_token|random_nonce|connect|encode_request|write_request|read_response):(io_[0-9]+|[a-z_]+)\r?$') {
                $detail = "$($Matches[1])_$($Matches[2])"
            }
            throw "Forwarded Windows $Phase invocation failed with exit code $($process.ExitCode), failure $failure, detail $detail"
        }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

function Wait-RepositoryRefresh([string]$ProfileRoot, [string]$WorkingDirectory, [Diagnostics.Process]$Application) {
    # Opening a repository is accepted before its session becomes active, and a
    # slow runner can miss the app's two-second response window (busy). Retry
    # only those transient rejections and count busy ones in the report; other
    # forwarding failures remain fatal.
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while ($true) {
        if ($Application.HasExited) { throw "Packaged Windows application exited before repository refresh" }
        try {
            Invoke-Forwarded '"--command" "repository.refresh"' $ProfileRoot $WorkingDirectory "refresh"
            return
        } catch {
            if ($_.Exception.Message -notmatch '^Forwarded Windows refresh invocation failed with exit code 2, failure (precondition|busy), detail [a-z0-9_]+$') {
                throw
            }
            if ($Matches[1] -eq "busy") { $script:busyRetries += 1 }
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Packaged Windows repository refresh readiness timed out; last failure $($Matches[1])"
            }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Stop-ApplicationTree([Diagnostics.Process]$Application) {
    if ($Application.HasExited) { return }

    # PowerShell 5.1 turns native stderr into a terminating error under Stop.
    # taskkill can report a child that exited during /T while the app itself
    # was terminated. Check the process state rather than taskkill's text.
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = "taskkill.exe"
    $start.Arguments = "/PID $($Application.Id) /T /F"
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $terminator = [Diagnostics.Process]::new()
    $terminator.StartInfo = $start
    try {
        if (-not $terminator.Start()) { throw "Windows soak cleanup did not start" }
        if (-not $terminator.WaitForExit(10000)) {
            $terminator.Kill()
            $terminator.WaitForExit()
        }
    } finally {
        $terminator.Dispose()
    }

    if (-not $Application.WaitForExit(10000)) {
        $Application.Kill()
        if (-not $Application.WaitForExit(10000)) {
            throw "Packaged Windows application did not exit during cleanup"
        }
    }
}

function Save-SoakReport($Report) {
    $path = [System.IO.Path]::GetFullPath($ReportPath)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
}

$temporaryBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$workRoot = Join-Path $temporaryBase ("gitlama-windows-soak-" + [Guid]::NewGuid().ToString("N"))
$profileRoot = Join-Path $workRoot "profile"
[System.IO.Directory]::CreateDirectory($profileRoot) | Out-Null
$repositories = @()
$application = $null
$applicationStarted = $false
$applicationStderrTask = $null
$soakFailure = $null
$busyRetries = 0
$timer = [Diagnostics.Stopwatch]::StartNew()

try {
    foreach ($index in 0..2) {
        $repository = Join-Path $workRoot "repository-$index"
        [System.IO.Directory]::CreateDirectory($repository) | Out-Null
        & git.exe init --quiet $repository
        if ($LASTEXITCODE -ne 0) { throw "Windows soak repository initialization failed" }
        & git.exe -C $repository config user.name "GitLama Soak"
        & git.exe -C $repository config user.email "soak@example.invalid"
        & git.exe -C $repository config core.autocrlf false
        Set-Content -LiteralPath (Join-Path $repository "tracked.txt") -Value "initial" -Encoding ascii
        & git.exe -C $repository add tracked.txt
        & git.exe -C $repository commit --quiet -m initial
        if ($LASTEXITCODE -ne 0) { throw "Windows soak initial commit failed" }
        $repositories += $repository
    }

    $application = [Diagnostics.Process]::new()
    $application.StartInfo = New-StartInfo ('"' + $repositories[0] + '"') $profileRoot ([System.IO.Path]::GetDirectoryName($executablePath))
    $application.StartInfo.Environment["GITLAMA_FORWARDING_DIAGNOSTICS"] = "1"
    $application.StartInfo.RedirectStandardError = $true
    if (-not $application.Start()) { throw "Packaged Windows application did not start" }
    $applicationStarted = $true
    $applicationStderrTask = $application.StandardError.ReadToEndAsync()
    $settingsPath = Join-Path $profileRoot "settings.json"
    $settingsDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        if ($application.HasExited) { throw "Packaged Windows application exited before readiness" }
        if ([DateTime]::UtcNow -ge $settingsDeadline) { throw "Packaged Windows application readiness timed out" }
        Start-Sleep -Milliseconds 100
    }

    # Settings persistence precedes repository loading and CLI polling. Wait
    # for an accepted refresh before measuring forwarded traffic; exit code 2
    # means the app rejected this readiness probe while startup is in flight.
    $forwardingDeadline = [DateTime]::UtcNow.AddSeconds(45)
    $lastFailure = "unknown"
    $lastDetail = "unknown"
    while ($true) {
        if ($application.HasExited) { throw "Packaged Windows application exited before forwarding readiness" }
        try {
            Invoke-Forwarded '"--command" "repository.refresh"' $profileRoot $workRoot "readiness"
            break
        } catch {
            if ($_.Exception.Message -match '^Forwarded Windows readiness invocation failed with exit code \d+, failure ([A-Za-z]+), detail ([a-z0-9_]+)$') {
                $lastFailure = $Matches[1]
                $lastDetail = $Matches[2]
            }
            if ([DateTime]::UtcNow -ge $forwardingDeadline) {
                throw "Packaged Windows forwarding readiness timed out; last failure $lastFailure, detail $lastDetail"
            }
            Start-Sleep -Milliseconds 250
        }
    }

    foreach ($repository in $repositories[1..2]) {
        Invoke-Forwarded ('"' + $repository + '"') $profileRoot $workRoot "repository open"
        Wait-RepositoryRefresh $profileRoot $workRoot $application
    }
    Start-Sleep -Seconds 5
    $baselineWindow = Wait-GitLamaQuiescentWindow -Policy $policy `
        -DeadlineSeconds $policy.maximumQuiescentSettleSeconds `
        -Sample { Get-ResourceSample $application.Id $timer }
    $baselineSamples = @($baselineWindow.samples)
    if (-not $baselineWindow.accepted) {
        Save-SoakReport ([ordered]@{
            schema = 1; platform = "windows"
            acceptance = @{ passed = $false; failures = @("baseline-quiescence-timeout"); policy = $policy }
            quiescentBaselineSamples = $baselineSamples
            baselineSettlingSamples = $baselineWindow.settlingSamples
        })
        throw "Windows soak baseline did not quiesce"
    }

    $samples = @()
    $cycles = 0
    $workloadDeadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
    while ([DateTime]::UtcNow -lt $workloadDeadline) {
        $repository = $repositories[$cycles % $repositories.Count]
        Add-Content -LiteralPath (Join-Path $repository "tracked.txt") -Value "cycle $cycles" -Encoding ascii
        & git.exe -C $repository add tracked.txt
        if ($LASTEXITCODE -ne 0) { throw "Windows soak staging failed" }
        Invoke-Forwarded ('"' + $repository + '"') $profileRoot $workRoot "repository open"
        Wait-RepositoryRefresh $profileRoot $workRoot $application
        & git.exe -C $repository commit --quiet -m "cycle $cycles"
        if ($LASTEXITCODE -ne 0) { throw "Windows soak commit failed" }
        Wait-RepositoryRefresh $profileRoot $workRoot $application
        $samples += Get-ResourceSample $application.Id $timer
        $cycles += 1
        Start-Sleep -Seconds 1
    }
    if ($application.HasExited) { throw "Packaged Windows application exited during soak" }
    $baselineResources = [pscustomobject]@{
        threads = Get-Median @($baselineSamples | ForEach-Object { $_.threads })
        openFiles = Get-Median @($baselineSamples | ForEach-Object { $_.openFiles })
    }
    $finalWindow = Wait-GitLamaQuiescentWindow -Policy $policy -Baseline $baselineResources `
        -DeadlineSeconds $policy.maximumQuiescentSettleSeconds `
        -Sample { Get-ResourceSample $application.Id $timer }
    $finalSamples = @($finalWindow.samples)

    if ($samples.Count -lt 5) { throw "Windows soak requires at least five workload samples" }
    $steadyStart = [Math]::Max(1, [Math]::Floor($samples.Count / 5))
    $steadySamples = @($samples[$steadyStart..($samples.Count - 1)])
    $steadySlope = Get-Slope $steadySamples
    $threadBaseline = Get-Median @($baselineSamples | ForEach-Object { $_.threads })
    $threadFinal = Get-Median @($finalSamples | ForEach-Object { $_.threads })
    $handleBaseline = Get-Median @($baselineSamples | ForEach-Object { $_.openFiles })
    $handleFinal = Get-Median @($finalSamples | ForEach-Object { $_.openFiles })
    $failures = [Collections.Generic.List[string]]::new()
    if (-not $finalWindow.accepted) { $failures.Add("final-quiescence-timeout") }
    if ($steadySlope -gt $policy.maximumSteadyRssSlopeKiBPerSecond) { $failures.Add("steady-rss-slope") }
    if (($threadFinal - $threadBaseline) -gt $policy.maximumQuiescentThreadGrowth) { $failures.Add("thread-growth") }
    if (($handleFinal - $handleBaseline) -gt $policy.maximumQuiescentOpenFileGrowth) { $failures.Add("handle-growth") }
    if (@($finalSamples | Where-Object { $_.children -ne $policy.requiredQuiescentChildren }).Count -gt 0) {
        $failures.Add("remaining-child-process")
    }
    $rss = @($samples | ForEach-Object { $_.rssKiB })
    $report = [ordered]@{
        schema = 1
        platform = "windows"
        durationSeconds = [Math]::Round($finalSamples[-1].elapsedSeconds, 3)
        cycles = $cycles
        sampleCount = $samples.Count
        busyRefreshRetries = $busyRetries
        workload = "three repository tab switches, staged index changes, external commits, watcher events and explicit refresh"
        rssKiB = [ordered]@{
            first = $rss[0]
            median = [Math]::Round((Get-Median $rss))
            p95 = [Math]::Round((Get-Percentile $rss 0.95))
            max = ($rss | Measure-Object -Maximum).Maximum
            last = $rss[-1]
            linearSlopeKiBPerSecond = [Math]::Round((Get-Slope $samples), 3)
            steadyStateLinearSlopeKiBPerSecond = [Math]::Round($steadySlope, 3)
            steadyStateStartsAtSeconds = $steadySamples[0].elapsedSeconds
        }
        threads = [ordered]@{
            quiescentBaselineMedian = $threadBaseline
            workloadMax = ($samples | Measure-Object -Property threads -Maximum).Maximum
            quiescentFinalMedian = $threadFinal
            quiescentGrowth = $threadFinal - $threadBaseline
        }
        handles = [ordered]@{
            quiescentBaselineMedian = $handleBaseline
            workloadMax = ($samples | Measure-Object -Property openFiles -Maximum).Maximum
            quiescentFinalMedian = $handleFinal
            quiescentGrowth = $handleFinal - $handleBaseline
        }
        children = [ordered]@{
            workloadMax = ($samples | Measure-Object -Property children -Maximum).Maximum
            quiescentFinalMax = ($finalSamples | Measure-Object -Property children -Maximum).Maximum
        }
        acceptance = [ordered]@{
            passed = $failures.Count -eq 0
            failures = @($failures)
            policy = $policy
            quiescentGrowth = [ordered]@{
                threads = $threadFinal - $threadBaseline
                handles = $handleFinal - $handleBaseline
            }
        }
        baselineSettlingSamples = $baselineWindow.settlingSamples
        finalSettlingSamples = $finalWindow.settlingSamples
        quiescentBaselineSamples = $baselineSamples
        samples = $samples
        quiescentFinalSamples = $finalSamples
    }
    Save-SoakReport $report
    $reportFullPath = [System.IO.Path]::GetFullPath($ReportPath)
    if ($failures.Count -gt 0) { throw "Windows soak acceptance failed: $($failures -join ', ')" }
    Write-Output $reportFullPath
} catch {
    $soakFailure = $_
    throw
} finally {
    $cleanupFailures = [Collections.Generic.List[string]]::new()
    try {
        if ($applicationStarted) { Stop-ApplicationTree $application }
    } catch {
        $cleanupFailures.Add("process")
    }
    try {
        if ($soakFailure -and $applicationStderrTask -and $applicationStderrTask.Wait(5000)) {
            $ownerStderr = $applicationStderrTask.Result
            $ownerFailures = [Regex]::Matches(
                $ownerStderr,
                '(?m)^gitlama_windows_ipc=(server_read_request|server_verify_client|server_encode_response|server_write_response):(io_[0-9]+|[a-z_]+)\r?$'
            )
            if ($ownerFailures.Count -gt 0) {
                $lastOwnerFailure = $ownerFailures[$ownerFailures.Count - 1]
                Write-Warning "Windows owner IPC detail $($lastOwnerFailure.Groups[1].Value)_$($lastOwnerFailure.Groups[2].Value)"
            }
        }
    } catch {
        # Diagnostics must not replace the soak failure.
    }
    try {
        if ($application) { $application.Dispose() }
    } catch {
        $cleanupFailures.Add("process-handle")
    }
    try {
        if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
    } catch {
        $cleanupFailures.Add("working-directory")
    }
    if ($cleanupFailures.Count -gt 0) {
        if ($soakFailure) {
            Write-Warning "Windows soak cleanup incomplete after qualification failure"
        } else {
            throw "Windows soak cleanup failed: $($cleanupFailures -join ', ')"
        }
    }
}
