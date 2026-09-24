[CmdletBinding()]
param(
    [string]$AndroidSdk = 'D:\Androidstudio2',
    [string]$FlutterSdk = 'D:\flutter344\flutter',
    [string]$OutputRoot = 'outputs\RC4-HF-BLE-12',
    [string[]]$Ble11Evidence = @(),
    [switch]$CreateZip
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$androidRoot = Join-Path $repositoryRoot 'android'
$flutter = Join-Path $FlutterSdk 'bin\flutter.bat'
$dart = Join-Path $FlutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
$gradle = Join-Path $androidRoot 'gradlew.bat'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'
$apkAnalyzer = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\apkanalyzer.bat'
$workRoot = Join-Path $repositoryRoot 'build\ble12-work'
$null = New-Item -ItemType Directory -Path $workRoot -Force
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Get-ContainedRelativePath([string]$root, [string]$path) {
    $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($path)
    $prefix = "$rootFull$([System.IO.Path]::DirectorySeparatorChar)"
    if (!$pathFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected root: $pathFull"
    }
    return $pathFull.Substring($prefix.Length).Replace('\', '/')
}

function Invoke-NativeOutput(
    [string]$label,
    [scriptblock]$action
) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = @(& $action 2>&1)
        $nativeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($nativeExitCode -ne 0) {
        throw "$label failed with exit code $nativeExitCode."
    }
    return $nativeOutput
}

function Invoke-CandidateStep(
    [string]$label,
    [scriptblock]$action,
    [string]$logPath
) {
    Write-Host "BLE-12: $label"
    $started = Get-Date
    $output = @(Invoke-NativeOutput $label $action)
    Write-Utf8NoBom $logPath (($output | ForEach-Object { $_.ToString() }) -join "`n")
    return [ordered]@{
        name = $label
        status = 'passed'
        duration_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    }
}

function Add-SourceFile(
    [System.Collections.Generic.HashSet[string]]$paths,
    [string]$relativePath
) {
    $normalized = $relativePath.Replace('\', '/')
    $fullPath = Join-Path $repositoryRoot $normalized
    if (!(Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required BLE-12 source file is missing: $normalized"
    }
    $null = $paths.Add($normalized)
}

function Add-SourceDirectory(
    [System.Collections.Generic.HashSet[string]]$paths,
    [string]$relativeDirectory
) {
    $fullDirectory = Join-Path $repositoryRoot $relativeDirectory
    if (!(Test-Path -LiteralPath $fullDirectory -PathType Container)) {
        throw "Required BLE-12 source directory is missing: $relativeDirectory"
    }
    foreach ($file in Get-ChildItem -LiteralPath $fullDirectory -Recurse -File) {
        $relative = Get-ContainedRelativePath $repositoryRoot $file.FullName
        $null = $paths.Add($relative)
    }
}

function Get-Reference([string]$relativePath, [System.Collections.IDictionary]$artifacts) {
    return [ordered]@{
        file = $relativePath
        sha256 = $artifacts[$relativePath]
    }
}

function Get-TestCount([string]$directory, [string[]]$classNames) {
    $total = 0
    foreach ($className in $classNames) {
        $file = Join-Path $directory "TEST-$className.xml"
        if (!(Test-Path -LiteralPath $file)) { throw "Missing test report: $file" }
        [xml]$xml = Get-Content -Raw -LiteralPath $file
        if ([int]$xml.testsuite.failures -ne 0 -or [int]$xml.testsuite.errors -ne 0) {
            throw "Native test report contains failures: $className"
        }
        $total += [int]$xml.testsuite.tests
    }
    return $total
}

function Test-Emulator365([string]$version) {
    $match = [regex]::Match($version, '^(\d+)\.(\d+)')
    if (!$match.Success) { return $false }
    $major = [int]$match.Groups[1].Value
    $minor = [int]$match.Groups[2].Value
    return $major -gt 36 -or ($major -eq 36 -and $minor -ge 5)
}

if (!(Test-Path -LiteralPath $flutter) -or !(Test-Path -LiteralPath $dart)) {
    throw "Flutter SDK is incomplete: $FlutterSdk"
}
if (!(Test-Path -LiteralPath $gradle) -or !(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $apkAnalyzer)) {
    throw 'Android build tools, APK analyzer, or emulator are missing.'
}
$java21 = Get-ChildItem -Path "$env:USERPROFILE\.gradle\jdks" -Recurse -Filter java.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\eclipse_adoptium-21[^\\]*\\bin\\java\.exe$' } |
    Select-Object -First 1
if ($null -ne $java21) {
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java21.FullName)
} elseif ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw 'A Java 21 installation is required.'
}
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

$emulatorLine = (& $emulator -version | Select-Object -First 1)
$emulatorMatch = [regex]::Match($emulatorLine, '(\d+\.\d+\.\d+(?:\.\d+)?)')
$emulatorVersion = if ($emulatorMatch.Success) { $emulatorMatch.Groups[1].Value } else { 'unknown' }
$dualAvdCapable = Test-Emulator365 $emulatorVersion
$avds = @(& $emulator -list-avds)
if ($Ble11Evidence.Count -eq 0 -and $dualAvdCapable) {
    throw 'Emulator 36.5+ is available; run all four BLE-11 scenarios and pass their evidence files to -Ble11Evidence.'
}
if ($Ble11Evidence.Count -ne 0 -and $Ble11Evidence.Count -ne 4) {
    throw 'Exactly four BLE-11 evidence files are required.'
}
if ($Ble11Evidence.Count -eq 4 -and !$dualAvdCapable) {
    throw 'BLE-11 evidence cannot be accepted with an emulator below 36.5.'
}

$gitCommit = (& git rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $gitCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'Unable to resolve a full Git SHA.'
}
$branch = (& git branch --show-current).Trim()
$gitStatus = @(& git status --porcelain=v2)
$sourceState = if ($gitStatus.Count -eq 0) { 'clean_git_commit' } else { 'uncommitted_candidate_snapshot' }

$sourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($path in @(
    'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java',
    'android/app/src/main/java/deckers/thibault/aves/BirdBoxSecurityWriteStateMachine.java',
    'android/app/src/main/java/deckers/thibault/aves/BirdBoxConditionalBondFallbackPolicy.java',
    'android/app/src/test/java/deckers/thibault/aves/BirdBoxSecurityWriteStateMachineTest.java',
    'android/app/src/test/java/deckers/thibault/aves/BirdBoxConditionalBondFallbackPolicyTest.java',
    'android/app/src/main/AndroidManifest.xml',
    'android/app/build.gradle.kts',
    'android/settings.gradle.kts',
    'pubspec.yaml',
    'pubspec.lock',
    'lib/bird_companion/features/connection/domain/ble_connection_diagnostics.dart',
    'lib/bird_companion/features/connection/domain/provisioning_models.dart',
    'lib/bird_companion/features/connection/presentation/provisioning_cubit.dart',
    'integration_test/ble11_dual_avd_test.dart',
    'test/bird_companion/acceptance/ble11_simulated_evidence_test.dart',
    'test/bird_companion/acceptance/ble11_virtual_box_isolation_test.dart',
    'test/bird_companion/acceptance/ble12_candidate_package_test.dart',
    'test/bird_companion/features/connection/ble_connection_diagnostics_test.dart',
    'test/bird_companion/features/connection/ble_discovery_test.dart',
    'test/bird_companion/features/connection/provisioning_cubit_test.dart'
)) {
    Add-SourceFile $sourcePaths $path
}
foreach ($directory in @(
    'lib/bird_companion/features/connection/data/ble',
    'android/virtualBirdBox',
    'tool/ble11',
    'tool/ble12'
)) {
    Add-SourceDirectory $sourcePaths $directory
}

$sourceHashes = [ordered]@{}
$sortedSourcePaths = [string[]]@($sourcePaths)
[System.Array]::Sort($sortedSourcePaths, [System.StringComparer]::Ordinal)
foreach ($path in $sortedSourcePaths) {
    $sourceHashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repositoryRoot $path)).Hash.ToLowerInvariant()
}
$canonicalInventory = (($sortedSourcePaths | ForEach-Object { "$_=$($sourceHashes[$_])`n" }) -join '')
$canonicalPath = Join-Path $workRoot 'source-inventory.canonical.txt'
Write-Utf8NoBom $canonicalPath $canonicalInventory
$sourceTreeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalPath).Hash.ToLowerInvariant()
$candidateId = "ble12-$($sourceTreeHash.Substring(0, 16))"
$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputRoot))
}
$allowedOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'outputs')).TrimEnd('\', '/')
$allowedOutputPrefix = "$allowedOutputRoot$([System.IO.Path]::DirectorySeparatorChar)"
if ($resolvedOutputRoot -ne $allowedOutputRoot -and !$resolvedOutputRoot.StartsWith($allowedOutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BLE-12 output must remain under the repository outputs directory.'
}
$finalPackageRoot = Join-Path $resolvedOutputRoot $candidateId
$packageRoot = Join-Path $workRoot "package-$candidateId"
if ((Test-Path -LiteralPath $finalPackageRoot) -or (Test-Path -LiteralPath $packageRoot)) {
    throw "Candidate package or staging directory already exists and will not be overwritten: $candidateId"
}

$steps = [System.Collections.Generic.List[object]]::new()
$flutterTestLog = Join-Path $workRoot 'flutter-test.log'
$steps.Add((Invoke-CandidateStep 'Flutter full regression' {
    & $flutter test --no-pub --reporter compact
} $flutterTestLog))
$testText = Get-Content -Raw -LiteralPath $flutterTestLog
$testMatches = [regex]::Matches($testText, '\+(\d+): All tests passed!')
if ($testMatches.Count -eq 0) { throw 'Unable to read the Flutter test count.' }
$flutterTestCount = [int]$testMatches[$testMatches.Count - 1].Groups[1].Value

$analyzeLog = Join-Path $workRoot 'flutter-analyze.log'
$steps.Add((Invoke-CandidateStep 'Flutter static analysis' {
    & $flutter analyze --no-pub
} $analyzeLog))
if ((Get-Content -Raw -LiteralPath $analyzeLog) -notmatch 'No issues found!') {
    throw 'Flutter analysis did not report zero issues.'
}

$appNativeLog = Join-Path $workRoot 'app-native-tests.log'
$steps.Add((Invoke-CandidateStep 'App native BLE regression' {
    Push-Location $androidRoot
    try {
        & $gradle :app:testBirdDebugUnitTest `
            --tests deckers.thibault.aves.BirdBoxSecurityWriteStateMachineTest `
            --tests deckers.thibault.aves.BirdBoxConditionalBondFallbackPolicyTest `
            --no-daemon --no-configuration-cache
    } finally {
        Pop-Location
    }
} $appNativeLog))
$appNativeCount = Get-TestCount (Join-Path $repositoryRoot 'build\app\test-results\testBirdDebugUnitTest') @(
    'deckers.thibault.aves.BirdBoxSecurityWriteStateMachineTest',
    'deckers.thibault.aves.BirdBoxConditionalBondFallbackPolicyTest'
)

$virtualLog = Join-Path $workRoot 'virtual-birdbox-tests.log'
$steps.Add((Invoke-CandidateStep 'Virtual BirdBox tests and APK' {
    Push-Location $androidRoot
    try {
        & $gradle :virtualBirdBox:testDebugUnitTest :virtualBirdBox:assembleDebug `
            --no-daemon --no-configuration-cache
    } finally {
        Pop-Location
    }
} $virtualLog))
$virtualTestCount = Get-TestCount (Join-Path $repositoryRoot 'build\virtualBirdBox\test-results\testDebugUnitTest') @(
    'deckers.thibault.aves.virtualbirdbox.Rc4BleFrameCodecTest',
    'deckers.thibault.aves.virtualbirdbox.Ble11ScenarioStateTest'
)

$previousGitSha = $env:AVES_GIT_SHA
$env:AVES_GIT_SHA = $gitCommit
try {
    $appBuildLog = Join-Path $workRoot 'app-apk-build.log'
    $steps.Add((Invoke-CandidateStep 'BirdBox candidate debug APK' {
        & $flutter build apk --debug --flavor bird --no-pub
    } $appBuildLog))
} finally {
    if ($null -eq $previousGitSha) {
        Remove-Item Env:AVES_GIT_SHA -ErrorAction SilentlyContinue
    } else {
        $env:AVES_GIT_SHA = $previousGitSha
    }
}

$appApk = Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-bird-debug.apk'
$virtualApk = Join-Path $repositoryRoot 'build\virtualBirdBox\outputs\apk\debug\virtualBirdBox-debug.apk'
if (!(Test-Path -LiteralPath $appApk) -or !(Test-Path -LiteralPath $virtualApk)) {
    throw 'Candidate APK output is missing.'
}

$null = New-Item -ItemType Directory -Path $packageRoot
foreach ($directory in @('artifacts', 'reports', 'source', 'evidence\ble11', 'docs', 'templates')) {
    $null = New-Item -ItemType Directory -Path (Join-Path $packageRoot $directory)
}
Copy-Item -LiteralPath $appApk -Destination (Join-Path $packageRoot 'artifacts\BirdBox-1.14.8-172-BLE12-debug.apk')
Copy-Item -LiteralPath $virtualApk -Destination (Join-Path $packageRoot 'artifacts\VirtualBirdBox-BLE11-debug.apk')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'materials\field-integration-manual.zh-CN.md') -Destination (Join-Path $packageRoot 'docs\field-integration-manual.zh-CN.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'materials\diagnostic-return-guide.zh-CN.md') -Destination (Join-Path $packageRoot 'docs\diagnostic-return-guide.zh-CN.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'materials\ble12-return.template.json') -Destination (Join-Path $packageRoot 'templates\ble12-return.template.json')
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs\acceptance\rc4-hf-ble-03-evidence.template.json') -Destination (Join-Path $packageRoot 'templates\rc4-hf-ble-03-evidence.template.json')
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs\acceptance\rc4-hf-ble-04-release.template.json') -Destination (Join-Path $packageRoot 'templates\rc4-hf-ble-04-release.template.json')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'materials\verify_package.ps1') -Destination (Join-Path $packageRoot 'verify_package.ps1')

$appManifestOutput = @(Invoke-NativeOutput 'BirdBox APK manifest inspection' {
    & $apkAnalyzer manifest print $appApk
})
Write-Utf8NoBom (Join-Path $packageRoot 'reports\app-apk-manifest.xml') (($appManifestOutput | ForEach-Object { $_.ToString() }) -join "`n")
$virtualManifestOutput = @(Invoke-NativeOutput 'virtual BirdBox APK manifest inspection' {
    & $apkAnalyzer manifest print $virtualApk
})
Write-Utf8NoBom (Join-Path $packageRoot 'reports\virtual-birdbox-apk-manifest.xml') (($virtualManifestOutput | ForEach-Object { $_.ToString() }) -join "`n")

$sourceManifest = [ordered]@{
    schema_version = 1
    candidate_id = $candidateId
    git_commit = $gitCommit
    branch = $branch
    state = $sourceState
    source_tree_sha256 = $sourceTreeHash
    files = $sourceHashes
}
$sourceManifestPath = Join-Path $packageRoot 'source\source-manifest.json'
Write-Utf8NoBom $sourceManifestPath ($sourceManifest | ConvertTo-Json -Depth 100)

$flutterMachine = (& $flutter --version --machine 2>$null | ConvertFrom-Json)
$dartVersion = ((Invoke-NativeOutput 'Dart version query' { & $dart --version }) -join ' ').Trim()
$javaVersion = ((Invoke-NativeOutput 'Java version query' { & (Join-Path $env:JAVA_HOME 'bin\java.exe') -version } | Select-Object -First 1) -join ' ').Trim()
$gradleProperties = Get-Content -Raw -LiteralPath (Join-Path $androidRoot 'gradle\wrapper\gradle-wrapper.properties')
$gradleMatch = [regex]::Match($gradleProperties, 'gradle-([0-9.]+)-(?:bin|all)\.zip')
$gradleVersion = if ($gradleMatch.Success) { $gradleMatch.Groups[1].Value } else { 'unknown' }
$environment = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    os_version = [System.Environment]::OSVersion.VersionString
    os_architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    flutter_version = [string]$flutterMachine.frameworkVersion
    flutter_channel = [string]$flutterMachine.channel
    dart_version = $dartVersion
    java_version = $javaVersion
    gradle_version = $gradleVersion
    android_sdk = $AndroidSdk
    emulator_version = $emulatorVersion
    dual_avd_capable = $dualAvdCapable
    avds = $avds
}
$environmentPath = Join-Path $packageRoot 'reports\build-environment.json'
Write-Utf8NoBom $environmentPath ($environment | ConvertTo-Json -Depth 20)

