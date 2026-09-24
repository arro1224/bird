import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../ble11/ble11_evidence_validator.dart';

const ble12ExpectedScenarios = <String>{
  'success',
  'auto_bond',
  'fallback_once',
  'disconnect_once',
};

const ble12RequiredFrozenFiles = <String>{
  'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java',
  'android/app/src/main/java/deckers/thibault/aves/BirdBoxSecurityWriteStateMachine.java',
  'android/app/src/main/java/deckers/thibault/aves/BirdBoxConditionalBondFallbackPolicy.java',
  'lib/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart',
  'lib/bird_companion/features/connection/domain/ble_connection_diagnostics.dart',
  'lib/bird_companion/features/connection/presentation/provisioning_cubit.dart',
  'pubspec.yaml',
  'pubspec.lock',
  'android/app/build.gradle.kts',
  'android/settings.gradle.kts',
  'test/bird_companion/acceptance/ble12_candidate_package_test.dart',
};

final class Ble12CandidateValidation {
  const Ble12CandidateValidation({required this.errors});

  final List<String> errors;

  bool get passed => errors.isEmpty;

  Map<String, Object?> toJson({required Map<String, dynamic> manifest}) => {
    'gate': 'RC4-HF-BLE-12',
    'status': passed ? 'candidate_package_ready' : 'blocked',
    'candidate_id': manifest['candidate_id'],
    'simulation_status': _map(manifest['simulation'])['status'] ?? 'unknown',
    'hardware_status': 'pending',
    'releasable': false,
    'failure_count': errors.length,
    'failures': errors,
  };
}

