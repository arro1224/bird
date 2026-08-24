import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';
import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
const _pairingSessionId = 'ps_rc4_repository_test';
const _openRequest = '10000000-0000-4000-8000-000000000001';
const _authorizeRequest = '10000000-0000-4000-8000-000000000002';
const _apRequest = '10000000-0000-4000-8000-000000000003';
const _scanRequest = '10000000-0000-4000-8000-000000000004';
const _staRequest = '10000000-0000-4000-8000-000000000005';

void main() {
  group('A3 pairing ownership', () {
    late _Harness harness;

    setUp(() async {
      harness = await _Harness.create();
      await harness.connect();
    });

    tearDown(() => harness.close());

    test('pairing code stays on BLE and session is cleared on disconnect', () async {
      harness.ble.queueResponse(
        BleCommandType.openPairing,
        _event(
          ProvisioningEventType.pairingOpened,
          _openRequest,
          {
            'pairing_code_mode': 'fixed_dev',
            'code_expires_in': 600,
            'attempts_remaining': 3,
          },
        ),
      );
      harness.ble.queueResponse(
        BleCommandType.authorizePairing,
        _event(
          ProvisioningEventType.pairingAuthorized,
          _authorizeRequest,
          {
            'pairing_session_id': _pairingSessionId,
            'expires_in': 600,
          },
        ),
      );

      await harness.repository.openPairing();
      final authorization = await harness.repository.authorizePairing('246810');

      expect(
        harness.ble.requests.last.payload,
        {'pairing_code': '246810'},
      );
      expect(authorization.toString(), isNot(contains(_pairingSessionId)));

      await harness.repository.disconnect();
      await harness.connect();
      await expectLater(
        harness.repository.startDirectAp(),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.code,
            'code',
            ProvisioningErrorCode.authorizationRequired,
          ),
        ),
      );
    });
  });

  group('A4 AP/STA platform flow', () {
    late _Harness harness;

    setUp(() async {
      harness = await _Harness.create();
      await harness.connect();
      harness.ble.queueResponse(
        BleCommandType.openPairing,
        _event(
          ProvisioningEventType.pairingOpened,
          _openRequest,
          {
            'pairing_code_mode': 'fixed_dev',
            'code_expires_in': 600,
            'attempts_remaining': 3,
          },
        ),
      );
      harness.ble.queueResponse(
        BleCommandType.authorizePairing,
        _event(
          ProvisioningEventType.pairingAuthorized,
          _authorizeRequest,
          {
            'pairing_session_id': _pairingSessionId,
            'expires_in': 600,
          },
        ),
      );
      await harness.repository.openPairing();
      await harness.repository.authorizePairing('246810');
    });

    tearDown(() => harness.close());

    test('direct AP joins, binds, validates identity and exchanges token', () async {
      harness.ble.queueResponse(
        BleCommandType.startDirectAp,
        _event(
          ProvisioningEventType.commandAccepted,
          _apRequest,
          {
            'operation_id': 'op_direct_ap_test',
            'desired_mode': 'direct_ap',
            'provisioning_method': null,
          },
        ),
      );
      harness.wifi.queueJoinResult(
        const WifiJoinResult(
          outcome: WifiJoinOutcome.joined,
          network: BirdBoxWifiNetwork(
            handle: 'network-test-handle',
            ssid: 'BirdBox-82F41C9E',
          ),
        ),
      );

      final accepted = await harness.repository.startDirectAp();
      expect(accepted.operationId, 'op_direct_ap_test');

      final readyFuture = harness.repository.events.firstWhere(
        (event) => event.type == ProvisioningEventType.directApReady,
      );
      harness.ble.emitEvent(
        _event(
          ProvisioningEventType.directApReady,
          _apRequest,
          {
            'operation_id': 'op_direct_ap_test',
            'active_mode': 'direct_ap',
            'ssid': 'BirdBox-82F41C9E',
            'security': 'wpa2_personal',
            'passphrase': 'TEST_ONLY_NOT_A_REAL_SECRET',
            'gateway_ipv4': '192.168.82.1',
            'prefix_length': 24,
            'base_uri': harness.baseUri.toString(),
          },
        ),
      );
      await readyFuture.timeout(const Duration(seconds: 3));

      expect(harness.wifi.boundNetwork?.ssid, 'BirdBox-82F41C9E');
      expect(harness.server.lastRc4PairingClientId, _clientId);
      expect(harness.server.lastRc4PairingIncludedCode, isFalse);
      final credential = await harness.credentials.read(_deviceId);
      expect(credential?.clientId, _clientId);
      expect(credential?.baseUri, harness.baseUri);
    });

    test('scan batches aggregate out of order and STA config reuses token', () async {
      await harness.completeDirectApExchange();

      harness.ble.queueResponse(
        BleCommandType.scanWifi,
        _event(
          ProvisioningEventType.commandAccepted,
          _scanRequest,
          {
            'operation_id': 'op_scan_test',
            'desired_mode': 'infrastructure_sta',
            'provisioning_method': 'ble_scan_selection',
          },
        ),
      );
      await harness.repository.scanWifi();
      final resultsFuture = harness.repository.wifiScanResults.first;
      harness.ble.emitEvent(
        _event(
          ProvisioningEventType.wifiScanResults,
          _scanRequest,
          {
            'batch_index': 1,
            'batch_count': 2,
            'complete': true,
            'networks': [
              {
                'ssid': 'Studio',
                'bssid': 'AA:BB:CC:DD:EE:FF',
                'rssi_dbm': -45,
                'frequency_mhz': 5180,
                'security': 'wpa2_personal',
                'unsupported': false,
              },
            ],
          },
        ),
      );
      harness.ble.emitEvent(
        _event(
          ProvisioningEventType.wifiScanResults,
          _scanRequest,
          {
            'batch_index': 0,
            'batch_count': 2,
            'complete': false,
            'networks': [
              {
                'ssid': 'Studio',
                'bssid': 'aa:bb:cc:dd:ee:ff',
                'rssi_dbm': -70,
                'frequency_mhz': 2412,
                'security': 'wpa2_personal',
                'unsupported': false,
              },
              {
                'ssid': 'Guest',
                'bssid': '11:22:33:44:55:66',
                'rssi_dbm': -60,
                'frequency_mhz': 2412,
                'security': 'open',
                'unsupported': false,
              },
            ],
          },
        ),
      );

      final results = await resultsFuture.timeout(const Duration(seconds: 2));
      expect(results.map((item) => item.ssid), ['Studio', 'Guest']);
      expect(results.first.rssiDbm, -45);

      harness.ble.queueResponse(
        BleCommandType.setStaConfig,
        _event(
          ProvisioningEventType.commandAccepted,
          _staRequest,
          {
            'operation_id': 'op_sta_test',
            'desired_mode': 'infrastructure_sta',
            'provisioning_method': 'ble_manual',
          },
        ),
      );
      await harness.repository.setStaConfig(
        StaNetworkConfiguration(
          provisioningMethod: ProvisioningMethod.bleManual,
          selectionMethod: WifiSelectionMethod.manual,
          ssid: 'Studio',
          security: WifiSecurity.wpa2Personal,
          password: 'TEST_ONLY_NOT_A_REAL_SECRET',
          hidden: false,
          networkKind: StaNetworkKind.router,
        ),
      );

      final request = harness.ble.requests.last;
      final authorization = Map<String, dynamic>.from(
        request.payload['authorization'] as Map,
      );
      expect(authorization['type'], 'bearer_token');
      expect(request.payload['selection_method'], 'manual');
      expect(request.payload['bssid'], isNull);
      expect(request.toString(), isNot(contains('TEST_ONLY_NOT_A_REAL_SECRET')));
    });
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

  static Future<_Harness> create() async {
    final server = MockBoxServer(
      logRequests: false,
      deviceId: _deviceId,
      pairingSessionId: _pairingSessionId,
    );
    final baseUri = await server.start();
    final client = ApiClient();
    final deviceInfo = ProvisioningDeviceInfo.fromJson(
      _fixture('ble-device-info.rc4.json'),
    );
    final networkStatus =
        ProvisioningEvent.fromJson(
              _fixture('ble-network-status.rc4.json'),
            ).payload
            as ProvisioningNetworkStatus;
    final advertisement = BirdBoxAdvertisement(
      localName: 'BirdBox-82F41C9E',
      serviceUuids: const [BleProtocolConstants.serviceUuid],
      rssi: -40,
      platformDeviceId: 'opaque-android-handle',
    );
    final ble = FakeBirdBoxBleDataSource(
      deviceInfo: deviceInfo,
      networkStatus: networkStatus,
      advertisements: [advertisement],
    );
    final wifi = FakeBirdBoxWifiPlatform();
    final credentials = MemorySecureSessionStore();
    final repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: wifi,
      clientIdentityStore: MemoryClientIdentityStore(
        initialValue: _clientId,
      ),
      credentialStore: credentials,
      healthApi: HealthApi(client),
      pairingApi: PairingApi(client),
      requestIds: _SequenceRequestIdFactory(const [
        _openRequest,
        _authorizeRequest,
        _apRequest,
        _scanRequest,
        _staRequest,
      ]),
      clock: () => DateTime.utc(2026, 8, 24, 12),
    );
    return _Harness._(
      server: server,
      baseUri: baseUri,
      client: client,
      ble: ble,
      wifi: wifi,
      credentials: credentials,
      repository: repository,
    );
  }

  Future<void> connect() async {
    final device = await repository.discoverDevices().first;
    await repository.connect(device);
  }

  Future<void> completeDirectApExchange() async {
    ble.queueResponse(
      BleCommandType.startDirectAp,
      _event(
        ProvisioningEventType.commandAccepted,
        _apRequest,
        {
          'operation_id': 'op_direct_ap_setup',
          'desired_mode': 'direct_ap',
          'provisioning_method': null,
        },
      ),
    );
    wifi.queueJoinResult(
      const WifiJoinResult(
        outcome: WifiJoinOutcome.joined,
        network: BirdBoxWifiNetwork(
          handle: 'network-test-handle',
          ssid: 'BirdBox-82F41C9E',
        ),
      ),
    );
    await repository.startDirectAp();
    final readyFuture = repository.events.firstWhere(
      (event) => event.type == ProvisioningEventType.directApReady,
    );
    ble.emitEvent(
      _event(
        ProvisioningEventType.directApReady,
        _apRequest,
        {
          'operation_id': 'op_direct_ap_setup',
          'active_mode': 'direct_ap',
          'ssid': 'BirdBox-82F41C9E',
          'security': 'wpa2_personal',
          'passphrase': 'TEST_ONLY_NOT_A_REAL_SECRET',
          'gateway_ipv4': '192.168.82.1',
          'prefix_length': 24,
          'base_uri': baseUri.toString(),
        },
      ),
    );
    await readyFuture.timeout(const Duration(seconds: 3));
  }

  Future<void> close() async {
    await repository.dispose();
    await client.dispose();
    await server.close();
  }
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

final class _SequenceRequestIdFactory implements RequestIdFactory {
  _SequenceRequestIdFactory(this._values);

  final List<String> _values;
  var _index = 0;

  @override
  String create() => _values[_index++];
}
