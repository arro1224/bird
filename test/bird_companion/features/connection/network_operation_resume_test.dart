import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';
import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
const _currentOperation = 'op_current_after_reconnect';

void main() {
  test('BLE reconnect queries status and ignores every stale operation event', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final device = await harness.repository.discoverDevices().first;
    await harness.repository.connect(device);
    await harness.repository.disconnect();

    harness.ble.queueResponse(
      BleCommandType.getNetworkStatus,
      _event(
        ProvisioningEventType.networkStatus,
        '30000000-0000-4000-8000-000000000001',
        _busyStatus(),
      ),
    );
    await harness.repository.connect(device);

    expect(
      harness.ble.requests.last.type,
      BleCommandType.getNetworkStatus,
    );
    final current = harness.repository.events.firstWhere(
      (event) => event.operationId == _currentOperation,
    );
    harness.ble.emitLateEvent(
      _event(
        ProvisioningEventType.networkProgress,
        '30000000-0000-4000-8000-000000000099',
        {
          'operation_id': 'op_stale_before_reconnect',
          'operation_state': 'connecting_sta',
          'provisioning_method': 'ble_manual',
        },
      ),
    );
    harness.ble.emitEvent(
      _event(
        ProvisioningEventType.networkProgress,
        '30000000-0000-4000-8000-000000000001',
        {
          'operation_id': _currentOperation,
          'operation_state': 'obtaining_ip',
          'provisioning_method': 'ble_manual',
        },
      ),
    );

    expect(
      (await current.timeout(const Duration(seconds: 2))).operationId,
      _currentOperation,
    );
  });

  test('stop direct AP always requests previous STA restoration', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final device = await harness.repository.discoverDevices().first;
    await harness.repository.connect(device);
    harness.ble.queueResponse(
      BleCommandType.stopDirectAp,
      _event(
        ProvisioningEventType.commandAccepted,
        '30000000-0000-4000-8000-000000000001',
        {
          'operation_id': 'op_stop_direct_ap',
          'desired_mode': 'infrastructure_sta',
          'provisioning_method': null,
        },
      ),
    );

    await harness.repository.stopDirectAp();

    expect(
      harness.ble.requests.last.payload['restore_previous_sta'],
      isTrue,
    );
  });

  test('failed STA recovery rejoins the returned AP and relocates session', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final device = await harness.repository.discoverDevices().first;
    await harness.repository.connect(device);
    harness.ble.queueResponse(
      BleCommandType.setStaConfig,
      _event(
        ProvisioningEventType.commandAccepted,
        '30000000-0000-4000-8000-000000000001',
        {
          'operation_id': 'op_sta_with_ap_rollback',
          'desired_mode': 'infrastructure_sta',
          'provisioning_method': 'ble_manual',
        },
      ),
    );
    await harness.repository.setStaConfig(
      StaNetworkConfiguration(
        provisioningMethod: ProvisioningMethod.bleManual,
        selectionMethod: WifiSelectionMethod.manual,
        ssid: 'Target-WiFi',
        security: WifiSecurity.wpa2Personal,
        password: 'test-only-password',
        hidden: false,
        networkKind: StaNetworkKind.router,
      ),
    );
    harness.wifi.queueJoinResult(
      const WifiJoinResult(
        outcome: WifiJoinOutcome.joined,
        network: BirdBoxWifiNetwork(
          handle: 'recovered-ap-network',
          ssid: 'BirdBox-82F41C9E',
        ),
      ),
    );
    final recovered = harness.repository.events.firstWhere(
      (event) => event.type == ProvisioningEventType.networkRecovered,
    );
    harness.ble.emitEvent(
      _event(
        ProvisioningEventType.networkRecovered,
        '30000000-0000-4000-8000-000000000001',
        {
          'operation_id': 'op_sta_with_ap_rollback',
          'active_mode': 'direct_ap',
          'operation_state': 'ap_ready',
          'recovered_mode': 'direct_ap',
          'recovery_reason': 'previous_sta_connect_failed',
          'ssid': 'BirdBox-82F41C9E',
          'security': 'wpa2_personal',
          'passphrase': 'test-only-ap-password',
          'gateway_ipv4': '192.168.82.1',
          'prefix_length': 24,
          'base_uri': harness.baseUri.toString(),
        },
      ),
    );

    await recovered.timeout(const Duration(seconds: 3));
    expect(harness.wifi.boundNetwork?.handle, 'recovered-ap-network');
    expect(harness.rememberedBaseUri, harness.baseUri);
    expect(harness.rememberedMode, ProvisioningNetworkMode.directAp);
    expect((await harness.credentials.read(_deviceId))?.baseUri, harness.baseUri);
  });
}

