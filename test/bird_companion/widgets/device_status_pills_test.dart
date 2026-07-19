import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('状态胶囊展示真实状态并响应点击', (tester) async {
    await _setSize(tester, const Size(360, 800));
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DeviceStatusPills(
            status: _status,
            session: _connectedSession,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('电量 78%'), findsOneWidget);
    expect(find.text('685GB 可用'), findsOneWidget);
    await tester.tap(find.byType(DeviceStatusPills));
    expect(tapped, isTrue);
  });

  testWidgets('状态胶囊在 320dp 和 200% 字体下自动换行', (tester) async {
    await _setSize(tester, const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: DeviceStatusPills(
              status: _status,
              session: const DeviceSessionState(
                phase: DeviceSessionPhase.disconnected,
              ),
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('连接中断'), findsOneWidget);
  });
}

final _status = DeviceStatus(
  connection: DeviceConnection(
    id: '7B2A-9C31',
    name: '拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.lan,
  ),
  card: const CardStatus(inserted: true, readable: true),
  batteryPercent: 78,
  storageFreeBytes: 685 * 1024 * 1024 * 1024,
);

final _connectedSession = DeviceSessionState(
  phase: DeviceSessionPhase.connected,
  device: _status.connection,
);

void _noop() {}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
