import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/ble_provisioning_rc4_real_device_gate.dart';

void main() {
  late Directory root;
  late File apk;
  late String apkSha;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ble-rc4-k7-gate-');
    apk = File('${root.path}${Platform.pathSeparator}app-bird-release.apk')..writeAsBytesSync(const [1, 2, 3, 4]);
    apkSha = sha256.convert(apk.readAsBytesSync()).toString();
    File('${root.path}${Platform.pathSeparator}evidence.log').writeAsStringSync('K7 real-device run completed; identifiers redacted.');
    File('${root.path}${Platform.pathSeparator}redaction.txt').writeAsStringSync('Evidence reviewed; credentials and complete identifiers removed.');
    File('${root.path}${Platform.pathSeparator}approval.txt').writeAsStringSync('Protocol and QA release approvals recorded.');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('accepts complete K7-01 through K7-10 real-device evidence', () {
    final result = _validate(root: root, apk: apk, evidence: _evidence(apkSha));

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.verifiedCaseCount, 10);
    expect(result.toJson()['real_k7_status'], 'verified');
    expect(result.toJson()['releasable'], isTrue);
  });

  test('rejects pending, simulator, debug, dirty, unsigned, and bad hashes', () {
    final pending = _evidence(apkSha)
      ..['final_result'] = 'pending'
      ..['releasable'] = false
      ..['real_k7_status'] = 'pending';
    expect(_validate(root: root, apk: apk, evidence: pending).passed, isFalse);

    final simulator = _clone(_evidence(apkSha));
    ((simulator['environment'] as Map)['android_devices'] as List).first['serial'] = 'emulator-5554';
    expect(_validate(root: root, apk: apk, evidence: simulator).passed, isFalse);

    final debug = _clone(_evidence(apkSha));
    (debug['app'] as Map)['build_mode'] = 'debug';
    expect(_validate(root: root, apk: apk, evidence: debug).passed, isFalse);

    final dirty = _validate(
      root: root,
      apk: apk,
      evidence: _evidence(apkSha),
      worktreeDirty: true,
    );
    expect(dirty.passed, isFalse);

    final unsigned = _clone(_evidence(apkSha));
    (unsigned['app'] as Map)['signed'] = false;
    expect(_validate(root: root, apk: apk, evidence: unsigned).passed, isFalse);

    final badApkSha = _clone(_evidence(apkSha));
    (badApkSha['app'] as Map)['apk_sha256'] = '0' * 64;
    expect(_validate(root: root, apk: apk, evidence: badApkSha).passed, isFalse);

    final badCertificate = _clone(_evidence(apkSha));
    (badCertificate['app'] as Map)['certificate_sha256'] = 'd' * 64;
    expect(
      _validate(root: root, apk: apk, evidence: badCertificate).passed,
      isFalse,
    );
  });

  test('rejects missing or duplicated required K7 cases', () {
    final missing = _clone(_evidence(apkSha));
    (missing['cases'] as List).removeLast();
    final missingResult = _validate(root: root, apk: apk, evidence: missing);
    expect(missingResult.passed, isFalse);
    expect(missingResult.failures.join('\n'), contains('K7-10'));

    final duplicate = _clone(_evidence(apkSha));
    (duplicate['cases'] as List)[9] = Map<String, dynamic>.from(
      (duplicate['cases'] as List).first as Map,
    );
    final duplicateResult = _validate(root: root, apk: apk, evidence: duplicate);
    expect(duplicateResult.passed, isFalse);
    expect(duplicateResult.failures.join('\n'), contains('K7-01'));
  });

  test('rejects credentials, complete DPP URI, and complete MAC address', () {
    final sensitiveField = _clone(_evidence(apkSha));
    sensitiveField['password'] = 'must-not-be-recorded';
    final sensitiveResult = _validate(
      root: root,
      apk: apk,
      evidence: sensitiveField,
    );
    expect(sensitiveResult.passed, isFalse);
    expect(
      sensitiveResult.failures.join('\n'),
      contains('forbidden sensitive field'),
    );

    File('${root.path}${Platform.pathSeparator}evidence.log').writeAsStringSync(
      'DPP:K:PUBLICKEY;M:AA:BB:CC:DD:EE:FF;;',
    );
    final leakedResult = _validate(
      root: root,
      apk: apk,
      evidence: _evidence(apkSha),
    );
    expect(leakedResult.passed, isFalse);
    expect(leakedResult.failures.join('\n'), contains('complete DPP URI'));
    expect(leakedResult.failures.join('\n'), contains('complete MAC address'));
  });

  test('checked-in template remains non-releasable', () {
    final template =
        jsonDecode(
              File(
                'docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final result = _validate(root: root, apk: apk, evidence: template);

    expect(result.passed, isFalse);
    expect(result.toJson()['real_k7_status'], 'pending');
    expect(result.toJson()['releasable'], isFalse);
  });
}

BleProvisioningRc4RealDeviceGateResult _validate({
  required Directory root,
  required File apk,
  required Map<String, dynamic> evidence,
  bool worktreeDirty = false,
}) {
  return BleProvisioningRc4RealDeviceGateValidator.validate(
    baseline: _baseline(),
    evidence: evidence,
    repositoryRoot: root,
    apkFile: apk,
    currentGitSha: 'a' * 40,
    worktreeDirty: worktreeDirty,
    approvedCertificateSha256: 'c' * 64,
  );
}

Map<String, dynamic> _baseline() => {
  'status': 'ready',
  'unresolved_external_inputs': <Object>[],
  'box': {'firmware_sha': 'b' * 40},
};

Map<String, dynamic> _evidence(String apkSha) => {
  'schema_version': 1,
  'acceptance_suite': 'ble-provisioning-rc4-real-device',
  'captured_at': '2026-09-03T08:00:00Z',
  'final_result': 'passed',
  'releasable': true,
  'real_k7_status': 'verified',
  'environment': {
    'real_hardware': true,
    'operator': 'QA operator',
    'location': 'hardware lab',
    'android_devices': [
      {
        'id': 'android-primary',
        'serial': 'R58M123456Z',
        'manufacturer': 'Samsung',
        'model': 'SM-S9180',
        'os_version': 'Android 15',
        'physical': true,
      },
    ],
    'routers': [
      {
        'id': 'router-primary',
        'model': 'LabRouter X1',
        'firmware': '1.2.3',
        'band': '2.4GHz',
        'security': 'WPA2',
      },
    ],
  },
  'app': {
    'git_sha': 'a' * 40,
    'package_id': 'deckers.thibault.aves.bird',
    'build_mode': 'release',
    'signed': true,
    'signature_verified': true,
    'certificate_sha256': 'c' * 64,
    'apk_sha256': apkSha,
  },
  'box': {
    'device_id': 'birdbox-lab-01',
    'device_model': 'BirdBox K7',
    'hardware_serial': 'BOX-SERIAL-01',
    'firmware_sha': 'b' * 40,
    'api_version': 'v1',
  },
  'cases': [
    for (var index = 1; index <= 10; index++)
      {
        'id': 'K7-${index.toString().padLeft(2, '0')}',
        'status': 'passed',
        'summary': 'Real-device case passed with identifiers redacted.',
        'device_ids': ['android-primary'],
        'router_ids': index >= 6 ? ['router-primary'] : <String>[],
        'evidence': ['evidence.log'],
      },
  ],
  'evidence_summary': 'Ten RC4 K7 cases passed on physical hardware.',
  'redaction': {
    'reviewed': true,
    'reviewer': 'QA reviewer',
    'statement': 'Credentials and complete identifiers were removed.',
    'report': 'redaction.txt',
  },
  'approvals': {
    'protocol': {'status': 'approved', 'evidence': 'approval.txt'},
    'qa_release': {'status': 'approved', 'evidence': 'approval.txt'},
  },
};

Map<String, dynamic> _clone(Map<String, dynamic> value) => jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
