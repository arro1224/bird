[CmdletBinding()]
param(
    [ValidateSet('bond_first', 'already_bonded', 'auth_once', 'auth_persistent', 'att_timeout_first', 'att_timeout_middle', 'att_timeout_last', 'notification_failure', 'disconnect_once', 'response_delay', 'response_wrong', 'response_duplicate', 'business_timeout')]
    [string]$Scenario = 'bond_first',
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
$pairingJob = $null
$startupRetryCount = 0
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

function Wait-ForBoot([string]$serial, $process) {
    $deadline = (Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) { throw "Owned emulator $serial exited before boot. Inspect emulator stdout/stderr in $runDirectory." }
        $state = (& $adb -s $serial get-state 2>$null)
        if ($state -ne 'device') { Start-Sleep -Seconds 2; continue }
        $completed = [string](& $adb -s $serial shell getprop sys.boot_completed 2>$null)
        $completed = $completed.Trim()
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
    # Emulator 37.2 netsimd accepts --pcap, but no longer accepts --rssi.
    $arguments = "-avd `"$name`" -port $port -no-window -no-audio -no-boot-anim " +
        "-gpu swiftshader_indirect -netsim-args `"--pcap`""
    if ($WipeData) { $arguments += ' -wipe-data' }
    return Start-Process -FilePath $emulator -ArgumentList $arguments -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $runDirectory "$label-emulator.stdout.log") `
        -RedirectStandardError (Join-Path $runDirectory "$label-emulator.stderr.log")
}

function Assert-AvdIdentity([string]$serial, [string]$expectedName) {
    $actualName = ([string](& $adb -s $serial shell getprop ro.boot.qemu.avd_name)).Trim()
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
    if ($process.HasExited) { return }
    $state = [string](& $adb -s $serial get-state 2>$null)
    if ($state.Trim() -eq 'device') { & $adb -s $serial emu kill | Out-Null }
    else {
        # Only terminate processes parented by the exact launcher created above.
        Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $process.Id -and $_.Name -like 'qemu*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
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
    Wait-ForBoot $appSerial $appProcess
    Wait-ForBoot $boxSerial $boxProcess
    Assert-AvdIdentity $appSerial $AppAvd
    Assert-AvdIdentity $boxSerial $BoxAvd
    foreach ($ownedSerial in @($appSerial, $boxSerial)) {
        # These test-owned AVDs must remain awake while Flutter builds and the
        # real Android peer confirmation UI is pending.
        & $adb -s $ownedSerial shell svc power stayon true | Out-Null
        & $adb -s $ownedSerial shell settings put system screen_off_timeout 600000 | Out-Null
        & $adb -s $ownedSerial shell input keyevent KEYCODE_WAKEUP | Out-Null
        & $adb -s $ownedSerial shell wm dismiss-keyguard | Out-Null
    }
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
        # The endpoint's private journal is authoritative; logcat filtering can
        # omit a startup callback on some emulator revisions.
        $boxLogcat = (& $adb -s $boxSerial shell run-as $boxPackage cat files/ble11-events.jsonl 2>$null) -join "`n"
    } while ($boxLogcat -notmatch 'advertising_started' -and (Get-Date) -lt $advertisingDeadline)
    if ($boxLogcat -notmatch 'advertising_started') {
        $boxLogcat | Set-Content -LiteralPath (Join-Path $runDirectory 'box-startup-events.jsonl') -Encoding utf8
        $hardwareErrors = @(& $adb -s $boxSerial logcat -d | Where-Object { $_ -match 'Abort message:.*Hardware Error Event with code 0x42' })
        if ($hardwareErrors.Count -gt 0) {
            $hardwareErrors | Set-Content -LiteralPath (Join-Path $runDirectory 'box-startup-hardware-error.log') -Encoding utf8
            $startupRetryCount = 1
            # Only the observed emulator controller crash is eligible. This is
            # before the App command, and does not relax bonding/retry assertions.
            & $adb -s $boxSerial shell am force-stop $boxPackage | Out-Null
            Start-Sleep -Seconds 3
            & $adb -s $boxSerial shell am start -n "$boxPackage/deckers.thibault.aves.virtualbirdbox.VirtualBirdBoxActivity" --es scenario $Scenario --ez reset_log true | Out-Null
            $advertisingDeadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 500
                $boxLogcat = (& $adb -s $boxSerial shell run-as $boxPackage cat files/ble11-events.jsonl 2>$null) -join "`n"
            } while ($boxLogcat -notmatch 'advertising_started' -and (Get-Date) -lt $advertisingDeadline)
        }
    }
    if ($boxLogcat -notmatch 'advertising_started') {
        throw 'Virtual BirdBox did not start advertising within 30 seconds.'
    }
    # Test-owned AVDs only: acknowledge the observed Android Pair button.
    # This does not fake bond broadcasts, privileged APIs or SMP completion.
    $pairingJob = Start-Job -FilePath (Join-Path $PSScriptRoot 'confirm_ble20_avd_pairing.ps1') -ArgumentList $adb,$runDirectory

    Push-Location $repositoryRoot
    try {
        $testOutput = @(& $dart $flutterTools test integration_test\ble11_dual_avd_test.dart `
            -d $appSerial --flavor bird --no-pub "--dart-define=BLE11_SCENARIO=$Scenario" 2>&1 |
            Tee-Object -FilePath (Join-Path $runDirectory 'flutter-integration.log'))
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
    $appApi = ([string](& $adb -s $appSerial shell getprop ro.build.version.sdk)).Trim()
    $boxApi = ([string](& $adb -s $boxSerial shell getprop ro.build.version.sdk)).Trim()

    if (!$KeepRunning) {
        Stop-OwnedEmulator $appSerial $appProcess
        $appProcess = $null
        Stop-OwnedEmulator $boxSerial $boxProcess
        $boxProcess = $null
        Start-Sleep -Seconds 2
    }

    $pcapFiles = @()
    $artifactFiles = Get-ChildItem -LiteralPath $runDirectory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]netsimd[\\/]pcaps?[\\/]' -and $_.Name -match 'BLUETOOTH|(?:^|-)bt[.-]' }
    if ($KeepRunning) {
        # Active captures are not finalized. Preserve JSON for diagnosis, but
        # intentionally leave capture proof absent so acceptance fails closed.
        $artifactFiles = @()
        Write-Warning 'KeepRunning is diagnostic only; closed PCAP evidence requires a normal run.'
    }
    foreach ($file in $artifactFiles) {
        $relative = [System.IO.Path]::GetRelativePath($runDirectory, $file.FullName).Replace('\', '/')
        $pcapFiles += @{
            path = $relative
            transport = 'bluetooth'
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        }
    }

    $evidence = [ordered]@{
        schema_version = 2
        evidence_kind = 'virtual_birdbox_avd'
        security_flow = 'bond_first'
        endpoint_kind = 'virtual_birdbox'
        hardware_status = 'pending'
        scenario = $Scenario
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        test_exit_code = $testExitCode
        endpoint_startup_retry_count = $startupRetryCount
        endpoint_startup_retry_reason = $(if ($startupRetryCount -eq 1) { 'avd_hci_hardware_error_0x42' } else { $null })
        builds = [ordered]@{
            app = @{ apk_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $appApk).Hash.ToLowerInvariant() }
            box = @{ apk_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $boxApk).Hash.ToLowerInvariant() }
        }
        emulator = [ordered]@{
            version = $emulatorVersion
            app_avd = $AppAvd
            box_avd = $BoxAvd
            app_api = $appApi
            box_api = $boxApi
        }
        netsim = [ordered]@{
            pcap_requested = $true
            ble_rssi_dbm = $null
            rssi_configuration = 'netsim_default_no_fixed_rssi_claim'
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
    if ($null -ne $pairingJob) { Stop-Job $pairingJob; Remove-Job $pairingJob }
    if (!$KeepRunning) {
        Stop-OwnedEmulator $appSerial $appProcess
        Stop-OwnedEmulator $boxSerial $boxProcess
    }
}
