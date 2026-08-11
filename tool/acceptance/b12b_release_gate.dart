import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const b12bRequiredCases = <String>{
  'connect_mdns',
  'connect_qr',
  'connect_manual',
  'pair_session_restore_revocation',
  'device_status',
  'sd_detected',
  'sd_missing',
  'sd_unreadable',
  'sd_empty',
  'sd_reinsert_rescan',
  'scan_project_import_analysis',
  'job_resume_after_app_kill',
  'network_disconnect_reconnect',
  'ws_rest_convergence',
  'device_switch',
  'gallery_review',
  'egret_cross_page_search',
  'other_species_search',
  'combined_filter',
  'filter_cancel_partial_cache',
  'offline_replay_conflict',
  'copy_target_online',
  'copy_target_offline',
  'copy_target_insufficient_space',
  'copy_interrupted_resume',
  'copy_failures_report_logs',
  'battery_low',
  'external_power',
  'over_temperature',
  'layout_360_1_5x',
  'layout_426_1_3x',
  'signed_install',
  'rollback',
};

const _requiredBaselineBoxFields = <String>{
  'repository',
  'branch',
  'firmware_sha',
  'deployment_command',
  'database_schema_version',
  'database_migration',
  'database_rollback',
  'integration_base_url',
};

const _requiredApprovalRoles = <String>{
  'protocol',
  'flutter_core',
  'box_api',
  'qa_release',
};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final repoRoot = Directory.current.absolute;
  final evidenceFile = _resolveFile(repoRoot, options.evidencePath);
  final baselineFile = _resolveFile(repoRoot, options.baselinePath);
  final apkFile = _resolveFile(repoRoot, options.apkPath);
  final failures = <String>[];

  Map<String, dynamic> readJson(File file, String label) {
    if (!file.existsSync()) {
      failures.add('$label does not exist: ${file.path}');
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      failures.add('$label must contain a JSON object');
    } on FormatException catch (error) {
      failures.add('$label is invalid JSON: ${error.message}');
    }
    return <String, dynamic>{};
  }

  final baseline = readJson(baselineFile, 'baseline');
  final evidence = readJson(evidenceFile, 'evidence');
  final gitSha = await _git(repoRoot, const ['rev-parse', 'HEAD']);
  final dirty = (await _git(repoRoot, const ['status', '--porcelain'])).trim().isNotEmpty;
  final result = B12BReleaseGateValidator.validate(
    baseline: baseline,
    evidence: evidence,
    repoRoot: repoRoot,
    apkFile: apkFile,
    currentGitSha: gitSha.trim(),
    worktreeDirty: dirty,
    initialFailures: failures,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 2;
}

class B12BReleaseGateValidator {
  const B12BReleaseGateValidator._();

