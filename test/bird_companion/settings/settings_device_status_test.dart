import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default reconnect opens device discovery without a production scope', (tester) async {
    RouteSettings? route;
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          route = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('connection')),
          );
        },
        home: const SettingsShowcasePage(embedded: true),
      ),
    );

    await tester.tap(find.byKey(const Key('showcase-device-primary-action')));
    await tester.pumpAndSettle();

    _expectReconnectRoute(route);
  });

  testWidgets('default reconnect opens device discovery when the scoped session has no device', (tester) async {
    final session = _TestDeviceSessionCubit(const DeviceSessionState());
    final dependencies = _TestDependencies(session);
    RouteSettings? route;
    addTearDown(session.close);

    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: MaterialApp(
          onGenerateRoute: (settings) {
            route = settings;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('connection')),
            );
          },
          home: const SettingsShowcasePage(embedded: true),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('showcase-device-primary-action')));
    await tester.pumpAndSettle();

    expect(session.reconnectCount, 0);
    _expectReconnectRoute(route);
  });

  testWidgets('default reconnect preserves the latest scoped device and opens discovery', (tester) async {
    final session = _TestDeviceSessionCubit(const DeviceSessionState());
    final dependencies = _TestDependencies(session);
    final connection = _connection(id: 'known', name: '已知盒子');
    RouteSettings? route;
    addTearDown(session.close);

    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: dependencies,
        child: MaterialApp(
          onGenerateRoute: (settings) {
            route = settings;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('connection')),
            );
          },
          home: const SettingsShowcasePage(embedded: true),
        ),
      ),
    );

    session.emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: connection));
    await tester.pump();
    session.emit(DeviceSessionState(phase: DeviceSessionPhase.disconnected, device: connection));
    await tester.pumpAndSettle();

    expect(session.state.device, same(connection));
    expect(dependencies.deviceSessionCubit.state.device, same(connection));
    expect(find.text('已知盒子'), findsOneWidget);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重新连接'), findsOneWidget);

    await tester.tap(find.byKey(const Key('showcase-device-primary-action')));
    await tester.pump();

    expect(session.reconnectCount, 0);
    _expectReconnectRoute(route);
  });

  testWidgets('reconnect action invokes the injected callback once', (tester) async {
    var reconnectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShowcasePage(
          embedded: true,
          onReconnect: () => reconnectCount++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('showcase-device-primary-action')));
    await tester.pump();

    expect(reconnectCount, 1);
  });

  testWidgets('settings device card follows live connection and status state', (tester) async {
    final connection = DeviceConnection(
      id: 'k7-live',
      name: '拍鸟伴侣 K7 Pro',
      baseUri: Uri.parse('http://192.168.4.1:8080'),
      networkMode: NetworkMode.hotspot,
      signalStrength: 86,
    );
    final session = _TestStateCubit<DeviceSessionState>(const DeviceSessionState());
    final status = _TestStateCubit<DeviceStatusState>(const DeviceStatusState());
    addTearDown(session.close);
    addTearDown(status.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShowcasePage(
          deviceSession: session,
          deviceStatus: status,
        ),
      ),
    );

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('未连接拍鸟盒子'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '连接设备'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('showcase-device-primary-action'))).height,
      greaterThanOrEqualTo(48),
    );

    session.emit(const DeviceSessionState(phase: DeviceSessionPhase.connecting));
    await tester.pump();

    expect(find.bySemanticsLabel('正在连接设备'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    session.emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: connection));
    status.emit(
      DeviceStatusState(
        phase: DeviceStatusPhase.ready,
        status: DeviceStatus(
          connection: connection,
          card: const CardStatus(inserted: true, readable: true),
          batteryPercent: 82,
          storageFreeBytes: 734000000000,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('拍鸟伴侣 K7 Pro'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('82% · 684 GB 可用'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '设备详情'), findsOneWidget);
  });

  testWidgets('replacing state sources immediately shows their current state', (tester) async {
    final oldConnection = _connection(id: 'old', name: '旧盒子');
    final newConnection = _connection(id: 'new', name: '新盒子');
    final oldSession = _TestStateCubit<DeviceSessionState>(
      DeviceSessionState(phase: DeviceSessionPhase.connected, device: oldConnection),
    );
    final oldStatus = _TestStateCubit<DeviceStatusState>(
      _readyStatus(oldConnection, batteryPercent: 10),
    );
    final newSession = _TestStateCubit<DeviceSessionState>(
      DeviceSessionState(phase: DeviceSessionPhase.connected, device: newConnection),
    );
    final newStatus = _TestStateCubit<DeviceStatusState>(
      _readyStatus(newConnection, batteryPercent: 90),
    );
    addTearDown(oldSession.close);
    addTearDown(oldStatus.close);
    addTearDown(newSession.close);
    addTearDown(newStatus.close);

    StateStreamable<DeviceSessionState> session = oldSession;
    StateStreamable<DeviceStatusState> status = oldStatus;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SettingsShowcasePage(
              embedded: true,
              deviceSession: session,
              deviceStatus: status,
            );
          },
        ),
      ),
    );

    expect(find.text('旧盒子'), findsOneWidget);
    expect(find.text('10% · -- 可用'), findsOneWidget);

    rebuild(() {
      session = newSession;
      status = newStatus;
    });
    await tester.pump();

    expect(find.text('新盒子'), findsOneWidget);
    expect(find.text('90% · -- 可用'), findsOneWidget);
    expect(find.text('旧盒子'), findsNothing);
  });

  testWidgets('current work uses explicit demo fallback values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsShowcasePage(embedded: true),
      ),
    );

    expect(find.text('演示数据'), findsOneWidget);
    expect(find.text('演示批次'), findsOneWidget);
    expect(find.text('湖畔清晨 · 328 张照片 · 24 张待审'), findsOneWidget);
    expect(find.text('演示任务'), findsOneWidget);
    expect(find.text('AI 分析 · 65%'), findsOneWidget);
  });

  testWidgets('current work accepts injected summaries and callbacks', (tester) async {
    var batchOpenCount = 0;
    var taskOpenCount = 0;
    final page = SettingsShowcasePage(
      embedded: true,
      currentBatchTitle: '林地晨拍',
      currentBatchSummary: '412 张照片 · 36 张待审',
      currentTaskTitle: '导入/索引',
      currentTaskSummary: '168 / 412 · 41%',
      onOpenCurrentBatch: () => batchOpenCount++,
      onOpenCurrentTask: () => taskOpenCount++,
    );

    await tester.pumpWidget(MaterialApp(home: page));

    expect(find.text('演示数据'), findsNothing);
    expect(find.text('林地晨拍'), findsOneWidget);
    expect(find.text('412 张照片 · 36 张待审'), findsOneWidget);
    expect(find.text('导入/索引'), findsOneWidget);
    expect(find.text('168 / 412 · 41%'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('device-current-work-card'))).height, lessThanOrEqualTo(136));

    for (final key in const [Key('device-current-work-batch'), Key('device-current-work-task')]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(key));
      await tester.pump();
    }
    expect(batchOpenCount, 1);
    expect(taskOpenCount, 1);
    expect(
      find.ancestor(
        of: find.byKey(const Key('device-current-work-card')),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
  });
}

