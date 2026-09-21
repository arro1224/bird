import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rc4_hf_ble_03_evidence_validator.dart';

const rc4HfBle05VariantAHash = '2954ea9d4720b22b29b288c3a37eef17a13ff2c75e2ab1213e19664920be5108';
const rc4HfBle05VariantBHash = '12e0e4f1af0e7421d508908fab24cb60fc6e9347fe81db57c55d2ff8b4116ae8';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final repositoryRoot = Directory.current.absolute;
  final initialPackageFailures = <String>[];
  final manifestFile = _resolveFile(repositoryRoot, options.manifestPath);
  final manifest = _readJson(
    manifestFile,
    'BLE-05 handoff manifest',
    initialPackageFailures,
  );

  Map<String, dynamic>? returnedEvidence;
  Rc4HfBle03EvidenceValidation? returnedValidation;
  if (options.returnedEvidencePath.isNotEmpty) {
    final returnedFile = _resolveFile(
      repositoryRoot,
      options.returnedEvidencePath,
    );
    final returnedReadFailures = <String>[];
    returnedEvidence = _readJson(
      returnedFile,
      'returned BLE-03 evidence',
      returnedReadFailures,
    );
    returnedValidation = validateRc4HfBle03Evidence(
      returnedEvidence,
      evidenceRoot: returnedFile.parent,
    );
    if (returnedReadFailures.isNotEmpty) {
      returnedValidation = Rc4HfBle03EvidenceValidation(
        errors: [
          ...returnedReadFailures,
          ...returnedValidation.errors,
        ],
        scanRunsByKey: returnedValidation.scanRunsByKey,
        pairingRunCount: returnedValidation.pairingRunCount,
      );
    }
  }

  final result = Rc4HfBle05HandoffGateValidator.validate(
    manifest: manifest,
    packageRoot: manifestFile.parent,
    returnedEvidence: returnedEvidence,
    returnedValidation: returnedValidation,
    initialPackageFailures: initialPackageFailures,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 2;
}

final class Rc4HfBle05HandoffGateValidator {
  const Rc4HfBle05HandoffGateValidator._();

