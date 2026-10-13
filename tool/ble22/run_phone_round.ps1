#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppSerial,
    [Parameter(Mandatory)][string]$BoxSerial,
    [Parameter(Mandatory)][string]$AppApk,
    [Parameter(Mandatory)][string]$BoxApk,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$AppSha256,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$BoxSha256,
    [Parameter(Mandatory)][ValidateSet('P1','P2')][string]$Role,
    [ValidateSet('bond_first','already_bonded','auth_once','auth_persistent','att_timeout_first','att_timeout_middle','att_timeout_last','notification_failure','disconnect_once','response_delay','response_wrong','response_duplicate','business_timeout')][string]$Scenario='bond_first',
    [ValidateRange(1,100)][int]$Iteration=1,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$')][string]$RoundId,
    [string]$Adb='D:/Androidstudio2/platform-tools/adb.exe',
    [string]$Dart='D:/flutter344/flutter/bin/cache/dart-sdk/bin/dart.exe',
    [string]$FlutterTools='D:/flutter344/flutter/bin/cache/flutter_tools.snapshot',
    [string]$Python='python',
    [switch]$AutoConfirm,
    [switch]$ForegroundPairingSettings,
    [string]$AppPeerName='BirdBox-B1E11001',
    [string]$BoxPeerName='',
    [ValidateSet('Confirm','Cancel','Timeout')][string]$PairMode='Confirm'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$app='deckers.thibault.aves.bird'; $box='deckers.thibault.aves.virtualbirdbox.debug'
