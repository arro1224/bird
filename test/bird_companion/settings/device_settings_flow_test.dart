import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_details_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  testWidgets('device management selects an available device and exposes rescan', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(DeviceManagementPage(controller: controller)));

    expect(find.text('更换设备'), findsOneWidget);
    expect(find.byKey(const Key('device-current')), findsOneWidget);
    expect(find.byKey(const Key('device-available-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('device-available-1')));
    await tester.pump();
    expect(controller.selectedDeviceId, 'k7-nearby-1');
    await tester.pump(const Duration(seconds: 5));

    await tester.scrollUntilVisible(
      find.byKey(const Key('device-rescan')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('重新搜索'));
    await tester.pump();
    expect(find.text('正在重新搜索附近设备…'), findsOneWidget);
  });

  testWidgets('device details reconnect opens device discovery', (tester) async {
    final controller = BirdSettingsController();
    RouteSettings? route;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        onGenerateRoute: (settings) {
          route = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('connection')),
          );
        },
        home: DeviceDetailsPage(controller: controller),
      ),
    );

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.text('BirdAI 3.0.2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('device-reconnect')));
    await tester.pumpAndSettle();
    expect(route?.name, BirdRoutes.settingsDeviceManagement);
    expect(route?.arguments, isNull);
  });

  testWidgets('device details expands technical details', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(DeviceDetailsPage(controller: controller)));

    await tester.scrollUntilVisible(
      find.byKey(const Key('device-technical-details')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('device-technical-details')));
    await tester.pump();
    expect(find.text('API 版本'), findsOneWidget);
  });
}
