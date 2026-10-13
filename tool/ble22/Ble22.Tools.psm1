#requires -Version 7.4
Set-StrictMode -Version Latest

function Write-Ble22Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

function Invoke-Ble22Process {
    param([string]$File, [string[]]$Arguments, [string]$WorkingDirectory,
        [int]$TimeoutSeconds=30, [scriptblock]$Pump, [string]$LogPath)
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$File; $info.WorkingDirectory=$WorkingDirectory
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    foreach($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    $stdout=$null; $stderr=$null; $timedOut=$false; $started=$false
    try {
        if(!$process.Start()) { throw 'Process could not start.' }
        $started=$true
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while(!$process.WaitForExit(250)) {
            if([DateTime]::UtcNow -ge $deadline) { $timedOut=$true; $process.Kill($true); break }
            if($Pump) { & $Pump | Out-Null }
        }
        $process.WaitForExit()
        $result=@{exit_code=$(if($timedOut){124}else{$process.ExitCode});timed_out=$timedOut;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult()}
        if($LogPath) { [IO.File]::WriteAllText($LogPath,$result.stdout+"`n"+$result.stderr,[Text.UTF8Encoding]::new($false)) }
        return $result
    } finally {
        if($started -and !$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        if($LogPath -and $stdout -and $stderr) {
            try { [IO.File]::WriteAllText($LogPath,$stdout.GetAwaiter().GetResult()+"`n"+$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false)) } catch { }
        }
        $process.Dispose()
    }
}

function Receive-Ble22Artifact([string]$Adb,[string]$Serial,[string]$Package,[string]$Name,[string]$Destination,[string]$Sha256) {
    if($Name -notmatch '^[A-Za-z0-9._-]+\.(json|zip)$') { throw 'Invalid export artifact filename.' }
    $info=[Diagnostics.ProcessStartInfo]::new(); $info.FileName=$Adb
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    foreach($argument in @('-s',$Serial,'exec-out','run-as',$Package,'cat',"cache/ble_diagnostics/$Name")) { $info.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
    $stream=$null; $started=$false
    try {
        $started=$process.Start()
        if(!$started) { throw 'Export retrieval could not start.' }
        $stream=[IO.File]::Create($Destination)
        $copy=$process.StandardOutput.BaseStream.CopyToAsync($stream)
        $stderr=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit(30000)) { $process.Kill($true); $process.WaitForExit(); throw 'Export retrieval timed out.' }
        $copy.GetAwaiter().GetResult(); $null=$stderr.GetAwaiter().GetResult()
        if($process.ExitCode -ne 0) { throw 'Actual device export retrieval failed.' }
        $stream.Dispose(); $stream=$null
        if((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) { throw 'Received export SHA-256 differs from App.' }
    } finally {
        if($started -and !$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        if($stream) { $stream.Dispose() }; $process.Dispose()
    }
}

function Invoke-Ble22Adb {
    param([string]$Adb,[string]$Serial,[string[]]$Arguments,[string]$Root,[switch]$Optional)
    $result=Invoke-Ble22Process -File $Adb -Arguments (@('-s',$Serial)+$Arguments) -WorkingDirectory $Root
    if(!$Optional -and $result.exit_code -ne 0) { throw "ADB operation failed (exit=$($result.exit_code))." }
    if($result.exit_code -ne 0) { return '' }
    return $result.stdout.Trim()
}

function Assert-Ble22PhoneOnline([string]$Adb,[string]$Serial,[string]$Root) {
    if((Invoke-Ble22Adb $Adb $Serial @('get-state') $Root) -ne 'device') { throw 'Selected phone is not online and authorized.' }
}

function New-Ble22PhoneIdentity([string]$Serial,[string]$PhysicalSerial,[string]$Model,[string]$Manufacturer,[int]$Sdk) {
    if(!$PhysicalSerial -or $PhysicalSerial -in @('unknown','null','0') -or !$Model -or !$Manufacturer -or $Sdk -lt 23) { throw 'Physical phone identity is unavailable.' }
    $physicalAlias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($PhysicalSerial.Trim()))).ToLowerInvariant()
    $selectorAlias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Serial))).ToLowerInvariant()
    return @{device_alias=$physicalAlias;physical_device_alias=$physicalAlias;physical_identity_source='android_serial_property';adb_selector=$Serial;adb_selector_alias=$selectorAlias;adb_transport=$(if($Serial -match ':\d+$'){'tcpip'}else{'usb'});model=$Model;manufacturer=$Manufacturer;sdk_int=$Sdk}
}

