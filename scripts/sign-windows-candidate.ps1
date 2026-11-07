param(
    [string]$BundlePath,
    [string]$MsiPath,
    [string]$CertificateThumbprint = $env:WINDOWS_CERTIFICATE_THUMBPRINT,
    [string]$TimestampUrl = $env:WINDOWS_TIMESTAMP_URL
)

$ErrorActionPreference = "Stop"
$thumbprint = $CertificateThumbprint.Trim()
$timestamp = $TimestampUrl.Trim()
if (-not $thumbprint -and -not $timestamp) {
    Write-Output "Windows signing is not configured; candidate remains unsigned"
    exit 0
}
if (-not $thumbprint -or -not $timestamp) {
    throw "Windows signing thumbprint and timestamp URL must be configured together"
}
if ($thumbprint -notmatch '^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})$') {
    throw "Windows signing certificate thumbprint is invalid"
}
$timestampUri = [Uri]$timestamp
if ($timestampUri.Scheme -ne "https" -or -not $timestampUri.Host -or $timestampUri.UserInfo) {
    throw "Windows timestamp URL must be unauthenticated HTTPS"
}
if (-not (Get-Command signtool.exe -ErrorAction SilentlyContinue)) {
    throw "Configured Windows signing requires signtool.exe"
}
if (-not $BundlePath -and -not $MsiPath) { throw "A Windows bundle or MSI path is required" }

$targets = @()
if ($BundlePath) {
    $bundle = [IO.Path]::GetFullPath($BundlePath)
    if (-not (Test-Path -LiteralPath $bundle -PathType Container)) { throw "Windows release bundle does not exist" }
    $targets += @(Get-ChildItem -LiteralPath $bundle -Recurse -File |
        Where-Object { $_.Extension -in @(".exe", ".dll") } |
        Select-Object -ExpandProperty FullName)
    if ($targets.Count -eq 0) { throw "Windows release bundle has no signable payloads" }
}
if ($MsiPath) {
    $msi = [IO.Path]::GetFullPath($MsiPath)
    if (-not (Test-Path -LiteralPath $msi -PathType Leaf)) { throw "Windows MSI does not exist" }
    $targets += $msi
}

foreach ($target in $targets) {
    & signtool.exe sign /sha1 $thumbprint /fd SHA256 /tr $timestamp /td SHA256 $target
    if ($LASTEXITCODE -ne 0) { throw "Configured Windows signing failed" }
    & signtool.exe verify /pa /all $target
    if ($LASTEXITCODE -ne 0) { throw "Configured Windows signature verification failed" }
}
Write-Output "Configured Windows signatures passed"
