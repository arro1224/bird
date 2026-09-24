import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rc4_hf_ble_03_evidence_validator.dart';

const rc4HfBle04PackageId = 'deckers.thibault.aves.bird';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final repositoryRoot = Directory.current.absolute;
  final failures = <String>[];
  final evidenceFile = _resolveFile(repositoryRoot, options.evidencePath);
  final evidence = _readJson(evidenceFile, 'BLE-04 evidence', failures);
  final evidenceRoot = evidenceFile.parent;

  final configuredBle03Path = options.ble03EvidencePath.isNotEmpty ? options.ble03EvidencePath : _text(evidence['ble03_evidence_file']);
  final ble03File = _resolveFile(evidenceRoot, configuredBle03Path);
  final ble03Evidence = _readJson(ble03File, 'BLE-03 evidence', failures);
  final ble03Validation = validateRc4HfBle03Evidence(
    ble03Evidence,
    evidenceRoot: ble03File.parent,
  );

  final gitSha = await _git(
    repositoryRoot,
    const ['rev-parse', 'HEAD'],
    failures,
  );
  final gitStatus = await _git(
    repositoryRoot,
    const ['status', '--porcelain'],
    failures,
  );
  final result = Rc4HfBle04ReleaseGateValidator.validate(
    evidence: evidence,
    evidenceRoot: evidenceRoot,
    ble03Validation: ble03Validation,
    selectedScanVariant: _text(ble03Evidence['selected_scan_variant']),
    repositoryRoot: repositoryRoot,
    apkFile: _resolveFile(repositoryRoot, options.apkPath),
    mergedManifestFile: _resolveFile(repositoryRoot, options.manifestPath),
    currentGitSha: gitSha.trim(),
    worktreeDirty: gitStatus.trim().isNotEmpty,
    approvedCertificateSha256: options.approvedCertificateSha256,
    initialFailures: failures,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 2;
}

final class Rc4HfBle04ReleaseGateValidator {
  const Rc4HfBle04ReleaseGateValidator._();

