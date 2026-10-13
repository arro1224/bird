[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppSerial,
    [Parameter(Mandatory)][string]$BoxSerial,
    [ValidateSet('bond_first','already_bonded','auth_once','auth_persistent','att_timeout_first','att_timeout_middle','att_timeout_last','notification_failure','disconnect_once','response_delay','response_wrong','response_duplicate','business_timeout')]
    [string]$Scenario='bond_first',
    [string]$AndroidSdk='D:\Androidstudio2',
    [string]$FlutterSdk='D:\flutter344\flutter',
    [string]$OutputRoot='outputs\ble20-phones'
)
$ErrorActionPreference='Stop'
if ($AppSerial -eq $BoxSerial) { throw 'App and virtual box must use distinct phones.' }
$repositoryRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$adb=Join-Path $AndroidSdk 'platform-tools\adb.exe'
$flutter=Join-Path $FlutterSdk 'bin\flutter.bat'
$dart=Join-Path $FlutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
$boxPackage='deckers.thibault.aves.virtualbirdbox.debug'
$appPackage='deckers.thibault.aves.bird'
$runDirectory=Join-Path $repositoryRoot (Join-Path $OutputRoot "$(Get-Date -Format yyyyMMdd-HHmmss)-$Scenario")
$null=New-Item -ItemType Directory -Force $runDirectory
$utf8=[Text.UTF8Encoding]::new($false)
function Property([string]$serial,[string]$key) { return ([string](& $adb -s $serial shell getprop $key)).Trim() }
function Identity([string]$serial) {
    $alias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($serial))).ToLowerInvariant()
    return @{device_alias=$alias;model=(Property $serial 'ro.product.model');manufacturer=(Property $serial 'ro.product.manufacturer');sdk_int=[int](Property $serial 'ro.build.version.sdk')}
}
foreach ($serial in $AppSerial,$BoxSerial) {
    if (([string](& $adb -s $serial get-state)).Trim() -ne 'device') { throw 'Both selected phones must be online with USB debugging authorized.' }
}
$phones=@{app=(Identity $AppSerial);box=(Identity $BoxSerial)}
Push-Location $repositoryRoot
try {
    & $flutter build apk --debug --flavor bird --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'App debug APK build failed.' }
} finally { Pop-Location }
$appApk=Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-bird-debug.apk'
& $adb -s $AppSerial install -r -g $appApk
if ($LASTEXITCODE -ne 0) { throw 'App debug APK install failed.' }
$appPermissions=@()
if ($phones.app.sdk_int -ge 31) { $appPermissions += @('android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_CONNECT') }
if ($phones.app.sdk_int -le 32) { $appPermissions += @('android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION') }
foreach ($permission in $appPermissions) {
    & $adb -s $AppSerial shell pm grant $appPackage $permission
    if ($LASTEXITCODE -ne 0) { throw "App test permission was not granted: $permission" }
}
Push-Location (Join-Path $repositoryRoot 'android')
try { & ./gradlew.bat :virtualBirdBox:assembleDebug --offline; if ($LASTEXITCODE -ne 0) { throw 'Virtual APK build failed.' } }
finally { Pop-Location }
$boxApk=Join-Path $repositoryRoot 'build\virtualBirdBox\outputs\apk\debug\virtualBirdBox-debug.apk'
& $adb -s $BoxSerial install -r -t -g $boxApk
if ($LASTEXITCODE -ne 0) { throw 'Virtual APK install failed. See the debug-only manual-install instructions; do not use a release APK.' }
foreach ($permission in @('android.permission.BLUETOOTH_ADVERTISE','android.permission.BLUETOOTH_CONNECT')) {
    if ($phones.box.sdk_int -ge 31) { & $adb -s $BoxSerial shell pm grant $boxPackage $permission; if ($LASTEXITCODE -ne 0) { throw 'Virtual peripheral runtime permission was not granted.' } }
}
& $adb -s $BoxSerial shell am force-stop $boxPackage
& $adb -s $BoxSerial shell am start -n "$boxPackage/deckers.thibault.aves.virtualbirdbox.VirtualBirdBoxActivity" --es scenario $Scenario --ez reset_log true
if ($LASTEXITCODE -ne 0) { throw 'Virtual peripheral launch failed.' }
$deadline=(Get-Date).AddSeconds(30)
do {
    $lines=@(& $adb -s $BoxSerial shell run-as $boxPackage cat files/ble11-events.jsonl 2>$null)
    $advertising=($lines -join "`n") -match '"event_type":"advertising_started"'
    if (!$advertising) { Start-Sleep -Milliseconds 500 }
} while (!$advertising -and (Get-Date) -lt $deadline)
if (!$advertising) { throw 'No actual advertising success callback. Enable Bluetooth, approve permissions, and check phone peripheral support.' }
Write-Host 'Keep both phones unlocked and the virtual box foreground. Approve system Bluetooth pairing when prompted. already_bonded requires a preceding successful bond_first run; other first-bond scenarios require clearing that test bond in system settings.'
Push-Location $repositoryRoot
try {
    $testOutput=@(& $flutter test integration_test/ble11_dual_avd_test.dart -d $AppSerial --flavor bird --no-pub "--dart-define=BLE11_SCENARIO=$Scenario" 2>&1 | Tee-Object -FilePath (Join-Path $runDirectory 'integration.log'))
    $testExit=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $runDirectory 'integration.log'), ($testOutput -join "`n"), $utf8)
    $appLine=$testOutput | Where-Object { $_ -match 'BLE11_SIMULATED_EVIDENCE\s+(\{.*\})' } | Select-Object -Last 1
    $appEvidence=$null
    if ($appLine -match 'BLE11_SIMULATED_EVIDENCE\s+(\{.*\})') { $appEvidence=$Matches[1] | ConvertFrom-Json -AsHashtable }
    $boxEvents=@(& $adb -s $BoxSerial shell run-as $boxPackage cat files/ble11-events.jsonl | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
    $appApk=Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-bird-debug.apk'
    $evidence=@{
        schema_version=2;evidence_kind='virtual_birdbox_phone';hardware_status='pending';security_flow='bond_first';endpoint_kind='virtual_birdbox';scenario=$Scenario
        generated_at=(Get-Date).ToUniversalTime().ToString('o');test_exit_code=$testExit;phones=$phones
        builds=@{app=@{apk_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $appApk).Hash.ToLowerInvariant()};box=@{apk_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $boxApk).Hash.ToLowerInvariant()}}
        app_evidence=$appEvidence;box_events=$boxEvents
    }
    $evidencePath=Join-Path $runDirectory "$Scenario.evidence.json"
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 100), $utf8)
    & $dart tool/ble11/validate_ble11_evidence.dart $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "Phone virtual endpoint evidence failed validation: $evidencePath" }
    Write-Host "Phone virtual endpoint scenario passed: $evidencePath; real BirdBox remains pending."
} finally { Pop-Location }
