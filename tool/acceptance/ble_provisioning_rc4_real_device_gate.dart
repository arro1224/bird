import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const bleRc4RequiredCases = <String>{
  'K7-01',
  'K7-02',
  'K7-03',
  'K7-04',
  'K7-05',
  'K7-06',
  'K7-07',
  'K7-08',
  'K7-09',
  'K7-10',
};
const _routerCases = <String>{'K7-06', 'K7-07', 'K7-08', 'K7-09', 'K7-10'};
const _approvalRoles = <String>{'protocol', 'qa_release'};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final root = Directory.current.absolute;
  final failures = <String>[];
  final baseline = _readJson(_resolveFile(root, options.baselinePath), 'baseline', failures);
  final evidence = _readJson(_resolveFile(root, options.evidencePath), 'evidence', failures);
  final gitSha = await _git(root, const ['rev-parse', 'HEAD'], failures);
  final gitStatus = await _git(root, const ['status', '--porcelain'], failures);
  final result = BleProvisioningRc4RealDeviceGateValidator.validate(
    baseline: baseline,
    evidence: evidence,
    repositoryRoot: root,
    apkFile: _resolveFile(root, options.apkPath),
    currentGitSha: gitSha.trim(),
    worktreeDirty: gitStatus.trim().isNotEmpty,
    approvedCertificateSha256: options.approvedCertificateSha256,
    initialFailures: failures,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 2;
}

final class BleProvisioningRc4RealDeviceGateValidator {
  const BleProvisioningRc4RealDeviceGateValidator._();

