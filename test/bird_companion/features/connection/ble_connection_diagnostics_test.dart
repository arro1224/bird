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
      'bondState': 'not_bonded',
      'actualBondState': 'not_bonded',
      'conditionalBondFallbackAttempted': true,
      'bondInitiationSource': 'conditional_fallback',
      'securityGattStatusObserved': true,
      'errorCode': 'invalid_state',
      'sanitizedMessage': 'BirdBox GATT is already connected.',
    });

    final restored = BleConnectionDiagnosticEvent.fromJson(event.toJson());

    expect(restored.platformMethod, 'connect');
    expect(restored.pendingOperation, 'none');
    expect(restored.nativeState, 'gatt_present_not_ready');
    expect(restored.securityPhase, 'bonding');
    expect(restored.gattPresent, isTrue);
    expect(restored.linkReady, isFalse);
    expect(restored.connectionGeneration, 3);
    expect(restored.actualBondState, 'not_bonded');
    expect(restored.conditionalBondFallbackAttempted, isTrue);
    expect(restored.bondInitiationSource, 'conditional_fallback');
    expect(restored.securityGattStatusObserved, isTrue);
    expect(restored.errorCode, 'invalid_state');
    expect(
      restored.sanitizedMessage,
      'BirdBox GATT is already connected.',
    );
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
}
