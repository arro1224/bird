[CmdletBinding()]
param(
    [ValidateSet("Preflight", "Release")]
    [string]$Mode = "Preflight",
    [string]$FlutterCommand = "flutter",
    [string]$DartCommand = "dart",
    [string]$EvidencePath = "build\b7\b7-gate-evidence.json",
    [string]$RealBoxEvidencePath,
    [string]$B12BEvidencePath,
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$baselinePath = Join-Path $repoRoot "docs\contracts\birdbox-v1-baseline.json"
$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$steps = [System.Collections.Generic.List[object]]::new()
$startedAt = (Get-Date).ToUniversalTime()
$status = "running"
$failure = $null
$realBoxEvidence = $null
$script:simulatedAcceptance = $null

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath exited with code $LASTEXITCODE."
    }
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    $stepStarted = (Get-Date).ToUniversalTime()
    Write-Host ""
    Write-Host "=== $Name ==="
    try {
        & $Action
        $steps.Add([pscustomobject]@{
            name = $Name
            status = "passed"
            started_at = $stepStarted.ToString("o")
            duration_seconds = [math]::Round(
                ((Get-Date).ToUniversalTime() - $stepStarted).TotalSeconds,
                3
            )
        })
    } catch {
        $steps.Add([pscustomobject]@{
            name = $Name
            status = "failed"
            started_at = $stepStarted.ToString("o")
            duration_seconds = [math]::Round(
                ((Get-Date).ToUniversalTime() - $stepStarted).TotalSeconds,
                3
            )
            error = $_.Exception.Message
        })
        throw
    }
}

function Resolve-EvidencePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $repoRoot $Path
}

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $previousErrorAction = $ErrorActionPreference
    $output = @()
    $exitCode = $null
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($null -eq $exitCode -or $exitCode -ne 0) {
        throw "$FilePath exited with code $exitCode."
    }
    return ($output -join [Environment]::NewLine).Trim()
}

function Get-SafeCommandVersion {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    try {
        return Get-CommandVersion $FilePath $Arguments
    } catch {
        return "unavailable: $($_.Exception.Message)"
    }
}

function Resolve-JavaCommand {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $java) {
        return $java.Source
    }
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles (
            "Android\Android Studio\jbr\bin\java.exe"
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates += Join-Path $env:JAVA_HOME "bin\java.exe"
    }
    return $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

