import 'dart:async';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/simulation/embedded_demo/demo_runtime.dart';
import 'package:dio/dio.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/connection/fakes/fake_provisioning_repository.dart';

void main() {
  testWidgets('stop remains usable after an AP status refresh leaves the page idle and ten taps send once', (tester) async {
    final repository = _StopRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.networkStatus = _idleApStatus;
    await tester.tap(find.byTooltip('刷新蓝牙状态'));
    await tester.pumpAndSettle();
    expect(find.text('蓝牙控制已连接'), findsOneWidget);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, '停止盒子直连'));
    expect(button.onPressed, isNotNull);
    for (var i = 0; i < 10; i++) {
      button.onPressed!();
    }
    await tester.pumpAndSettle();
    expect(find.text('断开盒子直连？'), findsOneWidget);
    repository.statusGate = Completer<ProvisioningNetworkStatus>();
    final confirm = tester.widget<TextButton>(find.widgetWithText(TextButton, '断开并恢复 Wi-Fi'));
    confirm.onPressed!();
    await tester.pumpAndSettle();
    expect(repository.calls.where((c) => c == 'stopDirectAp'), isEmpty);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '停止盒子直连')).onPressed, isNull);
    repository.statusGate!.complete(_idleApStatus);
    await tester.pump();
    await tester.pump();
    expect(repository.calls.where((c) => c == 'stopDirectAp'), hasLength(1));
    expect(find.text('正在停止盒子直连'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scenario in ['cancel', 'mode_changed', 'ble_lost', 'page_exit', 'busy', 'validation_timeout']) {
    testWidgets('stop sends no command when $scenario occurs during confirmation or validation', (tester) async {
      final repository = _StopRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NetworkSettingsPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止盒子直连'));
      await tester.pumpAndSettle();
      if (scenario == 'cancel') {
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      } else {
        repository.statusGate = Completer<ProvisioningNetworkStatus>();
        await tester.tap(find.text('断开并恢复 Wi-Fi'));
        await tester.pumpAndSettle();
        if (scenario == 'ble_lost') {
          repository.emitDisconnect();
          await tester.pump();
        }
        if (scenario == 'page_exit') await tester.pumpWidget(const SizedBox.shrink());
        if (scenario == 'validation_timeout') {
          await tester.pump(const Duration(seconds: 16));
          await tester.pump();
          expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '停止盒子直连')).onPressed, isNotNull);
        }
        repository.statusGate!.complete(
          scenario == 'mode_changed'
              ? _staStatus
              : scenario == 'busy'
              ? _busyApStatus
              : _directApStatus,
        );
        await tester.pump();
        await tester.pump();
      }
      expect(repository.calls.where((c) => c == 'stopDirectAp'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('an explicit recovery entry starts once and does not verify or change business networking', (tester) async {
    final repository = _ColdControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository, deviceId: _deviceInfo.deviceId, recoverBleOnOpen: true),
      ),
    );
    await tester.pump();
    expect(repository.recoveries, 1);
    repository.result.complete(_deviceInfo);
    await tester.pumpAndSettle();
    expect(repository.verifications, 0);
    expect(repository.calls, isNot(contains('setStaConfig')));
    expect(repository.calls, isNot(contains('startDirectAp')));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('opening network settings alone does not automatically recover BLE', (tester) async {
    final repository = _ColdControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkSettingsPage(repository: repository, deviceId: _deviceInfo.deviceId),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.recoveries, 0);
    expect(find.text('恢复当前盒子蓝牙控制'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final error in <Object>[
    const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: true),
    const BleControlRecoveryException(BleControlRecoveryFailure.notFound),
  ]) {
    testWidgets('recovery presents the classified ${error.runtimeType} result', (tester) async {
      final repository = _ColdControlRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkSettingsPage(repository: repository, deviceId: _deviceInfo.deviceId, recoverBleOnOpen: true),
        ),
      );
      await tester.pump();
      repository.result.completeError(error);
      await tester.pumpAndSettle();
      expect(find.textContaining(error is ProvisioningException ? '需要蓝牙权限' : '未找到当前盒子蓝牙'), findsOneWidget);
      expect(repository.verifications, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('a stalled recovery exits with timeout text rather than a user-cancel claim', (tester) async {
    final repository = _ColdControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkSettingsPage(repository: repository, deviceId: _deviceInfo.deviceId, recoverBleOnOpen: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(find.textContaining('蓝牙恢复超时'), findsOneWidget);
    expect(repository.token?.isCancelled, true);
    expect(repository.token?.cancelError?.error, isA<BleControlRecoveryException>());
    repository.result.complete(_deviceInfo);
    await tester.pumpAndSettle();
    expect(find.text('蓝牙控制已断开'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('requires BLE reconnect when there is no trusted BLE session', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );

    expect(
      find.byKey(const Key('network-settings-ble-reconnect')),
      findsOneWidget,
    );
    expect(find.text('状态待确认'), findsOneWidget);
    expect(find.text('蓝牙控制已断开，恢复后才能读取盒子的网络状态。'), findsOneWidget);
  });

  testWidgets('loads Direct AP state and treats BLE loss as resumable', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      deviceInfo: _deviceInfo,
      networkStatus: _directApStatus,
      stopDirectApResult: const CommandAccepted(
        operationId: 'op_stop_settings',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('盒子热点'), findsOneWidget);
    expect(find.text('停止盒子直连'), findsOneWidget);

    await tester.tap(find.text('停止盒子直连'));
    await tester.pump();
    expect(find.text('断开盒子直连？'), findsOneWidget);
    expect(repository.calls, isNot(contains('stopDirectAp')));
    await tester.tap(find.text('断开并恢复 Wi-Fi'));
    await tester.pump();
    await tester.pump();
    expect(repository.calls, contains('stopDirectAp'));
    expect(find.text('正在停止盒子直连'), findsOneWidget);

    repository.emitDisconnect();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('network-settings-direct-ap')), findsOneWidget);
    expect(find.text('蓝牙控制已断开'), findsOneWidget);
    expect(find.text('恢复当前盒子蓝牙控制'), findsOneWidget);
    expect(find.text('停止盒子直连'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('demo Wi-Fi methods show the next step and return to settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = B7SimulatedProvisioningRepository();
    addTearDown(repository.dispose);
    await tester.runAsync(() async {
      await repository.connect(await repository.discoverDevices().first);
      await repository.openPairing();
      await repository.authorizePairing('123456');
    });
    ProvisioningCompletion? completion;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(
          repository: repository,
          phoneWifi: const DemoPhoneWifiPlatform(),
          demoMode: true,
          onProvisioningCompleted: (value) async => completion = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.byKey(const Key('settings-back')));
      await tester.pumpAndSettle();
    }

    List<String> formValues() => tester.widgetList<EditableText>(find.byType(EditableText)).map((field) => field.controller.text).toList();

    expect(find.text('选择其他 Wi-Fi'), findsNothing);
    await tap('连接手机当前 Wi-Fi');
    expect(formValues(), ['BirdLab-5G', '']);
    await back();

    await tap('搜索附近 Wi-Fi');
    await tap('BirdLab-5G');
    expect(formValues(), ['BirdLab-5G', '']);
    await back();
    await tap('停止盒子直连');
    expect(find.text('断开盒子直连？'), findsOneWidget);
    await tap('取消');

    await tap('手动输入 Wi-Fi');
    expect(formValues(), ['', '']);
    await back();

    await tap('扫描 Wi-Fi 二维码');
    await tap('识别演示二维码');
    expect(find.text('确认目标网络'), findsOneWidget);
    await tap('确认连接此 Wi-Fi');
    expect(find.text('盒子已加入 Wi-Fi'), findsOneWidget);
    await tap('完成');
    expect(completion?.networkMode, ProvisioningNetworkMode.infrastructureSta);
    expect(find.text('网络设置'), findsOneWidget);
    expect(find.text('路由器 Wi-Fi'), findsOneWidget);
    expect(find.text('停止盒子直连'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the network overview for router Wi-Fi and hides direct-AP actions', (tester) async {
    final repository = FakeProvisioningRepository(
      deviceInfo: _deviceInfo,
      networkStatus: _staStatus,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('network-settings-direct-ap')), findsOneWidget);
    expect(find.text('路由器 Wi-Fi'), findsOneWidget);
    expect(find.text('网络方式已知，App 与盒子的业务连接尚未验证'), findsOneWidget);
    expect(find.text('停止盒子直连'), findsNothing);
    expect(find.text('搜索附近 Wi-Fi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ten taps recover control once in place without HTTP verification', (tester) async {
    final repository = _ControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.emitDisconnect();
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('恢复当前盒子蓝牙控制'));
    }
    await tester.pump();
    expect(repository.recoveries, 1);
    expect(find.text('正在恢复蓝牙控制…'), findsOneWidget);
    repository.result.complete(_deviceInfo);
    await tester.pumpAndSettle();
    expect(find.byType(NetworkSettingsPage), findsOneWidget);
    expect(find.text('蓝牙控制已连接'), findsOneWidget);
    expect(find.text('网络方式已知，App 与盒子的业务连接尚未验证'), findsOneWidget);
    expect(repository.verifications, 0);
    expect(repository.calls.where((c) => c == 'getNetworkStatus'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancel and page exit ignore late BLE recovery, allowing retry', (tester) async {
    final repository = _ControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.emitDisconnect();
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复当前盒子蓝牙控制'));
    await tester.pump();
    final old = repository.result;
    await tester.tap(find.text('取消蓝牙恢复'));
    await tester.pump();
    expect(repository.token?.isCancelled, true);
    old.complete(_deviceInfo);
    await tester.pumpAndSettle();
    expect(find.text('蓝牙控制已断开'), findsOneWidget);
    repository.result = Completer<ProvisioningDeviceInfo>();
    await tester.tap(find.text('恢复当前盒子蓝牙控制'));
    await tester.pump();
    expect(repository.recoveries, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(repository.token?.isCancelled, true);
    repository.result.complete(_deviceInfo);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(repository.calls.where((c) => c == 'getNetworkStatus'), hasLength(1));
  });

  testWidgets('BLE recovery failure stays on settings and can retry', (tester) async {
    final repository = _ControlRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NetworkSettingsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    repository.emitDisconnect();
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复当前盒子蓝牙控制'));
    await tester.pump();
    repository.result.completeError(StateError('fake transport failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('蓝牙控制恢复未完成'), findsOneWidget);
    repository.result = Completer<ProvisioningDeviceInfo>();
    await tester.tap(find.text('恢复当前盒子蓝牙控制'));
    await tester.pump();
    repository.result.complete(_deviceInfo);
    await tester.pumpAndSettle();
    expect(repository.recoveries, 2);
    expect(find.text('蓝牙控制已连接'), findsOneWidget);
    expect(repository.verifications, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _StopRepository extends FakeProvisioningRepository implements BleControlRecovery {
  _StopRepository()
    : super(
        deviceInfo: _deviceInfo,
        networkStatus: _directApStatus,
        stopDirectApResult: const CommandAccepted(operationId: 'op_stop_once', desiredMode: ProvisioningNetworkMode.infrastructureSta),
      );
  Completer<ProvisioningNetworkStatus>? statusGate;
  @override
  Future<ProvisioningDeviceInfo> recoverBleControl(String deviceId, CancelToken cancelToken) async => _deviceInfo;
  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() => statusGate?.future ?? super.getNetworkStatus();
}

final _idleApStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.idle,
  busy: false,
  directAp: const DirectApSnapshot(ssid: 'BirdBox-Test'),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 11, 28),
);
final _busyApStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.infrastructureSta,
  operationState: NetworkOperationState.stoppingAp,
  busy: true,
  directAp: const DirectApSnapshot(ssid: 'BirdBox-Test'),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 11, 28),
);

class _ControlRepository extends FakeProvisioningRepository implements BleControlRecovery, ProvisioningNetworkStatusVerifier {
  _ControlRepository() : super(deviceInfo: _deviceInfo, networkStatus: _directApStatus);
  Completer<ProvisioningDeviceInfo> result = Completer();
  CancelToken? token;
  int recoveries = 0, verifications = 0;
  @override
  Future<ProvisioningDeviceInfo> recoverBleControl(String deviceId, CancelToken cancelToken) {
    expect(deviceId, _deviceInfo.deviceId);
    recoveries++;
    token = cancelToken;
    return result.future;
  }

  @override
  Future<void> verifyNetworkStatus(ProvisioningNetworkStatus status) async {
    verifications++;
    throw StateError('HTTP unavailable');
  }
}

class _ColdControlRepository extends _ControlRepository {
  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => null;
}

const _deviceInfo = ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-Test',
  firmwareVersion: '1.0.0',
  apiVersion: '1.0',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: Duration(minutes: 2),
  displayAvailable: true,
  capabilities: DeviceCapabilities(
    directAp: true,
    infrastructureSta: true,
    wifiScan: true,
    wifiManual: true,
    dppEnrolleeSupported: true,
    dppSupportedAkm: {'psk'},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);

final _directApStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.directAp,
  desiredMode: ProvisioningNetworkMode.directAp,
  operationState: NetworkOperationState.apReady,
  operationId: 'op_direct_settings',
  busy: false,
  baseUri: Uri.parse('http://192.168.8.1:8080'),
  directAp: const DirectApSnapshot(ssid: 'BirdBox-Test'),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  updatedAt: DateTime.utc(2026, 9, 2),
);

final _staStatus = ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.infrastructureSta,
  desiredMode: ProvisioningNetworkMode.infrastructureSta,
  operationState: NetworkOperationState.staConnected,
  operationId: 'op_sta_settings',
  busy: false,
  baseUri: Uri.parse('http://192.168.1.20:8080'),
  directAp: const DirectApSnapshot(),
  infrastructureSta: const InfrastructureStaSnapshot(ssid: 'Home Wi-Fi', ipv4: '192.168.1.20', saved: true),
  updatedAt: DateTime.utc(2026, 9, 2),
);
