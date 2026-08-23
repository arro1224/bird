import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

void main() {
  Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/$name').readAsStringSync()) as Map);

  late ProvisioningDeviceInfo deviceInfo;
  late ProvisioningNetworkStatus networkStatus;

  setUp(() {
    deviceInfo = ProvisioningDeviceInfo.fromJson(fixture('ble-device-info.rc4.json'));
    networkStatus = ProvisioningEvent.fromJson(fixture('ble-network-status.rc4.json')).payload as ProvisioningNetworkStatus;
  });

  test('Fake BLE covers compact/full/invalid extensions and notification ordering', () async {
    final compact = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: const {BleProtocolConstants.serviceUuid}, rssi: -50);
    final full = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, rssi: -51, companyIdentifier: 0xFFFF, manufacturerPayload: const [1, 0, 0x9E, 0x1C, 0xF4, 0x82, 1, 4]);
    final invalidExtension = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, rssi: -52, companyIdentifier: 1, manufacturerPayload: const [9]);
    final fake = FakeBirdBoxBleDataSource(deviceInfo: deviceInfo, networkStatus: networkStatus, advertisements: [compact, full, invalidExtension]);
    addTearDown(fake.dispose);

    final discovered = await fake.scan().toList();
    expect(discovered, hasLength(3));
    expect(discovered.every((item) => item.hasBirdBoxService), isTrue);
    expect(full.hasValidManufacturerExtension, isTrue);
    expect(invalidExtension.hasValidManufacturerExtension, isFalse);

    await fake.connect(compact);
    const request = BleCommandRequest(type: BleCommandType.startDirectAp, requestId: '550e8400-e29b-41d4-a716-446655440000', clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543');
    expect(() => fake.writeCommand(request), throwsStateError);
  });

  test('Fake BLE queues all nine commands and allows late/disconnect events', () async {
    final advertisement = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, rssi: -50);
    final fake = FakeBirdBoxBleDataSource(deviceInfo: deviceInfo, networkStatus: networkStatus, advertisements: [advertisement]);
    addTearDown(fake.dispose);
    await fake.connect(advertisement);
    await fake.subscribeRequiredNotifications();

    for (final command in BleCommandType.values) {
      final event = ProvisioningEvent(type: ProvisioningEventType.networkStatus, requestId: command.wireValue, deviceId: deviceInfo.deviceId, payload: networkStatus);
      fake.queueResponse(command, event);
      final response = await fake.writeCommand(BleCommandRequest(type: command, requestId: 'request-${command.index}', clientId: 'client'));
      expect(response.requestId, command.wireValue);
    }
    expect(fake.requests, hasLength(9));

    final lateEvents = <ProvisioningEvent>[];
    final subscription = fake.events.listen(lateEvents.add);
    fake.emitLateEvent(ProvisioningEvent(type: ProvisioningEventType.networkStatus, requestId: 'late', deviceId: deviceInfo.deviceId, payload: networkStatus));
    await Future<void>.delayed(Duration.zero);
    expect(lateEvents.single.requestId, 'late');
    await subscription.cancel();
    fake.simulateDisconnect();
    expect(fake.isConnected, isFalse);
  });

  test('Fake Wi-Fi represents join, binding and release without logging password', () async {
    final fake = FakeBirdBoxWifiPlatform();
    const network = BirdBoxWifiNetwork(handle: 'opaque-handle', ssid: 'BirdBox-82F41C9E');
    fake.queueJoinResult(const WifiJoinResult(outcome: WifiJoinOutcome.joined, network: network));

    final result = await fake.joinDirectAp(ssid: network.ssid, passphrase: 'NOT_A_REAL_SECRET');
    await fake.bindProcessToNetwork(result.network!);
    expect(fake.boundNetwork, network);
    await fake.releaseNetwork();
    expect(fake.boundNetwork, isNull);
  });

  test('Fake DPP covers capability, launch result and transient cleanup', () async {
    final fake = FakeBirdBoxDppPlatform(capability: const DppCapability(apiLevelSupported: true, easyConnectSupported: true, activityAvailable: true));
    fake.queueLaunchResult(const DppLaunchResult(outcome: DppLaunchOutcome.userCancelled));

    expect((await fake.checkCapability()).supported, isTrue);
    final result = await fake.launchEasyConnect(Uri.parse('DPP:K:REDACTED;;'));
    expect(result.outcome, DppLaunchOutcome.userCancelled);
    await fake.clearTransientUri();
    expect(fake.clearCount, 1);
  });

  test('Fake DPP can report a distinct timeout', () async {
    final fake = FakeBirdBoxDppPlatform(capability: const DppCapability(apiLevelSupported: true, easyConnectSupported: true, activityAvailable: true));
    fake.queueLaunchResult(const DppLaunchResult(outcome: DppLaunchOutcome.timedOut));

    final result = await fake.launchEasyConnect(Uri.parse('DPP:K:REDACTED;;'));
    expect(result.outcome, DppLaunchOutcome.timedOut);
  });
}
