import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/connection_method_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/sta_network_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_provisioning_repository.dart';

void main() {
  for (final entry in <(Object, String)>[
    (const ProvisioningCredentialSaveException(), '重试保存连接'),
    (const ProvisioningException(code: ProvisioningErrorCode.pairingSessionUsed, retryable: false), '重新安全授权'),
  ]) {
    testWidgets('BLE-21 failure exposes correct stage: ${entry.$2}', (tester) async {
      final repository = FakeProvisioningRepository(startDirectApError: entry.$1);
      final cubit = NetworkProvisioningCubit(repository);
      addTearDown(cubit.close);
      addTearDown(repository.dispose);
      await cubit.startDirectAp(_deviceInfo());
      var reauthorized = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: NetworkProvisioningPage(onBack: () {}, onReauthorize: () => reauthorized = true),
            ),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.text('扫描 Wi-Fi 二维码'), findsNothing);
      if (entry.$2 == '重新安全授权') {
        await tester.tap(find.text(entry.$2));
        expect(reauthorized, isTrue);
      }
    });
  }
  testWidgets('connection methods disable unsupported capabilities', (
    tester,
  ) async {
    ConnectionMethod? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ConnectionMethodPage(
            deviceName: 'BirdBox-1A2B3C4D',
            capabilities: _capabilities(directAp: false),
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('此盒子不支持直连模式'), findsOneWidget);
    await tester.tap(find.text('直连盒子'));
    await tester.pump();
    expect(selected, isNull);

    await tester.tap(find.text('加入现有 Wi-Fi'));
    expect(selected, ConnectionMethod.existingWifi);
  });

  testWidgets('manual Wi-Fi form validates and clears the password on submit', (
    tester,
  ) async {
    StaNetworkConfiguration? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StaNetworkForm(onSubmit: (value) => submitted = value),
        ),
      ),
    );

    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-password'))).obscureText,
      isTrue,
    );
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    expect(find.text('请输入 Wi-Fi 名称'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('wifi-ssid')),
      'Studio',
    );
    await tester.enterText(
      find.byKey(const ValueKey('wifi-password')),
      'synthetic-value',
    );
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();

    expect(submitted?.selectionMethod, WifiSelectionMethod.manual);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-password'))).controller?.text,
      isEmpty,
    );
  });

  testWidgets('Wi-Fi provisioning page scans and shows safe results', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      scanWifiResult: const CommandAccepted(
        operationId: 'op_scan',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
        provisioningMethod: ProvisioningMethod.bleScanSelection,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: NetworkProvisioningPage(onBack: () {}),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('连接手机当前 Wi-Fi'), findsOneWidget);
    expect(find.textContaining('首次连接请填写密码'), findsOneWidget);
    expect(find.text('扫描 Wi-Fi 二维码'), findsOneWidget);
    expect(find.text('选择或手动输入网络'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    // DPP is not offered this round: the card is gone, not merely disabled.
    expect(find.text('使用手机安全共享 Wi-Fi'), findsNothing);
    expect(find.textContaining('安全共享'), findsNothing);
    expect(
      tester.getTopLeft(find.text('连接手机当前 Wi-Fi')).dy,
      lessThan(tester.getTopLeft(find.text('扫描 Wi-Fi 二维码')).dy),
    );
    expect(
      tester.getTopLeft(find.text('扫描 Wi-Fi 二维码')).dy,
      lessThan(tester.getTopLeft(find.text('选择或手动输入网络')).dy),
    );

    await tester.tap(find.text('选择或手动输入网络'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('搜索附近 Wi-Fi'));
    await tester.tap(find.text('搜索附近 Wi-Fi'));
    await tester.pump();
    repository.emitEvent(
      ProvisioningEvent(
        type: ProvisioningEventType.wifiScanResults,
        requestId: 'request-scan',
        deviceId: _deviceInfo().deviceId,
        payload: const WifiScanBatch(
          batchIndex: 0,
          batchCount: 1,
          complete: true,
          networks: [
            WifiScanNetwork(
              ssid: 'Studio',
              bssid: 'AA:00:00:00:00:01',
              rssiDbm: -42,
              frequencyMhz: 2412,
              security: WifiSecurity.wpa2Personal,
              unsupported: false,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Studio'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('-42 dBm'), findsOneWidget);
  });

  testWidgets('DPP is not offered as a Wi-Fi provisioning method this round', (tester) async {
    final repository = FakeProvisioningRepository(
      dppAvailability: const DppAvailability(
        boxSupported: true,
        apiLevelSupported: true,
        easyConnectSupported: true,
        activityAvailable: true,
        sessionReady: true,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));
    await tester.pumpAndSettle();

    // Even when the phone and the box could support DPP, task 2 keeps it out of the entry list.
    expect(find.text('使用手机安全共享 Wi-Fi'), findsNothing);
    expect(find.text('连接手机当前 Wi-Fi'), findsOneWidget);
    expect(find.text('扫描 Wi-Fi 二维码'), findsOneWidget);
    expect(find.text('选择或手动输入网络'), findsOneWidget);
    expect(repository.calls, isNot(contains('startDppProvisioning')));
  });

  test('Wi-Fi QR credentials use wifi_qr without entering Cubit state', () async {
    final repository = FakeProvisioningRepository(
      setStaConfigResult: const CommandAccepted(
        operationId: 'op_qr',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
        provisioningMethod: ProvisioningMethod.wifiQr,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);

    await cubit.submitWifiQrCredentials(
      const WifiQrCredentials(
        ssid: 'Studio',
        security: WifiSecurity.wpa2Personal,
        password: 'synthetic-pass',
      ),
    );

    expect(repository.lastStaObservation?.provisioningMethod, ProvisioningMethod.wifiQr);
    expect(repository.lastStaObservation?.selectionMethod, WifiSelectionMethod.manual);
    expect(repository.lastStaObservation?.passwordProvided, isTrue);
    expect(cubit.state.toString(), isNot(contains('synthetic-pass')));
  });

  testWidgets('DPP unavailable returns to the safe method choice', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      startDppError: const ProvisioningException(
        code: ProvisioningErrorCode.systemDppActivityUnavailable,
        retryable: false,
        diagnosticMessage: 'DPP:K:PRIVATE;;',
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(find.text('手机暂不支持 DPP 配网'), findsOneWidget);
    expect(find.text('请选择扫描 Wi-Fi 二维码，或选择/手动输入网络。'), findsOneWidget);
    expect(find.textContaining('DPP:K:'), findsNothing);

    await tester.tap(find.text('选择其他方式'));
    await tester.pumpAndSettle();

    expect(find.text('连接到现有 Wi-Fi'), findsOneWidget);
  });

  testWidgets('network recovery is not reported as DPP success', (
    tester,
  ) async {
    final deviceInfo = _deviceInfo();
    final repository = FakeProvisioningRepository(
      startDppResult: const CommandAccepted(
        operationId: 'op_dpp_recovery',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
        provisioningMethod: ProvisioningMethod.androidDpp,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(deviceInfo);
    var completed = false;
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      _pageHarness(cubit, onCompleted: (_) => completed = true),
    );

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(repository.calls, contains('startDppProvisioning'));
    expect(cubit.state.activeOperationId, 'op_dpp_recovery');

    repository.emitEvent(
      ProvisioningEvent(
        type: ProvisioningEventType.networkRecovered,
        requestId: 'request-dpp-recovery',
        deviceId: deviceInfo.deviceId,
        payload: NetworkRecovered(
          operationId: 'op_dpp_recovery',
          activeMode: ProvisioningNetworkMode.directAp,
          operationState: NetworkOperationState.idle,
          recoveredMode: ProvisioningNetworkMode.directAp,
          recoveryReason: 'previous_sta_connect_failed',
          ssid: 'Synthetic-AP',
          security: WifiSecurity.wpa2Personal,
          passphrase: 'must-never-render',
          gatewayIpv4: '192.0.2.1',
          prefixLength: 24,
          baseUri: Uri.parse('http://192.0.2.1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('旧网络未能恢复'), findsOneWidget);
    expect(find.text('盒子已加入 Wi-Fi'), findsNothing);
    expect(find.text('完成'), findsNothing);
    expect(find.textContaining('must-never-render'), findsNothing);
    expect(find.textContaining('192.0.2.1'), findsNothing);
    expect(completed, isFalse);
  });

  testWidgets('rapid DPP taps start only one repository command', (tester) async {
    final startCompleter = Completer<CommandAccepted>();
    final fakeRepository = FakeProvisioningRepository();
    final repository = _PendingStartDppRepository(
      fakeRepository,
      startCompleter.future,
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(fakeRepository.dispose);
    addTearDown(() {
      if (!startCompleter.isCompleted) {
        startCompleter.complete(
          const CommandAccepted(
            operationId: 'op_dpp_single_flight',
            desiredMode: ProvisioningNetworkMode.infrastructureSta,
            provisioningMethod: ProvisioningMethod.androidDpp,
          ),
        );
      }
    });
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    unawaited(cubit.startDppProvisioning());

    expect(repository.startDppCalls, 1);

    startCompleter.complete(
      const CommandAccepted(
        operationId: 'op_dpp_single_flight',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
        provisioningMethod: ProvisioningMethod.androidDpp,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(cubit.state.activeOperationId, 'op_dpp_single_flight');
  });

  testWidgets('retryable DPP failure exposes one safe retry action', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      startDppError: const ProvisioningException(
        code: ProvisioningErrorCode.systemDppFailed,
        retryable: true,
        diagnosticMessage: 'DPP:K:PRIVATE;;',
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(find.text('重新尝试安全共享'), findsOneWidget);
    expect(find.textContaining('DPP:K:'), findsNothing);

    await tester.tap(find.text('重新尝试安全共享'));
    await tester.pump();

    expect(
      repository.calls.where((call) => call == 'startDppProvisioning'),
      hasLength(2),
    );
  });

  testWidgets('DPP timeout still offers a safe fresh attempt', (
    tester,
  ) async {
    final repository = FakeProvisioningRepository(
      startDppError: const ProvisioningException(
        code: ProvisioningErrorCode.dppTimeout,
        retryable: false,
        diagnosticMessage: 'DPP:K:PRIVATE;;',
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(find.text('重新尝试安全共享'), findsOneWidget);
    expect(find.textContaining('DPP:K:'), findsNothing);
  });

  testWidgets('non-DPP failure does not expose DPP retry', (tester) async {
    final repository = FakeProvisioningRepository(
      startDppError: const ProvisioningException(
        code: ProvisioningErrorCode.wifiScanFailed,
        retryable: true,
        diagnosticMessage: 'DPP:K:PRIVATE;;',
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(find.text('重新尝试安全共享'), findsNothing);
    expect(find.textContaining('DPP:K:'), findsNothing);
  });

  testWidgets('unknown DPP failure uses the safe generic fallback without retry', (
    tester,
  ) async {
    const privateDiagnostic = 'synthetic-private-diagnostic://password=secret';
    final repository = FakeProvisioningRepository(
      startDppError: StateError(privateDiagnostic),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    unawaited(cubit.startDppProvisioning());
    await tester.pump();
    await tester.pump();

    expect(find.text('操作未完成'), findsOneWidget);
    expect(find.text('请检查与盒子的连接后重试。'), findsOneWidget);
    expect(find.text('返回盒子直连'), findsOneWidget);
    expect(find.text('重新尝试安全共享'), findsNothing);
    expect(find.textContaining(privateDiagnostic), findsNothing);
  });

  testWidgets('phone Wi-Fi entry pre-fills the current name and still requires the password', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit, phoneWifi: const _FakePhoneWifi(ssid: 'Home-5G')));

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-ssid'))).controller?.text,
      'Home-5G',
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-password'))).obscureText,
      isTrue,
    );
    expect(find.byKey(const ValueKey('wifi-prefill-hint')), findsOneWidget);
    expect(find.textContaining('来源：手机 Wi-Fi 读取'), findsOneWidget);
    // A pre-filled name must never turn into an automatic submission.
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  testWidgets('missing phone Wi-Fi name explains itself instead of pretending to pre-fill', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      _pageHarness(
        cubit,
        phoneWifi: const _FakePhoneWifi(failure: PhoneWifiReadFailure.permissionDenied),
        requestLocationPermission: () async => false,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wifi-prefill-hint')), findsOneWidget);
    expect(find.textContaining('未授予定位权限'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-ssid'))).controller?.text,
      isEmpty,
    );
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  for (final entry in <(ProvisioningNetworkMode, String, String)>[
    (ProvisioningNetworkMode.infrastructureSta, '已恢复之前可用的 Wi-Fi', '不需要重新输入密码'),
    (ProvisioningNetworkMode.directAp, '旧网络未能恢复', '重新开启直连热点'),
    (ProvisioningNetworkMode.none, '恢复旧网络失败', '没有可恢复的旧网络'),
  ]) {
    testWidgets('recovery outcome is distinguishable: ${entry.$1.name}', (tester) async {
      final deviceInfo = _deviceInfo();
      final repository = FakeProvisioningRepository(
        startDppResult: const CommandAccepted(
          operationId: 'op_recovery_case',
          desiredMode: ProvisioningNetworkMode.infrastructureSta,
          provisioningMethod: ProvisioningMethod.androidDpp,
        ),
      );
      final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(deviceInfo);
      addTearDown(cubit.close);
      addTearDown(repository.dispose);
      await tester.pumpWidget(_pageHarness(cubit));

      await tester.pumpAndSettle();
      unawaited(cubit.startDppProvisioning());
      await tester.pump();

      repository.emitEvent(
        ProvisioningEvent(
          type: ProvisioningEventType.networkRecovered,
          requestId: 'request-recovery-case',
          deviceId: deviceInfo.deviceId,
          payload: NetworkRecovered(
            operationId: 'op_recovery_case',
            activeMode: ProvisioningNetworkMode.infrastructureSta,
            operationState: NetworkOperationState.idle,
            recoveredMode: entry.$1,
            recoveryReason: 'previous_sta_connect_failed',
            ssid: 'Synthetic-AP',
            security: WifiSecurity.wpa2Personal,
            passphrase: 'must-never-render',
            gatewayIpv4: '192.0.2.1',
            prefixLength: 24,
            baseUri: Uri.parse('http://192.0.2.1'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(entry.$2), findsOneWidget);
      expect(find.textContaining(entry.$3), findsOneWidget);
      // A fallback or a failed restore is never presented as a successful provisioning.
      expect(find.text('完成'), findsNothing);
      expect(find.text('盒子已加入 Wi-Fi'), findsNothing);
      expect(find.textContaining('must-never-render'), findsNothing);
    });
  }

  testWidgets('a failed Wi-Fi join is labelled as a join failure, not a Bluetooth problem', (tester) async {
    final repository = FakeProvisioningRepository(
      setStaConfigError: const ProvisioningException(
        code: ProvisioningErrorCode.staDhcpFailed,
        retryable: true,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_pageHarness(cubit));

    await tester.pumpAndSettle();
    await cubit.submitStaConfiguration(
      StaNetworkConfiguration(
        provisioningMethod: ProvisioningMethod.bleManual,
        selectionMethod: WifiSelectionMethod.manual,
        ssid: 'Studio',
        security: WifiSecurity.wpa2Personal,
        password: 'synthetic-pass',
        hidden: false,
        networkKind: StaNetworkKind.router,
      ),
    );
    await tester.pump();

    expect(cubit.state.failureOrigin, NetworkProvisioningFailureOrigin.wifiJoin);
    expect(find.text('加入 Wi-Fi 失败'), findsOneWidget);
    expect(find.textContaining('不需要重新配对'), findsOneWidget);
    expect(find.textContaining('synthetic-pass'), findsNothing);
    // Retrying stays possible without returning to the first step.
    expect(find.text('扫描 Wi-Fi 二维码'), findsOneWidget);
    expect(find.text('选择或手动输入网络'), findsOneWidget);
  });

  testWidgets('granting location on demand turns the missing name into a prefill', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    final reader = _GrantablePhoneWifi();
    var requested = 0;
    await tester.pumpWidget(
      _pageHarness(
        cubit,
        phoneWifi: reader,
        requestLocationPermission: () async {
          requested++;
          reader.granted = true;
          return true;
        },
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    expect(requested, 1);
    expect(reader.reads, 2, reason: '授权后必须重读一次');
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-ssid'))).controller?.text,
      'Home-5G',
    );
    expect(find.byKey(const ValueKey('wifi-prefill-hint')), findsOneWidget);
  });

  testWidgets('a denied location request is asked once and keeps the manual fallback', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    final reader = _GrantablePhoneWifi();
    var requested = 0;
    await tester.pumpWidget(
      _pageHarness(
        cubit,
        phoneWifi: reader,
        requestLocationPermission: () async {
          requested++;
          return false;
        },
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    // One prompt, no retry loop, and the field stays usable.
    expect(requested, 1);
    expect(reader.reads, 1);
    expect(find.byKey(const ValueKey('wifi-prefill-hint')), findsOneWidget);
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  testWidgets('an approximate-only location grant also triggers one upgrade request', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    final reader = _GrantablePhoneWifi(deniedAs: PhoneWifiReadFailure.approximateLocation);
    var requested = 0;
    await tester.pumpWidget(
      _pageHarness(
        cubit,
        phoneWifi: reader,
        requestLocationPermission: () async {
          requested++;
          reader.granted = true;
          return true;
        },
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    // Android 12+ only upgrades "approximate" to "precise" when the permission is requested again.
    expect(requested, 1);
    expect(reader.reads, 2);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('wifi-ssid'))).controller?.text,
      'Home-5G',
    );
  });

  testWidgets('an approximate-only location grant explains itself when the user declines the upgrade', (tester) async {
    final repository = FakeProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    final reader = _GrantablePhoneWifi(deniedAs: PhoneWifiReadFailure.approximateLocation);
    await tester.pumpWidget(
      _pageHarness(cubit, phoneWifi: reader, requestLocationPermission: () async => false),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wifi-prefill-hint')), findsOneWidget);
    expect(find.textContaining('大致位置'), findsOneWidget);
  });

  test('a confirmed Wi-Fi QR submits exactly one provisioning command', () async {
    final repository = FakeProvisioningRepository(
      setStaConfigResult: const CommandAccepted(
        operationId: 'op_qr_once',
        desiredMode: ProvisioningNetworkMode.infrastructureSta,
        provisioningMethod: ProvisioningMethod.wifiQr,
      ),
    );
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);

    const credentials = WifiQrCredentials(
      ssid: 'Studio',
      security: WifiSecurity.wpa2Personal,
      password: 'synthetic-pass',
    );
    // A double confirm (double tap, late frame) must not send a second set_sta_config.
    await Future.wait([
      cubit.submitWifiQrCredentials(credentials),
      cubit.submitWifiQrCredentials(credentials),
    ]);

    expect(repository.calls.where((call) => call == 'setStaConfig'), hasLength(1));
    expect(cubit.state.phase, NetworkProvisioningPhase.configuringSta);
  });
}

/// Phone platform double whose permission can be granted between two reads.
final class _GrantablePhoneWifi implements PhoneWifiPlatform {
  _GrantablePhoneWifi({this.deniedAs = PhoneWifiReadFailure.permissionDenied});

  final PhoneWifiReadFailure deniedAs;
  var granted = false;
  var reads = 0;

  @override
  Future<PhoneWifiSsid> currentSsid() async {
    reads++;
    return granted ? const PhoneWifiSsid.readable('Home-5G') : PhoneWifiSsid.unreadable(deniedAs);
  }

  @override
  Future<String?> pickQrImage() async => null;
}

/// Phone platform double: the prefill hint and the picked image path are what task 2 adds.
final class _FakePhoneWifi implements PhoneWifiPlatform {
  const _FakePhoneWifi({this.ssid, this.failure});

  final String? ssid;
  final PhoneWifiReadFailure? failure;

  @override
  Future<PhoneWifiSsid> currentSsid() async => ssid != null ? PhoneWifiSsid.readable(ssid!) : PhoneWifiSsid.unreadable(failure ?? PhoneWifiReadFailure.unavailable);

  @override
  Future<String?> pickQrImage() async => null;
}

Widget _pageHarness(
  NetworkProvisioningCubit cubit, {
  ValueChanged<Uri>? onCompleted,
  VoidCallback? onBack,
  PhoneWifiPlatform? phoneWifi,
  Future<bool> Function()? requestLocationPermission,
}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: BlocProvider.value(
      value: cubit,
      child: NetworkProvisioningPage(
        onBack: onBack ?? cubit.backToMethodSelection,
        onCompleted: onCompleted,
        phoneWifi: phoneWifi,
        requestLocationPermission: requestLocationPermission,
      ),
    ),
  ),
);

ProvisioningDeviceInfo _deviceInfo() => ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-1A2B3C4D',
  firmwareVersion: '1.0.0',
  apiVersion: '1.0',
  pairingCodeMode: PairingCodeMode.sessionRandom,
  pairingCodeLength: 6,
  pairingCodeTtl: const Duration(minutes: 2),
  displayAvailable: true,
  capabilities: _capabilities(),
);

DeviceCapabilities _capabilities({bool directAp = true}) => DeviceCapabilities(
  directAp: directAp,
  infrastructureSta: true,
  wifiScan: true,
  wifiManual: true,
  dppEnrolleeSupported: true,
  dppSupportedAkm: const {'psk'},
  modeSwitch: true,
  networkRecovery: true,
  bleFragmentationV1: true,
  wifiApStaConcurrency: false,
  apBand24Ghz: true,
  apBand5Ghz: false,
);

final class _PendingStartDppRepository implements ProvisioningRepository, DppAvailabilityRepository {
  _PendingStartDppRepository(this._delegate, this._startDppResult);

  final FakeProvisioningRepository _delegate;
  final Future<CommandAccepted> _startDppResult;
  var startDppCalls = 0;

  @override
  Stream<ProvisioningEvent> get events => _delegate.events;

  @override
  Future<DppAvailability> checkDppAvailability() => _delegate.checkDppAvailability();

  @override
  Future<CommandAccepted> startDppProvisioning() {
    startDppCalls++;
    return _startDppResult;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError('Unexpected repository call: ${invocation.memberName}');
}
