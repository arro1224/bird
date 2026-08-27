import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/ble_provisioning_rc4_acceptance.dart';

void main() {
  test('simulated RC4 acceptance emits a non-release ten-case report', () async {
    final report = await runBleProvisioningRc4Acceptance();
    final json = report.toJson();

    expect(json['result'], 'pass');
    expect(json['environment'], 'simulated');
    expect(json['releasable'], isFalse);
    expect(json['real_k7_status'], 'pending');
    expect(report.caseIds, [
      'SIM-01',
      'SIM-02',
      'SIM-03',
      'SIM-04',
      'SIM-05',
      'SIM-06',
      'SIM-07',
      'SIM-08',
      'SIM-09',
      'SIM-10',
    ]);
    expect(report.cases, everyElement(predicate<Map<String, Object?>>((value) => value['result'] == 'pass')));

    final serialized = jsonEncode(json);
    for (final secret in ['password', 'token', 'pairing_code', 'dpp://', 'AA:BB:CC']) {
      expect(serialized.toLowerCase(), isNot(contains(secret.toLowerCase())));
    }
  });

  test('rejects base URLs containing sensitive URI components', () async {
    for (final value in [
      'https://user:secret@example.test/box',
      'https://example.test/box?token=synthetic',
      'https://example.test/box#fragment',
    ]) {
      expect(
        () => runBleProvisioningRc4Acceptance(baseUri: Uri.parse(value)),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('aggregates a failed case into a failed report', () async {
    final report = await runBleProvisioningRc4Acceptance(
      runCase: (caseId) async => caseId != 'SIM-07',
    );

    expect(report.toJson()['result'], 'fail');
    expect(report.cases.singleWhere((value) => value['id'] == 'SIM-07')['result'], 'fail');
  });
}
