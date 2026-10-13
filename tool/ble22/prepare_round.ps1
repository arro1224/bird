#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^ble22-[A-Za-z0-9._-]{1,65}$')][string]$RoundId,
    [string]$FlutterSdk='D:/flutter344/flutter',[string]$AndroidSdk='D:/Androidstudio2',
    [string]$JavaHome='C:/Users/32714/.gradle/jdks/eclipse_adoptium-21-amd64-windows.2',
    [string]$SimulatedDeviceId='bbx-b1e11001b1e11001b1e11001b1e11001')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Ble22.Tools.psm1') -Force
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output=Join-Path $root "outputs/ble22/$RoundId"
if(Test-Path -LiteralPath $output) { throw 'Round directory already exists; use a new identity.' }
$null=New-Item -ItemType Directory -Path (Join-Path $output 'apks') -Force
$utf8=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=$utf8; $OutputEncoding=$utf8
$savedEnvironment=@{}
foreach($key in @('JAVA_HOME','AVES_BUILD_ID','AVES_SOURCE_FINGERPRINT','AVES_GIT_SHA')) { $savedEnvironment[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$manifest=@{round_id=$RoundId;build_id=$RoundId;hardware_status='pending';releasable=$false;phone_test_status='not_started';status='building';artifacts=@{}}
$manifest.reference_candidate='ble22-20261012-round18'
$manifest.unresolved_issues=@('vivo_first_bond_fresh_gatt_status_133')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'first_bond_run.template.json') -Destination (Join-Path $output 'first-bond-run.template.json')
try {
    $identity=Get-Ble22SourceIdentity $root
    $env:JAVA_HOME=$JavaHome; $env:AVES_BUILD_ID=$RoundId; $env:AVES_SOURCE_FINGERPRINT=$identity.fingerprint
    $env:AVES_GIT_SHA=(& git -C $root rev-parse HEAD).Trim()
    $manifest.source_fingerprint=$identity.fingerprint; $manifest.git_commit=$env:AVES_GIT_SHA
    $manifest.build_dirty=![string]::IsNullOrEmpty((& git -C $root status --porcelain) -join '')
    [IO.File]::WriteAllText((Join-Path $output 'source-files.sha256'),($identity.lines -join "`n")+"`n",$utf8)
    $dart=Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $flutter=Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
    $aapt=Join-Path $AndroidSdk 'build-tools/37.0.0/aapt2.exe'
    $definitions=@(
        @{key='transport';flavor='bird';target='integration_test/ble22_phone_test.dart';package='deckers.thibault.aves.bird';defines=@()},
        @{key='formal';flavor='bird';target='lib/main.dart';package='deckers.thibault.aves.bird';defines=@()},
        @{key='simulation';flavor='birdSim';target='lib/main_bird_simulated.dart';package='deckers.thibault.aves.bird.sim';defines=@("--dart-define=BIRD_SIMULATED_DEVICE_ID=$SimulatedDeviceId")}
    )
    foreach($entry in $definitions) {
        Write-Output "BLE22_BUILD $($entry.key)"
        $arguments=@($flutter,'build','apk','--debug','--no-pub','--flavor',$entry.flavor,'--target',$entry.target)+$entry.defines
        $result=Invoke-Ble22Process -File $dart -Arguments $arguments -WorkingDirectory $root -TimeoutSeconds 900 -LogPath (Join-Path $output "$($entry.key)-build.log")
        if($result.exit_code -ne 0) { throw "Build failed: $($entry.key)." }
        $apk=Join-Path $output "apks/$($entry.key)-debug.apk"
        Copy-Item -LiteralPath (Join-Path $root "build/app/outputs/flutter-apk/app-$($entry.flavor.ToLowerInvariant())-debug.apk") -Destination $apk
        $metadata=Invoke-Ble22Process -File $aapt -Arguments @('dump','badging',$apk) -WorkingDirectory $root
        if($metadata.exit_code -ne 0 -or $metadata.stdout -notmatch "package: name='$([regex]::Escape($entry.package))' versionCode='(\d+)' versionName='([^']+)'") { throw "APK metadata mismatch: $($entry.key)." }
        $manifest.artifacts[$entry.key]=@{path="apks/$($entry.key)-debug.apk";apk_sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant();entrypoint=$entry.target;package=$entry.package;version_code=[int]$Matches[1];version_name=$Matches[2];defines=$entry.defines}
    }
    Write-Output 'BLE22_BUILD virtual'
    Push-Location (Join-Path $root 'android')
    try { & .\gradlew.bat :virtualBirdBox:assembleDebug -PvirtualBirdBoxManualInstall=true --offline --console=plain *> (Join-Path $output 'virtual-build.log'); if($LASTEXITCODE -ne 0) { throw 'Virtual peripheral build failed.' } }
    finally { Pop-Location }
    $virtual=Join-Path $output 'apks/virtual-debug.apk'
    Copy-Item -LiteralPath (Join-Path $root 'build/virtualBirdBox/outputs/apk/debug/virtualBirdBox-debug.apk') -Destination $virtual
    $manifest.artifacts.virtual=@{path='apks/virtual-debug.apk';apk_sha256=(Get-FileHash -LiteralPath $virtual -Algorithm SHA256).Hash.ToLowerInvariant();package='deckers.thibault.aves.virtualbirdbox.debug';manual_install_debug=$true}
    if((Get-Ble22SourceIdentity $root).fingerprint -ne $identity.fingerprint) { throw 'Source files changed during the frozen build.' }
    $manifest.app_sha256=$manifest.artifacts.transport.apk_sha256
    $manifest.box_sha256=$manifest.artifacts.virtual.apk_sha256
    $manifest.app_entrypoint='integration_test/ble22_phone_test.dart'; $manifest.box_manual_install_debug=$true
    $manifest.status='built_not_phone_accepted'
} catch { $manifest.status='build_failed'; $manifest.failure_kind=$_.Exception.GetType().Name; $manifest.reason=$_.Exception.Message }
finally {
    foreach($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process') }
    Write-Ble22Json (Join-Path $output 'builds.json') $manifest
}
if($manifest.status -eq 'build_failed') { throw "BLE22 frozen build failed; see $output" }
Write-Output "BLE22_FROZEN $output"