$verification = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    candidate_id = $candidateId
    status = 'passed'
    evidence_kind = 'simulated'
    hardware_status = 'pending'
    releasable = $false
    flutter_test_count = $flutterTestCount
    flutter_analyze_issues = 0
    app_native_test_count = $appNativeCount
    virtual_birdbox_test_count = $virtualTestCount
    app_apk_build = 'passed'
    virtual_apk_build = 'passed'
    steps = $steps
}
$verificationPath = Join-Path $packageRoot 'reports\automated-verification.json'
Write-Utf8NoBom $verificationPath ($verification | ConvertTo-Json -Depth 30)

$expectedScenarios = @('success', 'auto_bond', 'fallback_once', 'disconnect_once')
$evidenceReferences = @()
if ($Ble11Evidence.Count -eq 0) {
    $simulationStatus = 'pending_environment'
    $ble11Status = [ordered]@{
        schema_version = 1
        evidence_kind = 'simulated'
        hardware_status = 'pending'
        releasable = $false
        status = $simulationStatus
        required_emulator_version = '36.5+'
        detected_emulator_version = $emulatorVersion
        dual_avd_capable = $false
        avds = $avds
        expected_scenarios = $expectedScenarios
        completed_scenarios = @()
        reason = 'Android Emulator is below 36.5; BLE-11 dual AVD execution is blocked.'
    }
} else {
    $observedScenarios = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($evidencePathValue in $Ble11Evidence) {
        $evidenceFile = Get-Item -LiteralPath $evidencePathValue
        & $dart (Join-Path $repositoryRoot 'tool\ble11\validate_ble11_evidence.dart') $evidenceFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "Invalid BLE-11 evidence: $($evidenceFile.FullName)" }
        $evidenceValue = Get-Content -Raw -LiteralPath $evidenceFile.FullName | ConvertFrom-Json
        $scenario = [string]$evidenceValue.scenario
        if ($scenario -notin $expectedScenarios -or !$observedScenarios.Add($scenario)) {
            throw "Duplicate or invalid BLE-11 scenario: $scenario"
        }
        $targetDirectory = Join-Path $packageRoot "evidence\ble11\$scenario"
        $null = New-Item -ItemType Directory -Path $targetDirectory
        foreach ($pcap in $evidenceValue.netsim.pcap_files) {
            $sourcePcap = [System.IO.Path]::GetFullPath((Join-Path $evidenceFile.Directory.FullName ([string]$pcap.path)))
            $evidenceDirectory = $evidenceFile.Directory.FullName.TrimEnd('\', '/')
            $evidenceDirectoryPrefix = "$evidenceDirectory$([System.IO.Path]::DirectorySeparatorChar)"
            if (!$sourcePcap.StartsWith($evidenceDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Unsafe BLE-11 PCAP path: $($pcap.path)"
            }
            if (!(Test-Path -LiteralPath $sourcePcap -PathType Leaf)) {
                throw "BLE-11 PCAP is missing: $sourcePcap"
            }
            $actualPcapHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePcap).Hash.ToLowerInvariant()
            if ($actualPcapHash -ne ([string]$pcap.sha256).ToLowerInvariant()) {
                throw "BLE-11 PCAP SHA-256 mismatch: $sourcePcap"
            }
            $pcapName = [System.IO.Path]::GetFileName($sourcePcap)
            $targetPcap = Join-Path $targetDirectory $pcapName
            Copy-Item -LiteralPath $sourcePcap -Destination $targetPcap
            $pcap.path = $pcapName
        }
        $targetEvidence = Join-Path $targetDirectory 'evidence.json'
        Write-Utf8NoBom $targetEvidence ($evidenceValue | ConvertTo-Json -Depth 100)
        $evidenceReferences += [ordered]@{ file = "evidence/ble11/$scenario/evidence.json" }
    }
    $simulationStatus = 'passed'
    $ble11Status = [ordered]@{
        schema_version = 1
        evidence_kind = 'simulated'
        hardware_status = 'pending'
        releasable = $false
        status = $simulationStatus
        required_emulator_version = '36.5+'
        detected_emulator_version = $emulatorVersion
        dual_avd_capable = $true
        avds = $avds
        expected_scenarios = $expectedScenarios
        completed_scenarios = @($observedScenarios | Sort-Object)
        reason = 'All required BLE-11 simulated scenarios passed.'
    }
}
$ble11StatusPath = Join-Path $packageRoot 'evidence\ble11-status.json'
Write-Utf8NoBom $ble11StatusPath ($ble11Status | ConvertTo-Json -Depth 30)

