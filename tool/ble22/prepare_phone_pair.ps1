#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AppSerial,[Parameter(Mandatory)][string]$BoxSerial,
    [Parameter(Mandatory)][ValidateSet('P1','P2')][string]$Role,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$AppSha256,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$BoxSha256,
    [Parameter(Mandatory)][string]$RecordPath,
    [switch]$StopOwnedApps,[string]$Adb='D:/Androidstudio2/platform-tools/adb.exe')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$record=@{schema_version=1;role=$Role;status='failed';generated_at=[DateTime]::UtcNow.ToString('o');phones=@{};owned_processes_stopped=$false;bond_baseline='native_verification_required';advertising='current_run_verification_required';hardware_status='pending';releasable=$false}
try {
    $record.phones=@{app=(Get-Ble22PhoneIdentity $Adb $AppSerial $root);box=(Get-Ble22PhoneIdentity $Adb $BoxSerial $root)}
    Assert-Ble22PhonePair $record.phones.app $record.phones.box $Role
    if((Get-Ble22InstalledHash $Adb $AppSerial 'deckers.thibault.aves.bird' $root) -ne $AppSha256 -or (Get-Ble22InstalledHash $Adb $BoxSerial 'deckers.thibault.aves.virtualbirdbox.debug' $root) -ne $BoxSha256) { throw 'Installed endpoint hashes do not match the candidate.' }
    $record.builds=@{app_sha256=$AppSha256;box_sha256=$BoxSha256;installed_verified=$true}
    if($StopOwnedApps) {
        foreach($serial in @($AppSerial,$BoxSerial)) {
            foreach($package in @('deckers.thibault.aves.bird','deckers.thibault.aves.virtualbirdbox.debug')) { $null=Invoke-Ble22Adb $Adb $serial @('shell','am','force-stop',$package) $root }
            Assert-Ble22PhoneOnline $Adb $serial $root
        }
        $record.owned_processes_stopped=$true
    }
    Assert-Ble22PhoneOnline $Adb $AppSerial $root; Assert-Ble22PhoneOnline $Adb $BoxSerial $root
    $record.status='identity_and_build_verified'
} catch { $record.reason=$_.Exception.Message; throw }
finally { Write-Ble22Json $RecordPath $record }
$record | ConvertTo-Json -Depth 10
