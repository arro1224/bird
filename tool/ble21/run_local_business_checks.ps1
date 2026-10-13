param(
    [string]$FlutterRoot = 'D:\flutter344\flutter',
    [string]$JavaHome = 'C:\Users\32714\.gradle\jdks\eclipse_adoptium-21-amd64-windows.2'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$flutterTools = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
if (!(Test-Path -LiteralPath $dart) -or !(Test-Path -LiteralPath $flutterTools)) { throw 'Flutter/Dart runtime is missing.' }
if (!(Test-Path -LiteralPath $JavaHome)) { throw 'JDK is missing; pass -JavaHome.' }
$previousJavaHome = $env:JAVA_HOME
$logRoot = Join-Path $repositoryRoot 'build\ble21'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
try {
    $env:JAVA_HOME = $JavaHome
    Push-Location (Join-Path $repositoryRoot 'android')
    try {
        & .\gradlew.bat :virtualBirdBox:testDebugUnitTest :virtualBirdBox:assembleDebug --offline --console=plain --rerun-tasks *> (Join-Path $logRoot 'native.log')
        if ($LASTEXITCODE -ne 0) { throw 'Native protocol checks failed; see native.log.' }
    } finally { Pop-Location }
    Push-Location $repositoryRoot
    try {
        & $dart $flutterTools test --no-pub --concurrency=4 test/bird_companion/features/connection test/bird_companion/acceptance/simulated_debug_entrypoint_test.dart test/bird_companion/acceptance/b7_simulated_demo_page_test.dart test/bird_companion/core/mock_box_server_test.dart test/bird_companion/core/provisioning_error_mapping_test.dart tool/ble21/virtual_protocol_contract_test.dart *> (Join-Path $logRoot 'flutter.log')
        if ($LASTEXITCODE -ne 0) { throw 'Business checks failed; see flutter.log.' }
        & $dart analyze lib/bird_companion/features/connection lib/bird_companion/simulation/simulated_bird_box_debug_app.dart lib/bird_companion/core/network/api_exception.dart lib/bird_companion/core/errors/user_message_mapper.dart tool/mock_box_server tool/ble21 test/bird_companion/features/connection test/bird_companion/acceptance/simulated_debug_entrypoint_test.dart *> (Join-Path $logRoot 'analyze.log')
        if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed; see analyze.log.' }
        & $dart run tool/contracts/verify_contracts.dart *> (Join-Path $logRoot 'contracts.log')
        if ($LASTEXITCODE -ne 0) { throw 'Schema/fixture checks failed; see contracts.log.' }
    } finally { Pop-Location }
    Write-Output "PASS BLE-21 local business checks. Logs: $logRoot"
    Write-Output 'Evidence scope: controlled BLE/Wi-Fi + real local HTTP. Real AP/STA, dual-phone RF and board acceptance remain pending.'
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
