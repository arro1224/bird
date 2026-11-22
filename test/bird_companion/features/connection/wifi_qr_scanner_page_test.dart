import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/wifi_qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D1 surface: the gallery entry must behave like the camera entry — one shared
/// evaluation, no silent target selection, and nothing sent before the user confirms.
void main() {
  const studio = 'WIFI:T:WPA;S:Studio;P:synthetic-value;;';
  const guest = 'WIFI:T:WPA3;S:Guest-Net;P:another-value;;';

  testWidgets('a valid picked image shows the target network without the password', (tester) async {
    final harness = await _openScanner(tester, picker: const _FakePicker(path: '/tmp/qr.png'), codes: [studio]);

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    await tester.pump();

    expect(find.text('确认目标网络'), findsOneWidget);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('WPA2-Personal'), findsOneWidget);
    // The password never reaches the confirmation surface.
    expect(find.textContaining('synthetic-value'), findsNothing);
    expect(find.text('确认连接此 Wi-Fi'), findsOneWidget);

    await tester.tap(find.text('确认连接此 Wi-Fi'));
    await tester.pump();
    await tester.pump();

    expect(harness.popped.single?.ssid, 'Studio');
    expect(harness.popped.single?.security.name, 'wpa2Personal');
  });

  testWidgets('a photo holding two different codes is rejected instead of picking the first', (tester) async {
    final harness = await _openScanner(tester, picker: const _FakePicker(path: '/tmp/two.png'), codes: [studio, guest]);

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('多个二维码'), findsOneWidget);
    expect(find.text('确认目标网络'), findsNothing);
    expect(find.text('等待扫码'), findsNothing);
    expect(harness.popped, isEmpty);

    // Still re-selectable: the gallery entry stays available.
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('重新扫描'), findsOneWidget);
  });

  testWidgets('a photo without any code asks for another image and does not submit', (tester) async {
    final harness = await _openScanner(tester, picker: const _FakePicker(path: '/tmp/blank.png'), codes: const []);

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('没有识别到二维码'), findsOneWidget);
    expect(find.text('确认目标网络'), findsNothing);
    expect(harness.popped, isEmpty);
  });

  testWidgets('cancelling the gallery picker leaves the page untouched', (tester) async {
    final harness = await _openScanner(tester, picker: const _FakePicker(path: null), codes: [studio]);

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    await tester.pump();

    expect(find.text('确认目标网络'), findsNothing);
    expect(find.textContaining('二维码'), findsWidgets);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(harness.popped, isEmpty);
  });

  testWidgets('a picker that cannot open explains itself and stays re-selectable', (tester) async {
    final harness = await _openScanner(
      tester,
      picker: const _FakePicker(error: PhoneWifiPickFailure.unavailable),
      codes: [studio],
    );

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('系统图片选择器打不开'), findsOneWidget);
    expect(find.text('确认目标网络'), findsNothing);
    expect(harness.popped, isEmpty);
  });
}

final class _ScannerHarness {
  const _ScannerHarness(this.popped);
  final List<WifiQrCredentials?> popped;
}

/// Pushes the scanner page so the confirmed credentials can be observed on pop.
Future<_ScannerHarness> _openScanner(
  WidgetTester tester, {
  required _FakePicker picker,
  required List<String?> codes,
}) async {
  final popped = <WifiQrCredentials?>[];
  // The camera preview is a full-width square; a taller surface keeps the gallery
  // and confirm controls inside the built part of the lazy list.
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<WifiQrCredentials>(
                  MaterialPageRoute<WifiQrCredentials>(
                    builder: (_) => WifiQrScannerPage(
                      phoneWifi: picker,
                      imageAnalyzer: (_) async => codes,
                    ),
                  ),
                );
                popped.add(result);
              },
              child: const Text('打开扫码页'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开扫码页'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(WifiQrScannerPage), findsOneWidget, reason: '扫码页必须被推入');
  return _ScannerHarness(popped);
}

final class _FakePicker implements PhoneWifiPlatform {
  const _FakePicker({this.path, this.error});

  final String? path;
  final PhoneWifiPickFailure? error;

  @override
  Future<PhoneWifiSsid> currentSsid() async => const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.unavailable);

  @override
  Future<String?> pickQrImage() async {
    final failure = error;
    if (failure != null) throw PhoneWifiPickException(failure);
    return path;
  }
}
