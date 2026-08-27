import 'package:flutter_test/flutter_test.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

import '../../../../tool/acceptance/ble_provisioning_rc4_acceptance.dart';
import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

void main() {
  test('simulated RC4 cases report bounded fake-adapter checks', () async {
    final report = await runBleProvisioningRc4Acceptance();

    expect(report.cases, hasLength(10));
    for (final entry in report.cases) {
      expect(entry['result'], 'pass', reason: entry['id'] as String);
      final checks = entry['checks'];
      expect(checks, isA<List<Object?>>(), reason: entry['id'] as String);
      expect((checks as List<Object?>), isNotEmpty, reason: entry['id'] as String);
    }
  });

  test('simulated case runner rejects unknown case ids', () async {
    final result = await runSimulatedRc4Case('SIM-99');

    expect(result['result'], 'fail');
    expect(result['id'], 'SIM-99');
  });

  test('Fake adapters exercise discovery, network, DPP, and recovery boundaries', () async {
    final advertisement = BirdBoxAdvertisement(
      localName: 'BirdBox-82F41C9E',
      serviceUuids: const {BleProtocolConstants.serviceUuid},
      rssi: -42,
    );
    final ble = FakeBirdBoxBleDataSource(
      deviceInfo: _deviceInfo,
      networkStatus: _networkStatus,
      advertisements: [advertisement],
    );
    addTearDown(ble.dispose);
    expect((await ble.scan().toList()), hasLength(1));
    await ble.connect(advertisement);
    await ble.subscribeRequiredNotifications();
    ble.queueResponse(
      BleCommandType.startDirectAp,
      ProvisioningEvent(
        type: ProvisioningEventType.commandAccepted,
        requestId: 'request-sim',
        deviceId: _deviceInfo.deviceId,
        payload: const CommandAccepted(
          operationId: 'op-sim',
          desiredMode: ProvisioningNetworkMode.directAp,
        ),
      ),
    );
    await ble.writeCommand(const BleCommandRequest(
      type: BleCommandType.startDirectAp,
      requestId: 'request-sim',
      clientId: 'client-sim',
    ));
    ble.simulateDisconnect();
    expect(ble.isConnected, isFalse);

    final wifi = FakeBirdBoxWifiPlatform();
    wifi.queueJoinResult(const WifiJoinResult(
      outcome: WifiJoinOutcome.joined,
      network: BirdBoxWifiNetwork(handle: 'opaque-network', ssid: 'BirdBox-SIM'),
    ));
    final joined = await wifi.joinDirectAp(ssid: 'BirdBox-SIM', passphrase: 'synthetic-only');
    await wifi.bindProcessToNetwork(joined.network!);
    expect(wifi.boundNetwork, isNotNull);
    await wifi.releaseNetwork();
    expect(wifi.boundNetwork, isNull);

    final dpp = FakeBirdBoxDppPlatform(
      capability: const DppCapability(
        apiLevelSupported: true,
        easyConnectSupported: true,
        activityAvailable: true,
      ),
    );
    dpp.queueLaunchResult(const DppLaunchResult(outcome: DppLaunchOutcome.systemAccepted));
    expect((await dpp.checkCapability()).supported, isTrue);
    expect(
      (await dpp.launchEasyConnect(Uri.parse('dpp:synthetic;;'))).systemAccepted,
      isTrue,
    );
    await dpp.clearTransientUri();
    expect(dpp.clearCount, 1);
  });
}

const _deviceInfo = ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
  deviceName: 'BirdBox-82F41C9E',
  firmwareVersion: '1.0.0',
  apiVersion: 'v1',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: Duration(minutes: 2),
  displayAvailable: false,
  capabilities: DeviceCapabilities(
    directAp: true,
    infrastructureSta: true,
    wifiScan: true,
    wifiManual: true,
    dppEnrolleeSupported: true,
    dppSupportedAkm: {'psk'},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);

final _networkStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.apReady,
  operationId: 'op-sim',
  busy: false,
  baseUri: Uri.parse('http://192.0.2.10:8080'),
  directAp: const DirectApSnapshot(
    ssid: 'BirdBox-SIM',
    security: WifiSecurity.wpa2Personal,
    gatewayIpv4: '192.0.2.1',
    prefixLength: 24,
    clientCount: 1,
  ),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 8, 27),
);