  static Rc4HfBle04ReleaseGateResult validate({
    required Map<String, dynamic> evidence,
    required Directory evidenceRoot,
    required Rc4HfBle03EvidenceValidation ble03Validation,
    required String selectedScanVariant,
    required Directory repositoryRoot,
    required File apkFile,
    required File mergedManifestFile,
    required String currentGitSha,
    required bool worktreeDirty,
    required String approvedCertificateSha256,
    Iterable<String> initialFailures = const [],
  }) {
    final failures = <String>[...initialFailures];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(evidence['schema_version'] == 1, 'schema_version must be 1.');
    require(
      evidence['release_gate'] == 'rc4-hf-ble-04',
      'release_gate must be rc4-hf-ble-04.',
    );
    require(
      evidence['final_result'] == 'passed',
      'final_result must be passed.',
    );
    require(
      DateTime.tryParse(_text(evidence['captured_at'])) != null,
      'captured_at must be an ISO-8601 timestamp.',
    );
    for (final path in _findPlaceholders(evidence, r'$')) {
      failures.add('Evidence contains an unresolved placeholder: $path.');
    }
    for (final path in _findSensitiveFields(evidence, r'$')) {
      failures.add('Evidence contains a forbidden sensitive field: $path.');
    }
    _scanTextForSecrets(jsonEncode(evidence), 'BLE-04 evidence JSON', failures);

    require(
      ble03Validation.passed,
      'BLE-03 real-device evidence gate must pass before release promotion.',
    );
    if (!ble03Validation.passed) {
      for (final error in ble03Validation.errors) {
        failures.add('BLE-03: $error');
      }
    }
    require(
      const {'A', 'B'}.contains(selectedScanVariant),
      'BLE-03 selected_scan_variant must be A or B.',
    );
    final expectedPolicy = switch (selectedScanVariant) {
      'A' => 'never_for_location',
      'B' => 'full_scan',
      _ => 'pending',
    };

    require(!worktreeDirty, 'BLE-04 release requires a clean Git worktree.');
    final candidate = _map(evidence['candidate']);
    require(
      candidate['package_id'] == rc4HfBle04PackageId,
      'candidate.package_id must be $rc4HfBle04PackageId.',
    );
    require(
      candidate['build_mode'] == 'release',
      'candidate.build_mode must be release.',
    );
    require(candidate['signed'] == true, 'candidate.signed must be true.');
    require(
      candidate['signature_verified'] == true,
      'candidate.signature_verified must be true.',
    );
    require(
      _sha40(candidate['git_commit']),
      'candidate.git_commit must be a full Git SHA.',
    );
    require(
      _text(candidate['git_commit']).toLowerCase() == currentGitSha.toLowerCase(),
      'candidate.git_commit does not match the checked-out revision.',
    );
    require(
      candidate['scan_permission_policy'] == expectedPolicy,
      'candidate.scan_permission_policy must be $expectedPolicy for BLE-03 variant $selectedScanVariant.',
    );
    require(
      DateTime.tryParse(_text(candidate['build_time'])) != null,
      'candidate.build_time must be an ISO-8601 timestamp.',
    );
    require(
      _sha256(candidate['apk_sha256']),
      'candidate.apk_sha256 must be SHA-256.',
    );
    require(
      _sha256(candidate['certificate_sha256']),
      'candidate.certificate_sha256 must be SHA-256.',
    );
    require(
      _sha256(approvedCertificateSha256),
      'An approved release certificate SHA-256 is required.',
    );
    require(
      _text(candidate['certificate_sha256']).toLowerCase() == approvedCertificateSha256.toLowerCase(),
      'candidate.certificate_sha256 does not match the approved certificate.',
    );

    require(apkFile.existsSync(), 'Release APK does not exist: ${apkFile.path}');
    require(
      _basename(apkFile.path).toLowerCase() == 'app-bird-release.apk',
      'Release APK must be named app-bird-release.apk.',
    );
    if (apkFile.existsSync()) {
      final actualSha = sha256.convert(apkFile.readAsBytesSync()).toString();
      require(
        _text(candidate['apk_sha256']).toLowerCase() == actualSha,
        'candidate.apk_sha256 does not match the release APK.',
      );
    }

    _validateMergedManifest(
      mergedManifestFile,
      candidate: candidate,
      expectedPolicy: expectedPolicy,
      require: require,
    );
    _validateProjectVersion(
      repositoryRoot,
      candidate: candidate,
      require: require,
    );
    _validateProductionDiagnosticPolicy(
      repositoryRoot,
      expectedPolicy: expectedPolicy,
      require: require,
    );
    _auditProductionSources(repositoryRoot, require: require);

    final evidenceReferences = <String>{};
    final approval = _map(evidence['release_approval']);
    require(
      approval['status'] == 'approved',
      'release_approval.status must be approved.',
    );
    require(
      _usableText(approval['reviewer']),
      'release_approval.reviewer is required.',
    );
    final approvalFile = _text(approval['evidence_file']);
    require(
      approvalFile.isNotEmpty,
      'release_approval.evidence_file is required.',
    );
    if (approvalFile.isNotEmpty) evidenceReferences.add(approvalFile);

    final rollback = _map(evidence['rollback']);
    require(rollback['tested'] == true, 'rollback.tested must be true.');
    final rollbackFile = _text(rollback['evidence_file']);
    require(rollbackFile.isNotEmpty, 'rollback.evidence_file is required.');
    if (rollbackFile.isNotEmpty) evidenceReferences.add(rollbackFile);

    for (final reference in evidenceReferences) {
      final file = _resolveFile(evidenceRoot, reference);
      require(file.existsSync(), 'Evidence file does not exist: $reference');
      if (file.existsSync() && _isTextEvidence(file)) {
        try {
          _scanTextForSecrets(
            file.readAsStringSync(),
            reference,
            failures,
          );
        } on FileSystemException {
          failures.add('Text evidence cannot be read safely: $reference');
        }
      }
    }

    return Rc4HfBle04ReleaseGateResult(
      failures: List.unmodifiable(failures),
      selectedScanVariant: selectedScanVariant,
      expectedScanPolicy: expectedPolicy,
      ble03HardwareVerified: ble03Validation.passed,
    );
  }
}

final class Rc4HfBle04ReleaseGateResult {
  const Rc4HfBle04ReleaseGateResult({
    required this.failures,
    required this.selectedScanVariant,
    required this.expectedScanPolicy,
    required this.ble03HardwareVerified,
  });

  final List<String> failures;
  final String selectedScanVariant;
  final String expectedScanPolicy;
  final bool ble03HardwareVerified;

  bool get passed => failures.isEmpty;

  Map<String, Object?> toJson() => {
    'gate': 'RC4-HF-BLE-04',
    'status': passed ? 'passed' : 'blocked',
    'releasable': passed,
    'ble03_hardware_status': ble03HardwareVerified ? 'verified' : 'pending',
    'selected_scan_variant': const {'A', 'B'}.contains(selectedScanVariant) ? selectedScanVariant : 'pending',
    'expected_scan_permission_policy': expectedScanPolicy,
    'failure_count': failures.length,
    'failures': failures,
  };
}

