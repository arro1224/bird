#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RoundDirectory,
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ApkSha256,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$GitCommit,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$SourceFingerprint,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$')][string]$BuildId,
    [string]$Aapt = 'D:/Androidstudio2/build-tools/37.0.0/aapt2.exe'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Ble22.Tools.psm1') -Force
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$round = (Resolve-Path -LiteralPath $RoundDirectory).Path
if (![IO.Path]::GetRelativePath($root, $round).StartsWith('outputs'+[IO.Path]::DirectorySeparatorChar+'ble22'+[IO.Path]::DirectorySeparatorChar)) { throw 'Round must be under workspace outputs/ble22.' }
$manifest = Join-Path $round 'round.json'
$record = Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
if ($record.suite -ne 'ble1019-v1' -or $null -ne $record.build) { throw 'Wrong suite or build already registered; use a fresh round.' }
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
if ([IO.Path]::GetExtension($apkPath) -ne '.apk' -or (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ApkSha256) { throw 'APK SHA-256 mismatch.' }
$inspection = Invoke-Ble22Process -File $Aapt -Arguments @('dump','badging',$apkPath) -WorkingDirectory $root
if ($inspection.exit_code -ne 0 -or $inspection.stdout -notmatch "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'") { throw 'APK metadata inspection failed.' }
$package = $Matches[1]; $code = [int]$Matches[2]; $version = $Matches[3]
if ($package -ne 'deckers.thibault.aves.bird') { throw 'Only the formal bird APK belongs in this acceptance round.' }
if ((Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ApkSha256) { throw 'APK changed during inspection.' }
$directory = Join-Path $round "artifacts/build-$BuildId"
if (Test-Path -LiteralPath $directory) { throw 'Build artifact directory already exists.' }
$null = New-Item -ItemType Directory -Path $directory
$savedApk = Join-Path $directory 'formal.apk'
Copy-Item -LiteralPath $apkPath -Destination $savedApk
if ((Get-FileHash -LiteralPath $savedApk -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ApkSha256) { throw 'Copied APK hash mismatch.' }
$metadata = Join-Path $directory 'aapt-metadata.log'
[IO.File]::WriteAllText($metadata, $inspection.stdout+"`nAPK_SHA256=$ApkSha256`n", [Text.UTF8Encoding]::new($false))
$record.build = @{
    apk=@{path=[IO.Path]::GetRelativePath($round,$savedApk).Replace('\','/');sha256=$ApkSha256};
    metadata_evidence=@{path=[IO.Path]::GetRelativePath($round,$metadata).Replace('\','/');sha256=(Get-FileHash -LiteralPath $metadata -Algorithm SHA256).Hash.ToLowerInvariant()};
    package_id=$package;version_name=$version;version_code=$code;git_commit=$GitCommit;
    source_fingerprint=$SourceFingerprint;build_id=$BuildId;
    native_integration_verified=$false;releasable=$false
}
# Preserve the pre-registration manifest. This is artifact registration only;
# no install, launch, Bluetooth operation or acceptance outcome is performed.
Copy-Item -LiteralPath $manifest -Destination (Join-Path $directory 'round-before-registration.json')
Write-Ble22Json (Join-Path $directory 'build.json') $record.build
Write-Ble22Json $manifest $record
Write-Output 'BLE1019_BUILD_REGISTERED hardware_executed=false releasable=false'
