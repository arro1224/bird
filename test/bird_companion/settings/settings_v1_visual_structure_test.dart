import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/display_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device home follows the v1 visual hierarchy', (tester) async {
    await _pumpPhone(tester, const SettingsShowcasePage(embedded: true));

    expect(find.byKey(const Key('v1-device-background')), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
    expect(find.byKey(const Key('v1-device-illustration')), findsOneWidget);
    expect(find.byKey(const Key('showcase-device-card')), findsOneWidget);
    expect(find.byKey(const Key('device-current-work-card')), findsOneWidget);
    expect(find.byKey(const Key('device-section-connection')), findsOneWidget);
    expect(find.byKey(const Key('device-section-photo')), findsOneWidget);
    expect(find.byKey(const Key('device-section-copy')), findsOneWidget);
    expect(find.byKey(const Key('device-section-support')), findsOneWidget);

    final deviceCardSize = tester.getSize(
      find.byKey(const Key('showcase-device-card')),
    );
    final entrySize = tester.getSize(
      find.byKey(const Key('showcase-device-management')),
    );
    expect(deviceCardSize.height, lessThanOrEqualTo(106));
    expect(entrySize.height, 40);
  });

  testWidgets('device secondary pages share the v1 background and centered top bar', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);

    await _pumpPhone(tester, DisplaySettingsPage(controller: controller));

    expect(find.byKey(const Key('v1-settings-background')), findsOneWidget);
    expect(find.byKey(const Key('settings-page-title')), findsOneWidget);
    expect(find.text('显示设置'), findsOneWidget);
    expect(find.byKey(const Key('settings-back')), findsOneWidget);
  });
}

Future<void> _pumpPhone(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: home,
    ),
  );
  await tester.pump();
}
