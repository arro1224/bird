#requires -Version 7.4
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tests=0
function Check([bool]$Condition,[string]$Message) { if(!$Condition) { throw $Message }; $script:tests++ }
Check ((@(Get-Ble22TransportPermissions 'deckers.thibault.aves.virtualbirdbox.debug' 31) -join ',') -eq 'android.permission.BLUETOOTH_CONNECT,android.permission.BLUETOOTH_ADVERTISE') 'Server received undeclared scan permission.'
Check (@(Get-Ble22TransportPermissions 'deckers.thibault.aves.virtualbirdbox.debug' 27).Count -eq 0) 'Legacy server received undeclared location permission.'
Check ((@(Get-Ble22TransportPermissions 'deckers.thibault.aves.bird' 31) -join ',') -eq 'android.permission.BLUETOOTH_SCAN,android.permission.BLUETOOTH_CONNECT') 'Modern App permission preparation is wrong.'
Check ((@(Get-Ble22TransportPermissions 'deckers.thibault.aves.bird' 27) -join ',') -eq 'android.permission.ACCESS_FINE_LOCATION') 'Legacy App permission preparation is wrong.'
$endpointEvents=@(
    @{schema_version=2;event_type='server_starting';fields=@{scenario='already_bonded';encrypted_write_permissions=$true}},
    @{schema_version=2;event_type='service_added';fields=@{scenario='already_bonded';status=0;characteristic_count=5}},
    @{schema_version=2;event_type='advertising_started';fields=@{scenario='already_bonded'}}
)
Check (Test-Ble22AdvertisingEvidence $endpointEvents 'already_bonded') 'Actual nested endpoint schema was not recognized.'
Check (!(Test-Ble22AdvertisingEvidence $endpointEvents 'auth_once')) 'Old scenario advertising was accepted.'
Check (!(Test-Ble22AdvertisingEvidence @($endpointEvents[0],$endpointEvents[1]) 'already_bonded')) 'API availability was accepted without advertising callback.'
$endpointEvents[1].fields.characteristic_count=4
Check (!(Test-Ble22AdvertisingEvidence $endpointEvents 'already_bonded')) 'Incomplete service was accepted.'
$endpointEvents[1].fields.characteristic_count=5; $endpointEvents[1].fields.status=133
Check (!(Test-Ble22AdvertisingEvidence $endpointEvents 'already_bonded')) 'Failed service registration was accepted.'
$endpointEvents[1].fields.status=0
foreach($entry in $endpointEvents) { $entry.fields.run_id='offline-run' }
Check (Test-Ble22AdvertisingEvidence $endpointEvents 'already_bonded' 'offline-run') 'Current-run advertising was not recognized.'
Check (!(Test-Ble22AdvertisingEvidence $endpointEvents 'already_bonded' 'old-run')) 'Old advertising in the same scenario was accepted.'
function Ui([string]$Package,[string]$Text,[string]$Button,[string]$Label='',[switch]$HasInput,[switch]$Duplicate) {
    $extra=if($HasInput){'<node enabled="true" class="android.widget.EditText" package="'+$Package+'" />'}else{''}
    $buttonNode='<node enabled="true" package="'+$Package+'" resource-id="android:id/button1" text="'+$Button+'" bounds="[20,40][100,120]" />'
    return [xml]('<hierarchy><node enabled="true" package="'+$Package+'"><node enabled="true" package="'+$Package+'" resource-id="android:id/message" text="'+$Text+'" /><node enabled="true" package="'+$Package+'" text="'+$Label+'" />'+$extra+$buttonNode+$(if($Duplicate){$buttonNode}else{''})+'</node></hierarchy>')
}
$action=Get-Ble22UiAction (Ui 'com.android.settings' '蓝牙配对请求 BirdBox-B1E11001' '配对') Pair '' 'BirdBox-B1E11001'
Check ($action.action -eq 'test_pairing_confirmed' -and $action.x -eq 60 -and $action.y -eq 80) 'Observed pairing bounds were not used.'
Check ((Get-Ble22UiAction (Ui 'com.android.settings' '蓝牙配对请求 PersonalWatch' '配对') Pair '' 'BirdBox-B1E11001').action -eq 'blocked') 'Unrelated bond was accepted.'
Check ((Get-Ble22UiAction (Ui 'com.example.other' '蓝牙配对请求 BirdBox-B1E11001' '配对') Pair '' 'BirdBox-B1E11001').action -eq 'none') 'Foreign package was accepted.'
Check ((Get-Ble22UiAction (Ui 'com.android.settings' '蓝牙配对请求 BirdBox-B1E11001' '配对' -HasInput) Pair '' 'BirdBox-B1E11001').reason -eq 'input_requires_operator') 'PIN input was accepted.'
Check ((Get-Ble22UiAction (Ui 'com.android.settings' '蓝牙配对请求 BirdBox-B1E11001' '配对' -Duplicate) Pair '' 'BirdBox-B1E11001').reason -eq 'ambiguous_controls') 'Ambiguous buttons were accepted.'
Check ((Get-Ble22UiAction (Ui 'com.vivo.packageinstaller' '安装应用' '继续安装' '拍鸟伴侣') Install '拍鸟伴侣').action -eq 'test_apk_install_confirmed') 'Known installer was not recognized.'
Check ((Get-Ble22UiAction (Ui 'com.vivo.packageinstaller' '安装应用' '继续安装' 'PersonalApp') Install '拍鸟伴侣').action -eq 'none') 'Unrelated APK was accepted.'
Check ((Get-Ble22UiAction (Ui 'com.android.settings' '蓝牙可被发现 120 秒' '允许') Discover '').action -eq 'test_peripheral_discoverable_120s') '120s discoverability was not recognized.'
Check ((Get-Ble22UiAction (Ui 'com.android.settings' '开启蓝牙' '允许') Discover '').action -eq 'none') 'Different Bluetooth request was accepted.'
[xml]$pairedList='<hierarchy><node enabled="true" package="com.android.settings" text="已配对的设备" /><node enabled="true" package="com.android.settings" text="BirdBox-B1E11001" /></hierarchy>'
Check ((Get-Ble22UiAction $pairedList Pair '' 'BirdBox-B1E11001').action -eq 'none') 'Ordinary paired-device list was mistaken for an unknown pairing dialog.'
[xml]$appUi='<hierarchy><node enabled="true" package="deckers.thibault.aves.bird" text="连接设备" /><node enabled="true" package="deckers.thibault.aves.bird" text="开始扫描" clickable="true" bounds="[0,0][100,100]" /></hierarchy>'
Check ((Get-Ble22UiAction $appUi AppButton '' '' '连接设备' '开始扫描').action -eq 'test_application_button_confirmed') 'Known application control was not matched.'
Check ((Get-Ble22UiAction $appUi AppButton '' '' '网络设置' '开始扫描').action -eq 'none') 'Wrong application page was accepted.'
Check ((Get-Ble22UiAction $appUi AppButton '' '' '' '开始扫描').action -eq 'blocked') 'Unspecified application context was accepted.'
$pwsh=(Get-Process -Id $PID).Path
$phone=New-Ble22PhoneIdentity 'usb-selector' 'physical-vivo' 'vivo X20' 'vivo' 27
$networkPhone=New-Ble22PhoneIdentity '192.168.1.5:5555' 'physical-vivo' 'vivo X20' 'vivo' 27
$huawei=New-Ble22PhoneIdentity 'huawei-usb' 'physical-huawei' 'FIN-AL60' 'HUAWEI' 31
Check ($phone.device_alias -eq $networkPhone.device_alias -and $phone.adb_selector_alias -ne $networkPhone.adb_selector_alias) 'One phone acquired two physical identities.'
Check ($networkPhone.adb_transport -eq 'tcpip' -and $phone.adb_transport -eq 'usb') 'ADB transport was misreported.'
$rejected=$false; try { Assert-Ble22PhonePair $phone $networkPhone P2 } catch { $rejected=$true }
Check $rejected 'Two selectors of one phone were accepted.'
Assert-Ble22PhonePair $phone $huawei P2
$rejected=$false; try { Assert-Ble22PhonePair $phone $huawei P1 } catch { $rejected=$true }
Check $rejected 'Incorrect physical roles were accepted.'
$rejected=$false; try { New-Ble22PhoneIdentity 'selector' '' 'vivo X20' 'vivo' 27 } catch { $rejected=$true }
Check $rejected 'Missing physical identity was accepted.'
$peerHash=Get-Ble22PeerAddressHash 'AA:BB:CC:DD:EE:FF' 'offline-run'
[xml]$addressUi='<hierarchy><node enabled="true" package="com.android.settings" text="蓝牙配对请求" /><node enabled="true" package="com.android.settings" resource-id="com.android.settings:id/message_subhead" text="aa:bb:cc:dd:ee:ff" /><node enabled="true" package="com.android.settings" resource-id="android:id/button1" text="配对" bounds="[20,40][100,120]" /><node enabled="true" package="com.android.settings" resource-id="android:id/button2" text="取消" bounds="[0,0][20,20]" /></hierarchy>'
$params=@{Xml=$addressUi;Mode='Pair';ExpectedPeerName='';ExpectedPeerAddressHash=$peerHash;RunId='offline-run'}
Check ((Get-Ble22UiAction @params).action -eq 'test_pairing_confirmed') 'Huawei address-only subhead was not matched to the actual peer hash.'
Check ((Get-Ble22UiAction @params -PairMode Cancel).action -eq 'test_pairing_cancelled') 'Owned cancellation was not distinct.'
Check ((Get-Ble22UiAction @params -PairMode Timeout).reason -eq 'owned_pairing_intentionally_left_for_timeout') 'Owned timeout was not observed without clicking.'
$params.RunId='stale-run'
Check ((Get-Ble22UiAction @params).action -eq 'blocked') 'An address hash from another run was accepted.'
Check ((Get-Ble22UiAction $addressUi Pair '' 'AA:BB:CC:DD:EE:FF').action -eq 'blocked') 'Bare address without current-run identity evidence was accepted.'
$observations=@(@{schema_version=2;event_type='connection_state_changed';fields=@{run_id='offline-run';scenario='bond_first';status=0;state=2;peer_address_hash=$peerHash}})
Check ((Get-Ble22ConnectedPeerHash $observations 'offline-run' 'bond_first') -eq $peerHash) 'Current native peer observation was rejected.'
Check (!(Get-Ble22ConnectedPeerHash $observations 'stale-run' 'bond_first')) 'Stale native peer was accepted.'
$observations+=@{schema_version=2;event_type='connection_state_changed';fields=@{run_id='offline-run';scenario='bond_first';status=0;state=2;peer_address_hash=('b'*64)}}
Check (!(Get-Ble22ConnectedPeerHash $observations 'offline-run' 'bond_first')) 'Ambiguous peer observations were accepted.'
[xml]$detail='<hierarchy><node enabled="true" package="com.android.settings" text="BirdBox-B1E11001" /><node enabled="true" package="com.android.settings" text="AA:BB:CC:DD:EE:FF" /><node enabled="true" package="com.android.settings" text="取消配对" clickable="true" bounds="[0,0][20,20]" /></hierarchy>'
Check ((Get-Ble22TestBondResetAction $detail 'BirdBox-B1E11001' $peerHash 'offline-run').baseline_status -eq 'native_verification_required') 'Unpair click was misreported as an unbonded baseline.'
$rejected=$false; try { Get-Ble22TestBondResetAction $detail 'BirdBox-B1E11001' ('b'*64) 'offline-run' } catch { $rejected=$true }
Check $rejected 'Unpair matched only a name without actual peer identity.'
$nativeDetail=@'
  ACTIVITY com.android.bluetoothsettings/.SubSettings token pid=123
    DeviceProfilesSettings{test}
      mArguments=Bundle[{device=AA:BB:CC:DD:EE:FF}]