function Get-Ble22PhoneIdentity([string]$Adb,[string]$Serial,[string]$Root) {
    Assert-Ble22PhoneOnline $Adb $Serial $Root
    $physical=Invoke-Ble22Adb $Adb $Serial @('shell','getprop','ro.serialno') $Root
    if(!$physical -or $physical -in @('unknown','null','0')) { $physical=Invoke-Ble22Adb $Adb $Serial @('shell','getprop','ro.boot.serialno') $Root }
    return New-Ble22PhoneIdentity $Serial $physical (Invoke-Ble22Adb $Adb $Serial @('shell','getprop','ro.product.model') $Root) (Invoke-Ble22Adb $Adb $Serial @('shell','getprop','ro.product.manufacturer') $Root) ([int](Invoke-Ble22Adb $Adb $Serial @('shell','getprop','ro.build.version.sdk') $Root))
}

function Assert-Ble22PhonePair($App,$Box,[string]$Role) {
    if($App.physical_device_alias -eq $Box.physical_device_alias) { throw 'Both ADB selectors refer to the same physical phone.' }
    $huawei=if($Role -eq 'P1'){$App}else{$Box}; $vivo=if($Role -eq 'P1'){$Box}else{$App}
    if($Role -notin @('P1','P2') -or $huawei.model -ne 'FIN-AL60' -or $huawei.sdk_int -ne 31 -or $vivo.model -ne 'vivo X20' -or $vivo.sdk_int -ne 27) { throw 'Phone identities do not match the Huawei/vivo role baseline.' }
}