  static B12BReleaseGateResult validate({
    required Map<String, dynamic> baseline,
    required Map<String, dynamic> evidence,
    required Directory repoRoot,
    required File apkFile,
    required String currentGitSha,
    required bool worktreeDirty,
    Iterable<String> initialFailures = const [],
  }) {
    final failures = <String>[...initialFailures];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(baseline['status'] == 'ready', 'frozen baseline status must be ready');
    final unresolved = baseline['unresolved_external_inputs'];
    require(unresolved is List && unresolved.isEmpty, 'frozen baseline still has unresolved external inputs');
    final baselineBox = _map(baseline['box']);
    for (final field in _requiredBaselineBoxFields) {
      require(_usableText(baselineBox[field]), 'frozen baseline is missing box.$field');
    }
    final baselineOwners = _map(baseline['owners']);
    for (final role in _requiredApprovalRoles) {
      final owner = _map(baselineOwners[role]);
      require(_usableText(owner['contact']), 'frozen baseline is missing owners.$role.contact');
    }

    require(evidence['schema_version'] == 1, 'evidence.schema_version must be 1');
    require(evidence['final_result'] == 'passed', 'evidence.final_result must be passed');
    require(_validDate(evidence['captured_at']), 'evidence.captured_at must be an ISO-8601 timestamp');
    _findSensitiveValues(evidence, r'$').forEach(
      (path) => failures.add('evidence contains a forbidden sensitive field: $path'),
    );
    _findPlaceholders(evidence, r'$').forEach(
      (path) => failures.add('evidence contains an unresolved placeholder: $path'),
    );

    require(!worktreeDirty, 'release gate requires a clean Git worktree');
    final app = _map(evidence['app']);
    require(app['build_mode'] == 'release', 'app.build_mode must be release');
    require(app['signed'] == true, 'app.signed must be true');
    require(app['signature_verified'] == true, 'app.signature_verified must be true');
    require(_sha40(app['git_sha']), 'app.git_sha must be a full Git SHA');
    require(app['git_sha'] == currentGitSha, 'app.git_sha does not match the checked-out revision');
    require(_sha256(app['apk_sha256']), 'app.apk_sha256 must be SHA-256');
    require(_sha256(app['certificate_sha256']), 'app.certificate_sha256 must be SHA-256');
    require(app['package_id'] == 'deckers.thibault.aves.bird', 'app.package_id must be the bird flavor package');
    require(apkFile.existsSync(), 'release APK does not exist: ${apkFile.path}');
    if (apkFile.existsSync()) {
      final actualHash = sha256.convert(apkFile.readAsBytesSync()).toString();
      require(app['apk_sha256'] == actualHash, 'app.apk_sha256 does not match the release APK');
      require(apkFile.path.toLowerCase().endsWith('app-bird-release.apk'), 'APK must be app-bird-release.apk');
    }

    final environment = _map(evidence['environment']);
    require(environment['real_hardware'] == true, 'environment.real_hardware must be true');
    final androidSerial = _text(environment['android_device_serial']).toLowerCase();
    require(androidSerial.isNotEmpty, 'environment.android_device_serial is required');
    require(!androidSerial.startsWith('emulator-'), 'Android emulator evidence is not real-hardware evidence');

    final box = _map(evidence['box']);
    final deviceId = _text(box['device_id']).toLowerCase();
    final deviceModel = _text(box['device_model']).toLowerCase();
    require(deviceId.isNotEmpty, 'box.device_id is required');
    require(!deviceId.contains('mock') && !deviceId.contains('simulator'), 'mock/simulator box evidence is forbidden');
    require(deviceModel.isNotEmpty, 'box.device_model is required');
    require(!deviceModel.contains('mock') && !deviceModel.contains('模拟'), 'mock/simulator box model is forbidden');
    require(_usableText(box['hardware_serial']), 'box.hardware_serial is required');
    require(_sha40(box['firmware_sha']) || _sha256(box['firmware_sha']), 'box.firmware_sha must be a full source or artifact SHA');
    require(box['firmware_sha'] == baselineBox['firmware_sha'], 'box.firmware_sha does not match the frozen baseline');
    require(box['api_version'] == 'v1', 'box.api_version must be v1');
    require(box['database_schema_version'] == baselineBox['database_schema_version'], 'box.database_schema_version does not match the frozen baseline');
    final baseUri = Uri.tryParse(_text(box['base_url']));
    require(baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty, 'box.base_url must be an absolute URL');
    if (baseUri != null) {
      final host = baseUri.host.toLowerCase();
      require(
        host != '127.0.0.1' && host != '::1' && host != 'localhost' && host != '10.0.2.2',
        'loopback/emulator box URL is forbidden',
      );
    }

    final cases = (evidence['cases'] as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();
    for (final id in b12bRequiredCases) {
      final matching = cases.where((item) => item['id'] == id).toList();
      require(matching.length == 1, 'required case must appear exactly once: $id');
      if (matching.length != 1) continue;
      final item = matching.single;
      require(item['status'] == 'passed', 'required case is not passed: $id');
      final references = _strings(item['evidence']);
      require(references.isNotEmpty, 'required case has no evidence files: $id');
      for (final reference in references) {
        require(_resolveFile(repoRoot, reference).existsSync(), 'evidence file does not exist for $id: $reference');
      }
    }

    final metrics = _map(evidence['metrics']);
    require(_int(metrics['photo_count']) >= 3672, 'metrics.photo_count must be at least 3672');
    require(_int(metrics['egret_matches']) > 0, 'metrics.egret_matches must be positive');
    require(_int(metrics['other_species_matches']) > 0, 'metrics.other_species_matches must be positive');
    require(_int(metrics['first_feedback_ms']) > 0, 'metrics.first_feedback_ms must be positive');
    require(_int(metrics['complete_search_ms']) >= _int(metrics['first_feedback_ms']), 'metrics.complete_search_ms must include first feedback');
    require(_number(metrics['memory_peak_mb']) > 0, 'metrics.memory_peak_mb must be positive');
    require(metrics['cancel_verified'] == true, 'metrics.cancel_verified must be true');

    final rollback = _map(evidence['rollback']);
    require(_usableText(rollback['app_artifact']), 'rollback.app_artifact is required');
    require(_usableText(rollback['firmware_artifact']), 'rollback.firmware_artifact is required');
    require(_usableText(rollback['instructions']), 'rollback.instructions is required');
    for (final field in const ['app_artifact', 'firmware_artifact', 'instructions']) {
      final reference = _text(rollback[field]);
      if (reference.isNotEmpty) {
        require(_resolveFile(repoRoot, reference).existsSync(), 'rollback file does not exist: $reference');
      }
    }

    final approvals = _map(evidence['approvals']);
    for (final role in _requiredApprovalRoles) {
      final approval = _map(approvals[role]);
      require(approval['status'] == 'approved', 'approval is missing for $role');
      final reference = _text(approval['evidence']);
      require(reference.isNotEmpty, 'approval evidence is missing for $role');
      if (reference.isNotEmpty) {
        require(_resolveFile(repoRoot, reference).existsSync(), 'approval evidence file does not exist for $role: $reference');
      }
    }

    return B12BReleaseGateResult(
      passed: failures.isEmpty,
      failures: List.unmodifiable(failures),
      requiredCaseCount: b12bRequiredCases.length,
      verifiedCaseCount: failures.isEmpty ? b12bRequiredCases.length : 0,
    );
  }
}

class B12BReleaseGateResult {
  const B12BReleaseGateResult({
    required this.passed,
    required this.failures,
    required this.requiredCaseCount,
    required this.verifiedCaseCount,
  });

