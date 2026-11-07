$ErrorActionPreference = "Stop"

$rustupVersion = "1.28.2"
$rustupSha256 = "88d8258dcf6ae4f7a80c7d1088e1f36fa7025a1cfd1343731b4ee6f385121fc0"
$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
$rustup = Join-Path $cargoBin "rustup.exe"

if (-not (Test-Path -LiteralPath $rustup)) {
    $temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    $installer = Join-Path $temporaryRoot "rustup-init.exe"
    $url = "https://static.rust-lang.org/rustup/archive/$rustupVersion/x86_64-pc-windows-msvc/rustup-init.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
    $actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $rustupSha256) {
        Remove-Item -Force -LiteralPath $installer
        throw "rustup-init checksum mismatch"
    }
    & $installer -y --no-modify-path --profile minimal --default-toolchain none
    if ($LASTEXITCODE -ne 0) {
        throw "rustup-init failed with exit code $LASTEXITCODE"
    }
    Remove-Item -Force -LiteralPath $installer
}

if (-not (Test-Path -LiteralPath $rustup)) {
    throw "rustup installation did not produce the expected executable"
}
$pathFile = if ($env:FORGEJO_PATH) { $env:FORGEJO_PATH } else { $env:GITHUB_PATH }
if (-not $pathFile) {
    throw "Forgejo did not provide a job PATH file"
}
[IO.File]::AppendAllText($pathFile, "$cargoBin`n", [Text.UTF8Encoding]::new($false))
$env:PATH = "$cargoBin;$env:PATH"
& $rustup --version
if ($LASTEXITCODE -ne 0) {
    throw "rustup verification failed with exit code $LASTEXITCODE"
}
