import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
const _sessionId = 'ps_a5_repository_test';
const _openRequest = '20000000-0000-4000-8000-000000000001';
const _authorizeRequest = '20000000-0000-4000-8000-000000000002';
const _dppRequest = '20000000-0000-4000-8000-000000000003';
const _cancelRequest = '20000000-0000-4000-8000-000000000004';
const _operationId = 'op_dpp_a5_test';

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _Harness.create();
    await harness.connectAndAuthorize();
  });

  tearDown(() => harness.close());

  test('merges authenticated box and Android DPP capabilities before display', () async {
    final availability = await harness.repository.checkDppAvailability();

    expect(availability.boxSupported, isTrue);
    expect(availability.apiLevelSupported, isTrue);
    expect(availability.easyConnectSupported, isTrue);
    expect(availability.activityAvailable, isTrue);
    expect(availability.sessionReady, isTrue);
    expect(availability.supported, isTrue);
  });

  test('merged DPP availability fails closed when Easy Connect is unavailable', () async {
    harness.dpp.capability = const DppCapability(
      apiLevelSupported: true,
      easyConnectSupported: false,
      activityAvailable: true,
    );

    final availability = await harness.repository.checkDppAvailability();

    expect(availability.boxSupported, isTrue);
    expect(availability.easyConnectSupported, isFalse);
    expect(availability.supported, isFalse);
  });

  test('launches Easy Connect for matching DPP bootstrap and clears URI', () async {
    harness.dpp.queueLaunchResult(
      const DppLaunchResult(outcome: DppLaunchOutcome.systemAccepted),
    );
    harness.queueDppStart();
    await harness.repository.startDppProvisioning();

    final bootstrap = harness.repository.events.firstWhere(
      (event) => event.type == ProvisioningEventType.dppBootstrapReady,
    );
    harness.ble.emitEvent(harness.bootstrapEvent());
    await bootstrap.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(harness.dpp.launchCount, 1);
    expect(harness.dpp.clearCount, 1);
    expect(
      harness.ble.requests.where(
        (request) => request.type == BleCommandType.cancelNetworkOperation,
      ),
      isEmpty,
    );
  });

  test('cancels the box operation when user cancels the system dialog', () async {
    harness.dpp.queueLaunchResult(
      const DppLaunchResult(outcome: DppLaunchOutcome.userCancelled),
    );
    harness.queueDppStart();
    harness.ble.queueResponse(
      BleCommandType.cancelNetworkOperation,
      _event(
        ProvisioningEventType.commandAccepted,
        _cancelRequest,
        {
          'operation_id': _operationId,
          'desired_mode': 'infrastructure_sta',
          'provisioning_method': 'android_dpp',
        },
      ),
    );
    await harness.repository.startDppProvisioning();

    final bootstrap = harness.repository.events.firstWhere(
      (event) => event.type == ProvisioningEventType.dppBootstrapReady,
    );
    harness.ble.emitEvent(harness.bootstrapEvent());
    await bootstrap.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final cancel = harness.ble.requests.last;
    expect(cancel.type, BleCommandType.cancelNetworkOperation);
    expect(cancel.payload['operation_id'], _operationId);
    expect(harness.dpp.clearCount, 1);
  });

  test('rejects DPP before BLE command when phone capability is unavailable', () async {
    harness.dpp.capability = const DppCapability(
      apiLevelSupported: true,
      easyConnectSupported: false,
      activityAvailable: true,
    );

    await expectLater(
      harness.repository.startDppProvisioning(),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.phoneDppNotSupported,
        ),
      ),
    );
    expect(
      harness.ble.requests.where(
        (request) => request.type == BleCommandType.startDppProvisioning,
      ),
      isEmpty,
    );
  });
}

final class _Harness {
  _Harness._({
    required this.client,
    required this.ble,
    required this.dpp,
    required this.repository,
  });

  final ApiClient client;
  final FakeBirdBoxBleDataSource ble;
  final FakeBirdBoxDppPlatform dpp;
  final ProvisioningRepositoryImpl repository;

  static Future<_Harness> create() async {
    final infoJson = _fixture('ble-device-info.rc4.json');
    final capabilities =
        Map<String, dynamic>.from(
            infoJson['capabilities'] as Map,
          )
          ..['dpp_enrollee_supported'] = true
          ..['dpp_supported_akm'] = ['psk'];
    infoJson['capabilities'] = capabilities;
    final networkStatus =
        ProvisioningEvent.fromJson(
              _fixture('ble-network-status.rc4.json'),
            ).payload
            as ProvisioningNetworkStatus;
    final ble = FakeBirdBoxBleDataSource(
      deviceInfo: ProvisioningDeviceInfo.fromJson(infoJson),
      networkStatus: networkStatus,
      advertisements: [
        BirdBoxAdvertisement(
          localName: 'BirdBox-82F41C9E',
          serviceUuids: const [BleProtocolConstants.serviceUuid],
          rssi: -40,
          platformDeviceId: 'opaque-a5-device',
        ),
      ],
    );
    final dpp = FakeBirdBoxDppPlatform(
      capability: const DppCapability(
        apiLevelSupported: true,
        easyConnectSupported: true,
        activityAvailable: true,
      ),
    );
    final client = ApiClient();
    final repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: dpp,
      clientIdentityStore: MemoryClientIdentityStore(
        initialValue: _clientId,
      ),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(client),
      pairingApi: PairingApi(client),
      requestIds: _SequenceRequestIdFactory(const [
        _openRequest,
        _authorizeRequest,
        _dppRequest,
        _cancelRequest,
      ]),
      clock: () => DateTime.utc(2026, 8, 25, 12),
    );
    return _Harness._(
      client: client,
      ble: ble,
      dpp: dpp,
      repository: repository,
    );
  }

  Future<void> connectAndAuthorize() async {
    final device = await repository.discoverDevices().first;
    await repository.connect(device);
    ble.queueResponse(
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
    ble.queueResponse(
      BleCommandType.authorizePairing,
      _event(
        ProvisioningEventType.pairingAuthorized,
        _authorizeRequest,
        {
          'pairing_session_id': _sessionId,
          'expires_in': 600,
        },
      ),
    );
    await repository.openPairing();
    await repository.authorizePairing('246810');
  }

  void queueDppStart() {
    ble.queueResponse(
      BleCommandType.startDppProvisioning,
      _event(
        ProvisioningEventType.commandAccepted,
        _dppRequest,
        {
          'operation_id': _operationId,
          'desired_mode': 'infrastructure_sta',
          'provisioning_method': 'android_dpp',
        },
      ),
    );
  }

  ProvisioningEvent bootstrapEvent() => _event(
    ProvisioningEventType.dppBootstrapReady,
    _dppRequest,
    {
      'operation_id': _operationId,
      'operation_state': 'waiting_dpp_configurator',
      'dpp_uri': 'DPP:K:TEST_PUBLIC_BOOTSTRAP_KEY;C:81/1;;',
      'expires_in_seconds': 120,
    },
  );

  Future<void> close() async {
    await repository.dispose();
    await client.dispose();
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
