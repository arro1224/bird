import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _scenario = String.fromEnvironment(
  'BLE11_SCENARIO',
  defaultValue: 'success',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BLE-11 production transport against the virtual BirdBox', (
    tester,
  ) async {
    expect(
      const {
        'success',
        'auto_bond',
        'fallback_once',
        'disconnect_once',
      },
      contains(_scenario),
    );
    final diagnostics = _MemoryConnectionDiagnosticSink();
    final source = PlatformBirdBoxBleDataSource(
      connectionDiagnosticSink: diagnostics,
      scanSessionIdFactory: () => 'ble11-simulated-$_scenario',
    );
    addTearDown(source.dispose);

    final advertisement = await source
        .scan(timeout: const Duration(seconds: 15))
        .firstWhere(
          (candidate) => candidate.localName == 'BirdBox-B1E11001',
        )
        .timeout(const Duration(seconds: 20));
    expect(advertisement.hasBirdBoxService, isTrue);
    expect(advertisement.platformDeviceId, isNotEmpty);

    await source.connect(advertisement);
    final info = await source.readDeviceInfo();
    expect(info.deviceId, 'bbx-b1e11001b1e11001b1e11001b1e11001');
    expect(info.deviceName, 'BirdBox-B1E11001');
    await source.subscribeRequiredNotifications();

    ProvisioningEvent? response;
    if (_scenario == 'disconnect_once') {
      await expectLater(
        source.writeCommand(_request('550e8400-e29b-41d4-a716-446655440111')),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await source.connect(advertisement);
      final reconnectedInfo = await source.readDeviceInfo();
      expect(reconnectedInfo.deviceId, info.deviceId);
      await source.subscribeRequiredNotifications();
      response = await source.writeCommand(
        _request('550e8400-e29b-41d4-a716-446655440112'),
      );
    } else {
      response = await source.writeCommand(
        _request('550e8400-e29b-41d4-a716-446655440110'),
      );
    }

    expect(response.type, ProvisioningEventType.pairingOpened);
    expect(
      response.requestId,
      anyOf(
        '550e8400-e29b-41d4-a716-446655440110',
        '550e8400-e29b-41d4-a716-446655440112',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final eventTypes = diagnostics.events.map((event) => event.eventType).toList(growable: false);
    expect(eventTypes, contains('notifications_ready'));
    expect(eventTypes, contains('command_succeeded'));
    if (_scenario == 'auto_bond') {
      expect(eventTypes, contains('security_recovery_completed'));
      expect(eventTypes, isNot(contains('conditional_bond_fallback_started')));
      _expectOneEncryptedRetry(diagnostics.events);
    } else if (_scenario == 'fallback_once') {
      expect(eventTypes, contains('conditional_bond_fallback_started'));
      expect(eventTypes, contains('security_recovery_completed'));
      _expectOneEncryptedRetry(diagnostics.events);
    } else if (_scenario == 'disconnect_once') {
      expect(eventTypes, contains('disconnected'));
      final generations = diagnostics.events.where((event) => event.connectionGeneration != null).map((event) => event.connectionGeneration!).toSet();
      expect(generations.length, greaterThanOrEqualTo(2));
    }

    final evidence = <String, Object?>{
      'schema_version': 1,
      'evidence_kind': 'simulated',
      'hardware_status': 'pending',
      'scenario': _scenario,
      'virtual_device': {
        'device_id': info.deviceId,
        'device_name': info.deviceName,
        'firmware_version': info.firmwareVersion,
      },
      'response_type': response.type.wireValue,
      'connection_generations': diagnostics.events.where((event) => event.connectionGeneration != null).map((event) => event.connectionGeneration!).toSet().toList()..sort(),
      'gatt_instances': diagnostics.events.where((event) => event.gattInstanceId != null).map((event) => event.gattInstanceId!).toSet().toList()..sort(),
      'events': diagnostics.events.map((event) => event.toJson()).toList(growable: false),
    };
    // The host runner extracts only this prefixed, already-redacted JSON line.
    // It must never be promoted to real-hardware evidence.
    // ignore: avoid_print
    print('BLE11_SIMULATED_EVIDENCE ${jsonEncode(evidence)}');
  });
}

BleCommandRequest _request(String requestId) => BleCommandRequest(
  type: BleCommandType.openPairing,
  requestId: requestId,
  clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
);

void _expectOneEncryptedRetry(
  List<BleConnectionDiagnosticEvent> events,
) {
  final retryEvents = events.where((event) => event.eventType == 'security_write_retrying').toList(growable: false);
  expect(retryEvents, hasLength(1));
  expect(retryEvents.single.retryCount, 1);
  expect(
    events.any(
      (event) => event.gattRebuilt == true && event.connectionGeneration != null && event.gattInstanceId != null,
    ),
    isTrue,
  );
}

final class _MemoryConnectionDiagnosticSink implements BleConnectionDiagnosticSink {
  final List<BleConnectionDiagnosticEvent> events = [];

  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async {
    events.add(event);
  }
}
