param(
    [Parameter(Mandatory = $true)][string]$MsiPath,
    [string]$Wix = "wix.exe",
    [switch]$RequireSignature,
    [string]$PreviousMsiPath,
    [switch]$RequireUpgrade,
    [int]$SoakSeconds = 0,
    [switch]$SoakAdvisory,
    [string]$SoakOutputPath,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$msi = [System.IO.Path]::GetFullPath($MsiPath)
if (-not (Test-Path -LiteralPath $msi -PathType Leaf)) { throw "MSI does not exist" }
& $Wix msi validate $msi
if ($LASTEXITCODE -ne 0) { throw "WiX MSI validation failed" }
if ($RequireSignature) {
    & signtool.exe verify /pa /all $msi
    if ($LASTEXITCODE -ne 0) { throw "MSI signature verification failed" }
}
if ($RequireUpgrade -and -not $PreviousMsiPath) { throw "Upgrade qualification requires -PreviousMsiPath" }

function Get-MsiProperty([string]$Path, [string]$Name) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($Path, 0))
    $query = "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$Name'"
    $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, @($query))
    $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null
    $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
    if (-not $record) { throw "MSI property is missing: $Name" }
    return $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
}

$productName = Get-MsiProperty $msi "ProductName"
$productVersion = Get-MsiProperty $msi "ProductVersion"
$productCode = Get-MsiProperty $msi "ProductCode"
$upgradeCode = Get-MsiProperty $msi "UpgradeCode"
$marketingVersion = Get-MsiProperty $msi "GITLAMA_MARKETING_VERSION"
$buildNumber = Get-MsiProperty $msi "GITLAMA_BUILD_NUMBER"
if ($productName -ne "GitLama") { throw "MSI ProductName changed" }
if ($productVersion -notmatch '^\d+\.\d+\.\d+$') { throw "MSI ProductVersion is invalid" }
if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw "MSI ProductCode is invalid" }
# The WiX source owns the product's upgrade identity.
[xml]$installerSource = Get-Content -Raw -LiteralPath (Join-Path $root "packaging/windows/gitlama.wxs")
$expectedUpgradeCode = "{" + ([guid]$installerSource.Wix.Package.UpgradeCode).ToString().ToUpperInvariant() + "}"
if ($upgradeCode -ne $expectedUpgradeCode) { throw "MSI UpgradeCode changed" }
$versionLines = @(Get-Content -LiteralPath (Join-Path $root "VERSION"))
if ($versionLines.Count -ne 2 -or $marketingVersion -ne $versionLines[0] -or $buildNumber -ne $versionLines[1]) {
    throw "MSI marketing or build identity differs from VERSION"
}

$installRoot = Join-Path $env:ProgramFiles "GitLama qualification"
$registrationPath = "Registry::HKEY_LOCAL_MACHINE\Software\GitLama"
$logRoot = Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }) "gitlama-msi-qualification"
[System.IO.Directory]::CreateDirectory($logRoot) | Out-Null
if (Test-Path -LiteralPath $installRoot) {
    $registration = Get-ItemProperty -LiteralPath $registrationPath -ErrorAction SilentlyContinue
    if (-not $registration -or $registration.InstallLocation.TrimEnd('\') -ine $installRoot.TrimEnd('\')) {
        throw "Refusing to overwrite an unrelated installation directory"
    }
    # WiX gives successive builds distinct ProductCodes, even at the same
    # version. Find the one installed under this dedicated qualification path
    # through the stable UpgradeCode, and refuse ambiguous installations.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GitLamaRelatedProducts {
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiEnumRelatedProducts(string upgradeCode, uint reserved, uint index, StringBuilder productCode);
}
'@
    $relatedProducts = [Collections.Generic.List[string]]::new()
    for ($index = 0; ; $index++) {
        $buffer = [Text.StringBuilder]::new(39)
        $result = [GitLamaRelatedProducts]::MsiEnumRelatedProducts($upgradeCode, 0, $index, $buffer)
        if ($result -eq 259) { break } # ERROR_NO_MORE_ITEMS
        if ($result -ne 0) { throw "Qualification MSI product lookup failed" }
        $relatedProducts.Add($buffer.ToString())
    }
    if ($relatedProducts.Count -ne 1) { throw "Qualification MSI product lookup was ambiguous" }
    $priorUninstallLog = Join-Path $logRoot "prior-uninstall.log"
    $priorUninstall = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/x", $relatedProducts[0], "/qn", "/norestart", "/l*v", "`"$priorUninstallLog`"")
    if ($priorUninstall.ExitCode -ne 0) { throw "Prior qualification MSI uninstall failed; inspect the private runner log" }
    if (Test-Path -LiteralPath $registrationPath) { throw "Prior qualification MSI left registry ownership" }
    if (Test-Path -LiteralPath $installRoot) {
        # This path was verified as the disposable qualification directory.
        # Remove files left by a previously interrupted validation run.
        try { Remove-Item -LiteralPath $installRoot -Recurse -Force }
        catch { throw "Prior qualification directory cleanup failed" }
    }
}
$installLog = Join-Path $logRoot "install.log"
$uninstallLog = Join-Path $logRoot "uninstall.log"

