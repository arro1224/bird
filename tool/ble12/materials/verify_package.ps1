[CmdletBinding()]
param(
    [string]$Manifest
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Manifest)) {
    $Manifest = Join-Path $scriptDirectory 'candidate-manifest.json'
}
$manifestFile = Get-Item -LiteralPath $Manifest
$packageRoot = $manifestFile.Directory.FullName
$packagePrefix = "$($packageRoot.TrimEnd('\', '/'))$([System.IO.Path]::DirectorySeparatorChar)"
$value = Get-Content -Raw -LiteralPath $manifestFile.FullName | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$artifactEntries = @($value.artifacts.PSObject.Properties)

if ($value.candidate_suite -ne 'rc4-hf-ble-12') { $failures.Add('candidate_suite mismatch') }
if ($value.evidence_kind -ne 'simulated') { $failures.Add('evidence_kind must remain simulated') }
if ($value.hardware_status -ne 'pending') { $failures.Add('hardware_status must remain pending') }
if ($value.releasable -ne $false) { $failures.Add('candidate must remain non-releasable') }

$expectedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($entry in $artifactEntries) {
    $relative = ([string]$entry.Name).Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative.Split('/') -contains '..') {
        $failures.Add("unsafe artifact path: $relative")
        continue
    }
    $null = $expectedFiles.Add($relative)
    $target = [System.IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
    if (!$target.StartsWith($packagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("artifact escapes package: $relative")
        continue
    }
    if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
        $failures.Add("artifact missing: $relative")
        continue
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$entry.Value).ToLowerInvariant()) {
        $failures.Add("artifact SHA-256 mismatch: $relative")
    }
}

$actualFiles = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
    $fullPath = [System.IO.Path]::GetFullPath($_.FullName)
    if (!$fullPath.StartsWith($packagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("payload escapes package: $fullPath")
    } else {
        $fullPath.Substring($packagePrefix.Length).Replace('\', '/')
    }
} | Where-Object { $_ -notin @('candidate-manifest.json', 'SHA256SUMS.txt') }
foreach ($relative in $actualFiles) {
    if (!$expectedFiles.Contains($relative)) { $failures.Add("unregistered payload: $relative") }
}

$sumsPath = Join-Path $packageRoot 'SHA256SUMS.txt'
if (!(Test-Path -LiteralPath $sumsPath -PathType Leaf)) {
    $failures.Add('SHA256SUMS.txt is missing')
} else {
    $sums = @{}
    foreach ($line in Get-Content -LiteralPath $sumsPath) {
        if ($line -match '^([0-9a-f]{64}) \*(.+)$') { $sums[$Matches[2]] = $Matches[1] }
    }
    $manifestSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestFile.FullName).Hash.ToLowerInvariant()
    if ($sums['candidate-manifest.json'] -ne $manifestSha) {
        $failures.Add('candidate manifest is not protected by SHA256SUMS.txt')
    }
    foreach ($entry in $artifactEntries) {
        $relative = ([string]$entry.Name).Replace('\', '/')
        if ($sums[$relative] -ne ([string]$entry.Value).ToLowerInvariant()) {
            $failures.Add("SHA256SUMS.txt mismatch: $relative")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 2
}

Write-Host "BLE-12 candidate_package_ready: $($value.candidate_id)"
Write-Host 'hardware_status=pending; releasable=false'