  static Rc4HfBle05HandoffGateResult validate({
    required Map<String, dynamic> manifest,
    required Directory packageRoot,
    Map<String, dynamic>? returnedEvidence,
    Rc4HfBle03EvidenceValidation? returnedValidation,
    Map<String, String> expectedBuildHashes = const {
      'A': rc4HfBle05VariantAHash,
      'B': rc4HfBle05VariantBHash,
    },
    Iterable<String> initialPackageFailures = const [],
  }) {
    final packageFailures = <String>[...initialPackageFailures];
    final returnFailures = <String>[];
    void requirePackage(bool condition, String message) {
      if (!condition) packageFailures.add(message);
    }

    void requireReturn(bool condition, String message) {
      if (!condition) returnFailures.add(message);
    }

    requirePackage(manifest['schema_version'] == 1, 'schema_version must be 1.');
    requirePackage(
      manifest['handoff_suite'] == 'rc4-hf-ble-05',
      'handoff_suite must be rc4-hf-ble-05.',
    );
    requirePackage(
      DateTime.tryParse(_text(manifest['created_at'])) != null,
      'created_at must be an ISO-8601 timestamp.',
    );
    requirePackage(
      manifest['purpose'] == 'external_real_hardware_acceptance',
      'purpose must be external_real_hardware_acceptance.',
    );
    requirePackage(
      manifest['hardware_status'] == 'pending',
      'handoff manifest hardware_status must remain pending.',
    );
    requirePackage(
      manifest['releasable'] == false,
      'handoff manifest must remain non-releasable.',
    );
    for (final path in _findPlaceholders(manifest, r'$')) {
      packageFailures.add('Handoff manifest contains a placeholder: $path.');
    }
    _scanTextForSecrets(
      jsonEncode(manifest),
      'handoff manifest',
      packageFailures,
    );

    final source = _map(manifest['source']);
    final deliveredGitCommit = _text(source['git_commit']).toLowerCase();
    requirePackage(
      _isSha40(deliveredGitCommit),
      'source.git_commit must be a full Git SHA.',
    );
    requirePackage(
      source['state'] == 'uncommitted_hotfix_snapshot',
      'source.state must disclose uncommitted_hotfix_snapshot.',
    );
    requirePackage(
      source['version_name'] == '1.14.8' && source['version_code'] == 172,
      'source version must be 1.14.8 (172).',
    );

    final builds = _map(manifest['builds']);
    final deliveredHashes = <String, String>{};
    for (final variant in const ['A', 'B']) {
      final build = _map(builds[variant]);
      final expectedHash = expectedBuildHashes[variant] ?? '';
      final expectedPolicy = variant == 'A' ? 'never_for_location' : 'full_scan';
      final expectedPackage = 'deckers.thibault.aves.bird.scan.${variant.toLowerCase()}';
      final hash = _text(build['apk_sha256']).toLowerCase();
      deliveredHashes[variant] = hash;
      requirePackage(
        build['package_id'] == expectedPackage,
        'builds.$variant.package_id must be $expectedPackage.',
      );
      requirePackage(
        build['build_mode'] == 'debug',
        'builds.$variant.build_mode must be debug.',
      );
      requirePackage(
        build['scan_permission_policy'] == expectedPolicy,
        'builds.$variant.scan_permission_policy must be $expectedPolicy.',
      );
      requirePackage(
        hash == expectedHash,
        'builds.$variant.apk_sha256 does not match the delivered BLE-03 artifact.',
      );
      requirePackage(
        _text(build['git_commit']).toLowerCase() == deliveredGitCommit,
        'builds.$variant.git_commit must match source.git_commit.',
      );
      final apk = _resolveFile(packageRoot, _text(build['apk_file']));
      requirePackage(
        apk.existsSync(),
        'builds.$variant APK does not exist: ${build['apk_file']}',
      );
      if (apk.existsSync()) {
        final actual = sha256.convert(apk.readAsBytesSync()).toString();
        requirePackage(
          actual == hash,
          'builds.$variant APK SHA-256 does not match the manifest.',
        );
      }
    }
    requirePackage(
      deliveredHashes['A'] != deliveredHashes['B'],
      'A and B APK hashes must be different.',
    );

    final materials = _map(manifest['materials']);
    for (final field in const [
      'test_manual',
      'evidence_template',
      'apk_verifier',
      'return_instructions',
    ]) {
      final material = _map(materials[field]);
      final reference = _text(material['file']);
      final expectedSha = _text(material['sha256']).toLowerCase();
      requirePackage(reference.isNotEmpty, 'materials.$field.file is required.');
      requirePackage(
        _isSha256(expectedSha),
        'materials.$field.sha256 must be SHA-256.',
      );
      if (reference.isEmpty) continue;
      final file = _resolveFile(packageRoot, reference);
      requirePackage(file.existsSync(), 'materials.$field.file does not exist.');
      if (file.existsSync()) {
        requirePackage(file.lengthSync() > 0, 'materials.$field.file is empty.');
        final actualSha = sha256.convert(file.readAsBytesSync()).toString();
        requirePackage(
          actualSha == expectedSha,
          'materials.$field SHA-256 does not match the manifest.',
        );
      }
    }

    final matrix = _map(manifest['required_matrix']);
    requirePackage(
      matrix['huawei_ab_baseline_runs_per_variant'] == 10,
      'required_matrix must require 10 Huawei A/B baseline runs per variant.',
    );
    requirePackage(
      matrix['huawei_selected_variant_runs_per_recovery_scenario'] == 10,
      'required_matrix must require 10 Huawei runs per recovery scenario.',
    );
    requirePackage(
      matrix['oppo_selected_variant_baseline_runs'] == 10,
      'required_matrix must require 10 OPPO selected-variant scans.',
    );
    requirePackage(
      matrix['oppo_first_pairing_runs'] == 5,
      'required_matrix must require five OPPO first-pairing runs.',
    );
    requirePackage(
      matrix['physical_k7_required'] == true,
      'required_matrix must require a physical K7.',
    );
    final scenarios = _strings(matrix['recovery_scenarios']).toSet();
    requirePackage(
      scenarios.length == rc4HfBleScanScenarios.length && scenarios.containsAll(rc4HfBleScanScenarios),
      'required_matrix.recovery_scenarios is incomplete.',
    );

    final returnedEvidenceSupplied = returnedEvidence != null;
    if (returnedEvidenceSupplied) {
      requireReturn(
        returnedValidation != null,
        'Returned BLE-03 validation result is required.',
      );
      if (returnedValidation != null && !returnedValidation.passed) {
        returnFailures.add(
          'Returned BLE-03 real-device evidence did not pass validation.',
        );
        for (final error in returnedValidation.errors) {
          returnFailures.add('BLE-03: $error');
        }
      }
      final returnedBuilds = _map(returnedEvidence['builds']);
      for (final variant in const ['A', 'B']) {
        final returnedBuild = _map(returnedBuilds[variant]);
        requireReturn(
          _text(returnedBuild['apk_sha256']).toLowerCase() == deliveredHashes[variant],
          'Returned builds.$variant APK is not the delivered BLE-05 artifact.',
        );
        requireReturn(
          _text(returnedBuild['git_commit']).toLowerCase() == deliveredGitCommit,
          'Returned builds.$variant Git commit does not match the handoff.',
        );
      }
      requireReturn(
        const {'A', 'B'}.contains(
          _text(returnedEvidence['selected_scan_variant']),
        ),
        'Returned evidence must select variant A or B.',
      );
    }

    return Rc4HfBle05HandoffGateResult(
      packageFailures: List.unmodifiable(packageFailures),
      returnFailures: List.unmodifiable(returnFailures),
      returnedEvidenceSupplied: returnedEvidenceSupplied,
    );
  }
}