  static BleProvisioningRc4RealDeviceGateResult validate({
    required Map<String, dynamic> baseline,
    required Map<String, dynamic> evidence,
    required Directory repositoryRoot,
    required File apkFile,
    required String currentGitSha,
    required bool worktreeDirty,
    required String approvedCertificateSha256,
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
    require(
      _sha40(baselineBox['firmware_sha']) || _sha256(baselineBox['firmware_sha']),
      'frozen baseline box.firmware_sha must be a full source or artifact SHA',
    );

    require(evidence['schema_version'] == 1, 'evidence.schema_version must be 1');
    require(
      evidence['acceptance_suite'] == 'ble-provisioning-rc4-real-device',
      'evidence.acceptance_suite must be ble-provisioning-rc4-real-device',
    );
    require(evidence['final_result'] == 'passed', 'evidence.final_result must be passed');
    require(evidence['releasable'] == true, 'evidence.releasable must be true');
    require(evidence['real_k7_status'] == 'verified', 'evidence.real_k7_status must be verified');
    require(DateTime.tryParse(_text(evidence['captured_at'])) != null, 'evidence.captured_at must be an ISO-8601 timestamp');
    for (final path in _findPlaceholders(evidence, r'$')) {
      failures.add('evidence contains an unresolved placeholder: $path');
    }
    for (final path in _findSensitiveFields(evidence, r'$')) {
      failures.add('evidence contains a forbidden sensitive field: $path');
    }
    _scanTextForSecrets(jsonEncode(evidence), 'evidence JSON', failures);

    require(!worktreeDirty, 'BLE rc4 release gate requires a clean Git worktree');
    final app = _map(evidence['app']);
    require(app['package_id'] == 'deckers.thibault.aves.bird', 'app.package_id must be the bird flavor package');
    require(app['build_mode'] == 'release', 'app.build_mode must be release');
    require(app['signed'] == true, 'app.signed must be true');
    require(app['signature_verified'] == true, 'app.signature_verified must be true');
    require(_sha40(app['git_sha']), 'app.git_sha must be a full Git SHA');
    require(app['git_sha'] == currentGitSha, 'app.git_sha does not match the checked-out revision');
    require(_sha256(app['apk_sha256']), 'app.apk_sha256 must be SHA-256');
    require(_sha256(app['certificate_sha256']), 'app.certificate_sha256 must be SHA-256');
    require(_sha256(approvedCertificateSha256), 'approved certificate SHA-256 is required');
    require(
      _text(app['certificate_sha256']).toLowerCase() == approvedCertificateSha256.toLowerCase(),
      'app.certificate_sha256 does not match the approved certificate',
    );
    require(apkFile.existsSync(), 'release APK does not exist: ${apkFile.path}');
    if (apkFile.existsSync()) {
      final actualApkSha = sha256.convert(apkFile.readAsBytesSync()).toString();
      require(app['apk_sha256'] == actualApkSha, 'app.apk_sha256 does not match the release APK');
      require(apkFile.path.toLowerCase().endsWith('app-bird-release.apk'), 'APK must be app-bird-release.apk');
    }

    final box = _map(evidence['box']);
    final deviceId = _text(box['device_id']).toLowerCase();
    final deviceModel = _text(box['device_model']).toLowerCase();
    require(deviceId.isNotEmpty, 'box.device_id is required');
    require(!deviceId.contains('mock') && !deviceId.contains('simulator'), 'mock/simulator box evidence is forbidden');
    require(deviceModel.isNotEmpty, 'box.device_model is required');
    require(!deviceModel.contains('mock') && !deviceModel.contains('模拟'), 'mock/simulator box model is forbidden');
    require(_usableText(box['hardware_serial']), 'box.hardware_serial is required');
    require(box['api_version'] == 'v1', 'box.api_version must be v1');
    require(
      _sha40(box['firmware_sha']) || _sha256(box['firmware_sha']),
      'box.firmware_sha must be a full source or artifact SHA',
    );
    require(box['firmware_sha'] == baselineBox['firmware_sha'], 'box.firmware_sha does not match the frozen baseline');

    final environment = _map(evidence['environment']);
    require(environment['real_hardware'] == true, 'environment.real_hardware must be true');
    require(_usableText(environment['operator']), 'environment.operator is required');
    require(_usableText(environment['location']), 'environment.location is required');
    final devices = _maps(environment['android_devices']);
    final deviceIds = <String>{};
    require(devices.isNotEmpty, 'environment.android_devices must not be empty');
    for (final device in devices) {
      final id = _text(device['id']);
      final serial = _text(device['serial']).toLowerCase();
      final model = _text(device['model']).toLowerCase();
      require(id.isNotEmpty && deviceIds.add(id), 'Android device ids must be non-empty and unique');
      require(device['physical'] == true, 'Android device $id must set physical=true');
      require(serial.isNotEmpty, 'Android device $id serial is required');
      require(!serial.startsWith('emulator-') && !serial.contains('simulator'), 'Android emulator evidence is forbidden: $id');
      require(_usableText(device['manufacturer']), 'Android device $id manufacturer is required');
      require(
        model.isNotEmpty && !model.contains('sdk_gphone') && !model.contains('generic'),
        'Android device $id model must identify physical hardware',
      );
      require(_usableText(device['os_version']), 'Android device $id os_version is required');
    }
    final routers = _maps(environment['routers']);
    final routerIds = <String>{};
    require(routers.isNotEmpty, 'environment.routers must not be empty');
    for (final router in routers) {
      final id = _text(router['id']);
      require(id.isNotEmpty && routerIds.add(id), 'router ids must be non-empty and unique');
      for (final field in const ['model', 'firmware', 'band', 'security']) {
        require(_usableText(router[field]), 'router $id $field is required');
      }
    }

    final evidenceReferences = <String>{};
    final cases = _maps(evidence['cases']);
    require(cases.length == bleRc4RequiredCases.length, 'evidence must contain exactly ten K7 cases');
    for (final id in bleRc4RequiredCases) {
      final matching = cases.where((item) => item['id'] == id).toList();
      require(matching.length == 1, 'required case must appear exactly once: $id');
      if (matching.length != 1) continue;
      final item = matching.single;
      require(item['status'] == 'passed', 'required case is not passed: $id');
      require(_usableText(item['summary']), 'required case has no redacted summary: $id');
      final caseDevices = _strings(item['device_ids']);
      require(caseDevices.isNotEmpty, 'required case has no Android device reference: $id');
      for (final reference in caseDevices) {
        require(deviceIds.contains(reference), 'unknown Android device reference for $id: $reference');
      }
      final caseRouters = _strings(item['router_ids']);
      if (_routerCases.contains(id)) {
        require(caseRouters.isNotEmpty, 'required case has no router reference: $id');
      }
      for (final reference in caseRouters) {
        require(routerIds.contains(reference), 'unknown router reference for $id: $reference');
      }
      final references = _strings(item['evidence']);
      require(references.isNotEmpty, 'required case has no evidence files: $id');
      evidenceReferences.addAll(references);
    }

    require(_usableText(evidence['evidence_summary']), 'evidence.evidence_summary is required');
    final redaction = _map(evidence['redaction']);
    require(redaction['reviewed'] == true, 'redaction.reviewed must be true');
    require(_usableText(redaction['reviewer']), 'redaction.reviewer is required');
    require(_usableText(redaction['statement']), 'redaction.statement is required');
    final redactionReport = _text(redaction['report']);
    require(redactionReport.isNotEmpty, 'redaction.report is required');
    if (redactionReport.isNotEmpty) evidenceReferences.add(redactionReport);

    final approvals = _map(evidence['approvals']);
    for (final role in _approvalRoles) {
      final approval = _map(approvals[role]);
      require(approval['status'] == 'approved', 'approval is missing for $role');
      final reference = _text(approval['evidence']);
      require(reference.isNotEmpty, 'approval evidence is missing for $role');
      if (reference.isNotEmpty) evidenceReferences.add(reference);
    }

    for (final reference in evidenceReferences) {
      final file = _resolveFile(repositoryRoot, reference);
      require(file.existsSync(), 'evidence file does not exist: $reference');
      if (file.existsSync() && _isTextEvidence(file)) {
        try {
          _scanTextForSecrets(file.readAsStringSync(), reference, failures);
        } on FileSystemException {
          failures.add('text evidence cannot be read safely: $reference');
        }
      }
    }

    return BleProvisioningRc4RealDeviceGateResult(
      passed: failures.isEmpty,
      failures: List.unmodifiable(failures),
      requiredCaseCount: bleRc4RequiredCases.length,
      verifiedCaseCount: failures.isEmpty ? bleRc4RequiredCases.length : 0,
    );
  }
}

final class BleProvisioningRc4RealDeviceGateResult {
  const BleProvisioningRc4RealDeviceGateResult({
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
    'gate': 'BLE-RC4-K7',
    'status': passed ? 'passed' : 'blocked',
    'releasable': passed,
    'real_k7_status': passed ? 'verified' : 'pending',
    'required_cases': requiredCaseCount,
    'verified_cases': verifiedCaseCount,
    'failure_count': failures.length,
    'failures': failures,
  };
}

final class _Options {
  const _Options({
    required this.evidencePath,
    required this.baselinePath,
    required this.apkPath,
    required this.approvedCertificateSha256,
  });

