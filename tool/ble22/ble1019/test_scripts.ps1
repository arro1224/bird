#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Ble22.Tools.psm1') -Force
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$pwsh = (Get-Process -Id $PID).Path
$checks = 0
function Check($condition, [string]$reason) { if (!$condition) { throw $reason }; $script:checks++ }
foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    Check ($errors.Count -eq 0) ('PowerShell parse failed: '+$script.Name)
}
$round = Join-Path $root ('outputs/ble22/ble1019-script-fixture-'+[Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $round
Write-Ble22Json (Join-Path $round 'round.json') @{suite='ble1019-v1';round_id='offline-script-fixture';build=$null}
$plan = Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'run_offline.ps1'),'-RoundDirectory',$round,'-PlanOnly') -WorkingDirectory $root
Check ($plan.exit_code -eq 0) 'Plan mode failed.'
$value = $plan.stdout | ConvertFrom-Json
Check ($value.mode -eq 'plan_only' -and $value.hardware_operations -eq 0 -and $value.apk_builds -eq 0 -and !$value.releasable) 'Plan mode changed scope.'
Check ($value.steps.Count -ge 8) 'Offline steps missing.'
Check (@($value.steps | Where-Object { $_.name -eq 'flutter-integration' -and $_.arguments -contains 'test/bird_companion/settings' -and $_.arguments -contains 'test/bird_companion/app' }).Count -eq 1) 'Settings and session integration coverage missing.'
Check (!(Test-Path -LiteralPath (Join-Path $round 'checks'))) 'Plan mode executed checks.'
$bad = Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'run_offline.ps1'),'-RoundDirectory',$round,'-Python',(Join-Path $round 'missing-python.exe')) -WorkingDirectory $root
Check ($bad.exit_code -ne 0 -and !(Test-Path -LiteralPath (Join-Path $round 'checks'))) 'Missing runtime must fail before checks.'
$build = Invoke-Ble22Process -File $pwsh -Arguments @('-NoProfile','-File',(Join-Path $PSScriptRoot 'register_build.ps1'),'-RoundDirectory',$round,'-Apk',(Join-Path $round 'missing.apk'),'-ApkSha256',('a'*64),'-GitCommit',('b'*40),'-SourceFingerprint',('c'*64),'-BuildId','synthetic-only','-Aapt',(Join-Path $round 'never-call-aapt.exe')) -WorkingDirectory $root
Check ($build.exit_code -ne 0) 'Missing APK must fail.'
Check ($null -eq (Get-Content -LiteralPath (Join-Path $round 'round.json') -Raw | ConvertFrom-Json).build) 'Failed APK registration changed manifest.'
Check (!(Test-Path -LiteralPath (Join-Path $round 'artifacts'))) 'Failed registration copied an APK.'
Write-Output "BLE1019_POWERSHELL_TESTS passed=$checks phone_operations=0 apk_builds=0"
