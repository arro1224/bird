abstract final class BleProtocolConstants {
  static const protocolVersion = '1.0-rc4';

  static const serviceUuid = '6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000';
  static const deviceInfoCharacteristicUuid = '6f7d0002-7a66-4c45-a1b9-5f4d2e3c1000';
  static const networkStatusCharacteristicUuid = '6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000';
  static const wifiConfigCharacteristicUuid = '6f7d0004-7a66-4c45-a1b9-5f4d2e3c1000';
  static const provisioningCommandCharacteristicUuid = '6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000';
  static const scanResultsCharacteristicUuid = '6f7d0006-7a66-4c45-a1b9-5f4d2e3c1000';

  static const characteristicUuids = <String>{
    deviceInfoCharacteristicUuid,
    networkStatusCharacteristicUuid,
    wifiConfigCharacteristicUuid,
    provisioningCommandCharacteristicUuid,
    scanResultsCharacteristicUuid,
  };

  static const allGattUuids = <String>{serviceUuid, ...characteristicUuids};
  static const notifyCharacteristicUuids = <String>{networkStatusCharacteristicUuid, scanResultsCharacteristicUuid};
  static const writeWithResponseCharacteristicUuids = <String>{wifiConfigCharacteristicUuid, provisioningCommandCharacteristicUuid};

  static const localNamePrefix = 'BirdBox-';
  static const developmentCompanyIdentifier = 0xFFFF;
  static const manufacturerPayloadLength = 8;
  static const advertisementStructureVersion = 0x01;
  static const protocolMajorVersion = 0x01;
  static const protocolCandidateVersion = 0x04;

  static const fragmentMagic = <int>[0x42, 0x42];
  static const fragmentProtocolVersion = 1;
  static const fragmentHeaderLength = 12;
  static const maximumMessageBytes = 4096;
  static const maximumFragmentCount = 256;
  static const fragmentReassemblyTimeout = Duration(seconds: 5);

  static const commandResponseTimeout = Duration(seconds: 3);
  static const wifiScanTimeout = Duration(seconds: 15);
  static const dppBootstrapTimeout = Duration(seconds: 120);
  static const dppTotalTimeout = Duration(seconds: 180);
  static const directApStartTimeout = Duration(seconds: 20);
  static const directApStopTimeout = Duration(seconds: 15);
  static const networkOperationTimeout = Duration(seconds: 75);
  static const healthRequestTimeout = Duration(seconds: 3);
  static const healthRetryInterval = Duration(seconds: 2);
  static const healthRetryWindow = Duration(seconds: 30);
  static const pairingSessionLifetime = Duration(seconds: 600);

  static const directApGatewayIpv4 = '192.168.82.1';
  static const directApPrefixLength = 24;
  static const directApHttpPort = 8080;
  static const directApBaseUri = 'http://192.168.82.1:8080';

  static String normalizeUuid(String value) => value.trim().toLowerCase();

  static bool isBirdBoxServiceUuid(String value) => normalizeUuid(value) == serviceUuid;

  static bool hasBirdBoxService(Iterable<String> serviceUuids) => serviceUuids.any(isBirdBoxServiceUuid);
}
