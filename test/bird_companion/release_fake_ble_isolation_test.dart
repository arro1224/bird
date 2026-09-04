import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks dependency path, helper wiring and executable gate', () {
    final gate = File(
      'tool/release/verify_production_integrity.dart',
    ).readAsStringSync();

    const realNeedles = [
      'PlatformBirdBoxBleDataSource()',
      'MethodChannelBirdBoxWifiPlatform()',
      'MethodChannelBirdBoxDppPlatform()',
      'rememberDynamicAddress:',
      'restoreSavedSession()',
      'Future<void> completeProvisioning(',
      'deviceSessionCubit.setConnectedFromStatus(status)',
    ];
    const fakeNeedles = [
      'FakeBirdBox',
      'FakeProvisioningRepository',
    ];

    expect(
      gate,
      contains(
        "const dependencyPath = 'lib/bird_companion/app/app_dependencies.dart';",
      ),
      reason: 'production gate must inspect the production dependency graph',
    );

    for (final needle in realNeedles) {
      expect(
        gate,
        matches(_gateCall('_requireContains', needle)),
        reason: 'production gate must require real dependency: $needle',
      );
    }
    for (final needle in fakeNeedles) {
      expect(
        gate,
        matches(_gateCall('_forbid', needle)),
        reason: 'production gate must forbid fake dependency: $needle',
      );
    }

    expect(
      gate,
      contains(
        'onProvisioningCompleted: dependencies.completeProvisioning',
      ),
      reason: 'production gate must require the session hand-off wiring',
    );
    expect(
      gate,
      contains('onProvisioningCompleted: onProvisioningCompleted'),
      reason: 'production gate must require router forwarding',
    );
    expect(
      gate,
      contains('widget.repository.disconnect()'),
      reason: 'production gate must require unfinished-flow cleanup',
    );
    for (final needle in const [
      'DppAvailabilityRepository',
      'checkDppAvailability()',
      '_dpp.checkCapability()',
      '使用手机安全共享 Wi-Fi',
      '扫描 Wi-Fi 二维码',
      '选择或手动输入网络',
      'WifiQrScannerPage()',
      'parseWifiQrCredentials',
    ]) {
      expect(
        gate,
        contains(needle),
        reason: 'production gate must lock the B2 requirement: $needle',
      );
    }

    final result = Process.runSync(
      _dartExecutableForFlutterTest(),
      ['tool/release/verify_production_integrity.dart'],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('PASS'));
    expect(result.stderr, isEmpty);
  });
}

RegExp _gateCall(String helper, String needle) {
  return RegExp(
    '^\\s*${RegExp.escape(helper)}\\s*'
    '\\(\\s*failures\\s*,\\s*dependencyPath\\s*,\\s*'
    "'${RegExp.escape(needle)}'\\s*,",
    multiLine: true,
  );
}

String _dartExecutableForFlutterTest() {
  final flutterCache = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent;
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  return File(
    '${flutterCache.path}${Platform.pathSeparator}'
    'dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}'
    '$executableName',
  ).path;
}