$upgradeResult = "not-run"
$downgradeResult = "not-run"
if ($PreviousMsiPath) {
    $previous = [System.IO.Path]::GetFullPath($PreviousMsiPath)
    if (-not (Test-Path -LiteralPath $previous -PathType Leaf)) { throw "Previous MSI does not exist" }
    & $Wix msi validate $previous
    if ($LASTEXITCODE -ne 0) { throw "Previous MSI validation failed" }
    if ((Get-MsiProperty $previous "UpgradeCode") -ne $upgradeCode) { throw "Previous MSI has another UpgradeCode" }
    $previousVersion = [version](Get-MsiProperty $previous "ProductVersion")
    if ($previousVersion -ge [version]$productVersion) { throw "Previous MSI is not older than the candidate" }
    $installPrevious = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/i", "`"$previous`"", "/qn", "/norestart", "INSTALLFOLDER=`"$installRoot`"")
    if ($installPrevious.ExitCode -ne 0) { throw "Previous MSI install failed" }
}

$install = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/i", "`"$msi`"", "/qn", "/norestart", "INSTALLFOLDER=`"$installRoot`"", "/l*v", "`"$installLog`"")
if ($install.ExitCode -ne 0) { throw "MSI install failed; inspect the private runner log" }
if ($PreviousMsiPath) { $upgradeResult = "passed" }

$installedExe = Join-Path $installRoot "gitlama.exe"
foreach ($required in @(
    "gitlama.exe",
    "gitlama_core.dll",
    "flutter_windows.dll",
    "data\flutter_assets\AssetManifest.bin",
    "data\flutter_assets\NOTICES.Z",
    "data\flutter_assets\THIRD_PARTY_NOTICES.md",
    "data\flutter_assets\assets\licenses\RUST-DEPENDENCIES.md",
    "data\flutter_assets\assets\licenses\FLUTTER-DEPENDENCIES.md",
    "data\flutter_assets\assets\licenses\SYNTAX-GRAMMARS.md"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot $required) -PathType Leaf)) {
        throw "Installed Flutter or Rust payload is missing: $required"
    }
}
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($installedExe)
if ($versionInfo.ProductName -ne "GitLama" -or $versionInfo.ProductVersion -notlike "$marketingVersion*") {
    throw "gitlama.exe has the wrong version resources"
}
$bytes = [IO.File]::ReadAllBytes($installedExe)
if ($bytes.Length -lt 160 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "gitlama.exe is not PE" }
$peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68) -ne 2) {
    throw "gitlama.exe is not a Windows GUI executable"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GitLamaIconProbe {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint ExtractIconEx(string fileName, int iconIndex, IntPtr[] large, IntPtr[] small, uint count);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr icon);
}
'@
$large = [IntPtr[]]::new(1)
$small = [IntPtr[]]::new(1)
try {
    $count = [GitLamaIconProbe]::ExtractIconEx($installedExe, 0, $large, $small, 1)
    if ($count -eq 0 -or ($large[0] -eq [IntPtr]::Zero -and $small[0] -eq [IntPtr]::Zero)) { throw "Executable has no icon" }
} finally {
    foreach ($icon in @($large[0], $small[0])) { if ($icon -ne [IntPtr]::Zero) { [void][GitLamaIconProbe]::DestroyIcon($icon) } }
}
$shortcut = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\GitLama\GitLama.lnk"
if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) { throw "Start menu shortcut is missing" }

if ($RequireSignature) {
    Get-ChildItem -LiteralPath $installRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".exe", ".dll") } |
        ForEach-Object {
            & signtool.exe verify /pa /all $_.FullName
            if ($LASTEXITCODE -ne 0) { throw "Installed executable signature failed" }
        }
}

if (-not $env:GITLAMA_NATIVE_TEST_TIMEOUT_SECONDS) {
    $env:GITLAMA_NATIVE_TEST_TIMEOUT_SECONDS = "180"
}
if (-not $env:GITLAMA_NATIVE_TEST_WAIT_SECONDS) {
    $env:GITLAMA_NATIVE_TEST_WAIT_SECONDS = "30"
}
& python.exe (Join-Path $root "scripts\native-smoke.py") $installRoot
if ($LASTEXITCODE -ne 0) { throw "Installed native bridge smoke failed" }
$repository = Join-Path $logRoot "repository with spaces"
if (Test-Path -LiteralPath $repository) { Remove-Item -LiteralPath $repository -Recurse -Force }
& git.exe init --quiet $repository
if ($LASTEXITCODE -ne 0) { throw "Repository fixture initialization failed" }

function Invoke-LaunchProbe([string]$ProfileName, [bool]$MissingGit) {
    $profile = Join-Path $logRoot $ProfileName
    if (Test-Path -LiteralPath $profile) { Remove-Item -LiteralPath $profile -Recurse -Force }
    $probeName = switch ($ProfileName) {
        "cold profile one" { "cold-profile-one" }
        "cold profile two" { "cold-profile-two" }
        "retained profile" { "missing-git" }
    }
    $probeArguments = @(
        "--executable", $installedExe, "--profile", $profile,
        "--name", $probeName,
        "--output", "dist/qualification/windows-launch-$probeName.json"
    )
    if (-not $MissingGit) { $probeArguments += @("--repository", $repository) }
    & python.exe (Join-Path $root "scripts/windows-launch-probe.py") @probeArguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "Installed app launch qualification failed: $probeName; inspect windows-launch report" }
    return $profile
}

[void](Invoke-LaunchProbe "cold profile one" $false)
[void](Invoke-LaunchProbe "cold profile two" $false)
$retainedProfile = Invoke-LaunchProbe "retained profile" $true
$soakResult = "not-run"
$soakExitCode = $null
if ($SoakSeconds -gt 0) {
    if (-not $SoakOutputPath) { throw "Windows soak output is required when soak is enabled" }
    # Never let an old report stand in for this installed candidate's run.
    if (Test-Path -LiteralPath $SoakOutputPath) { Remove-Item -LiteralPath $SoakOutputPath -Force }
    try {
        powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/soak-windows.ps1 `
            -Executable $installedExe `
            -DurationSeconds $SoakSeconds `
            -ReportPath $SoakOutputPath
        $soakExitCode = $LASTEXITCODE
        if ($soakExitCode -ne 0) { throw "Installed Windows soak failed" }
        if (-not (Test-Path -LiteralPath $SoakOutputPath -PathType Leaf)) { throw "Windows soak report missing" }
        $soakResult = "passed"
    } catch {
        $soakResult = "failed"
        # Startup/readiness failures may happen before resource samples exist.
        # Preserve any real report; otherwise retain an explicit incomplete run.
        if (-not (Test-Path -LiteralPath $SoakOutputPath -PathType Leaf)) {
            $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($SoakOutputPath))
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            [ordered]@{
                schema = 1
                platform = "windows"
                acceptance = [ordered]@{ passed = $false; failures = @("soak_incomplete") }
                exitCode = $soakExitCode
                samples = @()
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SoakOutputPath -Encoding utf8
        }
        if (-not $SoakAdvisory) { throw "Installed Windows soak failed; inspect the soak report" }
        Write-Warning "windows_soak_failed_advisory: inspect the retained soak report"
    }
}
$retainedMarker = Join-Path $retainedProfile "retained-after-uninstall"
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $retainedMarker)) | Out-Null
Set-Content -LiteralPath $retainedMarker -Value "retain" -Encoding ascii

