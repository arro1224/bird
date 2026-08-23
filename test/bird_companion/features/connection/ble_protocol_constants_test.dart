import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rc4 UUID and fragmentation constants stay frozen', () {
    expect(BleProtocolConstants.protocolVersion, '1.0-rc4');
    expect(BleProtocolConstants.allGattUuids, hasLength(6));
    expect(BleProtocolConstants.fragmentHeaderLength, 12);
    expect(BleProtocolConstants.maximumMessageBytes, 4096);
    expect(BleProtocolConstants.maximumFragmentCount, 256);
    expect(BleProtocolConstants.fragmentReassemblyTimeout, const Duration(seconds: 5));
  });

  test('UUID matching is lowercase normalized', () {
    expect(BleProtocolConstants.isBirdBoxServiceUuid(BleProtocolConstants.serviceUuid.toUpperCase()), isTrue);
  });

  test('compact advertisement is discoverable without Manufacturer Data', () {
    final advertisement = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, rssi: -55);

    expect(advertisement.hasBirdBoxService, isTrue);
    expect(advertisement.hasManufacturerExtension, isFalse);
    expect(advertisement.hasValidManufacturerExtension, isFalse);
  });

  test('malformed optional Manufacturer Data does not remove Service UUID candidate', () {
    final advertisement = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, rssi: -60, companyIdentifier: 0x1234, manufacturerPayload: const [1, 2]);

    expect(advertisement.hasBirdBoxService, isTrue);
    expect(advertisement.hasManufacturerExtension, isTrue);
    expect(advertisement.hasValidManufacturerExtension, isFalse);
  });
}