void _expectReconnectRoute(RouteSettings? route) {
  expect(route?.name, BirdRoutes.connection);
  expect(
    (route?.arguments as ConnectionArgs).entryMode,
    ConnectionEntryMode.addOrSwitch,
  );
}

class _TestStateCubit<T> extends Cubit<T> {
  _TestStateCubit(super.initialState);
}

class _TestDeviceSessionCubit extends Cubit<DeviceSessionState> implements DeviceSessionCubit {
  _TestDeviceSessionCubit(super.initialState);

  int reconnectCount = 0;

  @override
  Future<void> reconnect() async {
    reconnectCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDependencies implements BirdCompanionDependencies {
  _TestDependencies(this.deviceSessionCubit);

  @override
  final DeviceSessionCubit deviceSessionCubit;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DeviceConnection _connection({required String id, required String name}) => DeviceConnection(
  id: id,
  name: name,
  baseUri: Uri.parse('http://192.168.4.1:8080'),
  networkMode: NetworkMode.hotspot,
);

DeviceStatusState _readyStatus(DeviceConnection connection, {required int batteryPercent}) => DeviceStatusState(
  phase: DeviceStatusPhase.ready,
  status: DeviceStatus(
    connection: connection,
    card: const CardStatus(inserted: true, readable: true),
    batteryPercent: batteryPercent,
  ),
);
