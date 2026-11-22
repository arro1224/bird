import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Standard router payloads; the password is synthetic and never rendered.
  const wpa2 = 'WIFI:T:WPA;S:Studio;P:synthetic-value;;';
  const wpa3 = 'WIFI:T:WPA3;S:Studio-6G;P:synthetic-value;;';
  const transition = 'WIFI:T:WPA2/WPA3;S:Studio;P:synthetic-value;;';
  const open = 'WIFI:T:nopass;S:Guest;;';

  test('accepts one standard Wi-Fi code and keeps its security type', () {
    final outcome = evaluateWifiQrCodes([wpa2]);

    expect(outcome.isAccepted, isTrue);
    expect(outcome.failure, isNull);
    expect(outcome.credentials!.ssid, 'Studio');
    expect(outcome.credentials!.security, WifiSecurity.wpa2Personal);
    expect(outcome.credentials!.password, 'synthetic-value');
    // The credentials never print the password.
    expect(outcome.credentials.toString(), isNot(contains('synthetic-value')));
    expect(outcome.message, isEmpty);
  });

  test('camera and gallery agree on WPA3, transition and open networks', () {
    for (final entry in <(String, WifiSecurity)>[
      (wpa3, WifiSecurity.wpa3Personal),
      (transition, WifiSecurity.wpa2Wpa3Transition),
      (open, WifiSecurity.open),
    ]) {
      final outcome = evaluateWifiQrCodes([entry.$1]);
      expect(outcome.isAccepted, isTrue, reason: entry.$1);
      expect(outcome.credentials!.security, entry.$2);
    }
    expect(evaluateWifiQrCodes([open]).credentials!.password, isNull);
  });

  test('a frame or photo with several different codes is rejected, not reduced to the first', () {
    final outcome = evaluateWifiQrCodes([wpa2, wpa3]);

    expect(outcome.isAccepted, isFalse);
    expect(outcome.failure, WifiQrImportFailure.multipleCodes);
    expect(outcome.message, contains('多个二维码'));
  });

  test('the same code reported twice for one QR is folded into a single candidate', () {
    final outcome = evaluateWifiQrCodes([wpa2, wpa2, '  $wpa2  ']);

    expect(outcome.isAccepted, isTrue);
    expect(outcome.credentials!.ssid, 'Studio');
  });

  test('empty input is reported as no code rather than a Wi-Fi failure', () {
    expect(evaluateWifiQrCodes(const []).failure, WifiQrImportFailure.empty);
    expect(evaluateWifiQrCodes([null, '   ']).failure, WifiQrImportFailure.empty);
    expect(evaluateWifiQrCodes(const []).message, contains('没有识别到二维码'));
  });

  test('non Wi-Fi and malformed payloads are rejected with a re-selectable message', () {
    for (final payload in const [
      'https://example.test/link',
      'WIFI:T:WPA;S:Studio;', // missing the terminating ;;
      'WIFI:T:WEP;S:Studio;P:synthetic-value;;', // unsupported security
      'WIFI:T:WPA;S:Studio;S:Other;P:synthetic-value;;', // duplicated field
      'WIFI:T:WPA;S:;P:synthetic-value;;', // empty SSID
    ]) {
      final outcome = evaluateWifiQrCodes([payload]);
      expect(outcome.isAccepted, isFalse, reason: payload);
      expect(outcome.failure, WifiQrImportFailure.notWifiQr, reason: payload);
      expect(outcome.message, contains('标准 Wi-Fi 二维码'));
    }
  });

  test('escaped special characters survive both entry points identically', () {
    const escaped = r'WIFI:T:WPA;S:Cafe\;Bar;P:pa\;ss\\word;;';
    final outcome = evaluateWifiQrCodes([escaped]);

    expect(outcome.isAccepted, isTrue);
    expect(outcome.credentials!.ssid, 'Cafe;Bar');
    expect(outcome.credentials!.password, r'pa;ss\word');
  });
}
