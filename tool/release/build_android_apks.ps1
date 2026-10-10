param(
    [ValidateSet("Normal", "HuaweiAB", "Simulation")]
    [string]$Mode = "Normal",

    [ValidateSet("Debug", "Release")]
    [string]$BuildType = "Debug",

    [switch]$NoPub
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256Hex([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hasher.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
    } finally {
        $hasher.Dispose()
        $stream.Dispose()
    }
}

function Get-BuildSourceIdentity([string]$repositoryRoot) {
$sourcePaths = @(
    & git -C $repositoryRoot -c core.quotepath=false ls-files --cached --others --exclude-standard |
        Where-Object {
            $_ -notmatch '^(docs|doc|\.run)/' -and $_ -notmatch '(^|/)README\.md$'
        }
)
if ($LASTEXITCODE -ne 0 -or $sourcePaths.Count -eq 0) {
    throw "Unable to enumerate the tracked and non-ignored source files."
}
$ordinalSourcePaths = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $sourcePaths) { $ordinalSourcePaths.Add([string]$relativePath) }
$ordinalSourcePaths.Sort([System.StringComparer]::Ordinal)
$sourcePaths = $ordinalSourcePaths.ToArray()
$sourceFingerprintLines = foreach ($relativePath in $sourcePaths) {
    $sourcePath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        # A tracked deletion is part of the source state too. Preserve it in the fingerprint
        # rather than treating the deliberate rename/removal as a build-script failure.
        "{0}`t<deleted>" -f $relativePath.Replace('\', '/')
        continue
    }
    "{0}`t{1}" -f $relativePath.Replace('\', '/'), (Get-Sha256Hex $sourcePath)
}
$sourceFingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes(
    (($sourceFingerprintLines -join "`n") + "`n")
)
$sourceFingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $sourceFingerprint = ([BitConverter]::ToString(
        $sourceFingerprintHasher.ComputeHash($sourceFingerprintBytes)
    ) -replace '-', '').ToLowerInvariant()
} finally {
    $sourceFingerprintHasher.Dispose()
}
    return [PSCustomObject]@{fingerprint=$sourceFingerprint; paths=$sourcePaths; lines=$sourceFingerprintLines}
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$localPropertiesPath = Join-Path $repositoryRoot "android\local.properties"
if (-not (Test-Path -LiteralPath $localPropertiesPath)) {
    throw "android/local.properties is required to locate the Android SDK."
}
$androidSdkLine = Get-Content -LiteralPath $localPropertiesPath |
    Where-Object { $_ -match '^sdk\.dir=' } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($androidSdkLine)) {
    throw "sdk.dir is not configured in android/local.properties."
}
$androidSdk = ($androidSdkLine -replace '^sdk\.dir=', '').Replace('\\', '\')
$apksignerPath = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "apksigner.bat" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($apksignerPath)) {
    throw "apksigner.bat was not found under $androidSdk\\build-tools."
}

function Get-ApkCertificateSha256([string]$ApkPath) {
    # Recent JDKs print native-access warnings on stderr. Capture them with a non-terminating
    # preference so the certificate line can still be parsed under the script's strict default.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $verification = & $apksignerPath verify --print-certs $ApkPath 2>&1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed: $ApkPath"
    }
    $match = [regex]::Match(
        ($verification -join "`n"),
        '(?im)^.*certificate SHA-256 digest:\s*([0-9a-f]{64})\s*$'
    )
    if (-not $match.Success) {
        throw "APK certificate SHA-256 was not emitted by apksigner: $ApkPath"
    }
    return $match.Groups[1].Value.ToLowerInvariant()
}

if ($Mode -ne "Normal" -and $BuildType -ne "Debug") {
    throw "$Mode is an internal test mode and only supports Debug builds."
}

$flutterExecutable = Get-Command flutter -ErrorAction SilentlyContinue
$flutterCommand = if ($null -ne $flutterExecutable) { $flutterExecutable.Source } else { $null }
if ([string]::IsNullOrWhiteSpace($flutterCommand)) {
    if (-not (Test-Path -LiteralPath $localPropertiesPath)) {
        throw "flutter was not found and android/local.properties is missing."
    }
    $flutterSdkLine = Get-Content -LiteralPath $localPropertiesPath |
        Where-Object { $_ -match '^flutter\.sdk=' } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($flutterSdkLine)) {
        throw "flutter.sdk is not configured in android/local.properties."
    }
    $flutterSdk = ($flutterSdkLine -replace '^flutter\.sdk=', '').Replace('\\', '\')
    $flutterCommand = Join-Path $flutterSdk "bin\flutter.bat"
}
if (-not (Test-Path -LiteralPath $flutterCommand)) {
    throw "Flutter executable does not exist: $flutterCommand"
}

$versionLine = Get-Content -LiteralPath (Join-Path $repositoryRoot "pubspec.yaml") |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
if ($versionLine -notmatch '^version:\s*([^+\s]+)\+(\d+)\s*$') {
    throw "pubspec.yaml version must use versionName+versionCode."
}
$versionName = $Matches[1]
$versionCode = $Matches[2]
$gitSha = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $gitSha -notmatch '^[0-9a-f]{40}$') {
    throw "Unable to resolve the source Git SHA."
}
$workingTreeClean = [string]::IsNullOrWhiteSpace((& git -C $repositoryRoot status --porcelain) -join "`n")
$sourceIdentity = Get-BuildSourceIdentity $repositoryRoot
$sourceFingerprint = $sourceIdentity.fingerprint
$sourcePaths = $sourceIdentity.paths

