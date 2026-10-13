#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install','Pair','Discover','AppButton')][string]$Mode,
    [Parameter(Mandatory)][string]$Serial,[Parameter(Mandatory)][string]$ActionLog,
    [string]$ExpectedAppLabel,[string]$ExpectedPeerName='BirdBox-B1E11001',
    [string]$Adb='D:/Androidstudio2/platform-tools/adb.exe',
    [string]$ExpectedPageText,[string]$ButtonText,[string]$ExpectedPackage='deckers.thibault.aves.bird',
    [string]$ExpectedPeerAddressHash,[string]$RunId,[ValidateSet('Confirm','Cancel','Timeout')][string]$PairMode='Confirm')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if($Mode -eq 'Discover') {
    $null=Invoke-Ble22Adb $Adb $Serial @('shell','am','start','-a','android.bluetooth.adapter.action.REQUEST_DISCOVERABLE','--ei','android.bluetooth.adapter.extra.DISCOVERABLE_DURATION','120') $root
}
Invoke-Ble22UiStep $Adb $Serial $root $Mode $ActionLog $ExpectedAppLabel $ExpectedPeerName $ExpectedPageText $ButtonText $ExpectedPackage $ExpectedPeerAddressHash $RunId $PairMode | ConvertTo-Json -Depth 10