Future<Ble12CandidateValidation> validateBle12Candidate({
  required Map<String, dynamic> manifest,
  required Directory packageRoot,
  Directory? repositoryRoot,
}) async {
  final errors = <String>[];

  void require(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  require(manifest['schema_version'] == 1, 'schema_version must be 1.');
  require(
    manifest['candidate_suite'] == 'rc4-hf-ble-12',
    'candidate_suite must be rc4-hf-ble-12.',
  );
  require(
    RegExp(r'^ble12-[0-9a-f]{16}$').hasMatch(_text(manifest['candidate_id'])),
    'candidate_id must be derived from the frozen source fingerprint.',
  );
  require(
    DateTime.tryParse(_text(manifest['created_at'])) != null,
    'created_at must be ISO-8601.',
  );
  require(
    manifest['purpose'] == 'simulated_candidate_external_handoff',
    'purpose is invalid.',
  );
  require(
    manifest['evidence_kind'] == 'simulated',
    'evidence_kind must remain simulated.',
  );
  require(
    manifest['hardware_status'] == 'pending',
    'hardware_status must remain pending.',
  );
  require(manifest['releasable'] == false, 'candidate must remain non-releasable.');
  require(
    manifest['release_gate_status'] == 'blocked_hardware_pending',
    'formal release gate must remain blocked on hardware evidence.',
  );

  final productionBehavior = _map(manifest['production_behavior']);
  require(
    productionBehavior['state'] == 'frozen',
    'production BLE behavior must be frozen.',
  );
  require(
    productionBehavior['change_policy'] == 'new_evidence_required',
    'production behavior changes must require new evidence.',
  );

  final artifacts = _map(manifest['artifacts']);
  require(artifacts.isNotEmpty, 'artifact inventory is required.');
  for (final entry in artifacts.entries) {
    final relativePath = _safeRelativePath(entry.key, errors);
    final expectedHash = _text(entry.value).toLowerCase();
    require(_isSha256(expectedHash), 'artifact ${entry.key} must have SHA-256.');
    if (relativePath == null) continue;
    final file = _relativeFile(packageRoot, relativePath);
    require(file.existsSync(), 'artifact is missing: $relativePath');
    if (file.existsSync() && _isSha256(expectedHash)) {
      final actual = await _fileSha256(file);
      require(actual == expectedHash, 'artifact SHA-256 mismatch: $relativePath');
    }
  }
  final actualPayloads = packageRoot
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => _relativePath(packageRoot, file))
      .where(
        (path) => path != 'candidate-manifest.json' && path != 'SHA256SUMS.txt',
      )
      .toSet();
  require(
    actualPayloads.difference(artifacts.keys.toSet()).isEmpty,
    'package contains payloads not registered in artifacts.',
  );
  require(
    artifacts.keys.toSet().difference(actualPayloads).isEmpty,
    'artifact inventory references missing payloads.',
  );

  final source = _map(manifest['source']);
  final gitCommit = _text(source['git_commit']).toLowerCase();
  final sourceTreeHash = _text(source['source_tree_sha256']).toLowerCase();
  require(_isSha40(gitCommit), 'source.git_commit must be a full Git SHA.');
  require(_text(source['branch']).isNotEmpty, 'source.branch is required.');
  require(
    const {'clean_git_commit', 'uncommitted_candidate_snapshot'}.contains(
      source['state'],
    ),
    'source.state must disclose whether the candidate is dirty.',
  );
  require(_isSha256(sourceTreeHash), 'source.source_tree_sha256 is invalid.');
  final sourceManifest = await _readReferencedJson(
    packageRoot,
    _map(source['manifest']),
    'source manifest',
    errors,
  );
  final frozenFiles = _map(sourceManifest['files']).map(
    (key, value) => MapEntry(key.replaceAll('\\', '/'), _text(value).toLowerCase()),
  );
  require(
    sourceManifest['schema_version'] == 1,
    'source manifest schema_version must be 1.',
  );
  require(
    _text(sourceManifest['git_commit']).toLowerCase() == gitCommit,
    'source manifest Git SHA does not match candidate manifest.',
  );
  require(
    frozenFiles.keys.toSet().containsAll(ble12RequiredFrozenFiles),
    'source manifest does not cover every required production BLE file.',
  );
  require(
    frozenFiles.values.every(_isSha256),
    'source manifest contains an invalid file SHA-256.',
  );
  final computedTreeHash = sha256
      .convert(
        utf8.encode(_canonicalFileInventory(frozenFiles)),
      )
      .toString();
  require(
    computedTreeHash == sourceTreeHash,
    'source tree fingerprint does not match the source manifest '
    '(computed=$computedTreeHash, declared=$sourceTreeHash).',
  );
  if (_isSha256(sourceTreeHash)) {
    require(
      _text(manifest['candidate_id']) == 'ble12-${sourceTreeHash.substring(0, 16)}',
      'candidate_id does not match the frozen source fingerprint.',
    );
  }
  require(
    _text(sourceManifest['source_tree_sha256']).toLowerCase() == sourceTreeHash,
    'source manifest aggregate fingerprint does not match.',
  );
  require(
    sourceManifest['candidate_id'] == manifest['candidate_id'],
    'source manifest candidate_id does not match the candidate manifest.',
  );
  final safeFrozenPaths = <String>{};
  for (final path in frozenFiles.keys) {
    final safePath = _safeRelativePath(path, errors);
    if (safePath != null) safeFrozenPaths.add(safePath);
  }
  if (repositoryRoot != null) {
    for (final entry in frozenFiles.entries) {
      if (!safeFrozenPaths.contains(entry.key)) continue;
      final file = _relativeFile(repositoryRoot, entry.key);
      require(file.existsSync(), 'frozen repository file is missing: ${entry.key}');
      if (file.existsSync()) {
        require(
          await _fileSha256(file) == entry.value,
          'frozen production source changed after packaging: ${entry.key}',
        );
      }
    }
  }

  final builds = _map(manifest['builds']);
  await _validateBuild(
    build: _map(builds['app']),
    label: 'app',
    packageRoot: packageRoot,
    expectedPackage: 'deckers.thibault.aves.bird',
    expectedMode: 'debug_candidate',
    expectedGitCommit: gitCommit,
    errors: errors,
  );
  final virtualBuild = _map(builds['virtual_birdbox']);
  await _validateBuild(
    build: virtualBuild,
    label: 'virtual_birdbox',
    packageRoot: packageRoot,
    expectedPackage: 'deckers.thibault.aves.virtualbirdbox.debug',
    expectedMode: 'debug_test_only',
    expectedGitCommit: gitCommit,
    expectedVersionName: 'ble11',
    expectedVersionCode: 1,
    errors: errors,
  );
  require(
    virtualBuild['test_only'] == true,
    'virtual BirdBox must remain test-only.',
  );
  require(
    virtualBuild['release_variant_enabled'] == false,
    'virtual BirdBox release variant must remain disabled.',
  );

  final reports = _map(manifest['reports']);
  final environment = await _readReferencedJson(
    packageRoot,
    _map(reports['build_environment']),
    'build environment report',
    errors,
  );
  for (final field in const [
    'os_version',
    'flutter_version',
    'dart_version',
    'java_version',
    'gradle_version',
    'android_sdk',
    'emulator_version',
  ]) {
    require(_text(environment[field]).isNotEmpty, 'environment.$field is required.');
  }
  final verification = await _readReferencedJson(
    packageRoot,
    _map(reports['automated_verification']),
    'automated verification report',
    errors,
  );
  require(verification['status'] == 'passed', 'automated verification must pass.');
  final flutterTestCount = verification['flutter_test_count'] is num ? (verification['flutter_test_count'] as num).toInt() : -1;
  require(
    flutterTestCount >= 759,
    'Flutter full regression count must be at least 759.',
  );
  require(
    verification['flutter_analyze_issues'] == 0,
    'Flutter analysis must have zero issues.',
  );
  require(
    (verification['app_native_test_count'] as num?)?.toInt() == 20,
    'App native BLE regression must contain 20 tests.',
  );
  require(
    (verification['virtual_birdbox_test_count'] as num?)?.toInt() == 8,
    'virtual BirdBox regression must contain 8 tests.',
  );
  require(
    verification['app_apk_build'] == 'passed' && verification['virtual_apk_build'] == 'passed',
    'both candidate APK builds must pass.',
  );

  final simulation = _map(manifest['simulation']);
  final simulationStatus = simulation['status'];
  require(
    const {'passed', 'pending_environment'}.contains(simulationStatus),
    'simulation.status must be passed or pending_environment.',
  );
  require(
    _strings(simulation['expected_scenarios']).toSet().containsAll(
          ble12ExpectedScenarios,
        ) &&
        _strings(simulation['expected_scenarios']).toSet().length == ble12ExpectedScenarios.length,
    'simulation must name all four BLE-11 scenarios.',
  );
  final statusReport = await _readReferencedJson(
    packageRoot,
    _map(simulation['status_report']),
    'BLE-11 status report',
    errors,
  );
  require(
    statusReport['evidence_kind'] == 'simulated' && statusReport['hardware_status'] == 'pending',
    'BLE-11 status report must remain simulated and hardware pending.',
  );
  require(
    statusReport['status'] == simulationStatus,
    'BLE-11 status report does not match the candidate manifest.',
  );
  require(
    statusReport['detected_emulator_version'] == environment['emulator_version'],
    'BLE-11 status report emulator version does not match the build environment.',
  );
  final evidenceReferences = _maps(simulation['evidence_files']);
  if (simulationStatus == 'pending_environment') {
    require(
      evidenceReferences.isEmpty,
      'pending_environment must not claim completed BLE-11 evidence.',
    );
    require(
      _text(statusReport['reason']).isNotEmpty,
      'pending_environment must include an actionable reason.',
    );
    require(
      statusReport['dual_avd_capable'] == false,
      'pending_environment must disclose that dual AVD BLE is unavailable.',
    );
    require(
      environment['dual_avd_capable'] == false,
      'a capable environment may not skip the BLE-11 scenario matrix.',
    );
    require(
      !_emulatorAtLeast365(_text(environment['emulator_version'])),
      'Emulator 36.5+ may not use pending_environment.',
    );
  } else {
    require(
      environment['dual_avd_capable'] == true,
      'passed BLE-11 evidence requires a dual-AVD-capable environment.',
    );
    require(
      evidenceReferences.length == ble12ExpectedScenarios.length,
      'passed simulation requires four BLE-11 evidence files.',
    );
    final observedScenarios = <String>{};
    for (final reference in evidenceReferences) {
      final evidence = await _readReferencedJson(
        packageRoot,
        reference,
        'BLE-11 scenario evidence',
        errors,
      );
      final result = validateBle11Evidence(evidence);
      for (final error in result.errors) {
        errors.add('BLE-11 ${evidence['scenario'] ?? 'unknown'}: $error');
      }
      final scenario = _text(evidence['scenario']);
      if (scenario.isNotEmpty) observedScenarios.add(scenario);
      final evidenceFile = _relativeFile(
        packageRoot,
        _text(reference['file']),
      );
      for (final pcap in _maps(_map(evidence['netsim'])['pcap_files'])) {
        final pcapPath = _safeRelativePath(_text(pcap['path']), errors);
        if (pcapPath == null) continue;
        final pcapFile = File(
          '${evidenceFile.parent.path}${Platform.pathSeparator}${pcapPath.replaceAll('/', Platform.pathSeparator)}',
        );
        require(
          pcapFile.existsSync(),
          'BLE-11 PCAP is missing for $scenario: $pcapPath',
        );
        if (pcapFile.existsSync()) {
          require(
            await _fileSha256(pcapFile) == _text(pcap['sha256']).toLowerCase(),
            'BLE-11 PCAP SHA-256 mismatch for $scenario: $pcapPath',
          );
        }
      }
    }
    require(
      observedScenarios.length == ble12ExpectedScenarios.length && observedScenarios.containsAll(ble12ExpectedScenarios),
      'BLE-11 evidence does not cover the exact scenario matrix.',
    );
  }

  final materials = _map(manifest['materials']);
  for (final name in const [
    'field_manual',
    'diagnostic_guide',
    'return_template',
    'real_device_template',
    'release_template',
    'offline_verifier',
  ]) {
    await _validateReference(
      packageRoot,
      _map(materials[name]),
      'materials.$name',
      errors,
    );
  }

  final sumsFile = File(
    '${packageRoot.path}${Platform.pathSeparator}SHA256SUMS.txt',
  );
  require(sumsFile.existsSync(), 'SHA256SUMS.txt is missing.');
  if (sumsFile.existsSync()) {
    final sums = <String, String>{};
    for (final line in sumsFile.readAsLinesSync()) {
      final match = RegExp(r'^([0-9a-f]{64}) \*(.+)$').firstMatch(line.trim());
      if (match != null) sums[match.group(2)!.replaceAll('\\', '/')] = match.group(1)!;
    }
    require(
      sums['candidate-manifest.json'] ==
          await _fileSha256(
            File(
              '${packageRoot.path}${Platform.pathSeparator}candidate-manifest.json',
            ),
          ),
      'SHA256SUMS.txt does not protect candidate-manifest.json.',
    );
    for (final entry in artifacts.entries) {
      require(
        sums[entry.key] == _text(entry.value).toLowerCase(),
        'SHA256SUMS.txt mismatch: ${entry.key}',
      );
    }
  }

  _scanJsonForUnsafeClaimsAndSecrets(manifest, 'candidate manifest', errors);
  _scanJsonForUnsafeClaimsAndSecrets(environment, 'environment report', errors);
  _scanJsonForUnsafeClaimsAndSecrets(verification, 'verification report', errors);
  _scanJsonForUnsafeClaimsAndSecrets(statusReport, 'BLE-11 status report', errors);

  return Ble12CandidateValidation(errors: List.unmodifiable(errors));
}

