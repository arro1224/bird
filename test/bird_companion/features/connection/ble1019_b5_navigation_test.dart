import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/controlled_provisioning_repository.dart';

final device = ProvisioningDevice(
  scanId: 'box',
  advertisement: BirdBoxAdvertisement(localName: 'BirdBox-TEST', serviceUuids: const [], rssi: -45),
);
ProvisioningDeviceInfo info() => ProvisioningDeviceInfo.fromJson(Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map));
const window = PairingWindow(mode: PairingCodeMode.sessionRandom, codeExpiresIn: Duration(minutes: 2), attemptsRemaining: 3);

Future<void> authorized(ProvisioningCubit cubit) async {
  await cubit.selectDevice(device);
  await cubit.openPairing();
  await cubit.authorizePairing('123456');
  await Future<void>.delayed(Duration.zero);
  expect(cubit.state.phase, ProvisioningPhase.methodSelection);
}

class SessionRepository extends ControlledProvisioningRepository {
  SessionRepository() : super(devices: [device], deviceInfo: info(), pairingWindow: window);
  int releaseCalls = 0;
  Object? releaseError;
  Object? resumeError;
  Completer<void>? pendingConnect;
  @override
  Future<void> endSession(Object candidate) async {
    if (!ownsSession(candidate)) return;
    releaseCalls++;
    if (releaseError != null) throw releaseError!;
    await super.endSession(candidate);
  }

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice selected) async {
    await pendingConnect?.future;
    return super.connect(selected);
  }

  @override
  Future<void> resumeDiscovery(Object candidate) async {
    if (resumeError != null) throw resumeError!;
    await super.resumeDiscovery(candidate);
  }
}