$variants = switch ($Mode) {
    "Normal" {
        @([ordered]@{
            flavor = "bird"
            package_id = "deckers.thibault.aves.bird"
            target = "lib/main.dart"
            label = "BirdBox"
            scan_permission_policy = "never_for_location"
            scan_strategy_fallback_enabled = $true
        })
    }
    "HuaweiAB" {
        @(
            [ordered]@{
                flavor = "birdScanA"
            package_id = "deckers.thibault.aves.bird.scan.a"
            target = "lib/main.dart"
            label = "BirdBox-ScanA"
            scan_permission_policy = "never_for_location"
            scan_strategy_fallback_enabled = $true
            },
            [ordered]@{
                flavor = "birdScanB"
            package_id = "deckers.thibault.aves.bird.scan.b"
            target = "lib/main.dart"
            label = "BirdBox-ScanB"
            scan_permission_policy = "full_scan"
            scan_strategy_fallback_enabled = $true
            }
        )
    }
    "Simulation" {
        @([ordered]@{
            flavor = "birdSim"
            package_id = "deckers.thibault.aves.bird.sim"
            target = "lib/main_bird_simulated.dart"
            label = "BirdBox-Sim"
            scan_permission_policy = "never_for_location"
            scan_strategy_fallback_enabled = $false
        })
    }
}

$buildTypeValue = $BuildType.ToLowerInvariant()
$deliveryRole = if ($Mode -eq "Normal") {
    "app_board_backend_integration"
} else {
    "internal_experiment"
}
$deliveryDirectory = Join-Path $repositoryRoot (
    "build\delivery\{0}-{1}\{2}\{3}" -f $versionName, $versionCode, $Mode.ToLowerInvariant(), $buildTypeValue
)
New-Item -ItemType Directory -Path $deliveryDirectory -Force | Out-Null

$buildId = "ble-{0}-{1}" -f [DateTimeOffset]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), $sourceFingerprint.Substring(0, 12)
$buildEnvironmentNames = @('AVES_GIT_SHA', 'AVES_SOURCE_FINGERPRINT', 'AVES_BUILD_ID')
$previousBuildEnvironment = @{}
foreach ($name in $buildEnvironmentNames) { $previousBuildEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$env:AVES_GIT_SHA = $gitSha
$env:AVES_SOURCE_FINGERPRINT = $sourceFingerprint
$env:AVES_BUILD_ID = $buildId
$artifacts = @()
Push-Location $repositoryRoot
try {
    foreach ($variant in $variants) {
        $arguments = @(
            "build", "apk", "--$buildTypeValue",
            "--flavor", $variant.flavor,
            "-t", $variant.target
        )
        if ($NoPub) {
            $arguments += "--no-pub"
        }
        # Invoking flutter.bat directly can terminate the hosting PowerShell before this script
        # reaches the copy/manifest steps. `call` keeps control in this process on Windows.
        if ($flutterCommand.EndsWith(".bat", [System.StringComparison]::OrdinalIgnoreCase)) {
            & cmd.exe /d /c call $flutterCommand @arguments
        } else {
            & $flutterCommand @arguments
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed for flavor $($variant.flavor)."
        }

        $afterBuildIdentity = Get-BuildSourceIdentity $repositoryRoot
        $afterBuildGitSha = (& git -C $repositoryRoot rev-parse HEAD).Trim()
        if ($afterBuildIdentity.fingerprint -ne $sourceFingerprint -or $afterBuildGitSha -ne $gitSha) {
            throw "Source changed during the build; rebuild before generating a delivery manifest."
        }

        $sourceName = "app-{0}-{1}.apk" -f $variant.flavor.ToLowerInvariant(), $buildTypeValue
        $sourcePath = Join-Path $repositoryRoot "build\app\outputs\flutter-apk\$sourceName"
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Expected APK was not produced: $sourcePath"
        }
        $destinationName = "{0}-{1}-{2}-{3}.apk" -f $variant.label, $versionName, $versionCode, $buildTypeValue
        $destinationPath = Join-Path $deliveryDirectory $destinationName
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        $file = Get-Item -LiteralPath $destinationPath
        $artifacts += [ordered]@{
            file = $file.Name
            package_id = $variant.package_id
            flavor = $variant.flavor
            build_type = $buildTypeValue
            target = $variant.target
            scan_permission_policy = $variant.scan_permission_policy
            scan_strategy_fallback_enabled = $variant.scan_strategy_fallback_enabled
            bytes = $file.Length
            sha256 = Get-Sha256Hex $destinationPath
            signing_certificate_sha256 = Get-ApkCertificateSha256 $destinationPath
        }
    }
} finally {
    Pop-Location
    foreach ($name in $buildEnvironmentNames) { [Environment]::SetEnvironmentVariable($name, $previousBuildEnvironment[$name], 'Process') }
}

$manifest = [ordered]@{
    schema_version = 1
    generated_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
    mode = $Mode
    delivery_role = $deliveryRole
    official_delivery_flavor = if ($Mode -eq "Normal") { "bird" } else { $null }
    source = [ordered]@{
        git_sha = $gitSha
        working_tree_clean = $workingTreeClean
        build_dirty = -not $workingTreeClean
        build_id = $buildId
        source_fingerprint = $sourceFingerprint
        build_input_source_fingerprint = $sourceFingerprint
        build_input_file_count = $sourcePaths.Count
        version_name = $versionName
        version_code = [int]$versionCode
    }
    releasable = $Mode -eq "Normal" -and $BuildType -eq "Release" -and $workingTreeClean
    artifacts = $artifacts
}
[IO.File]::WriteAllText((Join-Path $deliveryDirectory "source-files.sha256"), (($sourceIdentity.lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$manifestPath = Join-Path $deliveryDirectory "build-manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Output "build_complete"
Write-Output "manifest=$manifestPath"
