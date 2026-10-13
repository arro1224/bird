#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$RoundDirectory,
    [Parameter(Mandatory)][string]$AuditPath,
    [string]$Adb='D:/Androidstudio2/platform-tools/adb.exe')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$directory=(Resolve-Path -LiteralPath $RoundDirectory).Path
$ownedRoot=[IO.Path]::GetFullPath((Join-Path $root 'outputs/ble22'))+[IO.Path]::DirectorySeparatorChar
if(!$directory.StartsWith($ownedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be in a project BLE22 round.' }
$package='deckers.thibault.aves.bird'
$audit=@{schema_version=1;status='in_progress';released=@();missing=@();skipped=@();hardware_status='pending';releasable=$false}
try {
    $phone=Get-Ble22PhoneIdentity $Adb $Serial $root; $audit.phone=$phone
    $pidResult=Invoke-Ble22Process -File $Adb -Arguments @('-s',$Serial,'shell','pidof',$package) -WorkingDirectory $root
    Assert-Ble22PhoneOnline $Adb $Serial $root
    if($pidResult.exit_code -ne 1 -or $pidResult.stdout.Trim() -or $pidResult.stderr.Trim()) { throw 'Transport process must be stopped, with an unambiguous PID check.' }
    foreach($path in Get-ChildItem -LiteralPath $directory -Filter evidence.json -Recurse) {
        $e=Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $received=Join-Path $path.DirectoryName 'receiver-verification.json'
        if(!$e['export'] -or !(Test-Path -LiteralPath $received -PathType Leaf)) { $audit.skipped+=@{run=$path.Directory.Name;reason='no_independent_received_verification'}; continue }
        $receiver=Get-Content -LiteralPath $received -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $name=$e['export']['file_name']
        if($name -notmatch '^BirdBox_BLE_[A-Za-z0-9._-]+\.(json|zip)$') { throw 'Unsafe cache artifact filename.' }
        $local=Join-Path $path.DirectoryName $name
        if(!(Test-Path -LiteralPath $local -PathType Leaf)) { throw 'Actual received file is missing.' }
        if(!(Test-Ble22ReceivedCacheReplica $e $receiver $phone (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() (Get-Item -LiteralPath $local).Length)) { $audit.skipped+=@{run=$e.run_id;reason='different_phone_or_non_transport_export'}; continue }
        Assert-Ble22PhoneOnline $Adb $Serial $root
        $remote="cache/ble_diagnostics/$name"
        $exists=Invoke-Ble22Process -File $Adb -Arguments @('-s',$Serial,'shell','run-as',$package,'test','-f',$remote) -WorkingDirectory $root
        Assert-Ble22PhoneOnline $Adb $Serial $root
        if($exists.exit_code -eq 1 -and !$exists.stdout.Trim() -and !$exists.stderr.Trim()) { $audit.missing+=@{run=$e.run_id;file_name=$name}; continue }
        if($exists.exit_code -ne 0) { throw 'Phone replica presence check failed.' }
        $hash=Invoke-Ble22Adb $Adb $Serial @('shell','run-as',$package,'sha256sum',$remote) $root
        if($hash -notmatch '^([a-f0-9]{64})\s' -or $Matches[1] -ne $e.export.sha256) { throw 'Phone replica differs from actual received file.' }
        $release=@{run_id=$e.run_id;file_name=$name;sha256=$e.export.sha256;released_at=[DateTime]::UtcNow.ToString('o');scope='verified_received_transport_cache_replica';status='release_attempted'}
        $audit.released+=$release
        Write-Ble22Json $AuditPath $audit
        $null=Invoke-Ble22Adb $Adb $Serial @('shell','run-as',$package,'rm',$remote) $root
        $remaining=Invoke-Ble22Process -File $Adb -Arguments @('-s',$Serial,'shell','run-as',$package,'test','-e',$remote) -WorkingDirectory $root
        Assert-Ble22PhoneOnline $Adb $Serial $root
        if($remaining.exit_code -ne 1 -or $remaining.stdout.Trim() -or $remaining.stderr.Trim()) { throw 'Replica release was not verified.' }
        $release.status='release_verified'
    }
    Assert-Ble22PhoneOnline $Adb $Serial $root
    $audit.status='completed'
} catch { $audit.status='failed'; $audit.reason=$_.Exception.Message; throw }
finally { Write-Ble22Json $AuditPath $audit }
$audit | ConvertTo-Json -Depth 10