void _validateMergedManifest(
  File manifest, {
  required Map<String, dynamic> candidate,
  required String expectedPolicy,
  required void Function(bool, String) require,
}) {
  require(
    manifest.existsSync(),
    'Merged release manifest does not exist: ${manifest.path}',
  );
  if (!manifest.existsSync()) return;
  final content = manifest.readAsStringSync();
  final scanPermissions = RegExp(
    r'''<uses-permission\b[^>]*android:name\s*=\s*["']android\.permission\.BLUETOOTH_SCAN["'][^>]*/?>''',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(content).map((match) => match.group(0)!).toList();
  require(
    scanPermissions.length == 1,
    'Merged manifest must contain exactly one BLUETOOTH_SCAN permission.',
  );
  if (scanPermissions.length == 1) {
    final declaresNeverForLocation = RegExp(
      r'''android:usesPermissionFlags\s*=\s*["'][^"']*neverForLocation[^"']*["']''',
      caseSensitive: false,
    ).hasMatch(scanPermissions.single);
    require(
      expectedPolicy == 'never_for_location' ? declaresNeverForLocation : !declaresNeverForLocation,
      'Merged manifest BLUETOOTH_SCAN policy does not match $expectedPolicy.',
    );
  }
  require(
    RegExp(
      r'''\bpackage\s*=\s*["']deckers\.thibault\.aves\.bird["']''',
    ).hasMatch(content),
    'Merged manifest package must be $rc4HfBle04PackageId.',
  );
  final versionName = RegExp(
    r'''android:versionName\s*=\s*["']([^"']+)["']''',
  ).firstMatch(content)?.group(1);
  final versionCode = RegExp(
    r'''android:versionCode\s*=\s*["']([^"']+)["']''',
  ).firstMatch(content)?.group(1);
  require(
    versionName == _text(candidate['version_name']),
    'candidate.version_name does not match the merged manifest.',
  );
  require(
    versionCode == _text(candidate['version_code']),
    'candidate.version_code does not match the merged manifest.',
  );
}

void _validateProjectVersion(
  Directory repositoryRoot, {
  required Map<String, dynamic> candidate,
  required void Function(bool, String) require,
}) {
  final pubspec = File(
    '${repositoryRoot.path}${Platform.pathSeparator}pubspec.yaml',
  );
  require(pubspec.existsSync(), 'pubspec.yaml is required for release gating.');
  if (!pubspec.existsSync()) return;
  final match = RegExp(
    r'^version:\s*([^+\s]+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  require(match != null, 'pubspec.yaml must contain version name and code.');
  if (match == null) return;
  require(
    match.group(1) == _text(candidate['version_name']),
    'candidate.version_name does not match pubspec.yaml.',
  );
  require(
    match.group(2) == _text(candidate['version_code']),
    'candidate.version_code does not match pubspec.yaml.',
  );
}

void _validateProductionDiagnosticPolicy(
  Directory repositoryRoot, {
  required String expectedPolicy,
  required void Function(bool, String) require,
}) {
  final gradle = File(
    '${repositoryRoot.path}${Platform.pathSeparator}android${Platform.pathSeparator}app${Platform.pathSeparator}build.gradle.kts',
  );
  require(
    gradle.existsSync(),
    'android/app/build.gradle.kts is required for release gating.',
  );
  if (!gradle.existsSync()) return;
  final source = gradle.readAsStringSync();
  final defaultConfig = _namedBlock(source, 'defaultConfig');
  require(
    defaultConfig != null,
    'Android defaultConfig block could not be inspected.',
  );
  if (defaultConfig == null) return;
  final birdFlavor = _matchedBlock(
    source,
    RegExp(r'create\(\s*"bird"\s*\)\s*\{'),
  );
  final effectiveConfig = birdFlavor != null && birdFlavor.contains('BLE_SCAN_PERMISSION_POLICY') ? birdFlavor : defaultConfig;
  final marker = 'buildConfigField("String", "BLE_SCAN_PERMISSION_POLICY", "\\"$expectedPolicy\\"")';
  require(
    effectiveConfig.contains(marker),
    'Production BuildConfig BLE_SCAN_PERMISSION_POLICY does not match $expectedPolicy.',
  );
}

void _auditProductionSources(
  Directory repositoryRoot, {
  required void Function(bool, String) require,
}) {
  final roots = [
    Directory(
      '${repositoryRoot.path}${Platform.pathSeparator}android${Platform.pathSeparator}app${Platform.pathSeparator}src${Platform.pathSeparator}main',
    ),
    Directory(
      '${repositoryRoot.path}${Platform.pathSeparator}lib${Platform.pathSeparator}bird_companion${Platform.pathSeparator}features${Platform.pathSeparator}connection',
    ),
  ];
  final forbidden = <String, RegExp>{
    'ensureBonded': RegExp(r'\bensureBonded\b'),
    'disconnectGattBeforeBond': RegExp(r'\bdisconnectGattBeforeBond\b'),
  };
  final createBondPattern = RegExp(r'\bcreateBond\s*\(');
  const conditionalFallbackFile = 'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java';
  const conditionalFallbackGuards = <String>[
    'CONDITIONAL_BOND_FALLBACK_DELAY_MS',
    'scheduleConditionalBondFallback',
    'securityGattStatusObserved',
    'BluetoothDevice.BOND_NONE',
    'tryMarkConditionalBondFallbackAttempted',
    'BirdBoxConditionalBondFallbackPolicy',
  ];
  for (final root in roots) {
    require(root.existsSync(), 'Production source root is missing: ${root.path}');
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !_isSourceFile(entity.path)) continue;
      final source = entity.readAsStringSync();
      for (final entry in forbidden.entries) {
        require(
          !entry.value.hasMatch(source),
          'Legacy pre-bond path ${entry.key} is forbidden in ${_relativePath(repositoryRoot, entity)}.',
        );
      }
      final createBondCount = createBondPattern.allMatches(source).length;
      if (createBondCount == 0) continue;
      final relativePath = _relativePath(repositoryRoot, entity).replaceAll('\\', '/');
      final guardedConditionalFallback = relativePath == conditionalFallbackFile && createBondCount == 1 && conditionalFallbackGuards.every(source.contains);
      require(
        guardedConditionalFallback,
        'Legacy pre-bond path BluetoothDevice.createBond is forbidden in $relativePath. '
        'Only the single audited post-security-write conditional fallback is allowed.',
      );
    }
  }
}