'@
[xml]$noAddressDetail='<hierarchy><node enabled="true" package="com.android.bluetoothsettings" text="BirdBox-B1E11001" /><node enabled="true" package="com.android.bluetoothsettings" text="BirdBox-B1E11001" /><node enabled="true" package="com.android.bluetoothsettings" clickable="true" bounds="[0,0][20,20]"><node enabled="true" package="com.android.bluetoothsettings" text="取消配对" clickable="false" /></node></hierarchy>'
Check ((Get-Ble22TestBondResetAction $noAddressDetail 'BirdBox-B1E11001' $peerHash offline-run $nativeDetail).peer_identity_source -eq 'observed_settings_fragment_arguments') 'Actual detail arguments and inherited unpair control were not recognized.'
$rejected=$false; try { Get-Ble22TestBondResetAction $noAddressDetail 'BirdBox-B1E11001' ('b'*64) offline-run $nativeDetail } catch {$rejected=$true}
Check $rejected 'Mismatched native detail peer was accepted.'
Check (!(Get-Ble22SettingsDetailPeerHash ($nativeDetail -replace 'com.android.bluetoothsettings/.SubSettings','com.example.other/.SubSettings') com.android.bluetoothsettings offline-run)) 'Foreign activity arguments were accepted.'
Check (!(Get-Ble22SettingsDetailPeerHash ($nativeDetail + "`n      mArguments=Bundle[{device=11:22:33:44:55:66}]") com.android.bluetoothsettings offline-run)) 'Ambiguous native detail addresses were accepted.'
$huaweiDetail=@'
  ACTIVITY com.android.settings/.Settings$DeviceProfilesSettingsActivity token pid=123
    DeviceProfilesSettings{test}
      mArguments=Bundle[{:settings:source_metrics=24, DEVICE_ID=AA:BB:CC:DD:EE:FF, intent=Intent { test }}]
