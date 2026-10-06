import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/rc4_hf_ble_16_evidence_validator.dart';

void main() {
  late Directory root;
  late Map<String, dynamic> evidence;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rc4-hf-ble-16-');
    evidence = _validEvidence(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('accepts a complete versioned artifact and T1-T8 evidence set', () {
    final result = validateRc4HfBle16Evidence(evidence, evidenceRoot: root);

    expect(result.passed, isTrue, reason: result.errors.join('\n'));
    expect(result.versionCode, 174);
    expect(result.artifacts.keys, containsAll(['bird', 'birdScanA', 'birdScanB']));
    expect(result.scenarioCount, 8);
    expect(result.toJson()['releasable'], isTrue);
  });

  test('checked-in pending template is fail-closed', () {
    final template =
        jsonDecode(
              File(
                'docs/acceptance/rc4-hf-ble-16-evidence.template.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final result = validateRc4HfBle16Evidence(
      template,
      evidenceRoot: Directory('docs/acceptance').absolute,
    );

    expect(result.passed, isFalse);
    expect(result.toJson()['status'], 'blocked');
    expect(result.errors.join('\n'), contains('unresolved placeholder'));
    expect(result.errors.join('\n'), contains('final_result must be passed'));
  });

  test('rejects reused version code and an APK hash mismatch', () {
    final source = evidence['source'] as Map<String, dynamic>;
    source['version_code'] = 173;
    final bird = (evidence['artifacts'] as Map<String, dynamic>)['bird'] as Map<String, dynamic>;
    bird['version_code'] = 173;
    bird['apk_sha256'] = 'f' * 64;

    final result = validateRc4HfBle16Evidence(evidence, evidenceRoot: root);

    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('greater than 173'));
    expect(result.errors.join('\n'), contains('does not match the APK'));
  });

  test('rejects a missing scenario and a failed OPPO run', () {
    final scenarios = evidence['scenarios'] as List<dynamic>;
    scenarios.removeWhere((item) => (item as Map)['id'] == 'T8');
    (scenarios.first as Map<String, dynamic>)['status'] = 'failed';
    ((scenarios.first as Map<String, dynamic>)['assertions'] as Map<String, dynamic>)['ack_received'] = false;

    final result = validateRc4HfBle16Evidence(evidence, evidenceRoot: root);

    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('scenarios must contain T8 exactly once'));
    expect(result.errors.join('\n'), contains('scenarios.T1.status must be passed'));
    expect(result.errors.join('\n'), contains('T1 must receive the K7 ACK'));
  });

  test('allows additive unknown fields without weakening validation', () {
    evidence['future_top_level'] = {'schema_extension': 2};
    final bird = (evidence['artifacts'] as Map<String, dynamic>)['bird'] as Map<String, dynamic>;
    bird['future_build_property'] = true;

    final result = validateRc4HfBle16Evidence(evidence, evidenceRoot: root);

    expect(result.passed, isTrue, reason: result.errors.join('\n'));
  });
}

