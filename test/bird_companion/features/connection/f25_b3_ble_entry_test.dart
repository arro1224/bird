import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../nov18_navigation_test_support.dart';
import 'fakes/reusable_provisioning_repository.dart';

void main() {
  for (final recover in [true, false]) {
    testWidgets('current STA business card directly opens ${recover ? 'BLE recovery' : 'network settings'} once', (tester) async {
      final repository = _Repository();
      final deps = _Dependencies(repository);
      final observer = B4RouteObserver();
      addTearDown(() async {
        await repository.dispose();
        await deps.close();
      });
      final original = deps.deviceSessionCubit.state.device;
      await pumpB4(
        tester,
        ConnectionPage(entryMode: ConnectionEntryMode.addOrSwitch, provisioningRepository: repository),
        deps,
        observers: [observer],
        routes: (settings) => BirdAppRouter.onGenerateRoute(settings, provisioningRepository: repository),
      );
      expect(find.text('业务连接有效，蓝牙控制未连接'), findsOneWidget);
      expect(find.byKey(const Key('ble-search-again')), findsOneWidget);
      final button = find.byKey(Key(recover ? 'current-business-recover-ble' : 'current-business-change-network'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await tester.tap(button, warnIfMissed: false);
        }
        // Cancelling the completed discovery stream drains the event queue.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(observer.count(BirdRoutes.settingsNetwork), 1);
      final route = observer.pushes.last.settings.arguments as NetworkSettingsArgs;
      expect(route.deviceId, firstBleInfo.deviceId);
      expect(route.recoverBleOnOpen, recover);
      expect(repository.recoveries, recover ? 1 : 0);
      expect(deps.deviceSessionCubit.state.device, same(original));
      expect(deps.deviceSessionCubit.state.isConnected, true);
      if (recover) {
        repository.result.complete(firstBleInfo);
        await tester.pumpAndSettle();
      }
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      if (recover) expect(find.text('当前盒子蓝牙控制已连接'), findsOneWidget);
      expect(deps.verifications, 0);
      expect(repository.calls, isNot(contains('setStaConfig')));
      expect(repository.calls, isNot(contains('startDirectAp')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (recover) {
        expect(repository.endedSessions, 0);
        expect(repository.currentBleDevice?.deviceInfo?.deviceId, firstBleInfo.deviceId);
      }
    });
  }
  testWidgets('switching business devices cancels recovery and blocks a late result', (tester) async {
    final repository = _Repository();
    final deps = _Dependencies(repository);
    addTearDown(() async {
      await repository.dispose();
      await deps.close();
    });
    await pumpB4(tester, NetworkSettingsPage(repository: repository, deviceId: firstBleInfo.deviceId, recoverBleOnOpen: true), deps);
    expect(repository.recoveries, 1);
    deps.deviceSessionCubit.switchDevice();
    await tester.pumpAndSettle();
    expect(repository.token?.isCancelled, true);
    repository.result.complete(firstBleInfo);
    await tester.pumpAndSettle();
    expect(find.text('当前设备已切换，请返回后打开新设备的网络设置。'), findsOneWidget);
    expect(deps.verifications, 0);
    expect(repository.calls, isNot(contains('getNetworkStatus')));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Session extends B4Session {
  _Session() {
    emit(
      DeviceSessionState(
        phase: DeviceSessionPhase.connected,
        device: DeviceConnection(id: firstBleInfo.deviceId, name: 'K7', baseUri: Uri.parse('http://192.0.2.2:8787'), networkMode: NetworkMode.infrastructureSta),
      ),
    );
  }
  @override
  void beginNetworkIntent(String id) {}
  @override
  void endNetworkIntent(String id) {}
}

class _Monitor extends ConnectivityMonitor {
  @override
  Stream<void> get onTransportChanged => const Stream.empty();
}

class _Dependencies extends B4Dependencies {
  _Dependencies(this.repository);
  final _Repository repository;
  final _session = _Session();
  @override
  _Session get deviceSessionCubit => _session;
  @override
  ProvisioningRepository get provisioningRepository => repository;
  @override
  ConnectivityMonitor get connectivityMonitor => _Monitor();
  int verifications = 0;
  @override
  DirectApHandoffCubit createDirectApHandoff() => DirectApHandoffCubit(
    store: cache,
    verify: (_, _) async {
      verifications++;
      throw StateError('BLE recovery must preserve business session');
    },
  );
  @override
  PendingDirectAp? pendingVerifiedBleEndpoint(ProvisioningDeviceInfo info) => null;
}

class _Repository extends ReusableProvisioningRepository implements BleControlRecovery {
  int recoveries = 0;
  CancelToken? token;
  final result = Completer<ProvisioningDeviceInfo>();
  _Repository() {
    owner = null;
    networkStatus = ProvisioningEvent.fromJson(Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync()) as Map)).payload as ProvisioningNetworkStatus;
  }
  @override
  Future<ProvisioningDeviceInfo> recoverBleControl(String id, CancelToken cancelToken) async {
    recoveries++;
    token = cancelToken;
    final info = await result.future;
    cancelToken.throwIfCancellationRequested();
    await super.connect(firstBleDevice);
    return info;
  }
}
