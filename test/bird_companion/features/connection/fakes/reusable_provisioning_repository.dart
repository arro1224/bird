import 'dart:async';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';

import 'controlled_provisioning_repository.dart';

/// Simulated transport for host and Android UI scenarios, never hardware proof.
class ReusableProvisioningRepository extends ControlledProvisioningRepository implements ReusableBleSession {
  ReusableProvisioningRepository({this.current, this.advertisements = const []}) {
    owner = Object();
  }
  ProvisioningDevice? current;
  List<ProvisioningDevice> advertisements;
  int claims = 0;
  final _changes = StreamController<void>.broadcast();
  @override
  Object? get observableSessionOwner => owner;
  @override
  ProvisioningDevice? get currentBleDevice => current;
  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => current?.deviceInfo;
  @override
  Stream<void> get sessionChanges => _changes.stream;
  @override
  Object claimSession() {
    claims++;
    final next = super.claimSession();
    _changes.add(null);
    return next;
  }

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) {
    calls.add('discover');
    return Stream.fromIterable(advertisements);
  }

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device) async {
    calls.add('connect:${device.scanId}');
    final info = device.scanId == secondBleDevice.scanId ? secondBleInfo : firstBleInfo;
    current = ProvisioningDevice(scanId: device.scanId, advertisement: device.advertisement, deviceInfo: info);
    _changes.add(null);
    return info;
  }

  @override
  void emitDisconnect() {
    current = null;
    super.emitDisconnect();
  }

  @override
  Future<void> disconnect() async {
    current = null;
    await super.disconnect();
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
    await super.dispose();
  }
}

final firstBleDevice = ProvisioningDevice(
  scanId: 'opaque-current-box',
  advertisement: BirdBoxAdvertisement(localName: 'BirdBox-Current', serviceUuids: const [BleProtocolConstants.serviceUuid], rssi: -40, platformDeviceId: 'opaque-current-box'),
  deviceInfo: firstBleInfo,
);
final secondBleDevice = ProvisioningDevice(
  scanId: 'opaque-other-box',
  advertisement: BirdBoxAdvertisement(localName: 'BirdBox-Other', serviceUuids: const [], rssi: -45, platformDeviceId: 'opaque-other-box'),
);
const firstBleInfo = ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-Current',
  firmwareVersion: 'test-only',
  apiVersion: 'v1',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: Duration(minutes: 2),
  displayAvailable: true,
  capabilities: _capabilities,
);
const secondBleInfo = ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-11111111111111111111111111111111',
  deviceName: 'BirdBox-Other',
  firmwareVersion: 'test-only',
  apiVersion: 'v1',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: Duration(minutes: 2),
  displayAvailable: true,
  capabilities: _capabilities,
);
const _capabilities = DeviceCapabilities(
  directAp: true,
  infrastructureSta: true,
  wifiScan: true,
  wifiManual: true,
  dppEnrolleeSupported: false,
  dppSupportedAkm: {},
  modeSwitch: true,
  networkRecovery: true,
  bleFragmentationV1: true,
  wifiApStaConcurrency: false,
  apBand24Ghz: true,
  apBand5Ghz: false,
);
