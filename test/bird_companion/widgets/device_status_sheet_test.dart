import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_metrics_grid.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设备状态抽屉在 360x800 中不溢出并显示真实状态', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DeviceStatusSheet(
            status: _status,
            onReconnect: _noop,
            onOpenDetails: _noop,
            onOpenTask: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('拍鸟伴侣 K7'), findsOneWidget);
    expect(find.text('电量 78%'), findsOneWidget);
    expect(find.text('685GB 可用 · 总容量 894GB'), findsOneWidget);
    expect(find.text('运行中 · 65%'), findsOneWidget);
  });

  testWidgets('点击设备指标卡会打开状态入口回调', (tester) async {
    await _setSize(tester);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DeviceMetricsGrid(status: _status, onTap: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(DeviceMetricsGrid));
    expect(tapped, isTrue);
  });

  testWidgets('状态抽屉使用真实会话状态而不是固定显示已连接', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DeviceStatusSheet(
            status: _status,
            session: const DeviceSessionState(
              phase: DeviceSessionPhase.disconnected,
            ),
            onReconnect: _noop,
            onOpenDetails: _noop,
          ),
        ),
      ),
    );

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('可尝试重新连接'), findsOneWidget);
  });
}

final _status = DeviceStatus(
  connection: DeviceConnection(
    id: '7B2A-9C31',
    name: '拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.lan,
  ),
  card: const CardStatus(inserted: true, readable: true, name: 'SanDisk 128GB · U3 · V30'),
  batteryPercent: 78,
  temperatureCelsius: 36,
  storageFreeBytes: 685 * 1024 * 1024 * 1024,
  storageTotalBytes: 894 * 1024 * 1024 * 1024,
  currentJob: const BirdJobStatus(
    id: 'job-1',
    type: BirdJobType.analysis,
    state: BirdJobState.running,
    totalCount: 3672,
    finishedCount: 2384,
  ),
);

void _noop() {}

Future<void> _setSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
