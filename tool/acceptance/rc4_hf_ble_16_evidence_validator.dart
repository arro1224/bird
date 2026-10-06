import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const rc4HfBle16MinimumExclusiveVersionCode = 173;

const _artifactContracts = <String, ({String packageId, String displayName, String buildMode, String policy})>{
  'bird': (
    packageId: 'deckers.thibault.aves.bird',
    displayName: '拍鸟伴侣',
    buildMode: 'release',
    policy: 'selected',
  ),
  'birdScanA': (
    packageId: 'deckers.thibault.aves.bird.scan.a',
    displayName: 'BirdBox 扫描 A',
    buildMode: 'debug',
    policy: 'never_for_location',
  ),
  'birdScanB': (
    packageId: 'deckers.thibault.aves.bird.scan.b',
    displayName: 'BirdBox 扫描 B',
    buildMode: 'debug',
    policy: 'full_scan',
  ),
};

const _automationIds = <String>{
  'flutter_analyze',
  'flutter_test',
  'android_bird_unit',
  'android_scan_a_unit',
  'android_scan_b_unit',
  'candidate_builds',
  'git_diff_check',
};

const _scenarioArtifacts = <String, String>{
  'T1': 'bird',
  'T2': 'bird',
  'T3': 'bird',
  'T4': 'birdScanA',
  'T5': 'birdScanB',
  'T6': 'bird',
  'T7': 'bird',
  'T8': 'bird',
};

final class Rc4HfBle16ArtifactIdentity {
  const Rc4HfBle16ArtifactIdentity({
    required this.packageId,
    required this.versionName,
    required this.versionCode,
    required this.gitCommit,
    required this.apkSha256,
    required this.scanPermissionPolicy,
  });

  final String packageId;
  final String versionName;
  final int versionCode;
  final String gitCommit;
  final String apkSha256;
  final String scanPermissionPolicy;
}

final class Rc4HfBle16EvidenceValidation {
  const Rc4HfBle16EvidenceValidation({
    required this.errors,
    required this.gitCommit,
    required this.versionName,
    required this.versionCode,
    required this.selectedScanVariant,
    required this.artifacts,
    required this.scenarioCount,
  });

  final List<String> errors;
  final String gitCommit;
  final String versionName;
  final int versionCode;
  final String selectedScanVariant;
  final Map<String, Rc4HfBle16ArtifactIdentity> artifacts;
  final int scenarioCount;

  bool get passed => errors.isEmpty;

  Map<String, Object?> toJson() => {
    'gate': 'RC4-HF-BLE-16',
    'status': passed ? 'passed' : 'blocked',
    'releasable': passed,
    'version_name': versionName,
    'version_code': versionCode,
    'git_commit': gitCommit,
    'selected_scan_variant': selectedScanVariant,
    'artifact_count': artifacts.length,
    'scenario_count': scenarioCount,
    'failure_count': errors.length,
    'failures': errors,
  };
}

