import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/b12b_release_gate.dart';

void main() {
  late Directory root;
  late File releaseApk;
  late String apkSha;

  setUp(() {
    root = Directory.systemTemp.createTempSync('b12b-gate-');
    File('${root.path}/evidence.log').writeAsStringSync('redacted evidence');
    File('${root.path}/previous.apk').writeAsBytesSync([1, 2, 3]);
    File('${root.path}/previous.firmware').writeAsBytesSync([4, 5, 6]);
    File('${root.path}/rollback.md').writeAsStringSync('rollback steps');
    File('${root.path}/approval.txt').writeAsStringSync('approved');
    releaseApk = File('${root.path}/app-bird-release.apk')..writeAsBytesSync([7, 8, 9]);
    apkSha = sha256.convert(releaseApk.readAsBytesSync()).toString();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('complete real-hardware evidence can pass the B12-B validator', () {
    final result = B12BReleaseGateValidator.validate(
      baseline: _baseline,
      evidence: _evidence(apkSha),
      repoRoot: root,
      apkFile: releaseApk,
      currentGitSha: _appSha,
      worktreeDirty: false,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.requiredCaseCount, b12bRequiredCases.length);
    expect(result.verifiedCaseCount, b12bRequiredCases.length);
  });

  test('simulator, debug, dirty and unsigned evidence is fail-closed', () {
    final evidence = _evidence(apkSha);
    evidence['environment'] = {
      'real_hardware': false,
      'android_device_serial': 'emulator-5554',
    };
    evidence['box'] = {
      ...Map<String, dynamic>.from(evidence['box']! as Map),
      'device_id': 'mock-k7-001',
      'device_model': 'K7 模拟盒子',
      'base_url': 'http://10.0.2.2:8787',
    };
    evidence['app'] = {
      ...Map<String, dynamic>.from(evidence['app']! as Map),
      'build_mode': 'debug',
      'signed': false,
      'signature_verified': false,
    };
    final debugApk = File('${root.path}/app-bird-debug.apk')..writeAsBytesSync([7, 8, 9]);

    final result = B12BReleaseGateValidator.validate(
      baseline: _baseline,
      evidence: evidence,
      repoRoot: root,
      apkFile: debugApk,
      currentGitSha: _appSha,
      worktreeDirty: true,
    );

    expect(result.passed, isFalse);
    expect(
      result.failures,
      contains('release gate requires a clean Git worktree'),
    );
    expect(
      result.failures,
      contains('environment.real_hardware must be true'),
    );
    expect(
      result.failures,
      contains('Android emulator evidence is not real-hardware evidence'),
    );
    expect(
      result.failures,
      contains('mock/simulator box evidence is forbidden'),
    );
    expect(result.failures, contains('app.build_mode must be release'));
    expect(result.failures, contains('app.signed must be true'));
    expect(result.failures, contains('app.signature_verified must be true'));
    expect(result.failures, contains('APK must be app-bird-release.apk'));
  });

  test('checked-in template contains every required B12-B case exactly once', () {
    final template =
        jsonDecode(
              File(
                'docs/acceptance/b12b-real-hardware-evidence.template.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final ids = (template['cases'] as List).whereType<Map>().map((item) => item['id']?.toString()).whereType<String>().toList();

    expect(ids.toSet(), b12bRequiredCases);
    expect(ids, hasLength(b12bRequiredCases.length));
  });

  test('formal B7 release mode cannot bypass the B12-B evidence gate', () {
    final source = File(
      'tool/release/run_b7_gate.ps1',
    ).readAsStringSync();

    expect(source, contains('[string]\$B12BEvidencePath'));
    expect(source, contains('Release mode requires -B12BEvidencePath.'));
    expect(source, contains('tool/acceptance/b12b_release_gate.dart'));
    expect(source, contains('B12-B real-hardware evidence'));
  });
}

const _appSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _firmwareSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final _baseline = <String, dynamic>{
  'status': 'ready',
  'unresolved_external_inputs': <Object>[],
  'box': {
    'repository': 'https://example.invalid/box.git',
    'branch': 'release/v1',
    'firmware_sha': _firmwareSha,
    'deployment_command': 'documented command',
    'database_schema_version': '7',
    'database_migration': 'migration.md',
    'database_rollback': 'rollback.md',
    'integration_base_url': 'http://192.168.4.1:8080',
  },
  'owners': {
    for (final role in const [
      'protocol',
      'flutter_core',
      'box_api',
      'qa_release',
    ])
      role: {'contact': '$role@example.invalid'},
  },
};

Map<String, dynamic> _evidence(String apkSha) => {
  'schema_version': 1,
  'captured_at': '2026-08-10T12:00:00Z',
  'final_result': 'passed',
  'environment': {
    'real_hardware': true,
    'android_device_serial': 'physical-device-001',
  },
  'app': {
    'git_sha': _appSha,
    'package_id': 'deckers.thibault.aves.bird',
    'build_mode': 'release',
    'signed': true,
    'signature_verified': true,
    'certificate_sha256': 'c' * 64,
    'apk_sha256': apkSha,
  },
  'box': {
    'device_id': 'k7-hardware-001',
    'device_model': 'BirdBox K7',
    'hardware_serial': 'K7-HW-001',
    'firmware_sha': _firmwareSha,
    'api_version': 'v1',
    'database_schema_version': '7',
    'base_url': 'http://192.168.4.1:8080',
  },
  'metrics': {
    'photo_count': 3672,
    'egret_matches': 120,
    'other_species_matches': 80,
    'first_feedback_ms': 150,
    'complete_search_ms': 2100,
    'memory_peak_mb': 220.5,
    'cancel_verified': true,
  },
  'cases': [
    for (final id in b12bRequiredCases)
      {
        'id': id,
        'status': 'passed',
        'evidence': ['evidence.log'],
      },
  ],
  'rollback': {
    'app_artifact': 'previous.apk',
    'firmware_artifact': 'previous.firmware',
    'instructions': 'rollback.md',
  },
  'approvals': {
    for (final role in const [
      'protocol',
      'flutter_core',
      'box_api',
      'qa_release',
    ])
      role: {
        'status': 'approved',
        'evidence': 'approval.txt',
      },
  },
};
