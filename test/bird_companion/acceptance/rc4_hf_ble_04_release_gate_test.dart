import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/rc4_hf_ble_03_evidence_validator.dart';
import '../../../tool/acceptance/rc4_hf_ble_04_release_gate.dart';

void main() {
  late Directory root;
  late File apk;
  late File manifest;
  late String apkSha;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rc4-hf-ble-04-');
    apk = File('${root.path}${Platform.pathSeparator}app-bird-release.apk')..writeAsBytesSync(const [4, 0, 4, 4]);
    apkSha = sha256.convert(apk.readAsBytesSync()).toString();
    manifest = File('${root.path}${Platform.pathSeparator}AndroidManifest.xml');
    _writeRepositoryFixture(
      root,
      policy: 'never_for_location',
      birdPolicy: 'full_scan',
    );
    _writeManifest(manifest, policy: 'full_scan');
    File('${root.path}${Platform.pathSeparator}release-approval.txt').writeAsStringSync('Release approved after redacted evidence review.');
    File('${root.path}${Platform.pathSeparator}rollback.txt').writeAsStringSync(
      'Signed previous build restored successfully on a physical test phone.',
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('accepts a signed release matching the BLE-03 selected variant', () {
    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: _releaseEvidence(apkSha),
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.toJson()['releasable'], isTrue);
    expect(result.toJson()['ble03_hardware_status'], 'verified');
    expect(result.expectedScanPolicy, 'full_scan');
  });

  test('accepts variant A inherited from the production default policy', () {
    _writeRepositoryFixture(root, policy: 'never_for_location');
    _writeManifest(manifest, policy: 'never_for_location');
    final evidence = _releaseEvidence(apkSha);
    (evidence['candidate'] as Map<String, dynamic>)['scan_permission_policy'] = 'never_for_location';

    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: evidence,
      selectedVariant: 'A',
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.expectedScanPolicy, 'never_for_location');
  });

  test('checked-in template remains blocked even with a valid fixture', () {
    final template =
        jsonDecode(
              File(
                'docs/acceptance/rc4-hf-ble-04-release.template.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: template,
      ble03Validation: const Rc4HfBle03EvidenceValidation(
        errors: ['Real OPPO/Huawei/K7 evidence is pending.'],
        scanRunsByKey: {},
        pairingRunCount: 0,
      ),
      selectedVariant: '',
    );

    expect(result.passed, isFalse);
    expect(result.toJson()['status'], 'blocked');
    expect(result.toJson()['ble03_hardware_status'], 'pending');
    expect(result.toJson()['selected_scan_variant'], 'pending');
    expect(
      result.failures.join('\n'),
      contains('BLE-03 real-device evidence gate must pass'),
    );
  });

  test('rejects debug, dirty, wrong package, certificate, Git and APK hash', () {
    final evidence = _releaseEvidence(apkSha);
    final candidate = evidence['candidate'] as Map<String, dynamic>;
    candidate['build_mode'] = 'debug';
    candidate['package_id'] = 'deckers.thibault.aves.bird.scan.b';
    candidate['certificate_sha256'] = 'd' * 64;
    candidate['git_commit'] = 'b' * 40;
    candidate['apk_sha256'] = 'e' * 64;

    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: evidence,
      worktreeDirty: true,
    );

    expect(result.passed, isFalse);
    final failures = result.failures.join('\n');
    expect(failures, contains('clean Git worktree'));
    expect(failures, contains('candidate.build_mode must be release'));
    expect(failures, contains('candidate.package_id'));
    expect(failures, contains('approved certificate'));
    expect(failures, contains('checked-out revision'));
    expect(failures, contains('does not match the release APK'));
  });

  test('rejects manifest and diagnostic policy drift plus legacy createBond', () {
    _writeManifest(manifest, policy: 'never_for_location');
    _writeRepositoryFixture(root, policy: 'never_for_location');
    File(
      '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}app${Platform.pathSeparator}src${Platform.pathSeparator}main${Platform.pathSeparator}Legacy.java',
    ).writeAsStringSync('void start() { device.createBond(); }');

    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: _releaseEvidence(apkSha),
    );

    expect(result.passed, isFalse);
    final failures = result.failures.join('\n');
    expect(failures, contains('Merged manifest BLUETOOTH_SCAN policy'));
    expect(failures, contains('Production BuildConfig'));
    expect(failures, contains('Legacy pre-bond path'));
  });

  test('rejects credential and complete MAC leakage in release evidence', () {
    File('${root.path}${Platform.pathSeparator}release-approval.txt').writeAsStringSync('password=birdbox-secret AA:BB:CC:DD:EE:FF');

    final result = _validate(
      root: root,
      apk: apk,
      manifest: manifest,
      evidence: _releaseEvidence(apkSha),
    );

    expect(result.passed, isFalse);
    expect(result.failures.join('\n'), contains('credential-like material'));
    expect(result.failures.join('\n'), contains('complete MAC address'));
  });
}