Map<String, dynamic> _validEvidence(Directory root) {
  const gitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const versionName = '1.14.9';
  const versionCode = 174;
  final evidenceFile = File('${root.path}${Platform.pathSeparator}evidence.txt')..writeAsStringSync('Redacted physical-device verification passed.');
  final artifacts = <String, Map<String, dynamic>>{};

  Map<String, dynamic> artifact({
    required String id,
    required String packageId,
    required String displayName,
    required String mode,
    required String policy,
  }) {
    final apk = File('${root.path}${Platform.pathSeparator}$id.apk')..writeAsBytesSync(utf8.encode('rc4-hf-ble-16-$id'));
    final value = <String, dynamic>{
      'package_id': packageId,
      'display_name': displayName,
      'flavor': id,
      'build_mode': mode,
      'version_name': versionName,
      'version_code': versionCode,
      'git_commit': gitSha,
      'apk_file': apk.path,
      'apk_size_bytes': apk.lengthSync(),
      'apk_sha256': sha256.convert(apk.readAsBytesSync()).toString(),
      'scan_permission_policy': policy,
      'strategy_fallback_enabled': id != 'bird',
      'diagnostic_identity_verified': true,
    };
    if (id == 'bird') {
      value['signed'] = true;
      value['signature_verified'] = true;
    }
    return value;
  }

  artifacts['bird'] = artifact(
    id: 'bird',
    packageId: 'deckers.thibault.aves.bird',
    displayName: '拍鸟伴侣',
    mode: 'release',
    policy: 'never_for_location',
  );
  artifacts['birdScanA'] = artifact(
    id: 'birdScanA',
    packageId: 'deckers.thibault.aves.bird.scan.a',
    displayName: 'BirdBox 扫描 A',
    mode: 'debug',
    policy: 'never_for_location',
  );
  artifacts['birdScanB'] = artifact(
    id: 'birdScanB',
    packageId: 'deckers.thibault.aves.bird.scan.b',
    displayName: 'BirdBox 扫描 B',
    mode: 'debug',
    policy: 'full_scan',
  );

  Map<String, dynamic> scenario(String id, String artifactId) {
    final phone = switch (id) {
      'T1' || 'T2' || 'T3' => 'OPPO Reno5',
      'T4' || 'T5' || 'T6' || 'T8' => 'Huawei Mate',
      _ => 'Xiaomi Test Phone',
    };
    final assertions = switch (id) {
      'T1' => {
        'ack_received': true,
        'create_bond_count': 1,
        'same_request_retried_once': true,
      },
      'T2' => {'ack_received': true, 'unexpected_pairing_prompt': false},
      'T3' => {'error_code': 'ble_pairing_timeout'},
      'T4' || 'T5' => {
        'birdbox_discovered_each_round': true,
        'strategy_counters_recorded': true,
      },
      'T6' => {'scan_connected_and_ack': true},
      'T7' => {'regression_passed': true, 'stale_callback_observed': false},
      _ => {'cleanup_verified': true, 'app_crashed': false},
    };
    return {
      'id': id,
      'status': 'passed',
      'artifact': artifactId,
      'apk_sha256': artifacts[artifactId]!['apk_sha256'],
      'rounds': id == 'T4' || id == 'T5' ? 3 : 1,
      'executed_at': '2026-10-06T08:00:00Z',
      'executor': 'QA operator',
      'environment_id': id == 'T4' || id == 'T5' ? 'huawei-ab-01' : 'device-$id',
      'phone': {
        'physical': true,
        'manufacturer': phone.split(' ').first,
        'model': phone,
        'android_release': '12',
        'sdk_int': 32,
        'bluetooth_state': 'enabled',
        'location_service_state': 'enabled',
      },
      'k7': {
        'physical': true,
        'model': 'BirdBox K7',
        'firmware_sha': 'b' * 40,
      },
      'assertions': assertions,
      'evidence_files': [evidenceFile.path],
    };
  }

  return {
    'schema_version': 1,
    'evidence_suite': 'rc4-hf-ble-16',
    'captured_at': '2026-10-06T09:00:00Z',
    'final_result': 'passed',
    'release_decision': 'approved',
    'selected_scan_variant': 'A',
    'source': {
      'git_commit': gitSha,
      'version_name': versionName,
      'version_code': versionCode,
    },
    'artifacts': artifacts,
    'automation': [
      for (final id in const [
        'flutter_analyze',
        'flutter_test',
        'android_bird_unit',
        'android_scan_a_unit',
        'android_scan_b_unit',
        'candidate_builds',
        'git_diff_check',
      ])
        {
          'id': id,
          'status': 'passed',
          'evidence_files': [evidenceFile.path],
        },
    ],
    'scenarios': [
      scenario('T1', 'bird'),
      scenario('T2', 'bird'),
      scenario('T3', 'bird'),
      scenario('T4', 'birdScanA'),
      scenario('T5', 'birdScanB'),
      scenario('T6', 'bird'),
      scenario('T7', 'bird'),
      scenario('T8', 'bird'),
    ],
    'known_limitations': <Object>[],
    'rollback': {
      'tested': true,
      'package_id': 'deckers.thibault.aves.bird',
      'version_name': '1.14.8',
      'version_code': 173,
      'apk_sha256': 'c' * 64,
      'evidence_file': evidenceFile.path,
    },
    'approvals': {
      for (final role in const ['app', 'board', 'qa'])
        role: {
          'status': 'approved',
          'reviewer': '$role reviewer',
          'evidence_file': evidenceFile.path,
        },
    },
  };
}