Future<void> _validateBuild({
  required Map<String, dynamic> build,
  required String label,
  required Directory packageRoot,
  required String expectedPackage,
  required String expectedMode,
  required String expectedGitCommit,
  String expectedVersionName = '1.14.8',
  int expectedVersionCode = 172,
  required List<String> errors,
}) async {
  void require(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  require(build['package_id'] == expectedPackage, '$label package_id is invalid.');
  require(build['build_mode'] == expectedMode, '$label build_mode is invalid.');
  require(
    build['version_name'] == expectedVersionName,
    '$label version_name must be $expectedVersionName.',
  );
  require(
    build['version_code'] == expectedVersionCode,
    '$label version_code must be $expectedVersionCode.',
  );
  require(
    _text(build['git_commit']).toLowerCase() == expectedGitCommit,
    '$label Git SHA does not match the frozen source.',
  );
  await _validateReference(packageRoot, build, 'builds.$label', errors);
  final apkManifest = await _validateReference(
    packageRoot,
    _map(build['manifest_report']),
    'builds.$label.manifest_report',
    errors,
  );
  if (apkManifest != null && apkManifest.existsSync()) {
    final xml = apkManifest.readAsStringSync();
    require(
      xml.contains('package="$expectedPackage"'),
      '$label APK manifest package does not match.',
    );
    require(
      xml.contains('android:versionName="$expectedVersionName"'),
      '$label APK manifest versionName does not match.',
    );
    require(
      xml.contains('android:versionCode="$expectedVersionCode"'),
      '$label APK manifest versionCode does not match.',
    );
    require(
      xml.contains('android:debuggable="true"'),
      '$label APK must be a debuggable candidate build.',
    );
    if (label == 'virtual_birdbox') {
      require(
        xml.contains('android:testOnly="true"'),
        'virtual_birdbox APK manifest must remain test-only.',
      );
    }
  }
}

Future<Map<String, dynamic>> _readReferencedJson(
  Directory packageRoot,
  Map<String, dynamic> reference,
  String label,
  List<String> errors,
) async {
  final file = await _validateReference(packageRoot, reference, label, errors);
  if (file == null || !file.existsSync()) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    errors.add('$label must contain a JSON object.');
  } on FormatException catch (error) {
    errors.add('$label is invalid JSON: ${error.message}');
  }
  return <String, dynamic>{};
}