Rc4HfBle16EvidenceValidation validateRc4HfBle16Evidence(
  Map<String, dynamic> evidence, {
  required Directory evidenceRoot,
}) {
  final errors = <String>[];
  void require(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  require(evidence['schema_version'] == 1, 'schema_version must be 1.');
  require(
    evidence['evidence_suite'] == 'rc4-hf-ble-16',
    'evidence_suite must be rc4-hf-ble-16.',
  );
  require(evidence['final_result'] == 'passed', 'final_result must be passed.');
  require(
    evidence['release_decision'] == 'approved',
    'release_decision must be approved.',
  );
  require(
    DateTime.tryParse(_text(evidence['captured_at'])) != null,
    'captured_at must be an ISO-8601 timestamp.',
  );
  for (final path in _findPlaceholders(evidence, r'$')) {
    errors.add('Evidence contains an unresolved placeholder: $path.');
  }
  require(
    !_containsPlaintextMac(evidence),
    'Evidence contains a plaintext Bluetooth address.',
  );
  require(
    !_containsForbiddenKey(evidence),
    'Evidence contains a forbidden secret field.',
  );

  final selectedVariant = _text(evidence['selected_scan_variant']);
  require(
    const {'A', 'B'}.contains(selectedVariant),
    'selected_scan_variant must be A or B.',
  );
  final selectedPolicy = selectedVariant == 'B' ? 'full_scan' : 'never_for_location';

  final source = _map(evidence['source']);
  final gitCommit = _text(source['git_commit']).toLowerCase();
  final versionName = _text(source['version_name']);
  final versionCode = source['version_code'] is int ? source['version_code'] as int : -1;
  require(_sha40(gitCommit), 'source.git_commit must be a full Git SHA.');
  require(_usableText(versionName), 'source.version_name is required.');
  require(
    versionCode > rc4HfBle16MinimumExclusiveVersionCode,
    'source.version_code must be greater than $rc4HfBle16MinimumExclusiveVersionCode.',
  );

  final artifactValues = _map(evidence['artifacts']);
  final artifactIdentities = <String, Rc4HfBle16ArtifactIdentity>{};
  for (final entry in _artifactContracts.entries) {
    final id = entry.key;
    final contract = entry.value;
    final artifact = _map(artifactValues[id]);
    require(artifact.isNotEmpty, 'artifacts.$id is required.');
    if (artifact.isEmpty) continue;
    final label = 'artifacts.$id';
    require(
      artifact['package_id'] == contract.packageId,
      '$label.package_id must be ${contract.packageId}.',
    );
    require(
      artifact['display_name'] == contract.displayName,
      '$label.display_name must be ${contract.displayName}.',
    );
    require(artifact['flavor'] == id, '$label.flavor must be $id.');
    require(
      artifact['build_mode'] == contract.buildMode,
      '$label.build_mode must be ${contract.buildMode}.',
    );
    if (id == 'bird') {
      require(artifact['signed'] == true, '$label.signed must be true.');
      require(
        artifact['signature_verified'] == true,
        '$label.signature_verified must be true.',
      );
    }
    require(
      artifact['version_name'] == versionName,
      '$label.version_name must match source.',
    );
    require(
      artifact['version_code'] == versionCode,
      '$label.version_code must match source.',
    );
    require(
      _text(artifact['git_commit']).toLowerCase() == gitCommit,
      '$label.git_commit must match source.',
    );
    final expectedPolicy = contract.policy == 'selected' ? selectedPolicy : contract.policy;
    require(
      artifact['scan_permission_policy'] == expectedPolicy,
      '$label.scan_permission_policy must be $expectedPolicy.',
    );
    if (id != 'bird') {
      require(
        artifact['strategy_fallback_enabled'] == true,
        '$label.strategy_fallback_enabled must be true.',
      );
    }
    require(
      artifact['diagnostic_identity_verified'] == true,
      '$label.diagnostic_identity_verified must be true.',
    );

    final apkSha = _text(artifact['apk_sha256']).toLowerCase();
    final apkPath = _text(artifact['apk_file']);
    require(_sha256(apkSha), '$label.apk_sha256 must be SHA-256.');
    require(_usableText(apkPath), '$label.apk_file is required.');
    if (_usableText(apkPath)) {
      final apk = _resolveFile(evidenceRoot, apkPath);
      require(apk.existsSync(), '$label APK does not exist: $apkPath.');
      if (apk.existsSync()) {
        final actualSha = sha256.convert(apk.readAsBytesSync()).toString();
        require(actualSha == apkSha, '$label.apk_sha256 does not match the APK.');
        require(
          artifact['apk_size_bytes'] == apk.lengthSync(),
          '$label.apk_size_bytes does not match the APK.',
        );
      }
    }
    artifactIdentities[id] = Rc4HfBle16ArtifactIdentity(
      packageId: _text(artifact['package_id']),
      versionName: _text(artifact['version_name']),
      versionCode: artifact['version_code'] is int ? artifact['version_code'] as int : -1,
      gitCommit: _text(artifact['git_commit']).toLowerCase(),
      apkSha256: apkSha,
      scanPermissionPolicy: _text(artifact['scan_permission_policy']),
    );
  }

  final automation = _maps(evidence['automation']);
  final automationIds = automation.map((item) => _text(item['id'])).toList();
  require(
    automationIds.toSet().length == automationIds.length,
    'automation IDs must be unique.',
  );
  for (final id in _automationIds) {
    final matches = automation.where((item) => item['id'] == id).toList();
    require(matches.length == 1, 'automation must contain $id exactly once.');
    if (matches.length == 1) {
      require(
        matches.single['status'] == 'passed',
        'automation.$id.status must be passed.',
      );
      _validateEvidenceFiles(
        evidenceRoot,
        matches.single['evidence_files'],
        'automation.$id',
        require,
        errors,
      );
    }
  }

  final scenarios = _maps(evidence['scenarios']);
  final scenarioIds = scenarios.map((item) => _text(item['id'])).toList();
  require(
    scenarioIds.toSet().length == scenarioIds.length,
    'scenario IDs must be unique.',
  );
  final scenariosById = <String, Map<String, dynamic>>{};
  for (final entry in _scenarioArtifacts.entries) {
    final matches = scenarios.where((item) => item['id'] == entry.key).toList();
    require(matches.length == 1, 'scenarios must contain ${entry.key} exactly once.');
    if (matches.length != 1) continue;
    final scenario = matches.single;
    scenariosById[entry.key] = scenario;
    _validateScenario(
      scenario,
      id: entry.key,
      expectedArtifact: entry.value,
      artifact: artifactIdentities[entry.value],
      evidenceRoot: evidenceRoot,
      require: require,
      errors: errors,
    );
  }
  _validateScenarioAssertions(scenariosById, require);
  _validateHuaweiComparison(scenariosById, require);

  require(
    evidence['known_limitations'] is List,
    'known_limitations must be a list.',
  );
  final rollback = _map(evidence['rollback']);
  require(rollback['tested'] == true, 'rollback.tested must be true.');
  require(
    rollback['package_id'] == _artifactContracts['bird']!.packageId,
    'rollback.package_id must use the production package.',
  );
  require(
    rollback['version_code'] is int && (rollback['version_code'] as int) > 0 && (rollback['version_code'] as int) < versionCode,
    'rollback.version_code must identify an older positive build.',
  );
  require(
    _sha256(rollback['apk_sha256']),
    'rollback.apk_sha256 must be SHA-256.',
  );
  _validateEvidenceFiles(
    evidenceRoot,
    [_text(rollback['evidence_file'])],
    'rollback',
    require,
    errors,
  );

  final approvals = _map(evidence['approvals']);
  for (final role in const ['app', 'board', 'qa']) {
    final approval = _map(approvals[role]);
    require(approval['status'] == 'approved', 'approvals.$role.status must be approved.');
    require(_usableText(approval['reviewer']), 'approvals.$role.reviewer is required.');
    _validateEvidenceFiles(
      evidenceRoot,
      [_text(approval['evidence_file'])],
      'approvals.$role',
      require,
      errors,
    );
  }

  return Rc4HfBle16EvidenceValidation(
    errors: List.unmodifiable(errors),
    gitCommit: gitCommit,
    versionName: versionName,
    versionCode: versionCode,
    selectedScanVariant: selectedVariant,
    artifacts: Map.unmodifiable(artifactIdentities),
    scenarioCount: scenariosById.length,
  );
}

void _validateScenario(
  Map<String, dynamic> scenario, {
  required String id,
  required String expectedArtifact,
  required Rc4HfBle16ArtifactIdentity? artifact,
  required Directory evidenceRoot,
  required void Function(bool, String) require,
  required List<String> errors,
}) {
  final label = 'scenarios.$id';
  require(scenario['status'] == 'passed', '$label.status must be passed.');
  require(scenario['artifact'] == expectedArtifact, '$label.artifact must be $expectedArtifact.');
  require(DateTime.tryParse(_text(scenario['executed_at'])) != null, '$label.executed_at must be ISO-8601.');
  require(_usableText(scenario['executor']), '$label.executor is required.');
  require(_usableText(scenario['environment_id']), '$label.environment_id is required.');
  final rounds = scenario['rounds'];
  require(rounds is int && rounds >= ((id == 'T4' || id == 'T5') ? 3 : 1), '$label.rounds is insufficient.');
  require(artifact != null, '$label references an unavailable artifact.');
  require(
    _text(scenario['apk_sha256']).toLowerCase() == artifact?.apkSha256,
    '$label.apk_sha256 must match the delivered artifact.',
  );
  final phone = _map(scenario['phone']);
  require(phone['physical'] == true, '$label.phone must be physical.');
  for (final field in const ['manufacturer', 'model', 'android_release']) {
    require(_usableText(phone[field]), '$label.phone.$field is required.');
  }
  require(phone['sdk_int'] is int, '$label.phone.sdk_int is required.');
  for (final field in const ['bluetooth_state', 'location_service_state']) {
    require(_usableText(phone[field]), '$label.phone.$field is required.');
  }
  final k7 = _map(scenario['k7']);
  require(k7['physical'] == true, '$label.k7 must be physical.');
  require(_usableText(k7['model']), '$label.k7.model is required.');
  require(_sha40(k7['firmware_sha']) || _sha256(k7['firmware_sha']), '$label.k7.firmware_sha must be a full SHA.');
  _validateEvidenceFiles(evidenceRoot, scenario['evidence_files'], label, require, errors);
}

void _validateScenarioAssertions(
  Map<String, Map<String, dynamic>> scenarios,
  void Function(bool, String) require,
) {
  Map<String, dynamic> values(String id) => _map(scenarios[id]?['assertions']);
  final t1 = values('T1');
  require(t1['ack_received'] == true, 'T1 must receive the K7 ACK.');
  require(t1['create_bond_count'] == 1, 'T1 must call createBond exactly once.');
  require(t1['same_request_retried_once'] == true, 'T1 must retry the same request exactly once.');
  final t2 = values('T2');
  require(t2['ack_received'] == true, 'T2 must receive the K7 ACK.');
  require(t2['unexpected_pairing_prompt'] == false, 'T2 must not show an unexpected pairing prompt.');
  require(values('T3')['error_code'] == 'ble_pairing_timeout', 'T3 must end with ble_pairing_timeout.');
  for (final id in const ['T4', 'T5']) {
    final result = values(id);
    require(result['birdbox_discovered_each_round'] == true, '$id must discover BirdBox in every round.');
    require(result['strategy_counters_recorded'] == true, '$id must record strategy counters.');
  }
  require(values('T6')['scan_connected_and_ack'] == true, 'T6 must scan, connect and receive ACK.');
  final t7 = values('T7');
  require(t7['regression_passed'] == true, 'T7 non-target regression must pass.');
  require(t7['stale_callback_observed'] == false, 'T7 must not observe a stale callback.');
  final t8 = values('T8');
  require(t8['cleanup_verified'] == true, 'T8 must verify cleanup.');
  require(t8['app_crashed'] == false, 'T8 must not crash the app.');
}

void _validateHuaweiComparison(
  Map<String, Map<String, dynamic>> scenarios,
  void Function(bool, String) require,
) {
  final a = scenarios['T4'];
  final b = scenarios['T5'];
  if (a == null || b == null) return;
  final phoneA = _map(a['phone']);
  final phoneB = _map(b['phone']);
  final k7A = _map(a['k7']);
  final k7B = _map(b['k7']);
  require(a['environment_id'] == b['environment_id'], 'T4 and T5 must use the same environment_id.');
  for (final field in const ['manufacturer', 'model', 'android_release', 'sdk_int', 'bluetooth_state', 'location_service_state']) {
    require(phoneA[field] == phoneB[field], 'T4 and T5 phone.$field must match.');
  }
  require(k7A['firmware_sha'] == k7B['firmware_sha'], 'T4 and T5 must use the same K7 firmware.');
}

void _validateEvidenceFiles(
  Directory root,
  Object? value,
  String label,
  void Function(bool, String) require,
  List<String> errors,
) {
  final paths = value is List ? value.map(_text).where((item) => item.isNotEmpty).toList() : <String>[];
  require(paths.isNotEmpty, '$label.evidence_files is required.');
  for (final path in paths) {
    final file = _resolveFile(root, path);
    require(file.existsSync(), '$label evidence file does not exist: $path.');
    if (!file.existsSync()) continue;
    require(file.lengthSync() > 0, '$label evidence file is empty: $path.');
    if (_isTextEvidence(file)) {
      final content = file.readAsStringSync();
      if (_containsPlaintextMac(content)) errors.add('$label evidence contains a plaintext Bluetooth address.');
      if (_containsCredentialText(content)) errors.add('$label evidence contains credential-like material.');
    }
  }
}

Iterable<String> _findPlaceholders(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _findPlaceholders(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (final entry in value.indexed) {
      yield* _findPlaceholders(entry.$2, '$path[${entry.$1}]');
    }
  } else if (value is String && RegExp(r'(^|[^a-z])(REQUIRED_|TODO(?:_|$)|PLACEHOLDER(?:_|$))', caseSensitive: false).hasMatch(value)) {
    yield path;
  }
}

bool _containsPlaintextMac(Object? value) {
  if (value is Map) return value.values.any(_containsPlaintextMac);
  if (value is List) return value.any(_containsPlaintextMac);
  return value is String && RegExp(r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b').hasMatch(value);
}

bool _containsForbiddenKey(Object? value) {
  if (value is List) return value.any(_containsForbiddenKey);
  if (value is! Map) return false;
  for (final entry in value.entries) {
    if (RegExp(r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)', caseSensitive: false).hasMatch(entry.key.toString())) return true;
    if (_containsForbiddenKey(entry.value)) return true;
  }
  return false;
}

bool _containsCredentialText(String value) => RegExp(
  r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s,;}]+',
  caseSensitive: false,
).hasMatch(value);

bool _isTextEvidence(File file) => const {'json', 'log', 'txt', 'md', 'csv', 'yaml', 'yml'}.contains(file.path.toLowerCase().split('.').last) && file.lengthSync() <= 10 * 1024 * 1024;
File _resolveFile(Directory root, String path) => File(path).isAbsolute ? File(path) : File('${root.path}${Platform.pathSeparator}$path');
Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) => (value as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList(growable: false);
String _text(Object? value) => value?.toString().trim() ?? '';
bool _usableText(Object? value) => _text(value).isNotEmpty && !RegExp(r'(^|[^a-z])(REQUIRED_|TODO(?:_|$)|PLACEHOLDER(?:_|$))', caseSensitive: false).hasMatch(_text(value));
bool _sha40(Object? value) => RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(_text(value));
bool _sha256(Object? value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(_text(value));

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/acceptance/rc4_hf_ble_16_evidence_validator.dart <evidence.json>');
    exitCode = 64;
    return;
  }
  final evidenceFile = File(arguments.single).absolute;
  if (!evidenceFile.existsSync()) {
    stderr.writeln('BLE-16 evidence file does not exist: ${evidenceFile.path}');
    exitCode = 66;
    return;
  }
  final decoded = jsonDecode(await evidenceFile.readAsString());
  if (decoded is! Map) {
    stderr.writeln('BLE-16 evidence root must be an object.');
    exitCode = 65;
    return;
  }
  final result = validateRc4HfBle16Evidence(
    Map<String, dynamic>.from(decoded),
    evidenceRoot: evidenceFile.parent,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 2;
}