void main() {
  test('foreground native snapshot error reaches UI without automatic retry', () async {
    final repository = SessionRepository();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await authorized(cubit);
    final before = List<String>.of(repository.calls);
    repository.resumeError = const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    await cubit.onAppResumed();
    expect(cubit.state.phase, ProvisioningPhase.failure);
    expect(cubit.state.error, isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleGattNotReady));
    expect(repository.calls, before);
  });
  test('return waits for one release and blocks every new BLE action until it finishes', () async {
    final repository = SessionRepository();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await authorized(cubit);
    final before = List<String>.of(repository.calls);
    repository.pendingEnd = Completer<void>();
    final first = cubit.returnToDiscovery();
    final duplicate = cubit.returnToDiscovery();
    expect(identical(first, duplicate), true);
    expect(cubit.state.phase, ProvisioningPhase.disconnecting);
    await Future<void>.delayed(Duration.zero);
    await cubit.discover();
    await cubit.selectDevice(device);
    await cubit.openPairing();
    await cubit.authorizePairing('123456');
    unawaited(cubit.retry());
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    expect(repository.calls, before);
    expect(repository.releaseCalls, 1);
    repository.pendingEnd!.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.linkStatus, BleLinkStatus.disconnected);
    expect(cubit.state.phase, ProvisioningPhase.discovered);
    expect(repository.calls.where((c) => c == 'discover').length, 1);
    expect(cubit.state.deviceInfo, isNull);
  });

  test('release failure keeps the gate closed until explicit retry succeeds', () async {
    final repository = SessionRepository();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      repository.releaseError = null;
      await cubit.close();
      await repository.dispose();
    });
    await authorized(cubit);
    repository.releaseError = StateError('private release error');
    await cubit.returnToDiscovery();
    expect(cubit.state.linkStatus, BleLinkStatus.releaseFailed);
    expect(cubit.state.phase, ProvisioningPhase.failure);
    final calls = List<String>.of(repository.calls);
    await cubit.selectDevice(device);
    await cubit.discover();
    await cubit.openPairing();
    expect(repository.calls, calls);
    repository.releaseError = null;
    await cubit.retry();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.phase, ProvisioningPhase.discovered);
    expect(cubit.state.error, isNull);
    expect(repository.releaseCalls, 2);
  });

  test('closing during return shares the pending release and never reclaims its owner', () async {
    final repository = SessionRepository()..pendingEnd = Completer<void>();
    final cubit = ProvisioningCubit(repository);
    final originalOwner = repository.owner;
    final returning = cubit.returnToDiscovery();
    await Future<void>.delayed(Duration.zero);
    final closing = cubit.close();
    repository.pendingEnd!.complete();
    await Future.wait([returning, closing]);
    expect(repository.releaseCalls, 1);
    expect(repository.owner, same(originalOwner));
    expect(repository.calls, isNot(contains('discover')));
    await repository.dispose();
  });

  test('transport loss clears trusted data and cannot automatically open pairing again', () async {
    final repository = SessionRepository();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await authorized(cubit);
    repository.emitDisconnect();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.linkStatus, BleLinkStatus.disconnected);
    expect(cubit.state.deviceInfo, isNull);
    expect(cubit.state.pairingWindow, isNull);
    expect(cubit.state.phase, ProvisioningPhase.failure);
    final count = repository.calls.where((c) => c == 'openPairing').length;
    await cubit.openPairing();
    expect(repository.calls.where((c) => c == 'openPairing').length, count);
  });

  test('cancel during preflight ignores the late connection result', () async {
    final repository = SessionRepository()..pendingConnect = Completer<void>();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    final selecting = cubit.selectDevice(device);
    await Future<void>.delayed(Duration.zero);
    repository.progress.add(const BlePairingProgress(requestId: 'prepare', stage: BlePairingStage.preflightPending));
    expect(cubit.state.phase, ProvisioningPhase.connecting);
    await cubit.openPairing();
    expect(repository.calls, isNot(contains('openPairing')));
    await cubit.returnToDiscovery();
    repository.pendingConnect!.complete();
    await selecting;
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.phase, ProvisioningPhase.discovered);
    expect(cubit.state.deviceInfo, isNull);
    expect(repository.calls, isNot(contains('openPairing')));
  });

  test('disconnect while pairing is unwinding cannot replace the source rejection', () async {
    final repository = SessionRepository()..pendingPairing = Completer<PairingWindow>();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.selectDevice(device);
    final pairing = cubit.openPairing();
    repository.emitDisconnect();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.linkStatus, BleLinkStatus.disconnected);
    repository.pendingPairing!.completeError(const ProvisioningException(code: ProvisioningErrorCode.blePairingRejected, retryable: false));
    await pairing;
    expect((cubit.state.error as ProvisioningException).code, ProvisioningErrorCode.blePairingRejected);
    expect(cubit.state.deviceInfo, isNull);
    expect(cubit.state.phase, ProvisioningPhase.failure);
  });

  testWidgets('method page returns through visible release state before scanning again', (tester) async {
    final repository = SessionRepository();
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    final cubit = tester.element(find.text('附近的盒子')).read<ProvisioningCubit>();
    await tester.runAsync(() => authorized(cubit));
    await tester.pumpAndSettle();
    expect(find.text('蓝牙已连接'), findsOneWidget);
    repository.pendingEnd = Completer<void>();
    final returns = find.byKey(const Key('ble-return-to-discovery'));
    await tester.ensureVisible(returns);
    await tester.pumpAndSettle();
    await tester.tap(returns);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('正在断开蓝牙，请稍候'), findsOneWidget);
    expect(find.text('连接此盒子'), findsNothing);
    expect(find.text('开始配对'), findsNothing);
    final back = tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '返回'));
    expect(back.onPressed, isNull);
    await tester.binding.handlePopRoute();
    expect(repository.releaseCalls, 1);
    repository.pendingEnd!.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('附近的盒子'), findsOneWidget);
    expect(find.text('蓝牙未连接'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });

  testWidgets('failed release disables device cards and offers retry release', (tester) async {
    final repository = SessionRepository();
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    final cubit = tester.element(find.text('附近的盒子')).read<ProvisioningCubit>();
    await tester.runAsync(() => authorized(cubit));
    repository.releaseError = StateError('private failure');
    await tester.runAsync(cubit.returnToDiscovery);
    await tester.pumpAndSettle();
    expect(find.text('蓝牙断开未完成，请重试断开；若持续失败，请关闭手机蓝牙后重试。'), findsOneWidget);
    expect(find.text('重试断开'), findsOneWidget);
    final button = find.ancestor(of: find.text('连接此盒子'), matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    repository.releaseError = null;
    await tester.tap(find.text('重试断开'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('蓝牙未连接'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });

  testWidgets('system back on the method page performs release instead of exiting the route', (tester) async {
    final repository = SessionRepository();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => ConnectionPage(provisioningRepository: repository))));
    await tester.pumpAndSettle();
    final cubit = tester.element(find.text('附近的盒子')).read<ProvisioningCubit>();
    await tester.runAsync(() => authorized(cubit));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('附近的盒子'), findsOneWidget);
    expect(navigator.currentState!.canPop(), true);
    expect(repository.releaseCalls, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });

  testWidgets('every public preflight stage hides start pairing and preserves cancel', (tester) async {
    final repository = SessionRepository()..pendingConnect = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    final cubit = tester.element(find.text('附近的盒子')).read<ProvisioningCubit>();
    final selecting = cubit.selectDevice(device);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (final stage in [BlePairingStage.preflightPending, BlePairingStage.resetConfirming, BlePairingStage.resetPending, BlePairingStage.waitingFreshAdvertisement, BlePairingStage.freshGattReconnecting]) {
      repository.progress.add(BlePairingProgress(requestId: 'prepare', stage: stage));
      await tester.pump();
      expect(find.text('开始配对'), findsNothing);
      expect(find.text('取消配对'), findsOneWidget);
    }
    await tester.runAsync(cubit.reset);
    repository.pendingConnect!.complete();
    await tester.runAsync(() => selecting);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });
}
