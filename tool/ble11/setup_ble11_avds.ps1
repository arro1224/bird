[CmdletBinding()]
param(
    [string]$AndroidSdk = 'D:\Androidstudio2',
    [string]$SystemImage = 'system-images;android-36.1;google_apis_playstore;x86_64',
    [string]$AppAvd = 'ble11_app_api36',
    [string]$BoxAvd = 'ble11_box_api36',
    [switch]$UpdateEmulator
)

$ErrorActionPreference = 'Stop'
$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\avdmanager.bat'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'

if (!(Test-Path -LiteralPath $sdkManager) -or !(Test-Path -LiteralPath $avdManager)) {
    throw "Android SDK command-line tools are missing under $AndroidSdk"
}

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $java = Get-ChildItem -Path "$env:USERPROFILE\.gradle\jdks" -Recurse -Filter java.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
        Select-Object -First 1
    if ($null -eq $java) { throw 'A Java 17+ installation is required.' }
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java.FullName)
}

if ($UpdateEmulator) {
    & $sdkManager 'emulator'
    if ($LASTEXITCODE -ne 0) { throw 'Android Emulator update failed.' }
}

$systemImagePath = Join-Path $AndroidSdk (($SystemImage -split ';') -join '\')
if (!(Test-Path -LiteralPath (Join-Path $systemImagePath 'package.xml'))) {
    & $sdkManager $SystemImage
    if ($LASTEXITCODE -ne 0) { throw "System image installation failed: $SystemImage" }
}

$versionLine = (& $emulator -version | Select-Object -First 1)
$versionMatch = [regex]::Match($versionLine, '(\d+)\.(\d+)\.(\d+)')
if (!$versionMatch.Success) { throw "Unable to parse emulator version: $versionLine" }
$major = [int]$versionMatch.Groups[1].Value
$minor = [int]$versionMatch.Groups[2].Value
if ($major -lt 36 -or ($major -eq 36 -and $minor -lt 5)) {
    throw "BLE-11 requires Android Emulator 36.5+; installed version is $($versionMatch.Value). Run again with -UpdateEmulator."
}

$existing = @(& $emulator -list-avds)
foreach ($name in @($AppAvd, $BoxAvd)) {
    if ($existing -contains $name) {
        Write-Host "AVD already exists: $name"
        continue
    }
    'no' | & $avdManager create avd --name $name --package $SystemImage --device 'pixel_6'
    if ($LASTEXITCODE -ne 0) { throw "Failed to create AVD: $name" }
    Write-Host "Created AVD: $name"
}

Write-Host "BLE-11 AVD setup ready with emulator $($versionMatch.Value)."
