import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production integrity gate enforces real BLE wiring and forbids fakes', () {
    final gate = File(
      'tool/release/verify_production_integrity.dart',
    ).readAsStringSync();

    const requiredChecks = [
      'PlatformBirdBoxBleDataSource()',
      'MethodChannelBirdBoxWifiPlatform()',
      'MethodChannelBirdBoxDppPlatform()',
      'rememberDynamicAddress:',
      'restoreSavedSession()',
      'FakeBirdBox',
      'FakeProvisioningRepository',
    ];

    for (final check in requiredChecks) {
      expect(gate, contains(check), reason: 'missing production gate check: $check');
    }
  });
}