'@
Check ((Get-Ble22SettingsDetailPeerHash $huaweiDetail com.android.settings offline-run) -eq $peerHash) 'Actual Huawei detail device ID was not recognized.'
[xml]$vivoPreference='<hierarchy><node enabled="true" package="com.android.bluetoothsettings" text="BirdBox-B1E11001" /><node enabled="true" package="com.android.bluetoothsettings" text="取消配对" class="android.widget.TextView" resource-id="android:id/title" clickable="false" bounds="[0,537][270,602]" /></hierarchy>'
Check ((Get-Ble22TestBondResetAction $vivoPreference 'BirdBox-B1E11001' $peerHash offline-run $nativeDetail).control_method -eq 'observed_vivo_preference_label') 'Observed vivo preference label with exact native identity was not recognized.'
$rejected=$false; try {Get-Ble22TestBondResetAction $vivoPreference 'BirdBox-B1E11001' $peerHash offline-run} catch {$rejected=$true}
Check $rejected 'Nonclickable preference label without exact native identity was accepted.'
$artifact=@{file_name='BirdBox_BLE_offline.json';sha256=('a'*64);payload_sha256=('a'*64);bytes=10}
$received=@{verified=$true;run_id='offline-run';file_name=$artifact.file_name;file_sha256=$artifact.sha256;payload_sha256=$artifact.payload_sha256;bytes=10}
$e=@{run_id='offline-run';export_received=$true;export=$artifact;builds=@{app=@{entrypoint='integration_test/ble22_phone_test.dart'}};phones=@{app=$phone}}
Check (Test-Ble22ReceivedCacheReplica $e $received $networkPhone ('a'*64) 10) 'Verified same-phone received replica was not eligible.'
Check (!(Test-Ble22ReceivedCacheReplica $e $received $huawei ('a'*64) 10)) 'Another phone replica was eligible.'
$rejected=$false; try { Test-Ble22ReceivedCacheReplica $e $received $phone ('b'*64) 10 } catch { $rejected=$true }
Check $rejected 'Changed received bytes were eligible for cache release.'
$received.verified=$false
$rejected=$false; try { Test-Ble22ReceivedCacheReplica $e $received $phone ('a'*64) 10 } catch { $rejected=$true }
Check $rejected 'Unverified receiver result was eligible for cache release.'
$module=Get-Module Ble22.Tools
& $module {
    $original=(Get-Item Function:Invoke-Ble22Process).ScriptBlock
    try {
        Set-Item Function:Invoke-Ble22Process { return @{exit_code=1;stdout='device';stderr='offline'} }
        if(Invoke-Ble22Adb fake offline @('get-state') '.' -Optional) { throw 'Optional ADB failure leaked success-shaped stdout.' }
        $failed=$false; try { Assert-Ble22PhoneOnline fake offline '.' } catch { $failed=$true }
        if(!$failed) { throw 'Offline ADB phone was accepted.' }
    } finally { Set-Item Function:Invoke-Ble22Process $original }
}
Check $true 'Offline ADB checks completed.'
$checkpoint=@{run_id='offline-run';scenario='bond_first';export_status='pending';export_stage='export_build_identity';app_evidence=@{capture_status='completed';scenario='bond_first';endpoint_kind='virtual_birdbox';build=@{package_id='deckers.thibault.aves.bird'}}}
Check (Test-Ble22PendingExportCheckpoint $checkpoint offline-run bond_first) 'Actual collected pending export was rejected.'
Check (!(Test-Ble22PendingExportCheckpoint $checkpoint stale-run bond_first)) 'Stale result could foreground an App.'
Check (!(Test-Ble22PendingExportCheckpoint $checkpoint offline-run auth_once)) 'Another scenario could foreground an App.'
Check (!(Test-Ble22PendingExportCheckpoint @{} offline-run bond_first)) 'Incomplete result was accepted.'
$other=$checkpoint.Clone();$other.export_status='prepared'
Check (!(Test-Ble22PendingExportCheckpoint $other offline-run bond_first)) 'Prepared export unnecessarily foregrounds the App.'
$other=$checkpoint.Clone();$other.export_stage='unknown'
Check (!(Test-Ble22PendingExportCheckpoint $other offline-run bond_first)) 'Unknown collection stage was accepted.'
$other=$checkpoint.Clone();$other.app_evidence=@{capture_status='pending';scenario='bond_first';endpoint_kind='virtual_birdbox';build=@{package_id='deckers.thibault.aves.bird'}}
Check (!(Test-Ble22PendingExportCheckpoint $other offline-run bond_first)) 'Unfinished transport could be foregrounded.'
$other=$checkpoint.Clone();$other.app_evidence=@{capture_status='completed';scenario='bond_first';endpoint_kind='virtual_birdbox';build=@{package_id='foreign.app'}}
Check (!(Test-Ble22PendingExportCheckpoint $other offline-run bond_first)) 'Foreign package could be foregrounded.'
$originalAdb=(Get-Item Function:Invoke-Ble22Adb).ScriptBlock
$originalUi=(Get-Item Function:Invoke-Ble22UiStep).ScriptBlock
$originalSettings=(Get-Item Function:Invoke-Ble22PairingSettings).ScriptBlock
$originalForeground=(Get-Item Function:Invoke-Ble22CollectedAppForeground).ScriptBlock
$global:ble22FixtureCalls=[Collections.Generic.List[object]]::new()
$global:ble22FixtureSettings=[Collections.Generic.List[object]]::new()
$global:ble22FixtureForeground=[Collections.Generic.List[object]]::new()
$global:ble22FixtureResult=''
try {
    Set-Item Function:global:Invoke-Ble22Adb {
        param($Adb,$Serial,$Arguments,$Root)
        if($Adb -ne 'offline-never-call-adb') { throw 'Unexpected pairing reader executable.' }
        if($Serial -eq 'app-selector' -and $Arguments[-1] -eq 'files/ble22-last-result.json') { return $global:ble22FixtureResult }
        if($Serial -ne 'box-selector') { throw 'Unexpected pairing reader endpoint.' }
        return '{"schema_version":2,"event_type":"connection_state_changed","fields":{"run_id":"offline-run","scenario":"bond_first","status":0,"state":2,"peer_address_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
    }
    Set-Item Function:global:Invoke-Ble22UiStep {
        param($Adb,$Serial,$Root,$Mode,$LogPath,$ExpectedPeerName,$RunId,$PairMode='Confirm',$ExpectedPeerAddressHash)
        $global:ble22FixtureCalls.Add(@{serial=$Serial;run_id=$RunId;pair_mode=$PairMode;peer_hash=$ExpectedPeerAddressHash})
    }
    Set-Item Function:global:Invoke-Ble22PairingSettings {
        param($Adb,$Serial,$Root,$RunId,$LogPath)
        $global:ble22FixtureSettings.Add(@{serial=$Serial;run_id=$RunId})
    }
    Set-Item Function:global:Invoke-Ble22CollectedAppForeground {
        param($Adb,$Serial,$Root,$RunId,$LogPath,$ExportStage)
        $global:ble22FixtureForeground.Add(@{serial=$Serial;run_id=$RunId;export_stage=$ExportStage})
    }
    function Build-FixturePump { return New-Ble22PairingPump -Adb offline-never-call-adb -AppSerial app-selector -BoxSerial box-selector -Root $root -RunId offline-run -Scenario bond_first -LogPath unused -PairMode Cancel }
    $fixturePump=Build-FixturePump
    Remove-Item Function:Build-FixturePump
    & $fixturePump
    Check ($global:ble22FixtureCalls.Count -eq 2) 'Escaped pairing closure did not read current events and process both endpoints.'
    Check ($global:ble22FixtureCalls[0].pair_mode -eq 'Cancel' -and $global:ble22FixtureCalls[1].pair_mode -eq 'Confirm' -and $global:ble22FixtureCalls[1].peer_hash -eq ('a'*64)) 'Pairing closure lost mode or current-run peer identity.'
    Check ($global:ble22FixtureSettings.Count -eq 0) 'Pairing settings foreground was enabled without the explicit test condition.'
    $foregroundPump=New-Ble22PairingPump -Adb offline-never-call-adb -AppSerial app-selector -BoxSerial box-selector -Root $root -RunId offline-run -Scenario bond_first -LogPath unused -ForegroundPairingSettings
    & $foregroundPump
    & $foregroundPump
    Check ($global:ble22FixtureSettings.Count -eq 2 -and $global:ble22FixtureSettings[0].serial -eq 'app-selector' -and $global:ble22FixtureSettings[1].serial -eq 'box-selector') 'Foreground condition was repeated or used for wrong endpoints.'
    Check ($global:ble22FixtureForeground.Count -eq 0) 'Missing checkpoint could bring the App foreground.'
    $global:ble22FixtureResult=$checkpoint | ConvertTo-Json -Depth 6 -Compress
    & $foregroundPump
    & $foregroundPump
    Check ($global:ble22FixtureForeground.Count -eq 1 -and $global:ble22FixtureForeground[0].serial -eq 'app-selector' -and $global:ble22FixtureForeground[0].run_id -eq 'offline-run') 'Collected App foreground return was repeated or used for wrong endpoint.'
    & $fixturePump
    Check ($global:ble22FixtureForeground.Count -eq 1) 'App was foregrounded without the explicit settings condition.'
} finally {
    Set-Item Function:global:Invoke-Ble22Adb $originalAdb
    Set-Item Function:global:Invoke-Ble22UiStep $originalUi
    Set-Item Function:global:Invoke-Ble22PairingSettings $originalSettings
    Set-Item Function:global:Invoke-Ble22CollectedAppForeground $originalForeground
    Remove-Variable ble22FixtureCalls -Scope Global
    Remove-Variable ble22FixtureSettings -Scope Global
    Remove-Variable ble22FixtureForeground -Scope Global
    Remove-Variable ble22FixtureResult -Scope Global
}
$argumentFixture=Join-Path $root 'build/ble22-argument-fixture.ps1'
[IO.File]::WriteAllText($argumentFixture,'param([string]$Value) [Console]::Write($Value)',[Text.UTF8Encoding]::new($false))
$result=Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-File',$argumentFixture,'literal $value with spaces') -WorkingDirectory $root
Check ($result.exit_code -eq 0 -and $result.stdout -eq 'literal $value with spaces') 'ArgumentList did not preserve literal arguments.'
$result=Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 15') -WorkingDirectory $root -TimeoutSeconds 1
Check ($result.timed_out -and $result.exit_code -eq 124) 'Owned process timeout was not bounded.'
$missing=Join-Path $root 'build/ble22-offline-missing.apk'
$round='offline-fixture-'+[Guid]::NewGuid().ToString('N')
$result=Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'run_phone_round.ps1'),'-AppSerial','offline-app','-BoxSerial','offline-box','-AppApk',$missing,'-BoxApk',$missing,'-AppSha256',('a'*64),'-BoxSha256',('b'*64),'-Role','P2','-RoundId',$round,'-Adb',(Join-Path $root 'build/ble22-never-call-adb.exe')) -WorkingDirectory $root
Check ($result.exit_code -eq 1) 'Missing APK did not fail.'
$file=Get-ChildItem -LiteralPath (Join-Path $root "outputs/ble22/$round") -Filter evidence.json -Recurse | Select-Object -First 1
$record=Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
Check ($record.run_status -eq 'startup_failed' -and $record.last_stage -eq 'preflight') 'Preflight failure evidence missing.'
Check ($record.test_invoked -eq $false -and $null -eq $record.test_exit_code -and $null -eq $record.app_evidence) 'Unexecuted phone test was fabricated.'
Check ($record.hardware_status -eq 'pending' -and $record.builds.app.local_verified -eq $false) 'Preflight failure identity is misleading.'
$parseCount=0
foreach($script in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in @('.ps1','.psm1') }) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "PowerShell parse failed: $($script.Name)"; $parseCount++
}
Write-Output "BLE22_TOOLS_TESTS passed=$tests parsed_scripts=$parseCount phone_operations=0"
