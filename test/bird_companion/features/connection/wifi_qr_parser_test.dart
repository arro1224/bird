import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses escaped personal Wi-Fi fields into the frozen wifi_qr request', () {
    final credentials = parseWifiQrCredentials(
      r'WIFI:T:WPA2;S:Studio\;Birds;P:bird\:pass123;H:true;B:aa:bb:cc:dd:ee:ff;;',
    );
    final configuration = credentials.toStaNetworkConfiguration();

    expect(credentials.ssid, 'Studio;Birds');
    expect(credentials.password, 'bird:pass123');
    expect(credentials.bssid, 'AA:BB:CC:DD:EE:FF');
    expect(credentials.hidden, isTrue);
    expect(configuration.provisioningMethod, ProvisioningMethod.wifiQr);
    expect(configuration.selectionMethod, WifiSelectionMethod.scanResult);
    expect(configuration.toString(), isNot(contains('bird:pass123')));
  });

  test('accepts open Wi-Fi without retaining an empty password', () {
    final credentials = parseWifiQrCredentials(
      'WIFI:T:nopass;S:Guest;P:;;',
    );

    expect(credentials.security, WifiSecurity.open);
    expect(credentials.password, isNull);
    expect(
      credentials.toStaNetworkConfiguration().selectionMethod,
      WifiSelectionMethod.manual,
    );
  });

  test('maps WPA3 and transition security types', () {
    expect(
      parseWifiQrCredentials(
        'WIFI:T:SAE;S:Studio;P:synthetic-pass;;',
      ).security,
      WifiSecurity.wpa3Personal,
    );
    expect(
      parseWifiQrCredentials(
        'WIFI:T:WPA2/WPA3;S:Studio;P:synthetic-pass;;',
      ).security,
      WifiSecurity.wpa2Wpa3Transition,
    );
  });

  test('rejects ambiguous, unsupported and unsafe payloads', () {
    const invalid = [
      'https://example.invalid/not-wifi',
      'WIFI:T:WEP;S:Studio;P:synthetic-pass;;',
      'WIFI:T:WPA2;S:Studio;S:Other;P:synthetic-pass;;',
      'WIFI:T:WPA2;S:Studio;P:short;;',
      'WIFI:T:nopass;S:Guest;P:must-not-exist;;',
      'WIFI:T:WPA2;S:Studio;P:synthetic-pass;B:not-a-mac;;',
      'WIFI:T:WPA2;S:Studio;P:synthetic-pass;X:unknown;;',
    ];

    for (final value in invalid) {
      expect(
        () => parseWifiQrCredentials(value),
        throwsFormatException,
        reason: value,
      );
      expect(tryParseWifiQrCredentials(value), isNull, reason: value);
    }
  });
}