  final String evidencePath;
  final String baselinePath;
  final String apkPath;
  final String approvedCertificateSha256;

  factory _Options.parse(List<String> arguments) {
    String value(String name, String fallback) {
      final prefix = '--$name=';
      return arguments.where((item) => item.startsWith(prefix)).map((item) => item.substring(prefix.length).trim()).firstOrNull ?? fallback;
    }

    return _Options(
      evidencePath: value('evidence', 'docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json'),
      baselinePath: value('baseline', 'docs/contracts/birdbox-v1-baseline.json'),
      apkPath: value('apk', 'build/app/outputs/flutter-apk/app-bird-release.apk'),
      approvedCertificateSha256: value('approved-certificate', ''),
    );
  }
}

Map<String, dynamic> _readJson(File file, String label, List<String> failures) {
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

Future<String> _git(Directory root, List<String> arguments, List<String> failures) async {
  final result = await Process.run('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) {
    failures.add('git ${arguments.join(' ')} failed');
    return '';
  }
  return result.stdout.toString();
}

File _resolveFile(Directory root, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${root.path}${Platform.pathSeparator}$path');
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) => (value as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();
List<String> _strings(Object? value) => (value as List? ?? const []).map(_text).where((item) => item.isNotEmpty).toList();
String _text(Object? value) => value?.toString().trim() ?? '';
bool _usableText(Object? value) => _text(value).isNotEmpty && !_text(value).toUpperCase().contains('REQUIRED');
bool _sha40(Object? value) => RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(_text(value));
bool _sha256(Object? value) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(_text(value));

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

Iterable<String> _findSensitiveFields(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final childPath = '$path.$key';
      if (RegExp(r'(password|passphrase|secret|pairing[_-]?(code|session)|access[_-]?token|refresh[_-]?token)', caseSensitive: false).hasMatch(key) && _text(entry.value).isNotEmpty) {
        yield childPath;
      }
      yield* _findSensitiveFields(entry.value, childPath);
    }
  } else if (value is List) {
    for (final entry in value.indexed) {
      yield* _findSensitiveFields(entry.$2, '$path[${entry.$1}]');
    }
  }
}

bool _isTextEvidence(File file) {
  final extension = file.path.toLowerCase().split('.').last;
  return const {'json', 'log', 'txt', 'md', 'csv', 'yaml', 'yml'}.contains(extension) && file.lengthSync() <= 10 * 1024 * 1024;
}

void _scanTextForSecrets(String content, String label, List<String> failures) {
  if (RegExp(r'DPP:[^\s\r\n]*;;', caseSensitive: false).hasMatch(content)) {
    failures.add('$label contains a complete DPP URI');
  }
  if (RegExp(r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b').hasMatch(content)) {
    failures.add('$label contains a complete MAC address');
  }
  if (RegExp(r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s,;}]+', caseSensitive: false).hasMatch(content)) {
    failures.add('$label contains credential-like material');
  }
}
