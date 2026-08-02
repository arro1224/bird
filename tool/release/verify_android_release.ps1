param(
    [string]$ApkPath = "build/app/outputs/flutter-apk/app-bird-release.apk",
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$ExpectedSignerSha256 = $env:AVES_RELEASE_CERT_SHA256
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedApk = Resolve-Path (Join-Path $repoRoot $ApkPath)

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $localPropertiesPath = Join-Path $repoRoot "android\local.properties"
    if (Test-Path -LiteralPath $localPropertiesPath) {
        $sdkLine = Get-Content -LiteralPath $localPropertiesPath |
            Where-Object { $_ -match "^sdk\.dir=" } |
            Select-Object -First 1
        if ($sdkLine) {
            $AndroidSdkRoot = $sdkLine.Substring("sdk.dir=".Length) -replace "\\\\", "\"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    throw "Android SDK path was not found. Set ANDROID_SDK_ROOT or android/local.properties."
}

$buildToolsRoot = Join-Path $AndroidSdkRoot "build-tools"
$apkSigner = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Where-Object { $_.Name -match "^\d+(\.\d+)+$" } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object {
        $candidate = Join-Path $_.FullName "apksigner.bat"
        if (Test-Path -LiteralPath $candidate) {
            Get-Item -LiteralPath $candidate
        }
    } |
    Select-Object -First 1

if (-not $apkSigner) {
    throw "apksigner.bat was not found below $buildToolsRoot."
}

$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $verificationOutput = @(
        & $apkSigner.FullName verify --verbose --print-certs $resolvedApk.Path 2>&1
    )
    $verificationExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorAction
}
$verificationOutput | ForEach-Object { Write-Host $_ }
if ($verificationExitCode -ne 0) {
    throw "Release APK signature verification failed: $($resolvedApk.Path)"
}

if ([string]::IsNullOrWhiteSpace($ExpectedSignerSha256)) {
    throw "Expected release certificate SHA-256 is missing. Set AVES_RELEASE_CERT_SHA256 or pass -ExpectedSignerSha256."
}
$digestLine = $verificationOutput |
    Select-String -Pattern "certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)" |
    Select-Object -First 1
if (-not $digestLine) {
    throw "apksigner output did not contain the signer certificate SHA-256 digest."
}
$actualSignerSha256 = $digestLine.Matches[0].Groups[1].Value -replace "[:\s]", ""
$expectedSigner = $ExpectedSignerSha256 -replace "[:\s]", ""
if ($actualSignerSha256.ToUpperInvariant() -ne $expectedSigner.ToUpperInvariant()) {
    throw "Release signer certificate SHA-256 does not match the approved fingerprint."
}

$apk = Get-Item -LiteralPath $resolvedApk.Path
$hash = Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256
Write-Host "Release APK verified."
Write-Host "Signer SHA-256: $($actualSignerSha256.ToUpperInvariant())"
Write-Host "Path: $($apk.FullName)"
Write-Host "Size: $($apk.Length) bytes"
Write-Host "SHA-256: $($hash.Hash)"
