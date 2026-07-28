param(
    [string]$ApkPath = "build/app/outputs/flutter-apk/app-bird-release.apk",
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT
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

& $apkSigner.FullName verify --verbose --print-certs $resolvedApk.Path
if ($LASTEXITCODE -ne 0) {
    throw "Release APK signature verification failed: $($resolvedApk.Path)"
}

$apk = Get-Item -LiteralPath $resolvedApk.Path
$hash = Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256
Write-Host "Release APK verified."
Write-Host "Path: $($apk.FullName)"
Write-Host "Size: $($apk.Length) bytes"
Write-Host "SHA-256: $($hash.Hash)"
