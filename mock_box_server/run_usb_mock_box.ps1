param(
    [ValidateSet('normal', 'slow', 'conflict', 'storage-full')]
    [string]$Scenario = 'normal',
    [int]$Port = 8080,
    [string]$PythonPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $PSScriptRoot 'server.py'
$localProperties = Join-Path $projectRoot 'android\local.properties'

if (-not $PythonPath) {
    $runtimeRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes'
    $PythonPath = Get-ChildItem -LiteralPath $runtimeRoot -Filter python.exe -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath)) {
    throw 'Python was not found. Pass python.exe with -PythonPath.'
}

$sdkLine = Get-Content -LiteralPath $localProperties | Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
if (-not $sdkLine) { throw 'sdk.dir is missing from android/local.properties.' }
$sdkPath = $sdkLine.Substring('sdk.dir='.Length) -replace '\\\\', '\'
$adb = Join-Path $sdkPath 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "ADB was not found: $adb" }

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
    if ($owner.CommandLine -notmatch 'mock_box_server[\\/]server\.py') {
        throw "Port $Port is owned by another process: PID $($listener.OwningProcess) $($owner.Name)"
    }
    Write-Host "Mock box is already running: PID $($listener.OwningProcess)"
} else {
    $process = Start-Process -FilePath $PythonPath `
        -ArgumentList @($serverPath, '--host', '0.0.0.0', '--port', $Port, '--scenario', $Scenario) `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800
    if ($process.HasExited) { throw 'Mock box failed to start. Run server.py directly to inspect the error.' }
    Write-Host "Mock box started: PID $($process.Id), scenario $Scenario"
}

$devices = & $adb devices
if (-not ($devices -match "\tdevice$")) {
    throw 'No authorized Android device was detected. Connect USB and allow USB debugging.'
}

& $adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
$probe = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/v1/device/status" -TimeoutSec 3
if ($probe.StatusCode -ne 200) { throw "Mock status endpoint returned HTTP $($probe.StatusCode)." }

Write-Host ''
Write-Host 'USB mock connection is ready. Enter this address in the app:' -ForegroundColor Green
Write-Host "http://127.0.0.1:$Port" -ForegroundColor Cyan