if ($PreviousMsiPath) {
    $downgrade = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/i", "`"$previous`"", "/qn", "/norestart", "INSTALLFOLDER=`"$installRoot`"")
    if ($downgrade.ExitCode -eq 0) { throw "Downgrade unexpectedly succeeded" }
    $downgradeResult = "passed"
}

$uninstall = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/x", "`"$msi`"", "/qn", "/norestart", "/l*v", "`"$uninstallLog`"")
if ($uninstall.ExitCode -ne 0) { throw "MSI uninstall failed; inspect the private runner log" }
if (Test-Path -LiteralPath $installRoot) {
    $remainingFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File -Force).Count
    $remainingDirectories = @(Get-ChildItem -LiteralPath $installRoot -Recurse -Directory -Force).Count
    throw "Uninstall left the installation directory: $remainingFiles files, $remainingDirectories subdirectories"
}
if (Test-Path -LiteralPath $registrationPath) { throw "Uninstall left registry ownership" }
if (Test-Path -LiteralPath $shortcut) { throw "Uninstall left the Start menu shortcut" }
if (-not (Test-Path -LiteralPath $retainedMarker -PathType Leaf)) { throw "Uninstall removed user configuration" }

if ($OutputPath) {
    $report = [ordered]@{
        schema = 1
        platform = "windows"
        architecture = "x86_64"
        artifact = [System.IO.Path]::GetFileName($msi)
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $msi).Hash.ToLowerInvariant()
        bytes = (Get-Item -LiteralPath $msi).Length
        productVersion = $productVersion
        marketingVersion = $marketingVersion
        buildNumber = [int]$buildNumber
        nativeBridge = "passed"
        install = "passed"
        launches = @("repository", "repository", "missing-git")
        upgrade = $upgradeResult
        downgradeRejection = $downgradeResult
        uninstall = "passed"
        userDataRetained = "passed"
        signature = $(if ($RequireSignature) { "passed" } else { "not-run" })
        soak = $soakResult
        soakAdvisory = [bool]$SoakAdvisory
        soakExitCode = $soakExitCode
    }
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
Write-Output "Windows MSI qualification passed"
