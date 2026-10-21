import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/ble22/phone_inspection_semantics.dart';

/// Uses the existing advertising peripheral. Never starts system pairing or
/// changes either endpoint's bond records. A legacy box is an observed blocker,
/// not a successful 0007 preflight run.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(stabilizePhoneInspectionSemantics(binding));
  const expectedName = String.fromEnvironment('BLE1019_PEER_NAME', defaultValue: 'BirdBox-B1E11001');
  const expectedId = String.fromEnvironment('BLE1019_PEER_ID', defaultValue: 'bbx-b1e11001b1e11001b1e11001b1e11001');

  testWidgets('inspect existing peripheral and use declared public preflight', (tester) async {
    final diagnostics = _Diagnostics();
    final platform = MethodChannelBirdBoxBlePlatform();
    final source = PlatformBirdBoxBleDataSource(platform: platform, connectionDiagnosticSink: diagnostics);
    final result = <String, Object?>{
      'schema_version': 1,
      'evidence_kind': 'existing_peripheral_inspection',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'e09_preflight_completed': false,
      'formal_acceptance': false,
      'status': 'running',
      'stage': 'build_identity',
    };
    (int, int)? inspectedOwner;
    try {
      result['app_build'] = await const MethodChannelBirdBoxBleDiagnosticFilePlatform().buildIdentity();
      result['stage'] = 'scan';
      final advertisement = await source.scan(timeout: const Duration(seconds: 15)).firstWhere((candidate) => candidate.localName == expectedName && candidate.hasBirdBoxService).timeout(const Duration(seconds: 20));
      result['stage'] = 'connect';
      await source.connect(advertisement);
      result['stage'] = 'public_device_info';
      final info = await source.readDeviceInfo();
      expect(info.deviceId, expectedId);
      result['peripheral'] = {'device_id': info.deviceId, 'firmware_version': info.firmwareVersion, 'pairing_preflight_v1': info.capabilities.pairingPreflightV1};
      final ownership = await platform.getGattOwnershipState(0);
      inspectedOwner = (ownership.connectionGeneration, ownership.gattInstanceId);
      final bond = await platform.getNativeBondState(ownership.connectionGeneration, platformDeviceId: advertisement.platformDeviceId!);
      result['initial_native_bond_state'] = bond.state.name;
      result['stage'] = 'capability_checked';
      if (!info.capabilities.pairingPreflightV1) {
        result['status'] = 'legacy_peripheral_requires_0007_upgrade';
      } else if (bond.state != NativeBondState.notBonded) {
        result['status'] = 'native_bond_none_required_for_public_preflight';
      } else {
        result['stage'] = 'production_prepare_connection';
        final prepared = await source.prepareConnection(advertisement, clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543');
        expect(prepared.deviceId, expectedId);
        final completed = diagnostics.events.where((event) => event.eventType == 'pairing_preflight_result' && event.resultCode == 'none');
        expect(completed, isNotEmpty);
        result['e09_preflight_completed'] = true;
        result['status'] = 'public_preflight_completed';
      }
    } catch (error) {
      result['status'] = 'failed';
      result['failure_kind'] = error.runtimeType.toString();
      rethrow;
    } finally {
      try {
        await source.disconnect();
        // The inspection can precede adoption of a native instance by the
        // public orchestrator. Clean up only the exact instance inspected here.
        if (inspectedOwner != null) {
          final remaining = await platform.getGattOwnershipState(inspectedOwner.$1);
          if (remaining.connected && remaining.connectionGeneration == inspectedOwner.$1 && remaining.gattInstanceId == inspectedOwner.$2 && !remaining.preparing && remaining.inflightRequest == null) {
            await platform.prepareControlledReconnect(requestId: 'inspection-cleanup', connectionGeneration: inspectedOwner.$1, gattInstanceId: inspectedOwner.$2, reason: 'inspection_complete');
          }
        }
        result['cleanup'] = 'completed';
      } catch (error) {
        result['cleanup'] = 'unconfirmed';
        result['cleanup_failure_kind'] = error.runtimeType.toString();
      }
      await source.dispose();
      result['events'] = diagnostics.events.map((event) => event.toJson()).toList();
      final bondCalls = diagnostics.events.where((event) => event.eventType == 'create_bond_invoked').length;
      result['create_bond_calls'] = bondCalls;
      final file = File('${Directory.systemTemp.parent.path}/files/ble1019-existing-peripheral-result.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(result), flush: true);
      // ignore: avoid_print
      print('BLE1019_EXISTING_PERIPHERAL ${jsonEncode(result)}');
      expect(bondCalls, 0);
      expect(result['cleanup'], 'completed');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

final class _Diagnostics implements BleConnectionDiagnosticSink {
  final events = <BleConnectionDiagnosticEvent>[];
  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async => events.add(event);
}