$runId="$(Get-Date -Format yyyyMMdd-HHmmss)-$Role-$Scenario-$Iteration-$([Guid]::NewGuid().ToString('N').Substring(0,6))"
$output=Join-Path $root "outputs/ble22/$RoundId/$runId"
$null=New-Item -ItemType Directory -Force $output
$utf8=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=$utf8; $OutputEncoding=$utf8
$forwardPort=$null; $appStarted=$false; $boxStarted=$false; $configPushed=$false; $configRemote="/data/local/tmp/ble22-$runId.json"
$evidence=@{
    schema_version=2;evidence_kind='virtual_birdbox_phone';hardware_status='pending';security_flow='bond_first';endpoint_kind='virtual_birdbox';scenario=$Scenario
    round_id=$RoundId;run_id=$runId;role=$Role;iteration=$Iteration;generated_at=[DateTime]::UtcNow.ToString('o')
    permission_mode='transport_auto_grant';run_status='startup_failed';last_stage='preflight';test_invoked=$false;test_exit_code=$null;validation_exit_code=$null
    debug_transport='adb_forward_loopback_vm_service_auth_disabled';phones=@{};box_events=@();app_evidence=$null;export=$null
    pairing_expected_outcome=$PairMode;pairing_check_status='not_checked'
    phone_peripheral_settings_foreground_condition=[bool]$ForegroundPairingSettings
    builds=@{app=@{apk_sha256=$AppSha256;entrypoint='integration_test/ble22_phone_test.dart';local_verified=$false;installed_verified=$false};box=@{apk_sha256=$BoxSha256;manual_install_debug=$true;local_verified=$false;installed_verified=$false}}
    cleanup=@{errors=@()}
    role_switch=@{owned_previous_roles_stopped=$false;current_advertising_verified=$false}
    native_logs=@{}
}
function AdbApp([string[]]$arguments) { Invoke-Ble22Adb $Adb $AppSerial $arguments $root }
function AdbBox([string[]]$arguments) { Invoke-Ble22Adb $Adb $BoxSerial $arguments $root }
function Read-Result {
    $raw=Invoke-Ble22Adb $Adb $AppSerial @('shell','run-as',$app,'cat','files/ble22-last-result.json') $root -Optional
    if($raw) {
        $result=$raw | ConvertFrom-Json -AsHashtable
        if($result.run_id -ne $runId -or $result.scenario -ne $Scenario) { throw 'Stale App result belongs to another run.' }
        $evidence.app_evidence=$result.app_evidence; $evidence.export=$result.export
        $evidence.export_status=$result.export_status
        if($result.export_stage) { $evidence.export_stage=$result.export_stage }
        if($result.export_failure_stage) { $evidence.export_failure_stage=$result.export_failure_stage }
        if($result.test_harness) { $evidence.test_harness=$result.test_harness }
        if($result.export_error_kind) { $evidence.export_error_kind=$result.export_error_kind }
    }
}
function Read-BoxEvents {
    $raw=AdbBox @('shell','run-as',$box,'cat','files/ble11-events.jsonl')
    $evidence.box_events=@($raw -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
}
function Receive-Export {
    $name=$evidence.export.file_name
    if($name -notmatch '^[A-Za-z0-9._-]+\.(json|zip)$') { throw 'Invalid export artifact filename.' }
    $destination=Join-Path $output $name
    Receive-Ble22Artifact $Adb $AppSerial $app $name $destination $evidence.export.sha256
    $evidence.export_received=$true
}
function Save-NativeObservation([string]$serial,[string]$package,[string]$tag,[string]$label) {
    $record=@{status='missing_process';tag=$tag;path="$label-native.log"}
    $evidence.native_logs[$label]=$record
    try {
        $taskAppPid=Invoke-Ble22Adb $Adb $serial @('shell','pidof',$package) $root -Optional
        if($taskAppPid -notmatch '^\d+$') { return }
        $result=Invoke-Ble22Process -File $Adb -Arguments @('-s',$serial,'logcat','-d',"--pid=$taskAppPid",'-v','threadtime','-s',$tag) -WorkingDirectory $root -LogPath (Join-Path $output $record.path)
        if($result.exit_code -ne 0) { throw 'Native process log collection failed.' }
        $record.status=if($result.stdout.Trim()){'collected'}else{'empty'}
        $record.sha256=(Get-FileHash -LiteralPath (Join-Path $output $record.path) -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch { $record.status='failed'; $record.reason=$_.Exception.Message }
}
try {
    if($AppSerial -eq $BoxSerial) { throw 'Two distinct phones are required.' }
    if($PairMode -ne 'Confirm' -and $Scenario -ne 'bond_first') { throw 'Pairing stop checks require the first-bond scenario.' }
    if($ForegroundPairingSettings -and !$AutoConfirm) { throw 'Foreground pairing settings requires the identified pairing observer.' }
    foreach($entry in @(@{path=$AppApk;sha=$AppSha256;role='app'},@{path=$BoxApk;sha=$BoxSha256;role='box'})) {
        if((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha) { throw 'Frozen APK hash changed.' }
        $evidence.builds[$entry.role].local_verified=$true
    }
    $evidence.last_stage='device_identity'; $evidence.phones=@{app=(Get-Ble22PhoneIdentity $Adb $AppSerial $root);box=(Get-Ble22PhoneIdentity $Adb $BoxSerial $root)}
    Assert-Ble22PhonePair $evidence.phones.app $evidence.phones.box $Role
    $evidence.last_stage='install'
    Install-Ble22Apk -Adb $Adb -Serial $AppSerial -Root $root -Apk $AppApk -Sha256 $AppSha256 -Package $app -AppLabel '拍鸟伴侣' -PermissionMode Transport -OutputDirectory $output -AutoConfirm:$AutoConfirm
    $evidence.builds.app.installed_verified=$true
    Install-Ble22Apk -Adb $Adb -Serial $BoxSerial -Root $root -Apk $BoxApk -Sha256 $BoxSha256 -Package $box -AppLabel 'BLE-11 Virtual BirdBox' -PermissionMode Transport -OutputDirectory $output -AutoConfirm:$AutoConfirm
    $evidence.builds.box.installed_verified=$true
    $evidence.last_stage='transport_permissions'
    foreach($endpoint in @(@{serial=$AppSerial;package=$app;sdk=$evidence.phones.app.sdk_int},@{serial=$BoxSerial;package=$box;sdk=$evidence.phones.box.sdk_int})) {
        $permissions=@(Get-Ble22TransportPermissions $endpoint.package $endpoint.sdk)
        foreach($permission in $permissions) { $null=Invoke-Ble22Adb $Adb $endpoint.serial @('shell','pm','grant',$endpoint.package,$permission) $root }
    }
    $null=AdbApp @('shell','am','force-stop',$box); $null=AdbBox @('shell','am','force-stop',$app)
    $null=AdbBox @('shell','am','force-stop',$box)
    $evidence.role_switch.owned_previous_roles_stopped=$true
    Assert-Ble22PhoneOnline $Adb $AppSerial $root; Assert-Ble22PhoneOnline $Adb $BoxSerial $root
    $evidence.last_stage='box_advertising'; $boxStarted=$true
    $launch=AdbBox @('shell','am','start','-W','-n',"$box/deckers.thibault.aves.virtualbirdbox.VirtualBirdBoxActivity",'--es','scenario',$Scenario,'--es','run_id',$runId,'--ez','reset_log','true')
    [IO.File]::WriteAllText((Join-Path $output 'box-launch.log'),$launch,$utf8)
    $advertising=$false
    for($i=0;$i -lt 20;$i++) {
        try { Read-BoxEvents } catch { $evidence.box_events=@() }
        $advertising=Test-Ble22AdvertisingEvidence $evidence.box_events $Scenario $runId
        if($advertising) { break }; Start-Sleep -Milliseconds 500
    }
    if(!$advertising) { throw 'Current scenario has no actual advertising callback.' }
    $evidence.role_switch.current_advertising_verified=$true
    $evidence.last_stage='app_configuration'
    Write-Ble22Json (Join-Path $output 'config.json') @{scenario=$Scenario;run_id=$runId}
    $null=AdbApp @('push',(Join-Path $output 'config.json'),$configRemote); $configPushed=$true
    $null=AdbApp @('shell','run-as',$app,'mkdir','-p','files')
    $null=AdbApp @('shell','run-as',$app,'cp',$configRemote,'files/ble22-config.json')
    $null=AdbApp @('shell','run-as',$app,'rm','-f','files/ble22-last-result.json')
    $null=AdbApp @('shell','am','force-stop',$app)
    $evidence.last_stage='vm_discovery'; $appStarted=$true
    $launch=AdbApp @('shell','am','start','-W','-n',"$app/deckers.thibault.aves.MainActivity",'--ez','start-paused','true','--ez','disable-service-auth-codes','true')
    [IO.File]::WriteAllText((Join-Path $output 'app-launch.log'),$launch,$utf8)
    $vmPort=$null
    for($i=0;$i -lt 4;$i++) {
        $appPid=AdbApp @('shell','pidof',$app)
        if($appPid) {
            $vmLog=AdbApp @('logcat','-d',"--pid=$appPid",'-s','flutter')
            $addresses=[regex]::Matches($vmLog,'http://127\.0\.0\.1:(\d+)/(?:[A-Za-z0-9_=\-]+/)?')
            if($addresses.Count) { $vmPort=$addresses[$addresses.Count-1].Groups[1].Value; break }
        }; Start-Sleep -Milliseconds 500
    }
    if(!$vmPort) {
        $appUid=AdbApp @('shell','run-as',$app,'id','-u')
        if($appUid -notmatch '^\d+$') { throw 'Cannot identify test app UID.' }
        $sockets=AdbApp @('shell','run-as',$app,'cat','/proc/net/tcp')
        $ports=@($sockets -split "`n" | ForEach-Object { if($_ -match "^\s*\d+: 0100007F:([0-9A-Fa-f]{4}) \S+ 0A \S+ \S+ \S+ $appUid\s") { [Convert]::ToInt32($Matches[1],16) } } | Select-Object -Unique)
        if($ports.Count -ne 1) { throw 'No unique app-owned loopback VM listener.' }; $vmPort=[string]$ports[0]
    }
    $evidence.last_stage='vm_forward'; $forwardPort=AdbApp @('forward','tcp:0',"tcp:$vmPort")
    if($forwardPort -notmatch '^\d+$') { throw 'VM service forward failed.' }
    $vmUri="http://127.0.0.1:$forwardPort/"
    if((Invoke-RestMethod "${vmUri}getVM" -TimeoutSec 10).result.type -ne 'VM') { throw 'App-owned listener is not a Dart VM.' }
    $evidence.last_stage='integration'; $evidence.run_status='test_failed'; $evidence.test_invoked=$true
    $pump=if($AutoConfirm) { New-Ble22PairingPump -Adb $Adb -AppSerial $AppSerial -BoxSerial $BoxSerial -Root $root -RunId $runId -Scenario $Scenario -LogPath (Join-Path $output 'operator-actions.jsonl') -AppPeerName $AppPeerName -BoxPeerName $BoxPeerName -PairMode $PairMode -ForegroundPairingSettings:$ForegroundPairingSettings }else{$null}
    $drive=Invoke-Ble22Process -File $Dart -Arguments @($FlutterTools,'drive','--no-pub','--flavor','bird','-d',$AppSerial,'--target','integration_test/ble22_phone_test.dart','--driver','tool/ble22/integration_driver.dart',"--use-existing-app=$vmUri",'--keep-app-running','--timeout=210') -WorkingDirectory $root -TimeoutSeconds 240 -Pump $pump -LogPath (Join-Path $output 'integration.log')
    $evidence.test_exit_code=$drive.exit_code
    Read-Result; Read-BoxEvents
    if(!$evidence.app_evidence) { throw 'Integration ended without an App evidence record.' }
    if($evidence.export_status -eq 'prepared') { $evidence.last_stage='export_retrieval'; Receive-Export }
    if($drive.exit_code -ne 0) { throw 'Integration test failed; actual App result was retained.' }
    if($evidence.export_status -ne 'prepared') { throw 'Actual diagnostic export was not prepared.' }
    $evidence.last_stage='collected'; $evidence.run_status='ready_to_validate'
} catch {
    $evidence.failure=@{stage=$evidence.last_stage;kind=$_.Exception.GetType().Name;reason=$_.Exception.Message}
} finally {
    if($appStarted) { try { Read-Result } catch { $evidence.cleanup.errors+=@('result_read_failed') } }
    if($boxStarted) { try { Read-BoxEvents } catch { $evidence.cleanup.errors+=@('box_events_read_failed') } }
    if($appStarted) { Save-NativeObservation $AppSerial $app BluetoothGatt app }
    if($boxStarted) { Save-NativeObservation $BoxSerial $box BluetoothGattServer box }
    if($evidence.export -and !$evidence.export_received) { try { Receive-Export } catch { $evidence.cleanup.errors+=@('failed_run_export_retrieval_failed') } }
    if($forwardPort -match '^\d+$') { try { $null=AdbApp @('forward','--remove',"tcp:$forwardPort") } catch { $evidence.cleanup.errors+=@('owned_forward_cleanup_failed') } }
    foreach($owned in @(@{started=$appStarted;serial=$AppSerial;package=$app},@{started=$boxStarted;serial=$BoxSerial;package=$box})) {
        if($owned.started) { try { $null=Invoke-Ble22Adb $Adb $owned.serial @('shell','am','force-stop',$owned.package) $root } catch { $evidence.cleanup.errors+=@('owned_app_cleanup_failed') } }
    }
    if($configPushed) { try { $null=Invoke-Ble22Adb $Adb $AppSerial @('shell','rm','-f',$configRemote) $root } catch { $evidence.cleanup.errors+=@('temporary_config_cleanup_failed') } }
    if($evidence.cleanup.errors.Count -and $evidence.run_status -eq 'ready_to_validate') { $evidence.run_status='cleanup_failed' }
    Write-Ble22Json (Join-Path $output 'evidence.json') $evidence
}
# Validate the final collected events after owned-resource cleanup, so a later
# read or cleanup failure cannot borrow an earlier passing validation log.
if($evidence.run_status -eq 'ready_to_validate') {
    try {
        $evidence.last_stage='validation'; $evidence.run_status='passed'
        Write-Ble22Json (Join-Path $output 'evidence.json') $evidence
        $validation=Invoke-Ble22Process -File $Dart -Arguments @('tool/ble11/validate_ble11_evidence.dart',(Join-Path $output 'evidence.json')) -WorkingDirectory $root -TimeoutSeconds 60 -LogPath (Join-Path $output 'validation.log')
        $evidence.validation_exit_code=$validation.exit_code
        if($validation.exit_code -ne 0) { throw 'Strict evidence validation failed.' }
        $evidence.last_stage='completed'
        if($Scenario -eq 'bond_first') { $evidence.pairing_check_status='passed_normal_first_bond' }
    } catch {
        $evidence.run_status='validation_failed'
        $evidence.failure=@{stage=$evidence.last_stage;kind=$_.Exception.GetType().Name;reason=$_.Exception.Message}
    } finally { Write-Ble22Json (Join-Path $output 'evidence.json') $evidence }
}
if($PairMode -ne 'Confirm') {
    $check=Invoke-Ble22Process -File $Python -Arguments @('tool/ble22/verify_pairing_stop.py',$output) -WorkingDirectory $root -TimeoutSeconds 30 -LogPath (Join-Path $output 'pairing-stop-validation.log')
    $evidence.pairing_check_status=if($check.exit_code -eq 0){'passed_expected_stop'}else{'failed_or_incomplete'}
    Write-Ble22Json (Join-Path $output 'evidence.json') $evidence
}
Write-Output "BLE22_RUN $output status=$($evidence.run_status) stage=$($evidence.last_stage)"
if($evidence.run_status -ne 'passed') { exit 1 }
exit 0