Push-Location $repoRoot
try {
    $gitSha = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve the App Git SHA."
    }
    $dirtyEntries = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the Git worktree."
    }
    if ($Mode -eq "Release" -and $dirtyEntries.Count -gt 0) {
        throw "Release mode requires a clean Git worktree."
    }

    if (-not $SkipPubGet) {
        Invoke-GateStep "flutter pub get" {
            Invoke-NativeCommand $FlutterCommand @("pub", "get")
        }
    }
    Invoke-GateStep "dart format" {
        Invoke-NativeCommand $DartCommand @(
            "format",
            "--output=none",
            "--set-exit-if-changed",
            "lib",
            "test",
            "tool"
        )
    }
    Invoke-GateStep "contract validation" {
        $arguments = @("run", "tool/contracts/verify_contracts.dart")
        if ($Mode -eq "Release") {
            $arguments += "--strict-baseline"
        }
        Invoke-NativeCommand $DartCommand $arguments
    }
    Invoke-GateStep "production integrity" {
        Invoke-NativeCommand $DartCommand @(
            "run",
            "tool/release/verify_production_integrity.dart"
        )
    }
    Invoke-GateStep "flutter analyze" {
        Invoke-NativeCommand $FlutterCommand @("analyze")
    }
    Invoke-GateStep "flutter test" {
        Invoke-NativeCommand $FlutterCommand @("test")
    }
    Invoke-GateStep "contract tests" {
        Invoke-NativeCommand $FlutterCommand @("test", "test/contracts")
    }
    Invoke-GateStep "task tests" {
        Invoke-NativeCommand $FlutterCommand @(
            "test",
            "test/bird_companion/tasks"
        )
    }
    Invoke-GateStep "settings tests" {
        Invoke-NativeCommand $FlutterCommand @(
            "test",
            "test/bird_companion/settings"
        )
    }
    Invoke-GateStep "bird debug APK" {
        Invoke-NativeCommand $FlutterCommand @(
            "build",
            "apk",
            "--debug",
            "--flavor",
            "bird",
            "-t",
            "lib/main.dart"
        )
    }

    if ($Mode -eq "Preflight") {
        Invoke-GateStep "simulated RC4 acceptance" {
            $runnerOutput = @(
                & $DartCommand "run" "tool/acceptance/ble_provisioning_rc4_acceptance.dart" 2>&1
            )
            if ($LASTEXITCODE -ne 0) {
                throw "$DartCommand simulated RC4 acceptance exited with code $LASTEXITCODE."
            }
            $runnerText = $runnerOutput -join [Environment]::NewLine
            $jsonMatch = [regex]::Match($runnerText, '(?s)\{.*\}')
            if (-not $jsonMatch.Success) {
                throw "Simulated RC4 acceptance did not emit a JSON report."
            }
            $script:simulatedAcceptance = $jsonMatch.Value | ConvertFrom-Json
            if ($script:simulatedAcceptance.result -ne "pass" -or
                $script:simulatedAcceptance.environment -ne "simulated" -or
                $script:simulatedAcceptance.releasable -ne $false -or
                $script:simulatedAcceptance.real_k7_status -ne "pending") {
                throw "Simulated RC4 acceptance did not produce fail-closed metadata."
            }
            if (@($script:simulatedAcceptance.cases).Count -ne 10) {
                throw "Simulated RC4 acceptance must report exactly ten cases."
            }
        }
    }

    if ($Mode -eq "Release") {
        $hasKeyProperties = Test-Path -LiteralPath (
            Join-Path $repoRoot "android\key.properties"
        )
        $hasSigningEnvironment = @(
            $env:AVES_RELEASE_STORE_FILE,
            $env:AVES_RELEASE_STORE_PASSWORD,
            $env:AVES_RELEASE_KEY_ALIAS,
            $env:AVES_RELEASE_KEY_PASSWORD
        ).Where({
            -not [string]::IsNullOrWhiteSpace($_)
        }).Count -eq 4
        if (-not $hasKeyProperties -and -not $hasSigningEnvironment) {
            throw "Release signing credentials are not configured."
        }
        if ([string]::IsNullOrWhiteSpace($env:AVES_RELEASE_CERT_SHA256)) {
            throw "AVES_RELEASE_CERT_SHA256 is required in Release mode."
        }
        if ([string]::IsNullOrWhiteSpace($RealBoxEvidencePath)) {
            throw "Release mode requires -RealBoxEvidencePath."
        }
        if ([string]::IsNullOrWhiteSpace($B12BEvidencePath)) {
            throw "Release mode requires -B12BEvidencePath."
        }
        $resolvedRealBoxEvidence = Resolve-EvidencePath $RealBoxEvidencePath
        if (-not (Test-Path -LiteralPath $resolvedRealBoxEvidence)) {
            throw "Real-box evidence was not found: $resolvedRealBoxEvidence"
        }
        $resolvedB12BEvidence = Resolve-EvidencePath $B12BEvidencePath
        if (-not (Test-Path -LiteralPath $resolvedB12BEvidence)) {
            throw "B12-B evidence was not found: $resolvedB12BEvidence"
        }
        $realBoxEvidence = Get-Content -LiteralPath $resolvedRealBoxEvidence -Raw |
            ConvertFrom-Json
        foreach ($required in @(
            "box_sha",
            "device_model",
            "api_version",
            "schema_version"
        )) {
            if ([string]::IsNullOrWhiteSpace($realBoxEvidence.$required)) {
                throw "Real-box evidence is missing $required."
            }
        }
        if ($realBoxEvidence.e2e_passed -ne $true) {
            throw "Real-box evidence does not record e2e_passed=true."
        }
        $requiredE2eCases = @(
            "connect_mdns",
            "connect_qr",
            "connect_manual",
            "pair_session_restore_revocation",
            "device_status",
            "scan_project_import_analysis",
            "job_resume_after_app_kill",
            "gallery_review",
            "offline_replay_conflict",
            "copy_failures_report_logs",
            "signed_install_rollback"
        )
        foreach ($caseId in $requiredE2eCases) {
            $caseEvidence = @($realBoxEvidence.cases) |
                Where-Object { $_.id -eq $caseId } |
                Select-Object -First 1
            if ($null -eq $caseEvidence -or $caseEvidence.status -ne "passed") {
                throw "Real-box E2E case is missing or not passed: $caseId."
            }
            if ([string]::IsNullOrWhiteSpace($caseEvidence.evidence)) {
                throw "Real-box E2E case has no evidence reference: $caseId."
            }
        }
        if ($realBoxEvidence.box_sha -ne $baseline.box.firmware_sha) {
            throw "Real-box evidence SHA does not match the frozen baseline."
        }

        Invoke-GateStep "bird signed release APK" {
            Invoke-NativeCommand $FlutterCommand @(
                "build",
                "apk",
                "--release",
                "--flavor",
                "bird",
                "-t",
                "lib/main.dart"
            )
        }
        Invoke-GateStep "release signature verification" {
            & powershell -ExecutionPolicy Bypass -File (
                Join-Path $repoRoot "tool\release\verify_android_release.ps1"
            )
            if ($LASTEXITCODE -ne 0) {
                throw "Android release signature verification failed."
            }
        }
        Invoke-GateStep "B12-B real-hardware evidence" {
            Invoke-NativeCommand $DartCommand @(
                "run",
                "tool/acceptance/b12b_release_gate.dart",
                "--evidence=$resolvedB12BEvidence",
                "--apk=build/app/outputs/flutter-apk/app-bird-release.apk"
            )
        }
    }
    $status = "passed"
} catch {
    $status = "failed"
    $failure = $_.Exception.Message
    throw
} finally {
    $apkPath = if ($Mode -eq "Release") {
        Join-Path $repoRoot "build\app\outputs\flutter-apk\app-bird-release.apk"
    } else {
        Join-Path $repoRoot "build\app\outputs\flutter-apk\app-bird-debug.apk"
    }
    $apk = if (Test-Path -LiteralPath $apkPath) {
        Get-Item -LiteralPath $apkPath
    } else {
        $null
    }
    $apkHash = if ($null -ne $apk) {
        (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash
    } else {
        $null
    }
    $javaCommand = Resolve-JavaCommand
    $javaVersion = if ($null -ne $javaCommand) {
        Get-CommandVersion $javaCommand @("-version")
    } else {
        $null
    }
    $gradleVersion = $null
    if ($null -ne $javaVersion) {
        try {
            $previousJavaHome = $env:JAVA_HOME
            $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $javaCommand)
            $gradleVersion = Get-CommandVersion (
                Join-Path $repoRoot "android\gradlew.bat"
            ) @("--version")
        } catch {
            $gradleVersion = "unavailable: $($_.Exception.Message)"
        } finally {
            $env:JAVA_HOME = $previousJavaHome
        }
    }
    $evidence = [ordered]@{
        gate = "B7"
        mode = $Mode
        status = $status
        started_at = $startedAt.ToString("o")
        finished_at = (Get-Date).ToUniversalTime().ToString("o")
        failure = $failure
        app = [ordered]@{
            repository = $baseline.app.repository
            branch = (& git branch --show-current).Trim()
            sha = (& git rev-parse HEAD).Trim()
            dirty = (@(& git status --porcelain)).Count -gt 0
        }
        box = [ordered]@{
            repository = $baseline.box.repository
            branch = $baseline.box.branch
            firmware_sha = $baseline.box.firmware_sha
            device_model = if ($null -ne $realBoxEvidence) {
                $realBoxEvidence.device_model
            } else {
                $null
            }
        }
        acceptance = if ($Mode -eq "Preflight") {
            [ordered]@{
                result = $script:simulatedAcceptance.result
                environment = "simulated"
                releasable = $false
                real_k7_status = "pending"
                cases = @($script:simulatedAcceptance.cases)
            }
        } else {
            [ordered]@{
                result = "pass"
                environment = "real_k7"
                releasable = $true
                real_k7_status = "verified"
            }
        }
        contract = [ordered]@{
            id = "$($baseline.contract_id)@$($baseline.contract_version)"
            api_version = $baseline.api_version
            database_schema_version = $baseline.box.database_schema_version
            baseline_status = $baseline.status
        }
        versions = [ordered]@{
            flutter = Get-SafeCommandVersion $FlutterCommand @("--version")
            dart = Get-SafeCommandVersion $DartCommand @("--version")
            java = $javaVersion
            gradle = $gradleVersion
        }
        apk = [ordered]@{
            path = if ($null -ne $apk) { $apk.FullName } else { $apkPath }
            exists = $null -ne $apk
            size_bytes = if ($null -ne $apk) { $apk.Length } else { $null }
            sha256 = $apkHash
        }
        steps = $steps
    }
    $resolvedEvidencePath = Resolve-EvidencePath $EvidencePath
    $evidenceDirectory = Split-Path -Parent $resolvedEvidencePath
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resolvedEvidencePath -Encoding UTF8
    Write-Host ""
    Write-Host "B7 evidence: $resolvedEvidencePath"
    Pop-Location
}
