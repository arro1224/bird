import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact, full and malformed optional advertisements remain candidates', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitAdvertisement(_advertisement('compact'));
    platform.emitAdvertisement(_advertisement('full', companyIdentifier: 0xFFFF, manufacturerPayload: Uint8List.fromList([1, 0, 0x9E, 0x1C, 0xF4, 0x82, 1, 4])));
    platform.emitAdvertisement(_advertisement('invalid', companyIdentifier: 1, manufacturerPayload: Uint8List.fromList([9])));
    final advertisements = await result;

    expect(advertisements, hasLength(3));
    expect(advertisements.every((item) => item.hasBirdBoxService), isTrue);
    expect(advertisements[0].platformDeviceId, 'handle-compact');
    expect(advertisements[1].hasValidManufacturerExtension, isTrue);
    expect(advertisements[2].hasValidManufacturerExtension, isFalse);
  });

  test('Local Name fallback is discoverable but never becomes a trusted identity', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitAdvertisement({..._advertisement('fallback'), 'serviceUuids': <String>[]});
    final advertisement = (await result).single;

    expect(advertisement.hasValidLocalName, isTrue);
    expect(advertisement.hasBirdBoxService, isFalse);
    expect(advertisement.toString(), isNot(contains('handle-fallback')));
  });

  test('connect negotiates MTU, reads authoritative GATT models and subscribes both notifications', () async {
    final platform = _FakeBlePlatform(negotiatedMtu: 64);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    final advertisement = advertisementFromPlatform(_advertisement('device'));
    const fragments = BleFragmentCodec();
    platform.queueRead(
      BleProtocolConstants.deviceInfoCharacteristicUuid,
      fragments.fragment(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsBytesSync(), messageId: 1, maximumFragmentBytes: 52),
    );
    platform.queueRead(
      BleProtocolConstants.networkStatusCharacteristicUuid,
      fragments.fragment(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsBytesSync(), messageId: 2, maximumFragmentBytes: 52),
    );

    await dataSource.connect(advertisement);
    final info = await dataSource.readDeviceInfo();
    final status = await dataSource.readNetworkStatus();
    await dataSource.subscribeRequiredNotifications();

    expect(platform.connectedHandle, 'handle-device');
    expect(platform.requestedMtu, 517);
    expect(info.deviceId, 'bbx-82f41c9e7a3d4b68a1501e21e536c649');
    expect(status.activeMode, ProvisioningNetworkMode.directAp);
    expect(platform.subscribed, {BleProtocolConstants.networkStatusCharacteristicUuid, BleProtocolConstants.scanResultsCharacteristicUuid});
  });

  test('write uses rc4 fragments and waits for the matching protocol response', () async {
    final platform = _FakeBlePlatform(negotiatedMtu: 64, encrypted: true);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.getNetworkStatus,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );

    final responseFuture = dataSource.writeCommand(request);
    await Future<void>.delayed(Duration.zero);
    final responseJson = File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync();
    final packets = const BleFragmentCodec().fragment(Uint8List.fromList(utf8.encode(responseJson)), messageId: 3, maximumFragmentBytes: 52);
    for (final packet in packets) {
      platform.emitNotification(BleProtocolConstants.networkStatusCharacteristicUuid, packet);
    }
    final response = await responseFuture;

    expect(response.type, ProvisioningEventType.networkStatus);
    expect(platform.writes, isNotEmpty);
    expect(platform.writes.every((write) => write.characteristicUuid == BleProtocolConstants.provisioningCommandCharacteristicUuid), isTrue);
    final requestBytes = BleFragmentReassembler();
    Uint8List? reassembled;
    for (final write in platform.writes) {
      reassembled = requestBytes.add(write.value) ?? reassembled;
    }
    final requestJson = jsonDecode(utf8.decode(reassembled!)) as Map<String, dynamic>;
    expect(requestJson['request_id'], request.requestId);
  });

  test('sensitive writes require a bonded encrypted link and disconnect never sends cancel', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.startDirectAp,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
      payload: {
        'authorization': {'type': 'pairing_session', 'value': 'REDACTED_TEST_ONLY'},
      },
    );

    await expectLater(
      dataSource.writeCommand(request),
      throwsA(isA<ProvisioningException>().having((error) => error.code, 'code', ProvisioningErrorCode.authorizationRequired)),
    );
    final disconnect = dataSource.disconnects.first;
    platform.emitDisconnect();
    await disconnect;
    expect(dataSource.isConnected, isFalse);
    expect(platform.writes, isEmpty);
  });
}

Map<String, dynamic> _advertisement(String suffix, {int? companyIdentifier, Uint8List? manufacturerPayload}) => {
  'deviceId': 'handle-$suffix',
  'localName': 'BirdBox-${suffix.toUpperCase()}',
  'serviceUuids': [BleProtocolConstants.serviceUuid.toUpperCase()],
  'rssi': -50,
  'companyIdentifier': companyIdentifier,
  'manufacturerPayload': manufacturerPayload,
};

final class _Write {
  const _Write(this.characteristicUuid, this.value);

  final String characteristicUuid;
  final Uint8List value;
}

final class _FakeBlePlatform implements BirdBoxBlePlatform {
  _FakeBlePlatform({this.negotiatedMtu = 23, this.encrypted = false});

  final int negotiatedMtu;
  final bool encrypted;
  final StreamController<Map<String, dynamic>> _scan = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _notifications = StreamController.broadcast();
  final StreamController<BleDisconnectEvent> _disconnects = StreamController.broadcast();
  final Map<String, List<Uint8List>> _reads = {};
  final Set<String> subscribed = {};
  final List<_Write> writes = [];
  String? connectedHandle;
  int? requestedMtu;

  @override
  Stream<Map<String, dynamic>> get scanResults => _scan.stream;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  @override
  Stream<BleDisconnectEvent> get disconnects => _disconnects.stream;

  void emitAdvertisement(Map<String, dynamic> value) => _scan.add(value);
  void emitNotification(String characteristicUuid, Uint8List value) => _notifications.add({'characteristicUuid': characteristicUuid, 'value': value});
  void emitDisconnect() => _disconnects.add(const BleDisconnectEvent(reason: 'link_lost', gattStatus: 133, unexpected: true));
  void queueRead(String characteristicUuid, List<Uint8List> packets) => _reads[characteristicUuid] = List.of(packets);

  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<void> startScan(Duration timeout) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String platformDeviceId) async => connectedHandle = platformDeviceId;
  @override
  Future<void> disconnect() async => emitDisconnect();
  @override
  Future<int> requestMtu(int mtu) async {
    requestedMtu = mtu;
    return negotiatedMtu;
  }

  @override
  Future<Uint8List> readCharacteristic(String characteristicUuid) async {
    final packets = _reads[characteristicUuid];
    if (packets == null || packets.isEmpty) throw StateError('No queued read for $characteristicUuid');
    return packets.removeAt(0);
  }

  @override
  Future<void> setNotify(String characteristicUuid, {required bool enabled}) async {
    if (enabled) {
      subscribed.add(characteristicUuid);
    } else {
      subscribed.remove(characteristicUuid);
    }
  }

  @override
  Future<void> writeWithResponse(String characteristicUuid, Uint8List value) async => writes.add(_Write(characteristicUuid, Uint8List.fromList(value)));
  @override
  Future<bool> isLinkEncrypted() async => encrypted;

  @override
  Future<void> dispose() async {
    await _scan.close();
    await _notifications.close();
    await _disconnects.close();
  }
}
