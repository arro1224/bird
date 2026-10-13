import 'package:flutter_test/flutter_test.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_critical_event_policy.dart';
import '../../../tool/ble22/capture_phone_flow.dart';
import 'ble20_bond_first_evidence_test.dart' show fixture;
import '../../../tool/ble11/bond_first_evidence_validator.dart';

void main() {
  test('early connection failure still collects evidence and preserves original failure', () async {
    final failure = StateError('connection');
    Object? collected;
    await expectLater(
      capturePhoneFlow<void>(
        operation: () async => throw failure,
        collect: (error) async {
          collected = error;
        },
      ),
      throwsA(same(failure)),
    );
    expect(collected, same(failure));
  });
  test('failed export cannot hide an earlier transport failure', () async {
    final failure = StateError('scan');
    await expectLater(capturePhoneFlow<void>(operation: () async => throw failure, collect: (_) async => throw const FormatException('export')), throwsA(same(failure)));
  });
  test('successful flow requires export to finish', () async {
    await expectLater(capturePhoneFlow<int>(operation: () async => 1, collect: (_) async => throw const FormatException('export')), throwsFormatException);
  });
  test('successful flow collects once and returns its value', () async {
    var calls = 0;
    expect(
      await capturePhoneFlow<int>(
        operation: () async => 3,
        collect: (error) async {
          expect(error, isNull);
          calls++;
        },
      ),
      3,
    );
    expect(calls, 1);
  });
  test('service-discovery platform fields survive saved JSON round trip', () {
    final event = BleConnectionDiagnosticEvent.fromPlatform({
      'eventType': 'gatt_service_discovery_api_returned',
      'occurredAtMs': 1,
      'traceId': 'trace',
      'serviceDiscoveryApiAccepted': true,
      'serviceDiscoveryElapsedMs': 41,
      'preparationElapsedMs': 42,
      'callbackGattIdentity': 123,
      'callbackGattIsCurrent': false,
      'resultCode': 'accepted',
    });
    final restored = BleConnectionDiagnosticEvent.fromJson(event.toJson());
    expect(restored.serviceDiscoveryApiAccepted, true);
    expect(restored.serviceDiscoveryElapsedMs, 41);
    expect(restored.preparationElapsedMs, 42);
    expect(restored.callbackGattIdentity, 123);
    expect(restored.callbackGattIsCurrent, false);
    expect(BleCriticalEventPolicy.isCritical(event.toJson()), true);
  });
  test('plausible command evidence cannot conceal a pre-command failure', () {
    final value = fixture('bond_first', phone: true);
    final app = value['app_evidence'] as Map<String, Object?>;
    app.addAll({'capture_status': 'failed', 'command_attempted': false, 'failure_stage': 'initial_notifications'});
    expect(validateBondFirstEvidence(value), contains('early scan/connect/notification failures cannot count as scenario acceptance.'));
  });
  test('runner startup failure cannot pass by borrowing complete App events', () {
    final value = fixture('bond_first', phone: true)..['run_status'] = 'startup_failed';
    expect(validateBondFirstEvidence(value), contains('phone runner did not complete all required checks.'));
  });
}
