import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_background.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_empty_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设备卡在 320dp 宽度中不溢出', (tester) async {
    await _setSize(tester, const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: DiscoveredDeviceCard(device: _device, onConnect: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('拍鸟伴侣 K7'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
  });

  testWidgets('未发现设备视觉基线 430x932', (tester) async {
    await _setSize(tester, const Size(430, 932));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: ConnectionBackground(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageHorizontal,
                  AppSpacing.sm,
                  AppSpacing.pageHorizontal,
                  AppSpacing.xl,
                ),
                children: [
                  SizedBox(
                    height: 52,
                    child: Center(
                      child: Text('查找设备', style: AppTheme.light().textTheme.headlineSmall),
                    ),
                  ),
                  const ConnectionEmptyView(onRetry: _noop, onScan: _noop, onManual: _noop),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(K7DeviceArtwork.asset),
        tester.element(find.byType(ConnectionBackground)),
      );
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(ConnectionBackground),
      matchesGoldenFile('goldens/connection_empty_430x932.png'),
    );
  });
}

final _device = DeviceConnection(
  id: '7B2A-9C31',
  name: '拍鸟伴侣 K7',
  baseUri: Uri.parse('http://192.168.1.9:8080'),
  networkMode: NetworkMode.lan,
);

void _noop() {}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
