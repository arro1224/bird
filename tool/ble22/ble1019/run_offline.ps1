#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RoundDirectory,
    [string]$Python = '',
    [string]$FlutterSdk = 'D:/flutter344/flutter',
    [switch]$PlanOnly,
    [switch]$SkipFlutter
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Ble22.Tools.psm1') -Force
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$round = (Resolve-Path -LiteralPath $RoundDirectory).Path
if (![IO.Path]::GetRelativePath($root, $round).StartsWith('outputs'+[IO.Path]::DirectorySeparatorChar+'ble22'+[IO.Path]::DirectorySeparatorChar)) { throw 'Round must be under workspace outputs/ble22.' }
$record = Get-Content -LiteralPath (Join-Path $round 'round.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($record.suite -ne 'ble1019-v1') { throw 'Wrong acceptance suite.' }
if (!$Python) {
    $Python = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
}
$dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutter = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$steps = @(
    @{name='python-1019';file=$Python;arguments=@('-m','unittest','discover','-s','tool/ble22/ble1019','-p','test_*.py','-v');timeout=120},
    @{name='python-ble22';file=$Python;arguments=@('tool/ble22/test_tools.py');timeout=120},
    @{name='python-receiver';file=$Python;arguments=@('tool/ble19/test_verify_diagnostic_file.py');timeout=120},
    @{name='powershell-tools';file=(Get-Process -Id $PID).Path;arguments=@('-NoProfile','-File',(Join-Path $root 'tool/ble22/test_tools.ps1'));timeout=120},
    @{name='powershell-1019';file=(Get-Process -Id $PID).Path;arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'test_scripts.ps1'));timeout=120}
)
if (!$SkipFlutter) {
    $steps += @(
        @{name='flutter-tests';file=$dart;arguments=@($flutter,'--suppress-analytics','--no-version-check','test','--no-pub','test/bird_companion/features/connection','test/bird_companion/core/provisioning_error_mapping_test.dart','test/contracts','--reporter','expanded');timeout=300},
        @{name='flutter-analyze';file=$dart;arguments=@($flutter,'--suppress-analytics','--no-version-check','analyze','--no-pub');timeout=180},
        @{name='contracts';file=$dart;arguments=@('--packages=.dart_tool/package_config.json','tool/contracts/verify_contracts.dart');timeout=60}
    )
}
$steps += @{name='acceptance-summary';file=$Python;arguments=@('tool/ble22/ble1019/acceptance.py','summarize',$round);timeout=60}
if ($PlanOnly) {
    @{mode='plan_only';steps=$steps;hardware_operations=0;apk_builds=0;releasable=$false} | ConvertTo-Json -Depth 8
    exit 0
}
foreach ($file in @($steps.file | Sort-Object -Unique)) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Required runtime is unavailable; pass explicit runtime paths.' }
}
$checkId = 'offline-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$output = Join-Path $round "checks/$checkId"
$null = New-Item -ItemType Directory -Path $output
$results = @()
$savedFlutterRoot = $env:FLUTTER_ROOT
$savedBytecode = $env:PYTHONDONTWRITEBYTECODE
$savedPythonUtf8 = $env:PYTHONUTF8
$savedPythonEncoding = $env:PYTHONIOENCODING
try {
    $env:FLUTTER_ROOT = $FlutterSdk
    $env:PYTHONDONTWRITEBYTECODE = '1'
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    foreach ($step in $steps) {
        Write-Output "BLE1019_CHECK $($step.name)"
        $log = Join-Path $output ($step.name+'.log')
        $process = Invoke-Ble22Process -File $step.file -Arguments $step.arguments -WorkingDirectory $root -TimeoutSeconds $step.timeout -LogPath $log
        $results += @{name=$step.name;exit_code=$process.exit_code;timed_out=$process.timed_out;log=$log;sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $native = [IO.File]::ReadAllText((Join-Path $root 'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java'))
    $dispatch = @{}
    foreach ($method in @('getNativeBondState','writePairingPreflight','getGattOwnershipState','prepareControlledReconnect')) {
        $dispatch[$method] = $native.Contains('"'+$method+'"')
    }
    $result = @{
        schema_version=1;round_id=$record.round_id;check_id=$checkId;checks=$results;
        offline_checks_passed=@($results | Where-Object { $_.exit_code -ne 0 }).Count -eq 0;
        flutter_executed=!$SkipFlutter;hardware_executed=$false;apk_built=$false;native_unit_tests_executed=$false;
        native_dispatch_literals_present=$dispatch;native_runtime_verified=$false;jointly_confirmed=$false;
        releasable=$false;scope='offline checks only; pending matrix is not a test pass'
    }
    Write-Ble22Json (Join-Path $output 'verification.json') $result
    Write-Output "BLE1019_OFFLINE_RESULT $(Join-Path $output 'verification.json')"
    if (!$result.offline_checks_passed) { exit 1 }
} finally {
    $env:FLUTTER_ROOT = $savedFlutterRoot
    $env:PYTHONDONTWRITEBYTECODE = $savedBytecode
    $env:PYTHONUTF8 = $savedPythonUtf8
    $env:PYTHONIOENCODING = $savedPythonEncoding
}
