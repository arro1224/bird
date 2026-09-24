[CmdletBinding()]
param(
    [ValidateSet('success', 'auto_bond', 'fallback_once', 'disconnect_once')]
    [string]$Scenario = 'success',
    [string]$AndroidSdk = 'D:\Androidstudio2',
    [string]$FlutterSdk = 'D:\flutter344\flutter',
    [string]$AppAvd = 'ble11_app_api36',
    [string]$BoxAvd = 'ble11_box_api36',
    [string]$OutputRoot = 'outputs\ble11',
    [switch]$WipeData,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$androidRoot = Join-Path $repositoryRoot 'android'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$dart = Join-Path $FlutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
$flutterTools = Join-Path $FlutterSdk 'bin\cache\flutter_tools.snapshot'
$gradle = Join-Path $androidRoot 'gradlew.bat'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $repositoryRoot (Join-Path $OutputRoot "$timestamp-$Scenario")
$null = New-Item -ItemType Directory -Path $runDirectory -Force
$env:ANDROID_TMP = $runDirectory
$appSerial = 'emulator-5554'
$boxSerial = 'emulator-5556'
$appProcess = $null
$boxProcess = $null
$appPackage = 'deckers.thibault.aves.bird'
$boxPackage = 'deckers.thibault.aves.virtualbirdbox.debug'

function Get-EmulatorVersion {
    $line = (& $emulator -version | Select-Object -First 1)
    $match = [regex]::Match($line, '(\d+)\.(\d+)\.(\d+)')
    if (!$match.Success) { throw "Unable to parse emulator version: $line" }
    $major = [int]$match.Groups[1].Value
    $minor = [int]$match.Groups[2].Value
    if ($major -lt 36 -or ($major -eq 36 -and $minor -lt 5)) {
        throw "BLE-11 requires Android Emulator 36.5+; installed version is $($match.Value)."
    }
    return $match.Value
}

function Wait-ForBoot([string]$serial) {
    & $adb -s $serial wait-for-device
    if ($LASTEXITCODE -ne 0) { throw "ADB could not find $serial" }
    $deadline = (Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $deadline) {
        $completed = (& $adb -s $serial shell getprop sys.boot_completed 2>$null).Trim()
        if ($completed -eq '1') { return }
        Start-Sleep -Seconds 2
    }
    throw "Timed out waiting for $serial to boot."
}

function Start-Ble11Avd(
    [string]$name,
    [int]$port,
    [string]$label
) {
    # Start-Process flattens an ArgumentList array. Keep netsim's two options inside
    # one explicitly quoted argument so --rssi is not interpreted by emulator.exe.
    $arguments = "-avd `"$name`" -port $port -no-window -no-audio -no-boot-anim " +
        "-gpu swiftshader_indirect -netsim-args=`"--pcap --rssi=ble:-55`""
    if ($WipeData) { $arguments += ' -wipe-data' }
    return Start-Process -FilePath $emulator -ArgumentList $arguments -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $runDirectory "$label-emulator.stdout.log") `
        -RedirectStandardError (Join-Path $runDirectory "$label-emulator.stderr.log")
}

function Assert-AvdIdentity([string]$serial, [string]$expectedName) {
    $actualName = (& $adb -s $serial shell getprop ro.boot.qemu.avd_name).Trim()
    if ($actualName -ne $expectedName) {
        throw "$serial is '$actualName', expected '$expectedName'. Stop the unrelated emulator before BLE-11."
    }
}

function Grant-BluetoothPermissions([string]$serial, [string]$packageName, [string[]]$permissions) {
    foreach ($permission in $permissions) {
        & $adb -s $serial shell pm grant $packageName $permission
        if ($LASTEXITCODE -ne 0) { throw "Unable to grant $permission to $packageName on $serial" }
    }
}

function Stop-OwnedEmulator([string]$serial, $process) {
    if ($null -eq $process) { return }
    & $adb -s $serial emu kill | Out-Null
    try { $process.WaitForExit(30000) } catch { Write-Warning "Unable to wait for $serial shutdown." }
}

$emulatorVersion = Get-EmulatorVersion
$availableAvds = @(& $emulator -list-avds)
if ($availableAvds -notcontains $AppAvd -or $availableAvds -notcontains $BoxAvd) {
    throw 'BLE-11 AVDs are missing. Run tool\ble11\setup_ble11_avds.ps1 first.'
}

try {
    $connected = (& $adb devices) -join "`n"
    if ($connected -match [regex]::Escape($appSerial) -or $connected -match [regex]::Escape($boxSerial)) {
        throw 'Emulator ports 5554 and 5556 must be free so BLE-11 can own both netsim/PCAP launches.'
    }
    $appProcess = Start-Ble11Avd $AppAvd 5554 'app'
    $boxProcess = Start-Ble11Avd $BoxAvd 5556 'box'
    Wait-ForBoot $appSerial
    Wait-ForBoot $boxSerial
    Assert-AvdIdentity $appSerial $AppAvd
    Assert-AvdIdentity $boxSerial $BoxAvd
    & $adb -s $appSerial shell svc bluetooth enable | Out-Null
    & $adb -s $boxSerial shell svc bluetooth enable | Out-Null
    Start-Sleep -Seconds 3

    Push-Location $androidRoot
    try {
        & $gradle :virtualBirdBox:assembleDebug
        if ($LASTEXITCODE -ne 0) { throw 'Virtual BirdBox APK build failed.' }
    } finally {
        Pop-Location
    }
    Push-Location $repositoryRoot
    try {
        & $dart $flutterTools build apk --debug --flavor bird --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'BirdBox App debug APK build failed.' }
    } finally {
        Pop-Location
    }

    $boxApk = Join-Path $repositoryRoot 'build\virtualBirdBox\outputs\apk\debug\virtualBirdBox-debug.apk'
    $appApk = Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-bird-debug.apk'
    & $adb -s $boxSerial install -r -t -g $boxApk
    if ($LASTEXITCODE -ne 0) { throw 'Virtual BirdBox APK install failed.' }
    & $adb -s $appSerial install -r -g $appApk
    if ($LASTEXITCODE -ne 0) { throw 'BirdBox App APK install failed.' }
    Grant-BluetoothPermissions $boxSerial $boxPackage @(
        'android.permission.BLUETOOTH_ADVERTISE',
        'android.permission.BLUETOOTH_CONNECT'
    )
    Grant-BluetoothPermissions $appSerial $appPackage @(
        'android.permission.BLUETOOTH_SCAN',
        'android.permission.BLUETOOTH_CONNECT'
    )

    & $adb -s $boxSerial logcat -c
    & $adb -s $boxSerial shell am force-stop $boxPackage
    & $adb -s $boxSerial shell am start -n "$boxPackage/deckers.thibault.aves.virtualbirdbox.VirtualBirdBoxActivity" --es scenario $Scenario --ez reset_log true
    if ($LASTEXITCODE -ne 0) { throw 'Virtual BirdBox launch failed.' }
    $advertisingDeadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $boxLogcat = (& $adb -s $boxSerial logcat -d -s BLE11_VIRTUAL_BOX:I '*:S') -join "`n"
    } while ($boxLogcat -notmatch 'advertising_started' -and (Get-Date) -lt $advertisingDeadline)
    if ($boxLogcat -notmatch 'advertising_started') {
        throw 'Virtual BirdBox did not start advertising within 30 seconds.'
    }

    Push-Location $repositoryRoot
    try {
        $testOutput = @(& $dart $flutterTools test integration_test\ble11_dual_avd_test.dart `
            -d $appSerial --flavor bird --no-pub "--dart-define=BLE11_SCENARIO=$Scenario" 2>&1)
        $testExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $testOutput | Set-Content -LiteralPath (Join-Path $runDirectory 'flutter-integration.log') -Encoding utf8

    $appEvidenceLine = $testOutput | Where-Object { $_ -match 'BLE11_SIMULATED_EVIDENCE\s+(\{.*\})' } | Select-Object -Last 1
    $appEvidence = $null
    if ($null -ne $appEvidenceLine -and $appEvidenceLine -match 'BLE11_SIMULATED_EVIDENCE\s+(\{.*\})') {
        $appEvidence = $Matches[1] | ConvertFrom-Json -AsHashtable
    }

    $boxLogLines = @(& $adb -s $boxSerial shell run-as $boxPackage cat files/ble11-events.jsonl 2>$null)
    $boxEvents = @()
    foreach ($line in $boxLogLines) {
        if (![string]::IsNullOrWhiteSpace($line)) {
            $boxEvents += ($line | ConvertFrom-Json -AsHashtable)
        }
    }
    $appApi = (& $adb -s $appSerial shell getprop ro.build.version.sdk).Trim()
    $boxApi = (& $adb -s $boxSerial shell getprop ro.build.version.sdk).Trim()

    if (!$KeepRunning) {
        Stop-OwnedEmulator $appSerial $appProcess
        $appProcess = $null
        Stop-OwnedEmulator $boxSerial $boxProcess
        $boxProcess = $null
        Start-Sleep -Seconds 2
    }

    $pcapFiles = @()
    $artifactFiles = Get-ChildItem -LiteralPath $runDirectory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]netsimd[\\/]pcap[\\/]' }
    foreach ($file in $artifactFiles) {
        $relative = [System.IO.Path]::GetRelativePath($runDirectory, $file.FullName).Replace('\', '/')
        $pcapFiles += @{
            path = $relative
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        }
    }

    $evidence = [ordered]@{
        schema_version = 1
        evidence_kind = 'simulated'
        hardware_status = 'pending'
        scenario = $Scenario
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        test_exit_code = $testExitCode
        emulator = [ordered]@{
            version = $emulatorVersion
            app_avd = $AppAvd
            box_avd = $BoxAvd
            app_api = $appApi
            box_api = $boxApi
        }
        netsim = [ordered]@{
            pcap_requested = $true
            ble_rssi_dbm = -55
            pcap_files = $pcapFiles
        }
        app_evidence = $appEvidence
        box_events = $boxEvents
    }
    $evidencePath = Join-Path $runDirectory "$Scenario.evidence.json"
    $evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    & $dart tool\ble11\validate_ble11_evidence.dart $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "BLE-11 evidence validation failed: $evidencePath" }
    Write-Host "BLE-11 scenario passed: $evidencePath"
} finally {
    if (!$KeepRunning) {
        Stop-OwnedEmulator $appSerial $appProcess
        Stop-OwnedEmulator $boxSerial $boxProcess
    }
}
