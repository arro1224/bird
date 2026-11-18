param(
    [ValidateSet('Debug', 'Release')][string]$BuildType = 'Release',
    [switch]$SkipTests,
    [string]$OutputDirectory,
    [ValidateSet('demo', 'repair-110', 'repair-14')][string]$DemoProfile = 'demo'
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$properties = Get-Content -LiteralPath (Join-Path $repositoryRoot 'android\local.properties')
$flutterRoot = (($properties | Where-Object { $_ -match '^flutter.sdk=' } | Select-Object -First 1) -replace '^flutter.sdk=', '').Replace('\\', '\')
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath 'C:\Program Files\Android\Android Studio\jbr')) {
    $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = 'build/delivery/embedded-demo-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff')
}
Push-Location $repositoryRoot
try {
    if (-not $SkipTests) {
        & cmd.exe /d /c call $flutter pub get --offline
        if ($LASTEXITCODE -ne 0) { throw 'Dependency preparation failed.' }
        & cmd.exe /d /c call $flutter test --no-pub test/bird_companion/simulation test/bird_companion/default_entrypoint_test.dart test/bird_companion/production_entrypoint_test.dart test/bird_companion/android_flavor_isolation_test.dart
        if ($LASTEXITCODE -ne 0) { throw 'Embedded demo or production-isolation tests failed.' }
    }
    & (Join-Path $PSScriptRoot 'release\build_android_apks.ps1') -Mode EmbeddedDemo -BuildType $BuildType -OutputDirectory $OutputDirectory -DemoProfile $DemoProfile
    $manifestPath = Join-Path (Join-Path $repositoryRoot $OutputDirectory) 'build-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($artifact in $manifest.artifacts) {
        Write-Output ('APK: ' + (Join-Path (Split-Path -Parent $manifestPath) $artifact.file))
    }
} finally { Pop-Location }
