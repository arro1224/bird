import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/connection_method_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/sta_network_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_provisioning_repository.dart';

void main() {
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

    expect(find.text('搜索附近 Wi-Fi'), findsOneWidget);
    expect(find.text('手动输入 Wi-Fi'), findsOneWidget);
    expect(find.text('使用 DPP 安全配网'), findsOneWidget);

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

    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('-42 dBm'), findsOneWidget);
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

    await tester.tap(find.text('使用 DPP 安全配网'));
    await tester.pump();

    expect(find.text('手机暂不支持 DPP 配网'), findsOneWidget);
    expect(find.text('请选择搜索 Wi-Fi 或手动输入继续连接。'), findsOneWidget);
    expect(find.textContaining('DPP:K:'), findsNothing);

    await tester.tap(find.text('选择其他方式'));
    await tester.pumpAndSettle();

    expect(find.text('选择 Wi-Fi 配网方式'), findsOneWidget);
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

    await tester.tap(find.text('使用 DPP 安全配网'));
    await tester.pump();

    expect(find.text('重新尝试 DPP'), findsOneWidget);
    expect(find.textContaining('DPP:K:'), findsNothing);

    await tester.tap(find.text('重新尝试 DPP'));
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

    await tester.tap(find.text('使用 DPP 安全配网'));
    await tester.pump();

    expect(find.text('重新尝试 DPP'), findsOneWidget);
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

    await tester.tap(find.text('使用 DPP 安全配网'));
    await tester.pump();

    expect(find.text('重新尝试 DPP'), findsNothing);
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

    await tester.tap(find.text('使用 DPP 安全配网'));
    await tester.pump();

    expect(find.text('操作未完成'), findsOneWidget);
    expect(find.text('请检查与盒子的连接后重试。'), findsOneWidget);
    expect(find.text('返回连接方式'), findsOneWidget);
    expect(find.text('重新尝试 DPP'), findsNothing);
    expect(find.textContaining(privateDiagnostic), findsNothing);
  });
}

Widget _pageHarness(
  NetworkProvisioningCubit cubit, {
  ValueChanged<Uri>? onCompleted,
  VoidCallback? onBack,
}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: BlocProvider.value(
      value: cubit,
      child: NetworkProvisioningPage(
        onBack: onBack ?? cubit.backToMethodSelection,
        onCompleted: onCompleted,
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
