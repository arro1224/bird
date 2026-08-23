import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/$name').readAsStringSync()) as Map);

  test('Device Info fixture is parsed strictly', () {
    final info = ProvisioningDeviceInfo.fromJson(fixture('ble-device-info.rc4.json'));

    expect(info.deviceId, 'bbx-82f41c9e7a3d4b68a1501e21e536c649');
    expect(info.capabilities.dppUsableByBox, isFalse);
    expect(info.capabilities.bleFragmentationV1, isTrue);
  });

  test('Device Info rejects missing, wrong type, unknown enum and wrong version', () {
    final missing = fixture('ble-device-info.rc4.json')..remove('device_id');
    final wrongType = fixture('ble-device-info.rc4.json')..['pairing_code_length'] = '6';
    final unknownEnum = fixture('ble-device-info.rc4.json')..['pairing_code_mode'] = 'magic';
    final wrongVersion = fixture('ble-device-info.rc4.json')..['protocol_version'] = '1.0-rc3';

    for (final json in [missing, wrongType, unknownEnum, wrongVersion]) {
      expect(() => ProvisioningDeviceInfo.fromJson(json), throwsA(isA<ProvisioningProtocolException>()));
    }
  });

  test('Network Status fixture preserves authoritative GATT state', () {
    final envelope = fixture('ble-network-status.rc4.json');
    final event = ProvisioningEvent.fromJson(envelope);
    final status = event.payload as ProvisioningNetworkStatus;

    expect(event.type, ProvisioningEventType.networkStatus);
    expect(status.activeMode, ProvisioningNetworkMode.directAp);
    expect(status.operationState, NetworkOperationState.apReady);
    expect(status.baseUri, Uri.parse('http://192.168.82.1:8080'));
  });

  test('sensitive event models redact passphrase and DPP URI', () {
    final ap = DirectApReady.fromJson({
      'operation_id': 'op_A1',
      'active_mode': 'direct_ap',
      'ssid': 'BirdBox-82F41C9E',
      'security': 'wpa2_personal',
      'passphrase': 'NOT_A_REAL_SECRET',
      'gateway_ipv4': '192.168.82.1',
      'prefix_length': 24,
      'base_uri': 'http://192.168.82.1:8080',
    });
    final dpp = DppBootstrapReady.fromJson({'operation_id': 'op_D1', 'operation_state': 'waiting_dpp_configurator', 'dpp_uri': 'DPP:K:REDACTED;;', 'expires_in_seconds': 120});

    expect(ap.toString(), isNot(contains('NOT_A_REAL_SECRET')));
    expect(dpp.toString(), isNot(contains('DPP:')));
  });

  test('Wi-Fi QR reuses set_sta_config model and never creates a DPP config', () {
    const credentials = WifiQrCredentials(ssid: 'Studio-WiFi', security: WifiSecurity.wpa2Personal, password: 'NOT_A_REAL_SECRET');
    final configuration = credentials.toStaNetworkConfiguration();

    expect(configuration.provisioningMethod, ProvisioningMethod.wifiQr);
    expect(configuration.selectionMethod, WifiSelectionMethod.manual);
    expect(configuration.bssid, isNull);
    expect(configuration.toString(), isNot(contains('NOT_A_REAL_SECRET')));
  });

  test('manual selection rejects BSSID and DPP rejects set_sta_config', () {
    expect(
      () => StaNetworkConfiguration(
        provisioningMethod: ProvisioningMethod.bleManual,
        selectionMethod: WifiSelectionMethod.manual,
        ssid: 'Studio-WiFi',
        bssid: 'AA:BB:CC:DD:EE:FF',
        security: WifiSecurity.open,
        hidden: false,
        networkKind: StaNetworkKind.router,
      ),
      throwsArgumentError,
    );
    expect(
      () => StaNetworkConfiguration(provisioningMethod: ProvisioningMethod.androidDpp, selectionMethod: WifiSelectionMethod.manual, ssid: 'Studio-WiFi', security: WifiSecurity.open, hidden: false, networkKind: StaNetworkKind.unknown),
      throwsArgumentError,
    );
  });

  test('authorization model only accepts frozen types and redacts its value', () {
    final authorization = ProvisioningAuthorization.fromJson({'type': 'pairing_session', 'value': 'REDACTED_TEST_ONLY'});

    expect(authorization.type, ProvisioningAuthorizationType.pairingSession);
    expect(authorization.toString(), isNot(contains('REDACTED_TEST_ONLY')));
    expect(() => ProvisioningAuthorization.fromJson({'type': 'password', 'value': 'REDACTED_TEST_ONLY'}), throwsA(isA<ProvisioningProtocolException>()));
  });
}
