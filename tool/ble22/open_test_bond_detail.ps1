#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Serial,[Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$PeerAddressHash,
    [Parameter(Mandatory)][string]$ActionLog,[string]$ExpectedPeerName='BirdBox-B1E11001',
    [ValidateRange(1,8)][int]$MaximumPages=6,[string]$Adb='D:/Androidstudio2/platform-tools/adb.exe')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$phone=Get-Ble22PhoneIdentity $Adb $Serial $root
$mutex=[Threading.Mutex]::new($false,"Local\BLE22-UI-$($phone.adb_selector_alias)")
$locked=$false; $remote="/data/local/tmp/ble22-details-$PID.xml"
function Snapshot {
    $null=Invoke-Ble22Adb $Adb $Serial @('shell','uiautomator','dump',$remote) $root
    [xml]$xml=Invoke-Ble22Adb $Adb $Serial @('shell','cat',$remote) $root
    $foreign=@($xml.SelectNodes('//node[@enabled="true"]') | Where-Object {$_.GetAttribute('package') -and $_.GetAttribute('package') -notin @('com.android.settings','com.android.bluetoothsettings','com.android.systemui')})
    if($foreign.Count) { throw 'Foreign surface is visible.' }
    return $xml
}
function Record($Decision) {
    $entry=@{run_id=$RunId;occurred_at=[DateTime]::UtcNow.ToString('o');phone=$phone;decision=$Decision;baseline_status='native_verification_required'}
    [IO.File]::AppendAllText($ActionLog,($entry | ConvertTo-Json -Depth 8 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
}
try {
    $locked=$mutex.WaitOne(5000)
    if(!$locked){throw 'Another operator owns this phone UI.'}
    $null=Invoke-Ble22Adb $Adb $Serial @('shell','am','start','-a','android.settings.BLUETOOTH_SETTINGS','-f','0x10008000') $root
    $seen=[Collections.Generic.HashSet[string]]::new()
    $expanded=$false
    for($page=0;$page -lt $MaximumPages;$page++) {
        $xml=Snapshot
        if(!$expanded) {
            $more=@($xml.SelectNodes('//node[@enabled="true"]') | Where-Object {$_.GetAttribute('package') -eq 'com.android.settings' -and $_.GetAttribute('resource-id') -eq 'android:id/title' -and $_.GetAttribute('class') -eq 'android.widget.TextView' -and $_.GetAttribute('text') -eq '更多'})
            if($more.Count -eq 1 -and $more[0].GetAttribute('bounds') -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
                $x=[int](([int]$Matches[1]+[int]$Matches[3])/2);$y=[int](([int]$Matches[2]+[int]$Matches[4])/2)
                $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','tap',[string]$x,[string]$y) $root
                Record @{action='observed_bluetooth_device_list_expanded'}
                $expanded=$true; $xml=Snapshot
            }
        }
        $names=@($xml.SelectNodes('//node[@enabled="true"]') | Where-Object {$_.GetAttribute('package') -in @('com.android.settings','com.android.bluetoothsettings') -and $_.GetAttribute('resource-id') -eq 'android:id/title' -and $_.GetAttribute('text') -eq $ExpectedPeerName})
        foreach($name in $names) {
            $buttons=@($name.ParentNode.ParentNode.SelectNodes('.//node[@enabled="true" and @clickable="true"]') | Where-Object {$_.GetAttribute('content-desc') -in @('设备设置','详情按钮')})
            if($buttons.Count -ne 1 -or $buttons[0].GetAttribute('bounds') -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'){continue}
            $key="$page/$($buttons[0].GetAttribute('bounds'))"
            if(!$seen.Add($key)){continue}
            $x=[int](([int]$Matches[1]+[int]$Matches[3])/2);$y=[int](([int]$Matches[2]+[int]$Matches[4])/2)
            $current=Snapshot
            $liveNames=@($current.SelectNodes('//node[@enabled="true"]') | Where-Object {$_.GetAttribute('package') -in @('com.android.settings','com.android.bluetoothsettings') -and $_.GetAttribute('resource-id') -eq 'android:id/title' -and $_.GetAttribute('text') -eq $ExpectedPeerName})
            $live=@(foreach($liveName in $liveNames){$liveName.ParentNode.ParentNode.SelectNodes('.//node[@enabled="true" and @clickable="true"]') | Where-Object {$_.GetAttribute('bounds') -eq $buttons[0].GetAttribute('bounds') -and $_.GetAttribute('content-desc') -in @('设备设置','详情按钮')}})
            if($live.Count -ne 1) { throw 'Observed test detail control changed before opening.' }
            $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','tap',[string]$x,[string]$y) $root
            $detail=Snapshot
            $dump=Invoke-Ble22Adb $Adb $Serial @('shell','dumpsys','activity','top') $root
            $package=$name.GetAttribute('package')
            $actual=Get-Ble22SettingsDetailPeerHash $dump $package $RunId
            Record @{action='test_named_detail_observed';page=$page;detail_peer_hash=$actual;matches_expected=($actual -eq $PeerAddressHash)}
            if($actual -eq $PeerAddressHash) {
                $null=Get-Ble22TestBondResetAction $detail $ExpectedPeerName $PeerAddressHash $RunId $dump
                Write-Output 'EXACT_TEST_PEER_DETAIL_VERIFIED'
                exit 0
            }
            $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','keyevent','4') $root
            $null=Snapshot
        }
        $xml=Snapshot
        $lists=@($xml.SelectNodes('//node[@enabled="true" and @scrollable="true"]') | Where-Object {$_.GetAttribute('package') -in @('com.android.settings','com.android.bluetoothsettings')})
        if($lists.Count -ne 1 -or $lists[0].GetAttribute('bounds') -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'){break}
        $x=[int](([int]$Matches[1]+[int]$Matches[3])/2);$top=[int]$Matches[2];$bottom=[int]$Matches[4];$height=$bottom-$top
        $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','swipe',[string]$x,[string][int]($bottom-$height*0.2),[string]$x,[string][int]($top+$height*0.2),'400') $root
    }
    throw 'No exact observed test peer detail found in bounded search; no binding removed.'
} catch {Record @{action='blocked';reason=$_.Exception.Message};throw}
finally {if($locked){try{$null=Invoke-Ble22Adb $Adb $Serial @('shell','rm','-f',$remote) $root}finally{$mutex.ReleaseMutex()}};$mutex.Dispose()}