String? _namedBlock(String source, String name) {
  return _matchedBlock(
    source,
    RegExp('\\b${RegExp.escape(name)}\\s*\\{'),
  );
}

String? _matchedBlock(String source, RegExp startPattern) {
  final match = startPattern.firstMatch(source);
  if (match == null) return null;
  var depth = 1;
  for (var index = match.end; index < source.length; index++) {
    if (source[index] == '{') depth++;
    if (source[index] == '}') depth--;
    if (depth == 0) return source.substring(match.end, index);
  }
  return null;
}

final class _Options {
  const _Options({
    required this.evidencePath,
    required this.ble03EvidencePath,
    required this.apkPath,
    required this.manifestPath,
    required this.approvedCertificateSha256,
  });

  final String evidencePath;
  final String ble03EvidencePath;
  final String apkPath;
  final String manifestPath;
  final String approvedCertificateSha256;

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
      evidencePath: value(
        'evidence',
        'docs/acceptance/rc4-hf-ble-04-release.template.json',
      ),
      ble03EvidencePath: value('ble03-evidence', ''),
      apkPath: value(
        'apk',
        'build/app/outputs/flutter-apk/app-bird-release.apk',
      ),
      manifestPath: value(
        'manifest',
        'build/app/intermediates/merged_manifests/birdRelease/processBirdReleaseManifest/AndroidManifest.xml',
      ),
      approvedCertificateSha256: value('approved-certificate', ''),
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

Future<String> _git(
  Directory root,
  List<String> arguments,
  List<String> failures,
) async {
  final result = await Process.run('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) {
    failures.add('git ${arguments.join(' ')} failed.');
    return '';
  }
  return result.stdout.toString();
}

File _resolveFile(Directory root, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${root.path}${Platform.pathSeparator}$path');
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String _text(Object? value) => value?.toString().trim() ?? '';
bool _usableText(Object? value) =>
    _text(value).isNotEmpty &&
    !RegExp(
      r'(^|[^A-Z])(?:REQUIRED|TODO|PLACEHOLDER)(?:[^A-Z]|$)',
      caseSensitive: false,
    ).hasMatch(_text(value));
bool _sha40(Object? value) => RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(_text(value));
bool _sha256(Object? value) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(_text(value));

String _basename(String path) => path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final filePath = file.absolute.path.replaceAll('\\', '/');
  return filePath.startsWith('$rootPath/') ? filePath.substring(rootPath.length + 1) : file.path;
}

bool _isSourceFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.dart') || lower.endsWith('.java') || lower.endsWith('.kt') || lower.endsWith('.kts');
}

bool _isTextEvidence(File file) {
  final lower = file.path.toLowerCase();
  return const ['.json', '.log', '.txt', '.md', '.csv', '.yaml', '.yml'].any(
        lower.endsWith,
      ) &&
      file.lengthSync() <= 10 * 1024 * 1024;
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
  } else if (value is String &&
      RegExp(
        r'(^|[^A-Z])(?:REQUIRED|TODO|PLACEHOLDER)(?:[^A-Z]|$)',
        caseSensitive: false,
      ).hasMatch(value)) {
    yield path;
  }
}

Iterable<String> _findSensitiveFields(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final childPath = '$path.$key';
      if (RegExp(
            r'(password|passphrase|secret|pairing[_-]?(code|session)|access[_-]?token|refresh[_-]?token)',
            caseSensitive: false,
          ).hasMatch(key) &&
          _text(entry.value).isNotEmpty) {
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
