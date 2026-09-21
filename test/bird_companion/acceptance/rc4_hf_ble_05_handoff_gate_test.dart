import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/rc4_hf_ble_03_evidence_validator.dart';
import '../../../tool/acceptance/rc4_hf_ble_05_handoff_gate.dart';

void main() {
  late Directory root;
  late Map<String, String> hashes;
  late Map<String, String> materialHashes;
  late Map<String, dynamic> manifest;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rc4-hf-ble-05-');
    hashes = <String, String>{};
    for (final variant in const ['A', 'B']) {
      final apk = File(
        '${root.path}${Platform.pathSeparator}scan-$variant.apk',
      )..writeAsBytesSync(utf8.encode('delivered-apk-$variant'));
      hashes[variant] = sha256.convert(apk.readAsBytesSync()).toString();
    }
    materialHashes = <String, String>{};
    for (final entry in const {
      'test_manual': 'manual.md',
      'evidence_template': 'template.json',
      'apk_verifier': 'verify.ps1',
      'return_instructions': 'return.md',
    }.entries) {
      final file = File('${root.path}${Platform.pathSeparator}${entry.value}')..writeAsStringSync('Safe handoff material: ${entry.value}');
      materialHashes[entry.key] = sha256.convert(file.readAsBytesSync()).toString();
    }
    manifest = _manifest(hashes, materialHashes);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('marks an intact package ready without claiming hardware validation', () {
    final result = _validate(
      root: root,
      manifest: manifest,
      hashes: hashes,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.handoffReady, isTrue);
    expect(result.returnedEvidenceVerified, isFalse);
    expect(result.toJson()['status'], 'handoff_ready');
    expect(result.toJson()['hardware_status'], 'pending');
    expect(result.toJson()['releasable'], isFalse);
  });

  test('verifies returned evidence only when it uses both delivered APKs', () {
    final returned = _returnedEvidence(hashes);
    final result = _validate(
      root: root,
      manifest: manifest,
      hashes: hashes,
      returnedEvidence: returned,
      returnedValidation: _passedBle03Validation,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.returnedEvidenceVerified, isTrue);
    expect(result.toJson()['status'], 'verified');
    expect(result.toJson()['hardware_status'], 'verified');
    expect(result.toJson()['next_gate'], 'RC4-HF-BLE-04');
    expect(result.toJson()['releasable'], isFalse);
  });

  test('rejects returned evidence from a different APK or source snapshot', () {
    final returned = _returnedEvidence(hashes);
    ((returned['builds'] as Map)['A'] as Map)['apk_sha256'] = 'f' * 64;
    ((returned['builds'] as Map)['B'] as Map)['git_commit'] = 'e' * 40;

    final result = _validate(
      root: root,
      manifest: manifest,
      hashes: hashes,
      returnedEvidence: returned,
      returnedValidation: _passedBle03Validation,
    );

    expect(result.passed, isFalse);
    expect(result.handoffReady, isTrue);
    expect(result.toJson()['returned_evidence_status'], 'blocked');
    expect(result.failures.join('\n'), contains('not the delivered'));
    expect(result.failures.join('\n'), contains('does not match the handoff'));
  });

  test('keeps hardware pending when returned BLE-03 evidence fails', () {
    final result = _validate(
      root: root,
      manifest: manifest,
      hashes: hashes,
      returnedEvidence: _returnedEvidence(hashes),
      returnedValidation: const Rc4HfBle03EvidenceValidation(
        errors: ['OPPO/Huawei/K7 matrix is incomplete.'],
        scanRunsByKey: {},
        pairingRunCount: 0,
      ),
    );

    expect(result.passed, isFalse);
    expect(result.handoffReady, isTrue);
    expect(result.toJson()['hardware_status'], 'pending');
    expect(
      result.failures.join('\n'),
      contains('Returned BLE-03 real-device evidence did not pass'),
    );
    expect(result.failures.join('\n'), contains('matrix is incomplete'));
  });

  test('rejects corrupt package, release claims, placeholders and missing files', () {
    final broken = _clone(manifest)
      ..['releasable'] = true
      ..['purpose'] = 'TODO_FILL_ME';
    ((broken['builds'] as Map)['A'] as Map)['package_id'] = 'deckers.thibault.aves.bird';
    (((broken['materials'] as Map)['test_manual'] as Map))['file'] = 'missing.md';
    File('${root.path}${Platform.pathSeparator}scan-A.apk').writeAsStringSync('corrupt');

    final result = _validate(
      root: root,
      manifest: broken,
      hashes: hashes,
    );

    expect(result.passed, isFalse);
    expect(result.handoffReady, isFalse);
    final failures = result.failures.join('\n');
    expect(failures, contains('non-releasable'));
    expect(failures, contains('placeholder'));
    expect(failures, contains('package_id'));
    expect(failures, contains('APK SHA-256'));
    expect(failures, contains('does not exist'));
  });

  test('checked-in external-lab package is intact and remains pending', () {
    final packageRoot = Directory('outputs/RC4-HF-BLE-05').absolute;
    final checkedInManifest =
        jsonDecode(
              File(
                '${packageRoot.path}${Platform.pathSeparator}handoff-manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final result = Rc4HfBle05HandoffGateValidator.validate(
      manifest: checkedInManifest,
      packageRoot: packageRoot,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.toJson()['status'], 'handoff_ready');
    expect(result.toJson()['hardware_status'], 'pending');
    expect(result.toJson()['releasable'], isFalse);
  });
}

const _passedBle03Validation = Rc4HfBle03EvidenceValidation(
  errors: [],
  scanRunsByKey: {},
  pairingRunCount: 5,
);

Rc4HfBle05HandoffGateResult _validate({
  required Directory root,
  required Map<String, dynamic> manifest,
  required Map<String, String> hashes,
  Map<String, dynamic>? returnedEvidence,
  Rc4HfBle03EvidenceValidation? returnedValidation,
}) => Rc4HfBle05HandoffGateValidator.validate(
  manifest: manifest,
  packageRoot: root,
  returnedEvidence: returnedEvidence,
  returnedValidation: returnedValidation,
  expectedBuildHashes: hashes,
);

Map<String, dynamic> _manifest(
  Map<String, String> hashes,
  Map<String, String> materialHashes,
) => {
  'schema_version': 1,
  'handoff_suite': 'rc4-hf-ble-05',
  'created_at': '2026-09-20T16:00:00+08:00',
  'purpose': 'external_real_hardware_acceptance',
  'hardware_status': 'pending',
  'releasable': false,
  'source': {
    'branch': 'thirdtime',
    'git_commit': 'a' * 40,
    'state': 'uncommitted_hotfix_snapshot',
    'version_name': '1.14.8',
    'version_code': 172,
  },
  'builds': {
    'A': {
      'apk_file': 'scan-A.apk',
      'apk_sha256': hashes['A'],
      'git_commit': 'a' * 40,
      'package_id': 'deckers.thibault.aves.bird.scan.a',
      'build_mode': 'debug',
      'scan_permission_policy': 'never_for_location',
    },
    'B': {
      'apk_file': 'scan-B.apk',
      'apk_sha256': hashes['B'],
      'git_commit': 'a' * 40,
      'package_id': 'deckers.thibault.aves.bird.scan.b',
      'build_mode': 'debug',
      'scan_permission_policy': 'full_scan',
    },
  },
  'materials': {
    'test_manual': {
      'file': 'manual.md',
      'sha256': materialHashes['test_manual'],
    },
    'evidence_template': {
      'file': 'template.json',
      'sha256': materialHashes['evidence_template'],
    },
    'apk_verifier': {
      'file': 'verify.ps1',
      'sha256': materialHashes['apk_verifier'],
    },
    'return_instructions': {
      'file': 'return.md',
      'sha256': materialHashes['return_instructions'],
    },
  },
  'required_matrix': {
    'huawei_ab_baseline_runs_per_variant': 10,
    'huawei_selected_variant_runs_per_recovery_scenario': 10,
    'oppo_selected_variant_baseline_runs': 10,
    'oppo_first_pairing_runs': 5,
    'physical_k7_required': true,
    'recovery_scenarios': [
      'baseline',
      'bluetooth_toggled',
      'permission_regranted',
      'foreground_resumed',
    ],
  },
};

Map<String, dynamic> _returnedEvidence(Map<String, String> hashes) => {
  'selected_scan_variant': 'B',
  'builds': {
    'A': {'apk_sha256': hashes['A'], 'git_commit': 'a' * 40},
    'B': {'apk_sha256': hashes['B'], 'git_commit': 'a' * 40},
  },
};

Map<String, dynamic> _clone(Map<String, dynamic> value) => jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