  final bool passed;
  final List<String> failures;
  final int requiredCaseCount;
  final int verifiedCaseCount;

  Map<String, Object> toJson() => {
    'gate': 'B12-B',
    'status': passed ? 'passed' : 'blocked',
    'required_cases': requiredCaseCount,
    'verified_cases': verifiedCaseCount,
    'failure_count': failures.length,
    'failures': failures,
  };
}

class _Options {
  const _Options({
    required this.evidencePath,
    required this.baselinePath,
    required this.apkPath,
  });

  final String evidencePath;
  final String baselinePath;
  final String apkPath;

  factory _Options.parse(List<String> arguments) {
    String value(String name, String fallback) {
      final prefix = '--$name=';
      return arguments.where((item) => item.startsWith(prefix)).map((item) => item.substring(prefix.length).trim()).firstOrNull ?? fallback;
    }

    return _Options(
      evidencePath: value('evidence', 'docs/acceptance/b12b-real-hardware-evidence.template.json'),
      baselinePath: value('baseline', 'docs/contracts/birdbox-v1-baseline.json'),
      apkPath: value('apk', 'build/app/outputs/flutter-apk/app-bird-release.apk'),
    );
  }
}

Future<String> _git(Directory repoRoot, List<String> arguments) async {
  final result = await Process.run('git', arguments, workingDirectory: repoRoot.path);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout.toString();
}

File _resolveFile(Directory root, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${root.path}${Platform.pathSeparator}$path');
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<String> _strings(Object? value) => (value as List? ?? const []).map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
String _text(Object? value) => value?.toString().trim() ?? '';
int _int(Object? value) => value is num ? value.toInt() : -1;
double _number(Object? value) => value is num ? value.toDouble() : -1;
bool _usableText(Object? value) => _text(value).isNotEmpty && !_text(value).toUpperCase().contains('REQUIRED');
bool _sha40(Object? value) => RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(_text(value));
bool _sha256(Object? value) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(_text(value));
bool _validDate(Object? value) => DateTime.tryParse(_text(value)) != null;

Iterable<String> _findSensitiveValues(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final childPath = '$path.$key';
      if (RegExp(r'(token|password|secret|pairing[_-]?code)', caseSensitive: false).hasMatch(key) && _text(entry.value).isNotEmpty) {
        yield childPath;
      }
      yield* _findSensitiveValues(entry.value, childPath);
    }
  } else if (value is List) {
    for (final entry in value.indexed) {
      yield* _findSensitiveValues(entry.$2, '$path[${entry.$1}]');
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
  } else if (value is String && RegExp(r'(REQUIRED|TODO|PLACEHOLDER)', caseSensitive: false).hasMatch(value)) {
    yield path;
  }
}
