import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ble12/ble12_candidate_validator.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture.create());
  tearDown(() => fixture.dispose());

  test('accepts an honest pending-environment candidate package', () async {
    final result = await fixture.validate();

    expect(result.passed, isTrue, reason: result.errors.join('\n'));
    expect(
      result.toJson(manifest: fixture.manifest),
      containsPair('status', 'candidate_package_ready'),
    );
    expect(
      result.toJson(manifest: fixture.manifest),
      containsPair('hardware_status', 'pending'),
    );
  });

  test('rejects hardware and release promotion claims', () async {
    fixture.manifest['hardware_status'] = 'verified';
    fixture.manifest['releasable'] = true;

    final result = await fixture.validate();

    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('must remain pending'));
    expect(result.errors.join('\n'), contains('non-releasable'));
  });

  test('rejects artifact corruption and unregistered payloads', () async {
    fixture.file('artifacts/app.apk').writeAsStringSync('tampered');
    fixture.file('unexpected.txt').writeAsStringSync('not registered');

    final result = await fixture.validate();

    expect(result.errors.join('\n'), contains('artifact SHA-256 mismatch'));
    expect(result.errors.join('\n'), contains('not registered'));
  });

  test('rejects source drift after candidate freeze', () async {
    final changed = fixture.repositoryFile(
      ble12RequiredFrozenFiles.first,
    );
    changed.writeAsStringSync('changed after candidate freeze');

    final result = await fixture.validate(withRepository: true);

    expect(
      result.errors.join('\n'),
      contains('frozen production source changed after packaging'),
    );
  });

  test('rejects skipping BLE-11 on a capable emulator', () async {
    final environment = fixture.readJson('reports/environment.json')..['dual_avd_capable'] = true;
    fixture
        .file('reports/environment.json')
        .writeAsStringSync(
          jsonEncode(environment),
        );

    final result = await fixture.validate();

    expect(
      result.errors.join('\n'),
      contains('a capable environment may not skip'),
    );
  });

  test('rejects incomplete automated verification', () async {
    final report = fixture.readJson('reports/verification.json')
      ..['flutter_test_count'] = 758
      ..['app_apk_build'] = 'failed';
    fixture
        .file('reports/verification.json')
        .writeAsStringSync(
          jsonEncode(report),
        );

    final result = await fixture.validate();

    expect(result.errors.join('\n'), contains('at least 759'));
    expect(result.errors.join('\n'), contains('APK builds must pass'));
  });

  test('rejects a candidate id not derived from the source fingerprint', () async {
    fixture.manifest['candidate_id'] = 'ble12-0000000000000000';

    final result = await fixture.validate();

    expect(
      result.errors.join('\n'),
      contains('candidate_id does not match the frozen source fingerprint'),
    );
  });

  test('rejects APK identity inconsistent with the inspected manifest', () async {
    const path = 'reports/app-apk-manifest.xml';
    fixture
        .file(path)
        .writeAsStringSync(
          _apkManifest(
            packageId: 'unexpected.package',
            versionName: '1.14.8',
            versionCode: 172,
          ),
        );
    final hash = _sha(fixture.file(path));
    (fixture.manifest['artifacts'] as Map<String, dynamic>)[path] = hash;
    final builds = fixture.manifest['builds'] as Map<String, dynamic>;
    final app = builds['app'] as Map<String, dynamic>;
    (app['manifest_report'] as Map<String, dynamic>)['sha256'] = hash;

    final result = await fixture.validate();

    expect(
      result.errors.join('\n'),
      contains('app APK manifest package does not match'),
    );
  });
}

final class _Fixture {
  _Fixture({
    required this.root,
    required this.packageRoot,
    required this.repositoryRoot,
    required this.manifest,
  });

  final Directory root;
  final Directory packageRoot;
  final Directory repositoryRoot;
  final Map<String, dynamic> manifest;