Rc4HfBle04ReleaseGateResult _validate({
  required Directory root,
  required File apk,
  required File manifest,
  required Map<String, dynamic> evidence,
  Rc4HfBle03EvidenceValidation ble03Validation = const Rc4HfBle03EvidenceValidation(
    errors: [],
    scanRunsByKey: {},
    pairingRunCount: 5,
  ),
  String selectedVariant = 'B',
  bool worktreeDirty = false,
}) {
  return Rc4HfBle04ReleaseGateValidator.validate(
    evidence: evidence,
    evidenceRoot: root,
    ble03Validation: ble03Validation,
    selectedScanVariant: selectedVariant,
    repositoryRoot: root,
    apkFile: apk,
    mergedManifestFile: manifest,
    currentGitSha: 'a' * 40,
    worktreeDirty: worktreeDirty,
    approvedCertificateSha256: 'c' * 64,
  );
}

Map<String, dynamic> _releaseEvidence(String apkSha) => {
  'schema_version': 1,
  'release_gate': 'rc4-hf-ble-04',
  'captured_at': '2026-09-20T08:00:00Z',
  'final_result': 'passed',
  'ble03_evidence_file': 'ble03.json',
  'candidate': {
    'package_id': 'deckers.thibault.aves.bird',
    'build_mode': 'release',
    'signed': true,
    'signature_verified': true,
    'git_commit': 'a' * 40,
    'version_name': '1.14.8',
    'version_code': 172,
    'build_time': '2026-09-20T07:30:00Z',
    'apk_sha256': apkSha,
    'certificate_sha256': 'c' * 64,
    'scan_permission_policy': 'full_scan',
  },
  'release_approval': {
    'status': 'approved',
    'reviewer': 'QA release reviewer',
    'evidence_file': 'release-approval.txt',
  },
  'rollback': {'tested': true, 'evidence_file': 'rollback.txt'},
};

void _writeRepositoryFixture(
  Directory root, {
  required String policy,
  String? birdPolicy,
}) {
  File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync('name: fixture\nversion: 1.14.8+172\n');
  final gradle = File(
    '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle.kts',
  )..createSync(recursive: true);
  gradle.writeAsStringSync('''
android {
  defaultConfig {
    buildConfigField("String", "BLE_SCAN_PERMISSION_POLICY", "\\"$policy\\"")
  }
  productFlavors {
    create("bird") {
      ${birdPolicy == null ? '' : 'buildConfigField("String", "BLE_SCAN_PERMISSION_POLICY", "\\"$birdPolicy\\"")'}
    }
  }
}
''');
  File(
      '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}app${Platform.pathSeparator}src${Platform.pathSeparator}main${Platform.pathSeparator}Safe.java',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync('final class Safe {}');
  File(
      '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}bird_companion${Platform.pathSeparator}features${Platform.pathSeparator}connection${Platform.pathSeparator}safe.dart',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync('final class SafeConnection {}');
}

void _writeManifest(File file, {required String policy}) {
  final flag = policy == 'never_for_location' ? ' android:usesPermissionFlags="neverForLocation"' : '';
  file.writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="deckers.thibault.aves.bird"
    android:versionCode="172"
    android:versionName="1.14.8">
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"$flag />
</manifest>
''');
}