final class Rc4HfBle05HandoffGateResult {
  const Rc4HfBle05HandoffGateResult({
    required this.packageFailures,
    required this.returnFailures,
    required this.returnedEvidenceSupplied,
  });

  final List<String> packageFailures;
  final List<String> returnFailures;
  final bool returnedEvidenceSupplied;

  bool get handoffReady => packageFailures.isEmpty;
  bool get returnedEvidenceVerified => returnedEvidenceSupplied && handoffReady && returnFailures.isEmpty;
  bool get passed => handoffReady && (!returnedEvidenceSupplied || returnFailures.isEmpty);

  List<String> get failures => [...packageFailures, ...returnFailures];

  Map<String, Object?> toJson() => {
    'gate': 'RC4-HF-BLE-05',
    'status': !handoffReady
        ? 'blocked'
        : returnedEvidenceVerified
        ? 'verified'
        : returnedEvidenceSupplied
        ? 'blocked'
        : 'handoff_ready',
    'handoff_ready': handoffReady,
    'returned_evidence_status': !returnedEvidenceSupplied
        ? 'pending'
        : returnedEvidenceVerified
        ? 'verified'
        : 'blocked',
    'hardware_status': returnedEvidenceVerified ? 'verified' : 'pending',
    'releasable': false,
    'next_gate': returnedEvidenceVerified ? 'RC4-HF-BLE-04' : 'RC4-HF-BLE-03',
    'failure_count': failures.length,
    'failures': failures,
  };
}

final class _Options {
  const _Options({
    required this.manifestPath,
    required this.returnedEvidencePath,
  });

  final String manifestPath;
  final String returnedEvidencePath;

  factory _Options.parse(List<String> arguments) {
    String value(String name, String fallback) {
      final prefix = '--$name=';
      for (final argument in arguments) {
        if (argument.startsWith(prefix)) {
          return argument.substring(prefix.length).trim();
        }
      }
      return fallback;
    }

    return _Options(
      manifestPath: value(
        'manifest',
        'outputs/RC4-HF-BLE-05/handoff-manifest.json',
      ),
      returnedEvidencePath: value('returned-evidence', ''),
    );
  }
}

Map<String, dynamic> _readJson(
  File file,
  String label,
  List<String> failures,
) {
  if (!file.existsSync()) {
    failures.add('$label does not exist: ${file.path}');
    return <String, dynamic>{};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    failures.add('$label must contain a JSON object.');
  } on FormatException catch (error) {
    failures.add('$label is invalid JSON: ${error.message}');
  }
  return <String, dynamic>{};
}

File _resolveFile(Directory root, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${root.path}${Platform.pathSeparator}$path');
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<String> _strings(Object? value) => (value as List? ?? const []).map(_text).where((item) => item.isNotEmpty).toList();
String _text(Object? value) => value?.toString().trim() ?? '';
bool _isSha40(Object? value) => RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(_text(value));
bool _isSha256(Object? value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(_text(value));

Iterable<String> _findPlaceholders(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _findPlaceholders(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (final entry in value.indexed) {
      yield* _findPlaceholders(entry.$2, '$path[${entry.$1}]');
    }
  } else if (value is String &&
      RegExp(
        r'(^|[^a-z])(REQUIRED_|TODO(?:_|$)|PLACEHOLDER(?:_|$))',
        caseSensitive: false,
      ).hasMatch(value)) {
    yield path;
  }
}

void _scanTextForSecrets(
  String content,
  String label,
  List<String> failures,
) {
  if (RegExp(r'DPP:[^\s\r\n]*;;', caseSensitive: false).hasMatch(content)) {
    failures.add('$label contains a complete DPP URI.');
  }
  if (RegExp(r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b').hasMatch(content)) {
    failures.add('$label contains a complete MAC address.');
  }
  if (RegExp(
    r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s,;}]+',
    caseSensitive: false,
  ).hasMatch(content)) {
    failures.add('$label contains credential-like material.');
  }
}