Future<File?> _validateReference(
  Directory packageRoot,
  Map<String, dynamic> reference,
  String label,
  List<String> errors,
) async {
  final relativePath = _safeRelativePath(_text(reference['file']), errors);
  final expectedHash = _text(reference['sha256']).toLowerCase();
  if (!_isSha256(expectedHash)) errors.add('$label.sha256 must be SHA-256.');
  if (relativePath == null) return null;
  final file = _relativeFile(packageRoot, relativePath);
  if (!file.existsSync()) {
    errors.add('$label file is missing: $relativePath');
    return file;
  }
  if (file.lengthSync() == 0) errors.add('$label file is empty.');
  if (_isSha256(expectedHash) && await _fileSha256(file) != expectedHash) {
    errors.add('$label SHA-256 mismatch.');
  }
  return file;
}

String? _safeRelativePath(String value, List<String> errors) {
  final normalized = value.replaceAll('\\', '/').trim();
  final segments = normalized.split('/');
  if (normalized.isEmpty || normalized.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(normalized) || segments.contains('..') || segments.contains('.')) {
    errors.add('unsafe package-relative path: $value');
    return null;
  }
  return normalized;
}

File _relativeFile(Directory root, String relativePath) => File(
  '${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
);

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final filePath = file.absolute.path.replaceAll('\\', '/');
  return filePath.substring(rootPath.length + 1);
}

