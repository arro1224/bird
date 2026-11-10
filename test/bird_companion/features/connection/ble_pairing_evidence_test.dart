import 'package:aves/bird_companion/features/connection/domain/ble_pairing_evidence.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v10-9 无预检请求/结果、无 createBond 证据时不得判用户拒绝', () {
    const evidence = BlePairingEvidence(preflightRequested: false, preflightResultReceived: false, createBondInvoked: false);
    expect(evidence.attributableToUserRejection, isFalse);
    expect(evidence.bondDisappearedCode, ProvisioningErrorCode.bleBondLost);
    expect(evidence.bondDisappearedDiagnostic, contains('without_rejection_evidence'));
  });

  test('v10-9 只有 App 真有本轮预检请求与结果，或原生主动 createBond，才允许判拒绝', () {
    expect(
      const BlePairingEvidence(preflightRequested: true, preflightResultReceived: true, createBondInvoked: false).bondDisappearedCode,
      ProvisioningErrorCode.blePairingRejected,
    );
    expect(
      const BlePairingEvidence(preflightRequested: false, preflightResultReceived: false, createBondInvoked: true).bondDisappearedCode,
      ProvisioningErrorCode.blePairingRejected,
    );
    expect(
      const BlePairingEvidence(preflightRequested: true, preflightResultReceived: false, createBondInvoked: false).attributableToUserRejection,
      isFalse,
    );
  });
}
