import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../tool/ble11/bond_first_evidence_validator.dart';
import '../tool/ble22/capture_phone_flow.dart';

const _defaultScenario = String.fromEnvironment('BLE11_SCENARIO', defaultValue: 'bond_first');

void main({String? scenario, Future<String> Function()? scenarioResolver, Future<void> Function(Map<String, Object?>)? onEvidence}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bond-first production transport against virtual BirdBox', (tester) async {
    final _scenario = await scenarioResolver?.call() ?? scenario ?? _defaultScenario;
    expect(bondFirstScenarios, contains(_scenario));
    final diagnostics = _MemoryConnectionDiagnosticSink();
    final source = PlatformBirdBoxBleDataSource(
      connectionDiagnosticSink: diagnostics,
      scanSessionIdFactory: () => 'ble20-virtual-$_scenario',
      maximumWriteFragmentBytes: _scenario.startsWith('att_timeout_') ? 20 : 512,
    );
    addTearDown(source.dispose);
    Map<String, Object?>? build;
    ProvisioningDeviceInfo? info;
    var stage = 'build_identity';
    var commandAttempted = false;
    const request = BleCommandRequest(
      type: BleCommandType.openPairing,
      requestId: '550e8400-e29b-41d4-a716-446655440110',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );
    ProvisioningEvent? response;
    ProvisioningException? failure;
    late Map<String, Object?> evidence;
    await capturePhoneFlow<void>(
      operation: () async {
        build = await const MethodChannelBirdBoxBleDiagnosticFilePlatform().buildIdentity();
        stage = 'scan';
        final advertisement = await source.scan(timeout: const Duration(seconds: 15)).firstWhere((candidate) => candidate.localName == 'BirdBox-B1E11001').timeout(const Duration(seconds: 20));
        expect(advertisement.hasBirdBoxService, isTrue);
        stage = 'connect';
        await source.connect(advertisement);
        stage = 'device_info';
        info = await source.readDeviceInfo();
        expect(info!.deviceId, 'bbx-b1e11001b1e11001b1e11001b1e11001');
        stage = 'initial_notifications';
        await source.subscribeRequiredNotifications();
        stage = 'command';
        commandAttempted = true;
        try {
          response = await source.writeCommand(request);
        } on ProvisioningException catch (error) {
          failure = error;
        }
      },
      collect: (earlyFailure) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        evidence = <String, Object?>{
          'schema_version': 2, 'evidence_kind': 'virtual_birdbox_app', 'hardware_status': 'pending',
          'security_flow': 'bond_first', 'endpoint_kind': 'virtual_birdbox', 'scenario': _scenario,
          'build': build, 'capture_status': earlyFailure == null ? 'completed' : 'failed',
          'last_stage': stage, 'command_attempted': commandAttempted,
          if (earlyFailure != null) 'failure_stage': stage,
          if (earlyFailure != null) 'failure_kind': earlyFailure.runtimeType.toString(),
          if (commandAttempted) 'request_id': request.requestId,
          // Only hash the fixed public command when its execution was attempted.
          if (commandAttempted) 'message_sha256': sha256.convert(const BleMessageCodec().encodeRequest(request)).toString(),
          'test_fragment_bytes_limit': _scenario.startsWith('att_timeout_') ? 20 : 512,
          if (info != null) 'virtual_device': {'device_id': info!.deviceId, 'firmware_version': info!.firmwareVersion},
          'response_type': response?.type.wireValue,
          'failure_code': failure?.code.wireValue ?? (earlyFailure is ProvisioningException ? earlyFailure.code.wireValue : null),
          'events': diagnostics.events.map((event) => event.toJson()).toList(),
          'initial_bond_state': diagnostics.events.where((event) => event.eventType == 'user_start_pairing').firstOrNull?.bondState,
        };
        // ignore: avoid_print
        print('BLE11_SIMULATED_EVIDENCE ${jsonEncode(evidence)}');
        await onEvidence?.call(evidence);
      },
    );
    final success = const {
      'bond_first',
      'already_bonded',
      'auth_once',
      'att_timeout_first',
      'att_timeout_middle',
      'att_timeout_last',
      'response_delay',
      'response_duplicate',
    }.contains(_scenario);
    if (success) {
      expect(failure, isNull);
      expect(response?.type, ProvisioningEventType.pairingOpened);
      expect(response?.requestId, request.requestId);
    } else {
      expect(response, isNull);
      expect(failure, isNotNull);
      if (_scenario == 'auth_persistent') expect(failure?.code, ProvisioningErrorCode.bleEncryptedRetryFailed);
      if (_scenario == 'business_timeout' || _scenario == 'response_wrong') expect(failure?.code, ProvisioningErrorCode.pairingOpenTimeout);
    }
    final events = diagnostics.events.where((event) => event.requestId == request.requestId).toList();
    final initialBond = evidence['initial_bond_state'];
    if (_scenario == 'bond_first') expect(initialBond, 'not_bonded');
    if (_scenario == 'already_bonded') expect(initialBond, 'bonded');
    expect(events.where((event) => event.eventType == 'create_bond_invoked').length, initialBond == 'bonded' ? 0 : 1);
    final retries = events.where((event) => event.eventType == 'security_write_retrying').toList();
    expect(retries.length, _scenario == 'auth_once' || _scenario == 'auth_persistent' || _scenario.startsWith('att_timeout_') ? 1 : 0);
    expect(retries.every((event) => event.retryCount == 1), isTrue);
    expect(events.where((event) => event.eventType == (success ? 'command_succeeded' : 'command_failed')).length, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final class _MemoryConnectionDiagnosticSink implements BleConnectionDiagnosticSink {
  final List<BleConnectionDiagnosticEvent> events = [];
  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async {
    events.add(event);
  }
}