String _canonicalFileInventory(Map<String, String> files) {
  final paths = files.keys.toList()..sort();
  return paths.map((path) => '$path=${files[path]}\n').join();
}

Future<String> _fileSha256(File file) async => (await sha256.bind(file.openRead()).first).toString();

void _scanJsonForUnsafeClaimsAndSecrets(
  Map<String, dynamic> value,
  String label,
  List<String> errors,
) {
  final encoded = jsonEncode(value);
  if (RegExp(
    r'\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b',
    caseSensitive: false,
  ).hasMatch(encoded)) {
    errors.add('$label contains a complete MAC address.');
  }
  if (RegExp(
    r'"(?:password|passphrase|token|secret|pairing_code)"\s*:\s*"(?!\[REDACTED\])[^\"]+"',
    caseSensitive: false,
  ).hasMatch(encoded)) {
    errors.add('$label contains credential-like material.');
  }
  if (RegExp(
    r'"hardware_status"\s*:\s*"verified"',
    caseSensitive: false,
  ).hasMatch(encoded)) {
    errors.add('$label attempts to claim hardware verification.');
  }
  if (RegExp(
    r'"releasable"\s*:\s*true',
    caseSensitive: false,
  ).hasMatch(encoded)) {
    errors.add('$label attempts to claim release eligibility.');
  }
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List ? value.map(_map).where((item) => item.isNotEmpty).toList(growable: false) : const [];

List<String> _strings(Object? value) => value is List ? value.map(_text).where((item) => item.isNotEmpty).toList(growable: false) : const [];

String _text(Object? value) => value?.toString().trim() ?? '';
bool _isSha40(Object? value) => RegExp(r'^[0-9a-f]{40}$').hasMatch(_text(value));
bool _isSha256(Object? value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(_text(value));

bool _emulatorAtLeast365(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 36 || major == 36 && minor >= 5;
}