$artifactHashes = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName) {
    $relative = Get-ContainedRelativePath $packageRoot $file.FullName
    $artifactHashes[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
}
foreach ($reference in $evidenceReferences) {
    $reference.sha256 = $artifactHashes[[string]$reference.file]
}

$manifest = [ordered]@{
    schema_version = 1
    candidate_suite = 'rc4-hf-ble-12'
    candidate_id = $candidateId
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    purpose = 'simulated_candidate_external_handoff'
    evidence_kind = 'simulated'
    hardware_status = 'pending'
    releasable = $false
    release_gate_status = 'blocked_hardware_pending'
    production_behavior = [ordered]@{
        state = 'frozen'
        change_policy = 'new_evidence_required'
    }
    source = [ordered]@{
        git_commit = $gitCommit
        branch = $branch
        state = $sourceState
        source_tree_sha256 = $sourceTreeHash
        manifest = Get-Reference 'source/source-manifest.json' $artifactHashes
    }
    builds = [ordered]@{
        app = [ordered]@{
            file = 'artifacts/BirdBox-1.14.8-172-BLE12-debug.apk'
            sha256 = $artifactHashes['artifacts/BirdBox-1.14.8-172-BLE12-debug.apk']
            package_id = 'deckers.thibault.aves.bird'
            build_mode = 'debug_candidate'
            version_name = '1.14.8'
            version_code = 172
            git_commit = $gitCommit
            manifest_report = Get-Reference 'reports/app-apk-manifest.xml' $artifactHashes
        }
        virtual_birdbox = [ordered]@{
            file = 'artifacts/VirtualBirdBox-BLE11-debug.apk'
            sha256 = $artifactHashes['artifacts/VirtualBirdBox-BLE11-debug.apk']
            package_id = 'deckers.thibault.aves.virtualbirdbox.debug'
            build_mode = 'debug_test_only'
            version_name = 'ble11'
            version_code = 1
            git_commit = $gitCommit
            test_only = $true
            release_variant_enabled = $false
            manifest_report = Get-Reference 'reports/virtual-birdbox-apk-manifest.xml' $artifactHashes
        }
    }
    reports = [ordered]@{
        build_environment = Get-Reference 'reports/build-environment.json' $artifactHashes
        automated_verification = Get-Reference 'reports/automated-verification.json' $artifactHashes
    }
    simulation = [ordered]@{
        status = $simulationStatus
        expected_scenarios = $expectedScenarios
        status_report = Get-Reference 'evidence/ble11-status.json' $artifactHashes
        evidence_files = $evidenceReferences
    }
    materials = [ordered]@{
        field_manual = Get-Reference 'docs/field-integration-manual.zh-CN.md' $artifactHashes
        diagnostic_guide = Get-Reference 'docs/diagnostic-return-guide.zh-CN.md' $artifactHashes
        return_template = Get-Reference 'templates/ble12-return.template.json' $artifactHashes
        real_device_template = Get-Reference 'templates/rc4-hf-ble-03-evidence.template.json' $artifactHashes
        release_template = Get-Reference 'templates/rc4-hf-ble-04-release.template.json' $artifactHashes
        offline_verifier = Get-Reference 'verify_package.ps1' $artifactHashes
    }
    artifacts = $artifactHashes
}
$manifestPath = Join-Path $packageRoot 'candidate-manifest.json'
Write-Utf8NoBom $manifestPath ($manifest | ConvertTo-Json -Depth 100)

$sumLines = [System.Collections.Generic.List[string]]::new()
$manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
$sumLines.Add("$manifestHash *candidate-manifest.json")
foreach ($path in ($artifactHashes.Keys | Sort-Object)) {
    $sumLines.Add("$($artifactHashes[$path]) *$path")
}
Write-Utf8NoBom (Join-Path $packageRoot 'SHA256SUMS.txt') (($sumLines -join "`n") + "`n")

& $dart (Join-Path $repositoryRoot 'tool\ble12\validate_ble12_candidate.dart') `
    "--manifest=$manifestPath" "--repository=$repositoryRoot"
if ($LASTEXITCODE -ne 0) { throw 'BLE-12 semantic validation failed.' }
& (Join-Path $packageRoot 'verify_package.ps1') -Manifest $manifestPath
if ($LASTEXITCODE -ne 0) { throw 'BLE-12 offline integrity validation failed.' }

$null = New-Item -ItemType Directory -Path $resolvedOutputRoot -Force
Move-Item -LiteralPath $packageRoot -Destination $finalPackageRoot
$packageRoot = $finalPackageRoot

if ($CreateZip) {
    $zipPath = "$packageRoot.zip"
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "BLE-12 ZIP SHA-256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant())"
}

Write-Host "BLE-12 candidate package: $packageRoot"
Write-Host "candidate_id=$candidateId"
Write-Host 'hardware_status=pending; releasable=false'