  static _Fixture create() {
    final root = Directory.systemTemp.createTempSync('ble12-candidate-');
    final packageRoot = Directory('${root.path}${Platform.pathSeparator}package')..createSync();
    final repositoryRoot = Directory('${root.path}${Platform.pathSeparator}repository')..createSync();

    final sourceFiles = <String, String>{};
    for (final path in ble12RequiredFrozenFiles) {
      final content = 'source:$path';
      final sourceFile = _write(repositoryRoot, path, content);
      sourceFiles[path] = _sha(sourceFile);
    }
    final canonicalPaths = sourceFiles.keys.toList()..sort();
    final sourceTreeHash = sha256
        .convert(
          utf8.encode(
            canonicalPaths.map((path) => '$path=${sourceFiles[path]}\n').join(),
          ),
        )
        .toString();
    const gitCommit = '1234567890abcdef1234567890abcdef12345678';
    final candidateId = 'ble12-${sourceTreeHash.substring(0, 16)}';

    final sourceManifest = {
      'schema_version': 1,
      'candidate_id': candidateId,
      'git_commit': gitCommit,
      'branch': 'fixture',
      'state': 'uncommitted_candidate_snapshot',
      'source_tree_sha256': sourceTreeHash,
      'files': sourceFiles,
    };
    _writeJson(packageRoot, 'source/source-manifest.json', sourceManifest);
    _write(packageRoot, 'artifacts/app.apk', 'app apk fixture');
    _write(packageRoot, 'artifacts/virtual.apk', 'virtual apk fixture');
    _write(
      packageRoot,
      'reports/app-apk-manifest.xml',
      _apkManifest(
        packageId: 'deckers.thibault.aves.bird',
        versionName: '1.14.8',
        versionCode: 172,
      ),
    );
    _write(
      packageRoot,
      'reports/virtual-apk-manifest.xml',
      _apkManifest(
        packageId: 'deckers.thibault.aves.virtualbirdbox.debug',
        versionName: 'ble11',
        versionCode: 1,
        testOnly: true,
      ),
    );
    _writeJson(packageRoot, 'reports/environment.json', {
      'schema_version': 1,
      'os_version': 'Windows fixture',
      'flutter_version': '3.44.5',
      'dart_version': '3.12.0',
      'java_version': '21',
      'gradle_version': '9.6.0',
      'android_sdk': r'D:\Androidstudio2',
      'emulator_version': '36.2.12',
      'dual_avd_capable': false,
    });
    _writeJson(packageRoot, 'reports/verification.json', {
      'schema_version': 1,
      'status': 'passed',
      'evidence_kind': 'simulated',
      'hardware_status': 'pending',
      'releasable': false,
      'flutter_test_count': 759,
      'flutter_analyze_issues': 0,
      'app_native_test_count': 20,
      'virtual_birdbox_test_count': 8,
      'app_apk_build': 'passed',
      'virtual_apk_build': 'passed',
    });
    _writeJson(packageRoot, 'evidence/status.json', {
      'schema_version': 1,
      'evidence_kind': 'simulated',
      'hardware_status': 'pending',
      'releasable': false,
      'status': 'pending_environment',
      'dual_avd_capable': false,
      'detected_emulator_version': '36.2.12',
      'reason': 'Emulator is below 36.5.',
    });
    for (final path in const [
      'docs/field.md',
      'docs/diagnostic.md',
      'templates/return.json',
      'templates/real.json',
      'templates/release.json',
      'verify_package.ps1',
    ]) {
      _write(packageRoot, path, 'safe material: $path');
    }

    final artifacts = <String, String>{};
    for (final entity in packageRoot.listSync(recursive: true)) {
      if (entity is File) {
        final path = entity.path.substring(packageRoot.path.length + 1).replaceAll('\\', '/');
        artifacts[path] = _sha(entity);
      }
    }
    Map<String, dynamic> ref(String path) => {
      'file': path,
      'sha256': artifacts[path],
    };
    final manifest = <String, dynamic>{
      'schema_version': 1,
      'candidate_suite': 'rc4-hf-ble-12',
      'candidate_id': candidateId,
      'created_at': '2026-09-23T00:00:00Z',
      'purpose': 'simulated_candidate_external_handoff',
      'evidence_kind': 'simulated',
      'hardware_status': 'pending',
      'releasable': false,
      'release_gate_status': 'blocked_hardware_pending',
      'production_behavior': {
        'state': 'frozen',
        'change_policy': 'new_evidence_required',
      },
      'source': {
        'git_commit': gitCommit,
        'branch': 'fixture',
        'state': 'uncommitted_candidate_snapshot',
        'source_tree_sha256': sourceTreeHash,
        'manifest': ref('source/source-manifest.json'),
      },
      'builds': {
        'app': {
          ...ref('artifacts/app.apk'),
          'package_id': 'deckers.thibault.aves.bird',
          'build_mode': 'debug_candidate',
          'version_name': '1.14.8',
          'version_code': 172,
          'git_commit': gitCommit,
          'manifest_report': ref('reports/app-apk-manifest.xml'),
        },
        'virtual_birdbox': {
          ...ref('artifacts/virtual.apk'),
          'package_id': 'deckers.thibault.aves.virtualbirdbox.debug',
          'build_mode': 'debug_test_only',
          'version_name': 'ble11',
          'version_code': 1,
          'git_commit': gitCommit,
          'test_only': true,
          'release_variant_enabled': false,
          'manifest_report': ref('reports/virtual-apk-manifest.xml'),
        },
      },
      'reports': {
        'build_environment': ref('reports/environment.json'),
        'automated_verification': ref('reports/verification.json'),
      },
      'simulation': {
        'status': 'pending_environment',
        'expected_scenarios': ble12ExpectedScenarios.toList(),
        'status_report': ref('evidence/status.json'),
        'evidence_files': <Object>[],
      },
      'materials': {
        'field_manual': ref('docs/field.md'),
        'diagnostic_guide': ref('docs/diagnostic.md'),
        'return_template': ref('templates/return.json'),
        'real_device_template': ref('templates/real.json'),
        'release_template': ref('templates/release.json'),
        'offline_verifier': ref('verify_package.ps1'),
      },
      'artifacts': artifacts,
    };
    final manifestFile = _writeJson(
      packageRoot,
      'candidate-manifest.json',
      manifest,
    );
    final sumLines = <String>[
      '${_sha(manifestFile)} *candidate-manifest.json',
      ...artifacts.entries.map((entry) => '${entry.value} *${entry.key}'),
    ]..sort();
    _write(packageRoot, 'SHA256SUMS.txt', '${sumLines.join('\n')}\n');

    return _Fixture(
      root: root,
      packageRoot: packageRoot,
      repositoryRoot: repositoryRoot,
      manifest: manifest,
    );
  }