function Get-Ble22PeerAddressHash([string]$Address,[string]$RunId) {
    if($Address -notmatch '^(?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$' -or $RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$') { throw 'Invalid current-run peer identity.' }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($RunId+':'+$Address.ToUpperInvariant()))).ToLowerInvariant()
}

function Get-Ble22ConnectedPeerHash($Events,[string]$RunId,[string]$Scenario) {
    $peers=@($Events | Where-Object { $_.schema_version -eq 2 -and $_.event_type -eq 'connection_state_changed' -and $_.fields['run_id'] -eq $RunId -and $_.fields['scenario'] -eq $Scenario -and $_.fields.status -eq 0 -and $_.fields.state -eq 2 } | ForEach-Object { $_.fields['peer_address_hash'] } | Where-Object { $_ -match '^[a-f0-9]{64}$' } | Sort-Object -Unique)
    if($peers.Count -eq 1) { return $peers[0] }
    return ''
}

function New-Ble22PairingPump {
    param([string]$Adb,[string]$AppSerial,[string]$BoxSerial,[string]$Root,[string]$RunId,[string]$Scenario,[string]$LogPath,
        [string]$AppPeerName='BirdBox-B1E11001',[string]$BoxPeerName='',
        [ValidateSet('Confirm','Cancel','Timeout')][string]$PairMode='Confirm',[switch]$ForegroundPairingSettings)
    $settingsState=@{opened=$false;appReturned=$false}
    # GetNewClosure copies variables, not caller-local functions. Only exported
    # module commands may be used after this callback leaves the runner scope.
    return {
        $null=Invoke-Ble22UiStep -Adb $Adb -Serial $AppSerial -Root $Root -Mode Pair -LogPath $LogPath -ExpectedPeerName $AppPeerName -RunId $RunId -PairMode $PairMode
        $raw=Invoke-Ble22Adb $Adb $BoxSerial @('shell','run-as','deckers.thibault.aves.virtualbirdbox.debug','cat','files/ble11-events.jsonl') $Root
        $events=@($raw -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
        $peerHash=Get-Ble22ConnectedPeerHash $events $RunId $Scenario
        if($ForegroundPairingSettings -and $peerHash -and !$settingsState.opened) {
            foreach($serial in @($AppSerial,$BoxSerial)) { Invoke-Ble22PairingSettings $Adb $serial $Root $RunId $LogPath }
            $settingsState.opened=$true
        }
        if($peerHash -or $BoxPeerName) { $null=Invoke-Ble22UiStep -Adb $Adb -Serial $BoxSerial -Root $Root -Mode Pair -LogPath $LogPath -ExpectedPeerName $BoxPeerName -ExpectedPeerAddressHash $peerHash -RunId $RunId }
        if($ForegroundPairingSettings -and $settingsState.opened -and !$settingsState.appReturned) {
            $resultRaw=Invoke-Ble22Adb $Adb $AppSerial @('shell','run-as','deckers.thibault.aves.bird','cat','files/ble22-last-result.json') $Root -Optional
            if($resultRaw) {
                $collected=$resultRaw | ConvertFrom-Json -AsHashtable
                if(Test-Ble22PendingExportCheckpoint $collected $RunId $Scenario) {
                    Invoke-Ble22CollectedAppForeground $Adb $AppSerial $Root $RunId $LogPath $collected.export_stage
                    $settingsState.appReturned=$true
                }
            }
        }
    }.GetNewClosure()
}

function Test-Ble22PendingExportCheckpoint($Result,[string]$RunId,[string]$Scenario) {
    if($Result -isnot [Collections.IDictionary]) { return $false }
    foreach($key in @('run_id','scenario','export_status','export_stage','app_evidence')) { if(!$Result.Contains($key)) { return $false } }
    if(!$Result -or $Result.run_id -ne $RunId -or $Result.scenario -ne $Scenario -or $Result.export_status -ne 'pending' -or
        $Result.export_stage -notin @('connection_event_store','connection_event_snapshot','export_build_identity','native_file_prepare')) { return $false }
    $app=$Result.app_evidence
    if($app -isnot [Collections.IDictionary]) { return $false }
    foreach($key in @('capture_status','scenario','endpoint_kind','build')) { if(!$app.Contains($key)) { return $false } }
    if($app.build -isnot [Collections.IDictionary] -or !$app.build.Contains('package_id')) { return $false }
    return $app -and $app.capture_status -in @('completed','failed') -and $app.scenario -eq $Scenario -and
        $app.endpoint_kind -eq 'virtual_birdbox' -and $app.build.package_id -eq 'deckers.thibault.aves.bird'
}

function Invoke-Ble22CollectedAppForeground([string]$Adb,[string]$Serial,[string]$Root,[string]$RunId,[string]$LogPath,[string]$ExportStage) {
    Assert-Ble22PhoneOnline $Adb $Serial $Root
    $alias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Serial))).ToLowerInvariant()
    $mutex=[Threading.Mutex]::new($false,"Local\BLE22-UI-$alias")
    $locked=$false
    try {
        $locked=$mutex.WaitOne(5000)
        if(!$locked) { throw 'Another operator owns this phone UI.' }
        $before=Invoke-Ble22Adb $Adb $Serial @('shell','pidof','deckers.thibault.aves.bird') $Root
        if($before -notmatch '^\d+$') { throw 'No unique running test App process.' }
        $null=Invoke-Ble22Adb $Adb $Serial @('shell','am','start','-n','deckers.thibault.aves.bird/deckers.thibault.aves.MainActivity') $Root
        $after=Invoke-Ble22Adb $Adb $Serial @('shell','pidof','deckers.thibault.aves.bird') $Root
        if($after -ne $before) { throw 'Test App process changed during foreground return.' }
        $record=@{run_id=$RunId;occurred_at=[DateTime]::UtcNow.ToString('o');adb_selector_alias=$alias;mode='environment';decision=@{action='collected_test_app_returned_to_foreground';export_stage=$ExportStage;existing_process_verified=$true;not_product_pre_pairing_requirement=$true}}
        [IO.File]::AppendAllText($LogPath,($record | ConvertTo-Json -Depth 5 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}

function Invoke-Ble22PairingSettings([string]$Adb,[string]$Serial,[string]$Root,[string]$RunId,[string]$LogPath) {
    Assert-Ble22PhoneOnline $Adb $Serial $Root
    $alias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Serial))).ToLowerInvariant()
    $mutex=[Threading.Mutex]::new($false,"Local\BLE22-UI-$alias")
    $locked=$false
    try {
        $locked=$mutex.WaitOne(5000)
        if(!$locked) { throw 'Another operator owns this phone UI.' }
        $null=Invoke-Ble22Adb $Adb $Serial @('shell','am','start','-a','android.settings.BLUETOOTH_SETTINGS') $Root
        $record=@{run_id=$RunId;occurred_at=[DateTime]::UtcNow.ToString('o');adb_selector_alias=$alias;mode='environment';decision=@{action='test_pairing_settings_foreground';not_product_pre_pairing_requirement=$true}}
        [IO.File]::AppendAllText($LogPath,($record | ConvertTo-Json -Depth 5 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}

function Test-Ble22PeerPrompt([string]$Text,[string]$ExpectedPeerName,[string]$ExpectedPeerAddressHash,[string]$RunId) {
    if($ExpectedPeerAddressHash) {
        if($ExpectedPeerAddressHash -notmatch '^[a-f0-9]{64}$' -or !$RunId) { return $false }
        $addresses=@([regex]::Matches($Text,'(?i)(?:[a-f0-9]{2}:){5}[a-f0-9]{2}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        if($addresses.Count -ne 1) { return $false }
        return (Get-Ble22PeerAddressHash $addresses[0] $RunId) -eq $ExpectedPeerAddressHash
    }
    if(!$ExpectedPeerName -or $ExpectedPeerName -match '^(?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$') { return $false }
    return $Text.Contains($ExpectedPeerName)
}

function Get-Ble22SettingsDetailPeerHash([string]$ActivityDump,[string]$Package,[string]$RunId) {
    $activity=if($Package -eq 'com.android.settings'){'com\.android\.settings/\.Settings\$DeviceProfilesSettingsActivity'}elseif($Package -eq 'com.android.bluetoothsettings'){'com\.android\.bluetoothsettings/\.SubSettings'}else{return ''}
    $blocks=[regex]::Matches($ActivityDump,'(?ms)^\s*ACTIVITY '+$activity+'\b.*?(?=^\s*ACTIVITY |\z)')
    if($blocks.Count -ne 1 -or $blocks[0].Value -notmatch 'DeviceProfilesSettings') { return '' }
    $addresses=@([regex]::Matches($blocks[0].Value,'(?m)^\s*mArguments=Bundle\[.*?(?:DEVICE_ID|device)=((?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2})(?=[,}\]])') | ForEach-Object {$_.Groups[1].Value.ToUpperInvariant()} | Sort-Object -Unique)
    if($addresses.Count -ne 1) { return '' }
    return Get-Ble22PeerAddressHash $addresses[0] $RunId
}

function Get-Ble22TestBondResetAction([xml]$Xml,[string]$ExpectedPeerName,[string]$PeerAddressHash,[string]$RunId,[string]$ActivityDump='') {
    $nodes=@($Xml.SelectNodes('//node[@enabled="true"]'))
    $allowed=@('com.android.settings','com.android.bluetoothsettings')
    if(@($nodes | Where-Object { $_.GetAttribute('package') -and $_.GetAttribute('package') -notin ($allowed+@('com.android.systemui')) }).Count) { throw 'Foreign surface is visible.' }
    foreach($package in $allowed) {
        $owned=@($nodes | Where-Object { $_.GetAttribute('package') -eq $package })
        $name=@($owned | Where-Object { $_.GetAttribute('text') -eq $ExpectedPeerName })
        $address=@($owned | Where-Object { Test-Ble22PeerPrompt $_.GetAttribute('text') '' $PeerAddressHash $RunId })
        $nativeIdentity=$ActivityDump -and (Get-Ble22SettingsDetailPeerHash $ActivityDump $package $RunId) -eq $PeerAddressHash
        $button=@($owned | Where-Object { $_.GetAttribute('text') -in @('取消配对','Unpair','Forget') } | ForEach-Object {
            $label=$_; $control=$label
            while($control -and $control.Name -eq 'node' -and $control.GetAttribute('package') -eq $package -and $control.GetAttribute('clickable') -ne 'true') { $control=$control.ParentNode }
            if($control -and $control.Name -eq 'node' -and $control.GetAttribute('package') -eq $package -and $control.GetAttribute('clickable') -eq 'true') { $control }
            elseif($nativeIdentity -and $package -eq 'com.android.bluetoothsettings' -and $label.GetAttribute('resource-id') -eq 'android:id/title' -and $label.GetAttribute('class') -eq 'android.widget.TextView' -and $label.GetAttribute('text') -eq '取消配对') { $label }
        })
        if($name.Count -lt 1 -or !($address.Count -eq 1 -or $nativeIdentity) -or $button.Count -ne 1) { continue }
        $bounds=[regex]::Match($button[0].GetAttribute('bounds'),'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        if(!$bounds.Success) { throw 'Missing observed unpair bounds.' }
        return @{action='owned_test_unpair_clicked';package=$package;x=[int](([int]$bounds.Groups[1].Value+[int]$bounds.Groups[3].Value)/2);y=[int](([int]$bounds.Groups[2].Value+[int]$bounds.Groups[4].Value)/2);baseline_status='native_verification_required';peer_identity_source=$(if($address.Count -eq 1){'visible_detail_address'}else{'observed_settings_fragment_arguments'});control_method=$(if($button[0].GetAttribute('clickable') -eq 'true'){'clickable_control'}else{'observed_vivo_preference_label'})}
    }
    throw 'Open the exact test peer detail with matching name and address; baseline is not verified.'
}

function Test-Ble22ReceivedCacheReplica($Evidence,$Receiver,$Phone,[string]$ActualHash,[long]$ActualBytes) {
    if(!$Evidence['export_received'] -or $Evidence['builds']['app']['entrypoint'] -ne 'integration_test/ble22_phone_test.dart') { return $false }
    $identity=$Evidence['phones']['app']
    $matches=if($identity['physical_device_alias']){$identity['physical_device_alias'] -eq $Phone.physical_device_alias}else{$identity['device_alias'] -eq $Phone.adb_selector_alias}
    if(!$matches) { return $false }
    $artifact=$Evidence['export']; $name=$artifact['file_name']
    if($name -notmatch '^BirdBox_BLE_[A-Za-z0-9._-]+\.(json|zip)$') { throw 'Unsafe cache artifact filename.' }
    if(!$Receiver['verified'] -or $Receiver['run_id'] -ne $Evidence['run_id'] -or $Receiver['file_name'] -ne $name -or $Receiver['file_sha256'] -ne $artifact['sha256'] -or $Receiver['payload_sha256'] -ne $artifact['payload_sha256'] -or $Receiver['bytes'] -ne $artifact['bytes'] -or $ActualHash -ne $artifact['sha256'] -or $ActualBytes -ne $artifact['bytes']) { throw 'Actual received file and independent verification do not match.' }
    return $true
}

function Get-Ble22InstalledHash([string]$Adb,[string]$Serial,[string]$Package,[string]$Root) {
    $path=Invoke-Ble22Adb $Adb $Serial @('shell','pm','path',$Package) $Root -Optional
    if($path -notmatch '^package:([^\r\n]+)$') { return $null }
    $hash=Invoke-Ble22Adb $Adb $Serial @('shell','sha256sum',$Matches[1]) $Root
    if($hash -notmatch '^([0-9a-f]{64})\s') { throw 'Installed APK hash is unavailable.' }
    return $Matches[1]
}

function Get-Ble22TransportPermissions([string]$Package,[int]$Sdk) {
    if($Package -eq 'deckers.thibault.aves.virtualbirdbox.debug') {
        if($Sdk -ge 31) { return @('android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_ADVERTISE') }
        return @()
    }
    if($Package -eq 'deckers.thibault.aves.bird') {
        if($Sdk -ge 31) { return @('android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_CONNECT') }
        return @('android.permission.ACCESS_FINE_LOCATION')
    }
    throw 'Unknown transport endpoint package.'
}

function Test-Ble22AdvertisingEvidence($Events,[string]$Scenario,[string]$RunId='') {
    $current=@($Events | Where-Object { $_.schema_version -eq 2 -and $_.fields -and $_.fields.scenario -eq $Scenario -and (!$RunId -or $_.fields['run_id'] -eq $RunId) })
    $started=@($current | Where-Object { $_.event_type -eq 'server_starting' -and $_.fields.encrypted_write_permissions -eq $true }).Count -gt 0
    $service=@($current | Where-Object { $_.event_type -eq 'service_added' -and $_.fields.status -eq 0 -and $_.fields.characteristic_count -eq 5 }).Count -gt 0
    $advertising=@($current | Where-Object { $_.event_type -eq 'advertising_started' }).Count -gt 0
    return $started -and $service -and $advertising
}

function Get-Ble22UiAction {
    param([xml]$Xml,[ValidateSet('Install','Pair','Discover','AppButton')][string]$Mode,
        [string]$ExpectedAppLabel,[string]$ExpectedPeerName='BirdBox-B1E11001',
        [string]$ExpectedPageText,[string]$ButtonText,[string]$ExpectedPackage='deckers.thibault.aves.bird',
        [string]$ExpectedPeerAddressHash,[string]$RunId,[ValidateSet('Confirm','Cancel','Timeout')][string]$PairMode='Confirm')
    $nodes=@($Xml.SelectNodes('//node[@enabled="true"]'))
    $packages=@($nodes | ForEach-Object { $_.GetAttribute('package') } | Sort-Object -Unique)
    if($Mode -eq 'AppButton') {
        if(!$ExpectedPageText -or !$ButtonText -or $ExpectedPackage -notin @('deckers.thibault.aves.bird','deckers.thibault.aves.bird.sim','deckers.thibault.aves.virtualbirdbox.debug')) { return @{action='blocked';reason='application_context_required'} }
        if(@($packages | Where-Object { $_ -and $_ -notin @($ExpectedPackage,'com.android.systemui') }).Count) { return @{action='blocked';reason='foreign_surface_visible'} }
        $owned=@($nodes | Where-Object { $_.GetAttribute('package') -eq $ExpectedPackage })
        if(@($owned | Where-Object { $_.GetAttribute('text') -eq $ExpectedPageText }).Count -ne 1) { return @{action='none';reason='application_page_not_matched'} }
        $buttons=@($owned | Where-Object { $_.GetAttribute('text') -eq $ButtonText -and $_.GetAttribute('clickable') -eq 'true' })
        if($buttons.Count -ne 1) { return @{action='blocked';reason='application_control_not_unique'} }
        $bounds=[regex]::Match($buttons[0].GetAttribute('bounds'),'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if(!$bounds.Success) { return @{action='blocked';reason='missing_observed_bounds'} }
        return @{action='test_application_button_confirmed';package=$ExpectedPackage;x=[int](($bounds.Groups[1].Value -as [int])+($bounds.Groups[3].Value -as [int]))/2;y=[int](($bounds.Groups[2].Value -as [int])+($bounds.Groups[4].Value -as [int]))/2}
    }
    $allowed=if($Mode -eq 'Install') {
        @('com.android.packageinstaller','com.google.android.packageinstaller','com.vivo.packageinstaller')
    } else { @('com.android.settings','com.android.bluetooth','com.android.bluetoothsettings','com.android.systemui') }
    foreach($package in $allowed) {
        $owned=@($nodes | Where-Object { $_.GetAttribute('package') -eq $package })
        $texts=@($owned | ForEach-Object { $_.GetAttribute('text') })
        $text=$texts -join ' '
        $buttons=@(); $action=''
        $pairDialog=$text -match '配对请求|Pairing request' -or @($owned | Where-Object { $_.GetAttribute('resource-id') -eq 'android:id/button1' -and $_.GetAttribute('text') -in @('配对','确定','配对并连接','Pair','OK') }).Count -gt 0
        if($Mode -eq 'Install' -and $ExpectedAppLabel -and $texts -contains $ExpectedAppLabel) {
            $buttons=@($owned | Where-Object { $_.GetAttribute('text') -in @('安装','继续安装','Install','Continue installation') })
            $action='test_apk_install_confirmed'
        } elseif($Mode -eq 'Pair' -and $pairDialog -and $text -match '配对|pair') {
            if($package -eq 'com.android.systemui') {
                $buttons=@($owned | Where-Object { (Test-Ble22PeerPrompt $_.GetAttribute('text') $ExpectedPeerName $ExpectedPeerAddressHash $RunId) -and $_.GetAttribute('text') -match '配对请求|Pairing request' })
                $action='test_pairing_notification_opened'
            } else {
                $prompt=@($owned | Where-Object { $_.GetAttribute('resource-id') -match '(:id/message|:id/message_subhead|:id/pairing_subhead|:id/pairing_caption|:id/device_name)$' -and (Test-Ble22PeerPrompt $_.GetAttribute('text') $ExpectedPeerName $ExpectedPeerAddressHash $RunId) })
                if($prompt.Count -ne 1) { return @{action='blocked';reason='unrecognized_or_ambiguous_pairing_peer'} }
                if(@($owned | Where-Object { $_.GetAttribute('class') -like '*EditText*' }).Count) { return @{action='blocked';reason='input_requires_operator'} }
                if($PairMode -eq 'Timeout') { return @{action='none';reason='owned_pairing_intentionally_left_for_timeout'} }
                $buttonId=if($PairMode -eq 'Cancel'){'android:id/button2'}else{'android:id/button1'}
                $labels=if($PairMode -eq 'Cancel'){@('取消','拒绝','Cancel','Reject')}else{@('配对','确定','配对并连接','Pair','OK')}
                $buttons=@($owned | Where-Object { $_.GetAttribute('resource-id') -eq $buttonId -and $_.GetAttribute('text') -in $labels })
                $action=if($PairMode -eq 'Cancel'){'test_pairing_cancelled'}else{'test_pairing_confirmed'}
            }
        } elseif($Mode -eq 'Discover' -and $text -match '120' -and $text -match '检测|发现|discover') {
            $buttons=@($owned | Where-Object { $_.GetAttribute('resource-id') -eq 'android:id/button1' -and $_.GetAttribute('text') -in @('允许','确定','Allow','OK') })
            $action='test_peripheral_discoverable_120s'
        }
        if($buttons.Count -and @($owned | Where-Object { $_.GetAttribute('class') -like '*EditText*' }).Count) { return @{action='blocked';reason='input_requires_operator'} }
        if($buttons.Count -eq 1) {
            $bounds=[regex]::Match($buttons[0].GetAttribute('bounds'),'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
            if(!$bounds.Success) { return @{action='blocked';reason='missing_observed_bounds'} }
            return @{action=$action;package=$package;x=[int](($bounds.Groups[1].Value -as [int])+($bounds.Groups[3].Value -as [int]))/2;y=[int](($bounds.Groups[2].Value -as [int])+($bounds.Groups[4].Value -as [int]))/2}
        }
        if($buttons.Count -gt 1) { return @{action='blocked';reason='ambiguous_controls'} }
    }
    return @{action='none';reason='no_owned_confirmation';visible_packages=$packages}
}

function Invoke-Ble22UiStep {
    param([string]$Adb,[string]$Serial,[string]$Root,[string]$Mode,[string]$LogPath,
        [string]$ExpectedAppLabel,[string]$ExpectedPeerName='BirdBox-B1E11001',
        [string]$ExpectedPageText,[string]$ButtonText,[string]$ExpectedPackage='deckers.thibault.aves.bird',
        [string]$ExpectedPeerAddressHash,[string]$RunId,[ValidateSet('Confirm','Cancel','Timeout')][string]$PairMode='Confirm')
    Assert-Ble22PhoneOnline $Adb $Serial $Root
    $alias=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Serial))).ToLowerInvariant()
    $mutex=[Threading.Mutex]::new($false,"Local\BLE22-UI-$alias")
    $locked=$false; $remote="/data/local/tmp/ble22-ui-$PID.xml"
    try {
        $locked=$mutex.WaitOne(1000)
        if(!$locked) { throw 'Another operator owns this phone UI.' }
        $null=Invoke-Ble22Adb $Adb $Serial @('shell','uiautomator','dump',$remote) $Root
        [xml]$xml=Invoke-Ble22Adb $Adb $Serial @('shell','cat',$remote) $Root
        $decision=Get-Ble22UiAction $xml $Mode $ExpectedAppLabel $ExpectedPeerName $ExpectedPageText $ButtonText $ExpectedPackage $ExpectedPeerAddressHash $RunId $PairMode
        $entry=@{occurred_at=[DateTime]::UtcNow.ToString('o');adb_selector_alias=$alias;run_id=$RunId;mode=$Mode;pair_mode=$PairMode;decision=$decision}
        [IO.File]::AppendAllText($LogPath,($entry | ConvertTo-Json -Depth 10 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
        if($decision.action -eq 'blocked') { throw "UI action blocked: $($decision.reason)" }
        if($decision.action -ne 'none') { $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','tap',[string][int]$decision.x,[string][int]$decision.y) $Root }
        return $decision
    } finally {
        if($locked) {
            $null=Invoke-Ble22Adb $Adb $Serial @('shell','rm','-f',$remote) $Root -Optional
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Install-Ble22Apk {
    param([string]$Adb,[string]$Serial,[string]$Root,[string]$Apk,[string]$Sha256,[string]$Package,
        [string]$AppLabel,[ValidateSet('Transport','Ui')][string]$PermissionMode='Ui',[string]$OutputDirectory,
        [switch]$AutoConfirm)
    if((Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) { throw 'Frozen APK hash changed.' }
    if((Get-Ble22InstalledHash $Adb $Serial $Package $Root) -eq $Sha256) { return }
    $arguments=@('-s',$Serial,'install','--no-streaming','-r')
    if($PermissionMode -eq 'Transport') { $arguments+='-g' }
    $arguments+=$Apk
    $pump=if($AutoConfirm) { { $null=Invoke-Ble22UiStep $Adb $Serial $Root 'Install' (Join-Path $OutputDirectory 'operator-actions.jsonl') $AppLabel }.GetNewClosure() } else { $null }
    $result=Invoke-Ble22Process -File $Adb -Arguments $arguments -WorkingDirectory $Root -TimeoutSeconds 120 -Pump $pump -LogPath (Join-Path $OutputDirectory "install-$Package.log")
    if($result.exit_code -ne 0) { throw "APK installation failed or timed out (exit=$($result.exit_code))." }
    if((Get-Ble22InstalledHash $Adb $Serial $Package $Root) -ne $Sha256) { throw 'Installed APK differs from the frozen candidate.' }
}

function Get-Ble22SourceIdentity([string]$Root) {
    $paths=@(& git -C $Root -c core.quotepath=false ls-files --cached --others --exclude-standard | Where-Object { $_ -and $_ -notmatch '^(docs|doc|\.run)/' -and $_ -notmatch '(^|/)README\.md$' } | Select-Object -Unique)
    if($LASTEXITCODE -ne 0 -or !$paths.Count) { throw 'Unable to enumerate build sources.' }
    $ordered=[Collections.Generic.List[string]]::new()
    foreach($path in $paths) { $ordered.Add($path) }; $ordered.Sort([StringComparer]::Ordinal)
    $lines=@($ordered | ForEach-Object { $file=Join-Path $Root $_; $hash=if(Test-Path -LiteralPath $file -PathType Leaf){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}else{'<deleted>'}; "$_`t$hash" })
    $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")+"`n"))).ToLowerInvariant()
    return @{fingerprint=$fingerprint;lines=$lines}
}

Export-ModuleMember -Function *-Ble22*
