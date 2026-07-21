import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_failure_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_progress_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_success_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('连接中视图在 360x800 不溢出', (tester) async {
    await _pump(
      tester,
      const ConnectionProgressView(deviceName: '拍鸟伴侣 K7', onCancel: _noop),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('65%'), findsOneWidget);
    expect(find.text('正在连接中……'), findsOneWidget);
  });

  testWidgets('连接失败视图在 360x800 不溢出', (tester) async {
    await _pump(
      tester,
      const ConnectionFailureView(
        deviceName: '拍鸟伴侣 K7',
        message: UserMessage(title: '连接超时', message: '盒子未及时响应。', actionLabel: '重新连接'),
        onRetry: _noop,
        onScan: _noop,
        onChangeMethod: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('未能连接拍鸟伴侣 K7'), findsOneWidget);
  });

  testWidgets('连接成功视图在 360x800 不溢出', (tester) async {
    await _pump(
      tester,
      ConnectionSuccessView(
        status: _status,
        onOpenGallery: _noop,
        onOpenDevice: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('685GB'), findsOneWidget);
    expect(find.text('已识别'), findsOneWidget);
  });
}

final _status = DeviceStatus(
  connection: DeviceConnection(
    id: '7B2A-9C31',
    name: '拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.lan,
    isPaired: true,
  ),
  card: const CardStatus(inserted: true, readable: true, name: 'SanDisk 128GB'),
  batteryPercent: 78,
  storageFreeBytes: 685 * 1024 * 1024 * 1024,
);

void _noop() {}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pump();
}