  File file(String path) => File(
    '${packageRoot.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
  );

  File repositoryFile(String path) => File(
    '${repositoryRoot.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
  );

  Map<String, dynamic> readJson(String path) => Map<String, dynamic>.from(jsonDecode(file(path).readAsStringSync()) as Map);

  Future<Ble12CandidateValidation> validate({
    bool withRepository = false,
  }) => validateBle12Candidate(
    manifest: manifest,
    packageRoot: packageRoot,
    repositoryRoot: withRepository ? repositoryRoot : null,
  );

  void dispose() => root.deleteSync(recursive: true);
}

File _write(Directory root, String relativePath, String content) {
  final file = File(
    '${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
  file.parent.createSync(recursive: true);
  return file..writeAsStringSync(content);
}

File _writeJson(
  Directory root,
  String relativePath,
  Map<String, dynamic> value,
) => _write(root, relativePath, jsonEncode(value));

String _sha(File file) => sha256.convert(file.readAsBytesSync()).toString();

String _apkManifest({
  required String packageId,
  required String versionName,
  required int versionCode,
  bool testOnly = false,
}) =>
    '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$packageId"
    android:versionName="$versionName"
    android:versionCode="$versionCode">
  <application android:debuggable="true"${testOnly ? ' android:testOnly="true"' : ''} />
</manifest>
''';
