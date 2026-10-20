import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';
import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
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
  group('BLE-21 redemption and event ownership', () {
    test('HTTP handoff survives BLE disconnect before authorization exchange', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await harness.startAp();
      final ready = harness.repository.events.firstWhere((event) => event.type == ProvisioningEventType.directApReady);
      harness.ble.emitEvent(harness.apReady());
      await ready;
      await harness.repository.disconnect();
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 1);
      expect(await harness.credentials.read(_deviceId), isNotNull);
      expect(harness.wifi.requestedSsids, isEmpty);
    });
    test('deferred HTTP persistence retry needs no new network command', () async {
      final store = _FailOnceStore();
      final harness = await _Harness.create(credentialStore: store);
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      final cubit = NetworkProvisioningCubit(harness.repository);
      addTearDown(cubit.close);
      harness.ble.queueResponse(
        BleCommandType.startDirectAp,
        _event(ProvisioningEventType.commandAccepted, _apRequest, {
          'operation_id': 'op_direct_ap_setup',
          'desired_mode': 'direct_ap',
          'provisioning_method': null,
        }),
      );
      harness.wifi.queueJoinResult(
        const WifiJoinResult(
          outcome: WifiJoinOutcome.joined,
          network: BirdBoxWifiNetwork(handle: 'test', ssid: 'BirdBox-82F41C9E'),
        ),
      );
      await cubit.startDirectAp(harness.ble.deviceInfo);
      store.failNextWrite = true;
      final ready = harness.repository.events.firstWhere((event) => event.type == ProvisioningEventType.directApReady);
      harness.ble.emitEvent(harness.apReady());
      await ready;
      expect(harness.server.pairingExchangeCount, 0);
      await expectLater(harness.finishHttp(), throwsA(isA<ProvisioningCredentialSaveException>()));
      await harness.finishHttp();
      expect(cubit.state.phase, NetworkProvisioningPhase.success);
      expect(harness.server.pairingExchangeCount, 1);
      expect(harness.ble.requests.where((r) => r.type == BleCommandType.startDirectAp), hasLength(1));
    });
    test('save failure retries persistence without redeeming a consumed session', () async {
      final store = _FailOnceStore();
      final harness = await _Harness.create(credentialStore: store);
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      store.failNextWrite = true;
      await expectLater(harness.completeDirectApExchange(), throwsA(isA<ProvisioningCredentialSaveException>()));
      expect(harness.server.pairingExchangeCount, 1);
      expect(await store.read(_deviceId), isNull);
      await harness.finishHttp();
      expect(await store.read(_deviceId), isNotNull);
      expect(harness.server.pairingExchangeCount, 1);
    });

    test('same operation with stale request and duplicate terminal have no side effects', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await harness.startAp();
      final events = <ProvisioningEvent>[];
      final subscription = harness.repository.events.listen(events.add);
      addTearDown(subscription.cancel);
      harness.ble.emitEvent(harness.apReady(requestId: _scanRequest));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.wifi.requestedSsids, isEmpty);
      expect(harness.server.pairingExchangeCount, 0);
      final ready = harness.repository.events.first;
      harness.ble.emitEvent(harness.apReady());
      await ready;
      harness.ble.emitEvent(harness.apReady());
      harness.ble.emitEvent(
        _event(ProvisioningEventType.commandAccepted, _apRequest, {
          'operation_id': 'op_direct_ap_setup',
          'desired_mode': 'direct_ap',
          'provisioning_method': null,
        }),
      );
      harness.ble.emitEvent(harness.apReady());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.where((event) => event.terminal), hasLength(1));
      expect(harness.server.pairingExchangeCount, 0);
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 1);
    });

    test('superseded operation cannot redeem or overwrite the current one', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await harness.startAp();
      harness.ble.queueResponse(
        BleCommandType.startDirectAp,
        _event(ProvisioningEventType.commandAccepted, _scanRequest, {
          'operation_id': 'op_new_ap',
          'desired_mode': 'direct_ap',
          'provisioning_method': null,
        }),
      );
      await harness.repository.startDirectAp();
      harness.ble.emitEvent(harness.apReady());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.server.pairingExchangeCount, 0);
      final ready = harness.repository.events.first;
      harness.ble.emitEvent(harness.apReady(requestId: _scanRequest, operationId: 'op_new_ap'));
      await ready;
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 1);
    });

    test('HTTP failure requires fresh authorization instead of replaying session', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      harness.server.failNextPairingExchange = true;
      await expectLater(harness.completeDirectApExchange(), throwsA(isA<Exception>()));
      expect(harness.server.pairingExchangeCount, 1);
      await expectLater(
        harness.finishHttp(),
        throwsA(
          isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.authorizationRequired),
        ),
      );
      expect(harness.server.pairingExchangeCount, 1);
      harness.ble.queueResponse(
        BleCommandType.openPairing,
        _event(ProvisioningEventType.pairingOpened, _scanRequest, {
          'pairing_code_mode': 'fixed_dev',
          'code_expires_in': 600,
          'attempts_remaining': 3,
        }),
      );
      harness.ble.queueResponse(
        BleCommandType.authorizePairing,
        _event(ProvisioningEventType.pairingAuthorized, _staRequest, {
          'pairing_session_id': _pairingSessionId,
          'expires_in': 600,
        }),
      );
      await harness.repository.openPairing();
      await harness.repository.authorizePairing('246810');
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 2);
      expect(await harness.credentials.read(_deviceId), isNotNull);
    });

    test('HTTP identity mismatch fails before redemption', () async {
      final harness = await _Harness.create(httpDeviceId: 'bbx-11111111111111111111111111111111');
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await expectLater(
        harness.completeDirectApExchange(),
        throwsA(
          isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.deviceIdMismatch),
        ),
      );
      expect(harness.server.pairingExchangeCount, 0);
    });

    test('saved credential reconnects without a second HTTP redemption', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await harness.completeDirectApExchange();
      await harness.repository.disconnect();
      await harness.connect();
      expect(harness.repository.networkStatusResumeRequired, isTrue);
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 1);
    });

    test('unsolicited stale status and stale business failure cannot revive an operation', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.connect();
      await harness.authorize();
      await harness.startAp();
      final errors = <Object>[];
      final subscription = harness.repository.events.listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);
      harness.ble.emitError(
        const BleOperationFailure(
          requestId: _scanRequest,
          deviceId: _deviceId,
          error: ProvisioningException(code: ProvisioningErrorCode.apStartFailed, retryable: true),
        ),
      );
      final status = _fixture('ble-network-status.rc4.json');
      (status['payload'] as Map)['busy'] = true;
      (status['payload'] as Map)['operation_id'] = 'op_stale';
      harness.ble.emitEvent(ProvisioningEvent.fromJson(status));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors, isEmpty);
      final ready = harness.repository.events.first;
      harness.ble.emitEvent(harness.apReady());
      await ready;
      await harness.finishHttp();
      expect(harness.server.pairingExchangeCount, 1);
    });
  });
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

    test('does not stack a repository retry on the BLE security retry', () async {
      harness.ble.queueError(
        BleCommandType.openPairing,
        const ProvisioningException(
          code: ProvisioningErrorCode.bleEncryptedRetryFailed,
          retryable: true,
          diagnosticMessage: 'simulated exhausted encrypted retry',
        ),
      );
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

      await expectLater(
        harness.repository.openPairing(),
        throwsA(
          isA<ProvisioningException>().having(
            (error) => error.code,
            'code',
            ProvisioningErrorCode.bleEncryptedRetryFailed,
          ),
        ),
      );

      expect(
        harness.ble.requests.where(
          (request) => request.type == BleCommandType.openPairing,
        ),
        hasLength(1),
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

    test('direct AP readiness is forwarded before phone join; HTTP exchanges later', () async {
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

      expect(harness.wifi.boundNetwork, isNull);
      expect(harness.wifi.requestedSsids, isEmpty);
      expect(harness.server.pairingExchangeCount, 0);
      await harness.finishHttp();
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

    test('native Direct AP loss reaches the repository as a retryable error', () async {
      await harness.completeDirectApExchange();
      // Manual join no longer binds the process. Exercise a separately acquired
      // native local-only network to retain coverage of that optional bridge.
      await harness.wifi.bindProcessToNetwork(const BirdBoxWifiNetwork(handle: 'test-native-network', ssid: 'BirdBox-82F41C9E'));
      final errorExpectation = expectLater(
        harness.repository.events,
        emitsError(
          isA<ProvisioningException>().having((error) => error.code, 'code', ProvisioningErrorCode.networkInternalError).having((error) => error.retryable, 'retryable', isTrue),
        ),
      );

      harness.wifi.loseNetwork();

      await errorExpectation;
      expect(harness.wifi.boundNetwork, isNull);
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

  static Future<_Harness> create({MemorySecureSessionStore? credentialStore, String httpDeviceId = _deviceId}) async {
    final server = MockBoxServer(
      logRequests: false,
      deviceId: httpDeviceId,
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
    final credentials = credentialStore ?? MemorySecureSessionStore();
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

  Future<void> authorize() async {
    ble.queueResponse(
      BleCommandType.openPairing,
      _event(ProvisioningEventType.pairingOpened, _openRequest, {
        'pairing_code_mode': 'fixed_dev',
        'code_expires_in': 600,
        'attempts_remaining': 3,
      }),
    );
    ble.queueResponse(
      BleCommandType.authorizePairing,
      _event(ProvisioningEventType.pairingAuthorized, _authorizeRequest, {
        'pairing_session_id': _pairingSessionId,
        'expires_in': 600,
      }),
    );
    await repository.openPairing();
    await repository.authorizePairing('246810');
  }

  Future<void> startAp() async {
    ble.queueResponse(
      BleCommandType.startDirectAp,
      _event(ProvisioningEventType.commandAccepted, _apRequest, {
        'operation_id': 'op_direct_ap_setup',
        'desired_mode': 'direct_ap',
        'provisioning_method': null,
      }),
    );
    wifi.queueJoinResult(
      const WifiJoinResult(
        outcome: WifiJoinOutcome.joined,
        network: BirdBoxWifiNetwork(handle: 'test', ssid: 'BirdBox-82F41C9E'),
      ),
    );
    await repository.startDirectAp();
  }

  ProvisioningEvent apReady({String requestId = _apRequest, String operationId = 'op_direct_ap_setup'}) => _event(ProvisioningEventType.directApReady, requestId, {
    'operation_id': operationId,
    'active_mode': 'direct_ap',
    'ssid': 'BirdBox-82F41C9E',
    'security': 'wpa2_personal',
    'passphrase': 'TEST_ONLY_NOT_A_REAL_SECRET',
    'gateway_ipv4': '192.168.82.1',
    'prefix_length': 24,
    'base_uri': baseUri.toString(),
  });

  ProvisioningNetworkStatus terminalStatus() {
    final json = _fixture('ble-network-status.rc4.json');
    (json['payload'] as Map)['base_uri'] = baseUri.toString();
    (json['payload'] as Map)['operation_id'] = 'op_direct_ap_setup';
    return ProvisioningEvent.fromJson(json).payload as ProvisioningNetworkStatus;
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
    await finishHttp();
  }

  Future<void> finishHttp() => repository.prepareDirectApHttp(ProvisioningCompletion(deviceId: _deviceId, baseUri: baseUri, networkMode: ProvisioningNetworkMode.directAp), CancelToken());

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

final class _FailOnceStore extends MemorySecureSessionStore {
  bool failNextWrite = false;
  @override
  Future<void> write(SessionCredential credential) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('simulated secure storage failure');
    }
    await super.write(credential);
  }
}
