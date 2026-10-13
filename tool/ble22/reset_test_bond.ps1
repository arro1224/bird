#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$PeerAddressHash,
    [Parameter(Mandatory)][string]$ActionLog,
    [string]$ExpectedPeerName='BirdBox-B1E11001',
    [switch]$UseObservedSettingsDetail,
    [string]$Adb='D:/Androidstudio2/platform-tools/adb.exe')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$phone=Get-Ble22PhoneIdentity $Adb $Serial $root
$mutex=[Threading.Mutex]::new($false,"Local\BLE22-UI-$($phone.adb_selector_alias)")
$locked=$false; $remote="/data/local/tmp/ble22-reset-$PID.xml"
$record=@{run_id=$RunId;occurred_at=[DateTime]::UtcNow.ToString('o');phone=$phone;status='blocked';baseline_status='native_verification_required'}
try {
    $locked=$mutex.WaitOne(1000)
    if(!$locked) { throw 'Another operator owns this phone UI.' }
    $null=Invoke-Ble22Adb $Adb $Serial @('shell','uiautomator','dump',$remote) $root
    [xml]$xml=Invoke-Ble22Adb $Adb $Serial @('shell','cat',$remote) $root
    $activityDump=if($UseObservedSettingsDetail){Invoke-Ble22Adb $Adb $Serial @('shell','dumpsys','activity','top') $root}else{''}
    $decision=Get-Ble22TestBondResetAction $xml $ExpectedPeerName $PeerAddressHash $RunId $activityDump
    $null=Invoke-Ble22Adb $Adb $Serial @('shell','input','tap',[string][int]$decision.x,[string][int]$decision.y) $root
    $record.status='unpair_control_clicked'; $record.decision=$decision
} catch { $record.reason=$_.Exception.Message; throw }
finally {
    [IO.File]::AppendAllText($ActionLog,($record|ConvertTo-Json -Depth 10 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
    if($locked) { try { $null=Invoke-Ble22Adb $Adb $Serial @('shell','rm','-f',$remote) $root } finally { $mutex.ReleaseMutex() } }
    $mutex.Dispose()
}
$record | ConvertTo-Json -Depth 10
