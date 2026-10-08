import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(
    'bird_companion/birdbox_ble/methods',
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('preserves the native BLE state snapshot through JSON storage', () {
    final event = BleConnectionDiagnosticEvent.fromPlatform({
      'traceId': 'ble-scan-07',
      'occurredAtMs': 1790121600000,
      'eventType': 'platform_error',
      'packageId': 'deckers.thibault.aves.bird',
      'buildFlavor': 'bird',
      'buildType': 'debug',
      'appVersionName': '1.14.9',
      'appVersionCode': '174',
      'platformMethod': 'connect',
      'operationName': 'connect',
      'pendingOperation': 'none',
      'nativeState': 'gatt_present_not_ready',
      'securityPhase': 'bonding',
      'gattPresent': true,
      'linkReady': false,
      'scanning': false,
      'connectionGeneration': 3,
      'gattInstanceId': 1,
      'gattGeneration': 7,
      'bondState': 'not_bonded',
      'actualBondState': 'not_bonded',
      'conditionalBondFallbackAttempted': true,
      'bondInitiationSource': 'conditional_fallback',
      'securityGattStatusObserved': true,
      'attemptId': 'request-1:3:7:1000',
      'writeApiAccepted': true,
      'writeCallbackReceived': false,
      'securityWriteElapsedMs': 2000,
      'fallbackTrigger': 'write_callback_timeout',
      'bondStateAtTrigger': 'not_bonded',
      'createBondInvoked': true,
      'createBondReturned': true,
      'createBondStateBefore': 'not_bonded',
      'createBondStateAfter': 'bonding',
      'stateBefore': 'bonding',
      'stateAfter': 'bonded_recovering_gatt',
      'terminalOutcome': 'ble_pairing_timeout',
      'cleanupOutcome': 'complete',
      'errorCode': 'invalid_state',
      'sanitizedMessage': 'BirdBox GATT is already connected.',
    });

    final restored = BleConnectionDiagnosticEvent.fromJson(event.toJson());

    expect(restored.platformMethod, 'connect');
    expect(restored.packageId, 'deckers.thibault.aves.bird');
    expect(restored.buildFlavor, 'bird');
    expect(restored.buildType, 'debug');
    expect(restored.appVersionName, '1.14.9');
    expect(restored.appVersionCode, '174');
    expect(restored.pendingOperation, 'none');
    expect(restored.nativeState, 'gatt_present_not_ready');
    expect(restored.securityPhase, 'bonding');
    expect(restored.gattPresent, isTrue);
    expect(restored.linkReady, isFalse);
    expect(restored.connectionGeneration, 3);
    expect(restored.gattGeneration, 7);
    expect(restored.actualBondState, 'not_bonded');
    expect(restored.conditionalBondFallbackAttempted, isTrue);
    expect(restored.bondInitiationSource, 'conditional_fallback');
    expect(restored.securityGattStatusObserved, isTrue);
    expect(restored.attemptId, 'request-1:3:7:1000');
    expect(restored.writeApiAccepted, isTrue);
    expect(restored.writeCallbackReceived, isFalse);
    expect(restored.securityWriteElapsedMs, 2000);
    expect(restored.fallbackTrigger, 'write_callback_timeout');
    expect(restored.bondStateAtTrigger, 'not_bonded');
    expect(restored.createBondInvoked, isTrue);
    expect(restored.createBondReturned, isTrue);
    expect(restored.createBondStateBefore, 'not_bonded');
    expect(restored.createBondStateAfter, 'bonding');
    expect(restored.createBondException, isNull);
    expect(restored.stateBefore, 'bonding');
    expect(restored.stateAfter, 'bonded_recovering_gatt');
    expect(restored.terminalOutcome, 'ble_pairing_timeout');
    expect(restored.cleanupOutcome, 'complete');
    expect(restored.errorCode, 'invalid_state');
    expect(
      restored.sanitizedMessage,
      'BirdBox GATT is already connected.',
    );
  });

  test('legacy diagnostic JSON remains readable when BLE-14 fields are absent', () {
    final event = BleConnectionDiagnosticEvent.fromJson({
      'trace_id': 'legacy-trace',
      'occurred_at': '2026-10-05T00:00:00.000Z',
      'event_type': 'operation_failed',
      'source': 'android',
      'error_code': 'gatt_operation_failed',
    });

    expect(event.traceId, 'legacy-trace');
    expect(event.attemptId, isNull);
    expect(event.gattGeneration, isNull);
    expect(event.cleanupOutcome, isNull);
  });

  test('maps invalid_state with actionable fields and redacts its message', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(
        code: 'invalid_state',
        message:
            'password=hunter2 device=AA:BB:CC:DD:EE:FF '
            'DPP:K:PRIVATE;;',
        details: const {
          'platformMethod': 'connect',
          'operationName': 'connect',
          'pendingOperation': 'none',
          'nativeState': 'gatt_present_not_ready',
          'securityPhase': 'idle',
          'actualBondState': 'not_bonded',
          'gattPresent': true,
          'linkReady': false,
          'connectionGeneration': 2,
          'gattInstanceId': 1,
          'deviceAddressHash': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          'traceId': 'ble-scan-07',
        },
      );
    });
    final platform = MethodChannelBirdBoxBlePlatform();

    ProvisioningException? error;
    try {
      await platform.connect(
        'opaque-platform-handle',
        traceId: 'ble-scan-07',
      );
    } on ProvisioningException catch (value) {
      error = value;
    }

    expect(error, isNotNull);
    expect(error!.code, ProvisioningErrorCode.invalidRequest);
    expect(error.diagnosticMessage, contains('platformMethod=connect'));
    expect(
      error.diagnosticMessage,
      contains('nativeState=gatt_present_not_ready'),
    );
    expect(error.diagnosticMessage, contains('gattPresent=true'));
    expect(error.diagnosticMessage, contains('connectionGeneration=2'));
    expect(error.diagnosticMessage, contains('password=[REDACTED]'));
    expect(error.diagnosticMessage, contains('[REDACTED_MAC]'));
    expect(error.diagnosticMessage, contains('[REDACTED_DPP_URI]'));
    expect(error.diagnosticMessage, isNot(contains('hunter2')));
    expect(error.diagnosticMessage, isNot(contains('AA:BB:CC:DD:EE:FF')));
    expect(error.diagnosticMessage, isNot(contains('PRIVATE')));
    expect(error.diagnosticMessage, isNot(contains('opaque-platform-handle')));
  });

  test('maps stable and legacy BLE transport errors without using networkInternalError', () async {
    const expected = <String, ProvisioningErrorCode>{
      'ble_pairing_timeout': ProvisioningErrorCode.blePairingTimeout,
      'ble_bond_timeout': ProvisioningErrorCode.blePairingTimeout,
      'ble_gatt_operation_failed': ProvisioningErrorCode.bleGattOperationFailed,
      'gatt_operation_failed': ProvisioningErrorCode.bleGattOperationFailed,
      'ble_security_recovery_failed': ProvisioningErrorCode.bleSecurityRecoveryFailed,
      'location_service_disabled': ProvisioningErrorCode.locationServicesDisabled,
    };

    for (final entry in expected.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => throw PlatformException(code: entry.key),
      );
      final platform = MethodChannelBirdBoxBlePlatform();

      await expectLater(
        platform.connect('opaque-device', traceId: 'trace-1'),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
        reason: entry.key,
      );
    }
  });
}
