# Cargo builds the Qt application's C++ glue (cxx-qt) from PowerShell, outside a Visual
# Studio developer prompt; this loads that environment into the current session.
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Visual Studio Installer (vswhere.exe) is required for Windows builds"
}

$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) {
    throw "Visual Studio with the Desktop development with C++ workload is required"
}

$devCmd = Join-Path $installation "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $devCmd)) {
    throw "Visual Studio developer command prompt was not found at $devCmd"
}

$cmdFile = Join-Path $env:TEMP ("gitlama-msvc-{0}.cmd" -f [guid]::NewGuid().ToString("N"))
try {
    @(
        '@echo off'
        "call `"$devCmd`" -no_logo -arch=x64 -host_arch=x64 >nul"
        'if errorlevel 1 exit /b %errorlevel%'
        'set'
    ) | Set-Content -Path $cmdFile -Encoding Default

    $environment = & $env:ComSpec /d /c $cmdFile
    if ($LASTEXITCODE -ne 0) {
        throw "Visual Studio developer environment setup failed with exit code $LASTEXITCODE"
    }
    foreach ($line in $environment) {
        if ($line -match '^([^=][^=]*)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
} finally {
    Remove-Item -Path $cmdFile -Force -ErrorAction SilentlyContinue
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw "MSVC compiler is unavailable after Visual Studio environment setup"
}
$crtIncludes = @($env:INCLUDE -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'assert.h')) })
if ($crtIncludes.Count -eq 0) {
    throw "Windows SDK C runtime headers are unavailable: assert.h was not found in INCLUDE"
}
