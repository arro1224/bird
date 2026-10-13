#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Serial,[Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$Sha256,
    [Parameter(Mandatory)][ValidateSet('deckers.thibault.aves.bird','deckers.thibault.aves.bird.sim','deckers.thibault.aves.virtualbirdbox.debug')][string]$Package,
    [Parameter(Mandatory)][string]$AppLabel,
    [ValidateSet('Ui','Transport')][string]$PermissionMode='Ui',
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$Adb='D:/Androidstudio2/platform-tools/adb.exe',[switch]$AutoConfirm)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$null=New-Item -ItemType Directory -Force $OutputDirectory
$record=@{status='failed';permission_mode=$PermissionMode;package=$Package;expected_sha256=$Sha256;generated_at=[DateTime]::UtcNow.ToString('o');hardware_status='pending'}
try {
    Install-Ble22Apk -Adb $Adb -Serial $Serial -Root $root -Apk $Apk -Sha256 $Sha256 -Package $Package -AppLabel $AppLabel -PermissionMode $PermissionMode -OutputDirectory $OutputDirectory -AutoConfirm:$AutoConfirm
    $record.status='installed_hash_verified'
} catch { $record.failure_kind=$_.Exception.GetType().Name; $record.reason=$_.Exception.Message }
finally { Write-Ble22Json (Join-Path $OutputDirectory 'installation.json') $record }
if($record.status -ne 'installed_hash_verified') { exit 1 }
exit 0
