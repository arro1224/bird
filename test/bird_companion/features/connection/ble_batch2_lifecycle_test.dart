import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'fakes/controlled_provisioning_repository.dart';

const window = PairingWindow(mode: PairingCodeMode.sessionRandom, codeExpiresIn: Duration(minutes: 2), attemptsRemaining: 3);
final device = ProvisioningDevice(
  scanId: 'box',
  advertisement: BirdBoxAdvertisement(localName: 'BirdBox-TEST', serviceUuids: const [], rssi: -50),
);
ProvisioningDeviceInfo info() => ProvisioningDeviceInfo.fromJson(Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map));

void main() {
  test('permission settings return scans once only after grant and our departure', () async {
    var opens = 0;
    final repository = ControlledProvisioningRepository();
    final cubit = ProvisioningCubit(
      repository,
      permissionSettingsOpener: () async {
        opens++;
        return true;
      },
    );
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.openPermissionSettings();
    await cubit.openPermissionSettings();
    await cubit.onAppResumed();
    expect(repository.environmentReads, 0);
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    await cubit.onAppResumed();
    expect(opens, 1);
    expect(repository.calls.where((x) => x == 'discover'), hasLength(1));
  });

  test('permission settings cancellation or failed opening never triggers a scan', () async {
    for (final opened in [true, false]) {
      final repository = ControlledProvisioningRepository()..environment = const BleScanEnvironment(permission: BleScanPermissionState.denied, adapter: BleAdapterState.enabled);
      final cubit = ProvisioningCubit(repository, permissionSettingsOpener: () async => opened);
      await cubit.openPermissionSettings();
      await cubit.onAppBackgrounded();
      await cubit.onAppResumed();
      expect(repository.calls, isNot(contains('discover')));
      await cubit.close();
      await repository.dispose();
    }
  });

  test('old permission settings return cannot scan for a new page', () async {
    final repository = ControlledProvisioningRepository();
    final cubit = ProvisioningCubit(repository, permissionSettingsOpener: () async => true);
    await cubit.openPermissionSettings();
    await cubit.onAppBackgrounded();
    repository.claimSession();
    await cubit.onAppResumed();
    expect(repository.calls, isNot(contains('discover')));
    await cubit.close();
    await repository.dispose();
  });
  test('location return scans once only after our settings departure', () async {
    final repository = ControlledProvisioningRepository();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    expect(repository.environmentReads, 0);
    await cubit.openLocationSettings();
    await cubit.openLocationSettings();
    await cubit.onAppResumed();
    expect(repository.environmentReads, 0);
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    await cubit.onAppResumed();
    expect(repository.settingsCalls, 1);
    expect(repository.environmentReads, 1);
    expect(repository.calls.where((x) => x == 'discover'), hasLength(1));
  });

  test('return with location disabled keeps guidance and does not scan', () async {
    final repository = ControlledProvisioningRepository()..environment = const BleScanEnvironment(permission: BleScanPermissionState.granted, adapter: BleAdapterState.enabled, locationService: BleLocationServiceState.disabled);
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.openLocationSettings();
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    expect(repository.calls, isNot(contains('discover')));
    expect((cubit.state.error as ProvisioningException).code, ProvisioningErrorCode.locationServicesDisabled);
    expect(UserMessageMapper.fromError(cubit.state.error!).message, contains('App 不读取或上传您的位置'));
  });

  test('unavailable settings clears resume intent and exposes manual instruction', () async {
    final repository = ControlledProvisioningRepository()..settingsError = const ProvisioningException(code: ProvisioningErrorCode.locationSettingsUnavailable, retryable: false);
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.openLocationSettings();
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    expect(repository.environmentReads, 0);
    expect(UserMessageMapper.fromError(cubit.state.error!).message, contains('手动打开'));
  });

  test('system bond pause retains attempt; double click and reset ignore late result', () async {
    final repository = ControlledProvisioningRepository(deviceInfo: info())..pendingPairing = Completer<PairingWindow>();
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
    });
    await cubit.selectDevice(device);
    final pending = cubit.openPairing();
    await cubit.openPairing();
    final callsBefore = List<String>.of(repository.calls);
    repository.progress.add(const BlePairingProgress(requestId: 'request', stage: BlePairingStage.systemBond, attemptId: 'attempt', connectionGeneration: 2));
    await cubit.onAppBackgrounded();
    await cubit.onAppResumed();
    expect(repository.calls, callsBefore);
    expect(cubit.state.pairingProgress?.stage, BlePairingStage.systemBond);
    expect(repository.calls.where((x) => x == 'openPairing'), hasLength(1));
    await cubit.reset();
    repository.pendingPairing!.complete(window);
    await pending;
    expect(cubit.state.phase, ProvisioningPhase.idle);
    expect(repository.endedSessions, 1);
  });

  test('old page cleanup cannot reclaim or disconnect a newer page', () async {
    final repository = ControlledProvisioningRepository()..pendingEnd = Completer<void>();
    final old = ProvisioningCubit(repository);
    final reset = old.reset();
    await Future<void>.delayed(Duration.zero);
    final current = ProvisioningCubit(repository);
    final owner = repository.owner;
    repository.pendingEnd!.complete();
    await reset;
    await old.close();
    expect(repository.owner, same(owner));
    expect(repository.endedSessions, 0);
    expect(repository.calls, isNot(contains('disconnect')));
    await current.close();
    expect(repository.endedSessions, 1);
    await repository.dispose();
  });

  test('successful handoff keeps the owned session alive', () async {
    final repository = ControlledProvisioningRepository();
    final cubit = ProvisioningCubit(repository)..retainSession = true;
    await cubit.close();
    expect(repository.endedSessions, 0);
    await repository.dispose();
  });

  testWidgets('location error button opens settings and renders privacy guidance', (tester) async {
    final repository = ControlledProvisioningRepository(discoverError: const ProvisioningException(code: ProvisioningErrorCode.locationServicesDisabled, retryable: true));
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    expect(find.textContaining('App 不读取或上传您的位置'), findsOneWidget);
    await tester.tap(find.text('去开启位置信息'));
    await tester.pump();
    expect(repository.settingsCalls, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });

  testWidgets('pairing progress shows each native stage and allows owned cancel', (tester) async {
    final repository = ControlledProvisioningRepository(devices: [device], deviceInfo: info())..pendingPairing = Completer<PairingWindow>();
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    final cubit = tester.element(find.text('附近的盒子')).read<ProvisioningCubit>();
    await tester.runAsync(() => cubit.selectDevice(device));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始配对'));
    await tester.pump();
    for (final entry in const {BlePairingStage.systemBond: '正在完成系统蓝牙配对', BlePairingStage.reconnecting: '正在重新连接盒子', BlePairingStage.restoringNotifications: '正在恢复盒子通知', BlePairingStage.waitingResponse: '正在等待盒子确认'}.entries) {
      repository.progress.add(BlePairingProgress(requestId: 'req', stage: entry.key));
      await tester.pump();
      expect(find.textContaining(entry.value), findsOneWidget);
    }
    await tester.tap(find.text('取消配对'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    repository.pendingPairing!.complete(window);
    await tester.pump();
    expect(find.text('附近的盒子'), findsOneWidget);
    expect(repository.endedSessions, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });
}