final class _Harness {
  _Harness._({
    required this.server,
    required this.baseUri,
    required this.client,
    required this.ble,
    required this.wifi,
    required this.credentials,
    required this.repository,
  });

  final MockBoxServer server;
  final Uri baseUri;
  final ApiClient client;
  final FakeBirdBoxBleDataSource ble;
  final FakeBirdBoxWifiPlatform wifi;
  final MemorySecureSessionStore credentials;
  final ProvisioningRepositoryImpl repository;
  Uri? rememberedBaseUri;
  ProvisioningNetworkMode? rememberedMode;

  static Future<_Harness> create() async {
    final info = ProvisioningDeviceInfo.fromJson(
      _fixture('ble-device-info.rc4.json'),
    );
    final status =
        ProvisioningEvent.fromJson(
              _fixture('ble-network-status.rc4.json'),
            ).payload
            as ProvisioningNetworkStatus;
    final ble = FakeBirdBoxBleDataSource(
      deviceInfo: info,
      networkStatus: status,
      advertisements: [
        BirdBoxAdvertisement(
          localName: 'BirdBox-82F41C9E',
          serviceUuids: const [BleProtocolConstants.serviceUuid],
          rssi: -41,
          platformDeviceId: 'opaque-resume-device',
        ),
      ],
    );
    final credentials = MemorySecureSessionStore();
    await credentials.write(
      SessionCredential(
        deviceId: _deviceId,
        baseUri: Uri.parse('http://192.168.4.1:8080'),
        accessToken: 'test-token-not-a-real-secret',
        expiresAt: DateTime.utc(2026, 9, 25),
        apiVersion: 'v1',
        clientId: _clientId,
      ),
    );
    final server = MockBoxServer(
      deviceId: _deviceId,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final baseUri = await server.start();
    final client = ApiClient();
    final wifi = FakeBirdBoxWifiPlatform();
    late final _Harness harness;
    final repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: wifi,
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(
        initialValue: _clientId,
      ),
      credentialStore: credentials,
      healthApi: HealthApi(client),
      pairingApi: PairingApi(client),
      rememberDynamicAddress: (deviceId, uri, mode) async {
        harness.rememberedBaseUri = uri;
        harness.rememberedMode = mode;
      },
      requestIds: _SequentialIds(),
      clock: () => DateTime.utc(2026, 8, 25),
    );
    harness = _Harness._(
      server: server,
      baseUri: baseUri,
      client: client,
      ble: ble,
      wifi: wifi,
      credentials: credentials,
      repository: repository,
    );
    return harness;
  }

  Future<void> close() async {
    await repository.dispose();
    await client.dispose();
    await server.close();
  }
}

final class _SequentialIds implements RequestIdFactory {
  var _value = 0;

  @override
  String create() {
    _value++;
    return '30000000-0000-4000-8000-${_value.toString().padLeft(12, '0')}';
  }
}

Map<String, dynamic> _busyStatus() {
  final envelope = _fixture('ble-network-status.rc4.json');
  final status = Map<String, dynamic>.from(envelope['payload'] as Map);
  status
    ..['desired_mode'] = 'infrastructure_sta'
    ..['operation_state'] = 'connecting_sta'
    ..['operation_id'] = _currentOperation
    ..['busy'] = true;
  return status;
}

ProvisioningEvent _event(
  ProvisioningEventType type,
  String requestId,
  Map<String, dynamic> payload,
) => ProvisioningEvent.fromJson({
  'protocol_version': BleProtocolConstants.protocolVersion,
  'type': type.wireValue,
  'request_id': requestId,
  'device_id': _deviceId,
  'ok': true,
  'payload': payload,
});

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File('test/contracts/fixtures/$name').readAsStringSync(),
      )
      as Map,
);
