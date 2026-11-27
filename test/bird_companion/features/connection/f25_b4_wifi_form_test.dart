import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/sta_network_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_provisioning_repository.dart';

const _ssidKey = ValueKey('wifi-ssid');
const _passwordKey = ValueKey('wifi-password');
const _scanAccepted = CommandAccepted(operationId: 'op_scan', desiredMode: ProvisioningNetworkMode.infrastructureSta, provisioningMethod: ProvisioningMethod.bleScanSelection);

void main() {
  testWidgets('late phone read preserves typing until explicit use and never submits', (tester) async {
    final phone = _Phone();
    final pending = Completer<PhoneWifiSsid>();
    phone.next = () => pending.future;
    final (repository, _) = await _page(tester, phone: phone);
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pump();
    await tester.enterText(find.byKey(_ssidKey), 'My-edited-network');
    await tester.enterText(find.byKey(_passwordKey), 'draft-password');
    pending.complete(PhoneWifiSsid.readable('Phone-network', readAt: DateTime(2026, 11, 25, 9, 10, 11)));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'My-edited-network');
    expect(_text(tester, _passwordKey), 'draft-password');
    expect(find.textContaining('09:10:11'), findsOneWidget);
    expect(repository.calls, isNot(contains('setStaConfig')));
    await tester.tap(find.text('使用此名称'));
    await tester.pump();
    expect(_text(tester, _ssidKey), 'Phone-network');
    expect(_text(tester, _passwordKey), isEmpty);
  });

  testWidgets('failed refresh preserves draft and original name provenance; changed phone needs confirmation', (tester) async {
    final phone = _Phone();
    final (repository, _) = await _page(tester, phone: phone);
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_passwordKey), 'draft-password');
    phone.next = () async => const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.locationDisabled);
    await tester.tap(find.byKey(const ValueKey('wifi-refresh-phone')));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'Phone-network');
    expect(_text(tester, _passwordKey), 'draft-password');
    expect(find.textContaining('系统定位已关闭'), findsOneWidget);
    expect(find.textContaining('名称来源：手机 Wi-Fi'), findsOneWidget);
    phone.next = () async => const PhoneWifiSsid.readable('New-network');
    await tester.tap(find.byKey(const ValueKey('wifi-refresh-phone')));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'Phone-network');
    expect(find.text('使用此名称'), findsOneWidget);
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  testWidgets('read finishing after leaving form cannot reopen it or ask permission', (tester) async {
    final phone = _Phone();
    final pending = Completer<PhoneWifiSsid>();
    phone.next = () => pending.future;
    var permissions = 0;
    final (_, cubit) = await _page(
      tester,
      phone: phone,
      permission: () async {
        permissions++;
        return true;
      },
    );
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pump();
    cubit.returnToWifiMethodSelection();
    await tester.pump();
    pending.complete(const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.permissionDenied));
    await tester.pumpAndSettle();
    expect(find.byType(StaNetworkForm), findsNothing);
    expect(find.text('连接手机当前 Wi-Fi'), findsOneWidget);
    expect(permissions, 0);
    phone.next = () async => const PhoneWifiSsid.readable('Reentered-network');
    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'Reentered-network');
    expect(phone.reads, 2);
  });

  testWidgets('self-hotspot is explicitly selected, does not read client SSID, and submits its kind', (tester) async {
    final phone = _Phone();
    final (repository, _) = await _page(tester, phone: phone);
    await tester.tap(find.text('使用这台手机的热点'));
    await tester.pumpAndSettle();
    expect(phone.reads, 0);
    expect(_text(tester, _ssidKey), isEmpty);
    expect(find.byKey(const ValueKey('wifi-hotspot-hint')), findsOneWidget);
    await tester.enterText(find.byKey(_ssidKey), 'OPPO-personal-hotspot');
    await tester.enterText(find.byKey(_passwordKey), 'hotspot-password');
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    expect(repository.lastStaObservation?.networkKind, StaNetworkKind.thisPhoneHotspot);
    expect(repository.lastStaObservation?.selectionMethod, WifiSelectionMethod.manual);
    expect(repository.calls.where((c) => c == 'setStaConfig'), hasLength(1));
  });

  for (final reason in [PhoneWifiReadFailure.permissionDenied, PhoneWifiReadFailure.approximateLocation, PhoneWifiReadFailure.locationDisabled, PhoneWifiReadFailure.notConnected]) {
    testWidgets('unreadable ${reason.name} permits manual form without inferring hotspot', (tester) async {
      final phone = _Phone()..next = () async => PhoneWifiSsid.unreadable(reason);
      final (repository, _) = await _page(tester, phone: phone, permission: () async => false);
      await tester.tap(find.text('连接手机当前 Wi-Fi'));
      await tester.pumpAndSettle();
      expect(_text(tester, _ssidKey), isEmpty);
      expect(find.byKey(const ValueKey('wifi-hotspot-hint')), findsNothing);
      await tester.enterText(find.byKey(_ssidKey), 'Manual-target');
      await tester.enterText(find.byKey(_passwordKey), 'manual-password');
      await tester.tap(find.text('连接此 Wi-Fi'));
      await tester.pump();
      expect(repository.lastStaObservation?.networkKind, StaNetworkKind.router);
      expect(repository.lastStaObservation?.passwordProvided, isTrue);
    });
  }

  testWidgets('scan refresh preserves controllers and typing; explicit same-name AP changes clear passwords', (tester) async {
    final (repository, cubit) = await _page(tester);
    cubit.showManualWifi();
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(find.byKey(_ssidKey)).controller;
    await tester.enterText(find.byKey(_ssidKey), 'Typed-target');
    await tester.enterText(find.byKey(_passwordKey), 'typed-password');
    await cubit.scanWifi();
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(_ssidKey)).controller, same(controller));
    expect(_text(tester, _passwordKey), 'typed-password');
    expect(tester.widget<StaNetworkForm>(find.byType(StaNetworkForm)).scanStatus, WifiFormScanStatus.scanning);
    repository.emitEvent(_batch([_network('AA:00:00:00:00:01'), _network('AA:00:00:00:00:02', security: WifiSecurity.wpa3Personal), _network('AA:00:00:00:00:03')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'Typed-target');
    expect(_text(tester, _passwordKey), 'typed-password');
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:01')));
    await tester.pump();
    expect(_text(tester, _ssidKey), 'Same-name');
    expect(_text(tester, _passwordKey), isEmpty);
    await tester.enterText(find.byKey(_passwordKey), 'first-ap-password');
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:01')));
    await tester.pump();
    expect(_text(tester, _passwordKey), 'first-ap-password');
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:03')));
    await tester.pump();
    expect(_text(tester, _passwordKey), isEmpty);
    await tester.enterText(find.byKey(_passwordKey), 'same-security-other-ap-password');
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:02')));
    await tester.pump();
    expect(_text(tester, _passwordKey), isEmpty);
    expect(find.byKey(const ValueKey('wifi-security-wpa3Personal')), findsOneWidget);
    await tester.enterText(find.byKey(_passwordKey), 'second-ap-password');
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    expect(repository.lastStaObservation?.selectionMethod, WifiSelectionMethod.scanResult);
    expect(repository.lastStaObservation?.hasBssid, isTrue);
    expect(repository.calls.where((c) => c == 'setStaConfig'), hasLength(1));
  });

  testWidgets('scan failure, retry, cancellation, and empty result preserve the hidden-network draft', (tester) async {
    final repository = _ScanRepository();
    final (_, cubit) = await _page(tester, repository: repository);
    cubit.showManualWifi();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_ssidKey), 'Hidden-target');
    await tester.enterText(find.byKey(_passwordKey), 'hidden-password');
    await tester.tap(find.text('隐藏网络'));
    repository.scanFailure = true;
    await cubit.scanWifi();
    await tester.pumpAndSettle();
    expect(find.textContaining('搜索失败'), findsOneWidget);
    expect(_text(tester, _passwordKey), 'hidden-password');
    repository.scanFailure = false;
    await cubit.scanWifi();
    await tester.pump();
    await tester.tap(find.text('连接此 Wi-Fi'));
    expect(repository.calls, isNot(contains('setStaConfig')));
    await cubit.cancelWifiScan();
    repository.emitEvent(
      ProvisioningEvent(
        type: ProvisioningEventType.cancelled,
        requestId: 'cancel',
        deviceId: _info().deviceId,
        payload: const CancelledOperation(operationId: 'op_cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已取消搜索'), findsOneWidget);
    expect(_text(tester, _ssidKey), 'Hidden-target');
    expect(_text(tester, _passwordKey), 'hidden-password');
    await cubit.scanWifi();
    repository.emitEvent(_batch([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('未发现附近 Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    expect(repository.lastStaObservation?.hidden, isTrue);
    expect(repository.lastStaObservation?.hasBssid, isFalse);
  });

  testWidgets('unsupported scan target cannot alter draft or submit', (tester) async {
    final (repository, cubit) = await _page(tester);
    cubit.showManualWifi();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_ssidKey), 'Typed-target');
    await tester.enterText(find.byKey(_passwordKey), 'typed-password');
    await cubit.scanWifi();
    repository.emitEvent(_batch([_network('AA:00:00:00:00:01', unsupported: true)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:01')));
    await tester.pump();
    expect(_text(tester, _ssidKey), 'Typed-target');
    expect(_text(tester, _passwordKey), 'typed-password');
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  testWidgets('editing scan name removes BSSID; changing security clears old password including open transitions', (tester) async {
    StaNetworkConfiguration? submitted;
    _largeView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaNetworkForm(selectedNetwork: _network('AA:00:00:00:00:01'), onSubmit: (v) => submitted = v),
        ),
      ),
    );
    await tester.enterText(find.byKey(_passwordKey), 'old-password');
    await tester.tap(find.byKey(const ValueKey('wifi-security-wpa2Personal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开放网络').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wifi-security-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WPA3').last);
    await tester.pumpAndSettle();
    expect(_text(tester, _passwordKey), isEmpty);
    await tester.enterText(find.byKey(_ssidKey), 'Edited-target');
    await tester.enterText(find.byKey(_passwordKey), 'new-password');
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    expect(submitted?.ssid, 'Edited-target');
    expect(submitted?.bssid, isNull);
    expect(submitted?.security, WifiSecurity.wpa3Personal);
    expect(submitted?.selectionMethod, WifiSelectionMethod.manual);
  });

  testWidgets('box saved snapshot stays separate from phone read and does not prefill', (tester) async {
    _largeView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaNetworkForm(
            savedNetwork: const InfrastructureStaSnapshot(saved: true, ssid: 'Box-saved'),
            phoneWifi: PhoneWifiSsid.readable('Phone-read', readAt: DateTime(2026, 11, 25, 9, 10, 11)),
            onRefreshPhoneWifi: () {},
            onSubmit: (_) {},
          ),
        ),
      ),
    );
    expect(_text(tester, _ssidKey), 'Phone-read');
    expect(find.textContaining('盒子记录，不代表手机当前连接'), findsOneWidget);
    expect(find.textContaining('09:10:11'), findsNWidgets(2));
  });

  testWidgets('scan-only capability requires explicit selection before submit', (tester) async {
    _largeView(tester);
    StaNetworkConfiguration? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaNetworkForm(
            manualSupported: false,
            scanStatus: WifiFormScanStatus.complete,
            networks: [_network('AA:00:00:00:00:01')],
            onScan: () {},
            onSubmit: (v) => submitted = v,
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byKey(_ssidKey)).readOnly, isTrue);
    await tester.tap(find.text('连接此 Wi-Fi'));
    expect(submitted, isNull);
    await tester.tap(find.byKey(const ValueKey('wifi-result-AA:00:00:00:00:01')));
    await tester.pump();
    await tester.enterText(find.byKey(_passwordKey), 'scan-password');
    await tester.tap(find.text('连接此 Wi-Fi'));
    expect(submitted?.selectionMethod, WifiSelectionMethod.scanResult);
  });

  testWidgets('single-flight scan and pre-ACK cancel use only the accepted operation ID; late batches ignored', (tester) async {
    final repository = _ScanRepository()..pendingScan = Completer<CommandAccepted>();
    final (_, cubit) = await _page(tester, repository: repository);
    final scan = cubit.scanWifi();
    await cubit.scanWifi();
    await cubit.cancelWifiScan();
    expect(repository.calls.where((c) => c == 'scanWifi'), hasLength(1));
    expect(repository.calls.where((c) => c.startsWith('cancelNetworkOperation')), isEmpty);
    repository.pendingScan!.complete(_scanAccepted);
    await scan;
    expect(repository.calls.where((c) => c == 'cancelNetworkOperation:op_scan'), hasLength(1));
    repository.emitEvent(_batch([_network('AA:00:00:00:00:01')]));
    await tester.pump();
    expect(cubit.state.phase, NetworkProvisioningPhase.scanningWifi);
    expect(cubit.state.wifiNetworks, isEmpty);
    repository.emitEvent(
      ProvisioningEvent(
        type: ProvisioningEventType.cancelled,
        requestId: 'cancel',
        deviceId: _info().deviceId,
        payload: const CancelledOperation(operationId: 'op_cancel'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('scan ACK timeout returns to draft and ignores its late result', (tester) async {
    final repository = _ScanRepository()..pendingScan = Completer<CommandAccepted>();
    final (_, cubit) = await _page(tester, repository: repository, scanTimeout: const Duration(seconds: 1));
    cubit.showManualWifi();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_ssidKey), 'Timeout-draft');
    await tester.enterText(find.byKey(_passwordKey), 'timeout-password');
    final scan = cubit.scanWifi();
    await tester.pump(const Duration(seconds: 2));
    expect(cubit.state.phase, NetworkProvisioningPhase.failure);
    expect(cubit.state.failureOrigin, NetworkProvisioningFailureOrigin.wifiScan);
    repository.pendingScan!.complete(_scanAccepted);
    await scan;
    repository.emitEvent(_batch([_network('AA:00:00:00:00:01')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _ssidKey), 'Timeout-draft');
    expect(_text(tester, _passwordKey), 'timeout-password');
    expect(cubit.state.activeOperationId, isNull);
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  testWidgets('missing scan terminal and cancellation terminal have bounded wait', (tester) async {
    final (repository, cubit) = await _page(tester, scanTimeout: const Duration(seconds: 1));
    await cubit.scanWifi();
    await cubit.cancelWifiScan();
    await tester.pump(const Duration(seconds: 2));
    expect(cubit.state.phase, NetworkProvisioningPhase.failure);
    expect(cubit.state.failureOrigin, NetworkProvisioningFailureOrigin.wifiScan);
    expect(repository.calls, isNot(contains('setStaConfig')));
  });

  for (final entry in <(String, PhoneWifiReadFailure)>[
    ('permission_denied', PhoneWifiReadFailure.permissionDenied),
    ('permission_approximate', PhoneWifiReadFailure.approximateLocation),
    ('location_disabled', PhoneWifiReadFailure.locationDisabled),
    ('not_connected', PhoneWifiReadFailure.notConnected),
    ('unavailable', PhoneWifiReadFailure.unavailable),
  ]) {
    test('phone channel maps ${entry.$1} without claiming self-hotspot', () async {
      const channel = MethodChannel('f25-b4-phone-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => {'ssid': null, 'reason': entry.$1});
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final result = await const MethodChannelPhoneWifiPlatform(channel: channel).currentSsid();
      expect(result.isReadable, isFalse);
      expect(result.failure, entry.$2);
      expect(result.readAt, isNotNull);
    });
  }

  test('phone channel records read time and redacts SSID in diagnostic text', () async {
    const channel = MethodChannel('f25-b4-phone-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => {'ssid': ' Phone-network ', 'reason': null});
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final result = await const MethodChannelPhoneWifiPlatform(channel: channel).currentSsid();
    expect(result.ssid, 'Phone-network');
    expect(result.readAt, isNotNull);
    expect(result.toString(), isNot(contains('Phone-network')));
  });
}

void _largeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _text(WidgetTester tester, Key key) => tester.widget<TextField>(find.byKey(key)).controller!.text;

Future<(FakeProvisioningRepository, NetworkProvisioningCubit)> _page(
  WidgetTester tester, {
  _Phone? phone,
  FakeProvisioningRepository? repository,
  Future<bool> Function()? permission,
  Duration scanTimeout = const Duration(seconds: 30),
}) async {
  _largeView(tester);
  repository ??= _ScanRepository();
  final cubit = NetworkProvisioningCubit(repository, wifiScanTimeout: scanTimeout)..openWifiProvisioning(_info());
  addTearDown(() async {
    await cubit.close();
    await repository!.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: NetworkProvisioningPage(onBack: cubit.backToMethodSelection, phoneWifi: phone ?? _Phone(), requestLocationPermission: permission ?? () async => false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, cubit);
}

class _Phone implements PhoneWifiPlatform {
  Future<PhoneWifiSsid> Function() next = () async => const PhoneWifiSsid.readable('Phone-network');
  var reads = 0;
  @override
  Future<PhoneWifiSsid> currentSsid() {
    reads++;
    return next();
  }

  @override
  Future<String?> pickQrImage() async => null;
}

class _ScanRepository extends FakeProvisioningRepository {
  _ScanRepository()
    : super(
        scanWifiResult: _scanAccepted,
        setStaConfigResult: const CommandAccepted(operationId: 'op_sta', desiredMode: ProvisioningNetworkMode.infrastructureSta, provisioningMethod: ProvisioningMethod.bleManual),
        cancelResult: const CommandAccepted(operationId: 'op_cancel', desiredMode: ProvisioningNetworkMode.infrastructureSta, provisioningMethod: ProvisioningMethod.bleScanSelection),
      );
  Completer<CommandAccepted>? pendingScan;
  var scanFailure = false;
  @override
  Future<CommandAccepted> scanWifi() async {
    if (pendingScan != null || scanFailure) {
      calls.add('scanWifi');
      if (scanFailure) throw StateError('synthetic scan failure');
      return pendingScan!.future;
    }
    return super.scanWifi();
  }
}

WifiScanNetwork _network(String bssid, {WifiSecurity security = WifiSecurity.wpa2Personal, bool unsupported = false}) => WifiScanNetwork(
  ssid: 'Same-name',
  bssid: bssid,
  rssiDbm: -42,
  frequencyMhz: 2412,
  security: security,
  unsupported: unsupported,
);

ProvisioningEvent _batch(List<WifiScanNetwork> networks) => ProvisioningEvent(
  type: ProvisioningEventType.wifiScanResults,
  requestId: 'scan-request',
  deviceId: _info().deviceId,
  payload: WifiScanBatch(batchIndex: 0, batchCount: 1, complete: true, networks: networks),
);

ProvisioningDeviceInfo _info() => const ProvisioningDeviceInfo(
  protocolVersion: '1.0-rc4',
  minAppProtocolVersion: '1.0-rc4',
  deviceId: 'bbx-0123456789abcdef0123456789abcdef',
  deviceName: 'BirdBox-1A2B3C4D',
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
    dppEnrolleeSupported: false,
    dppSupportedAkm: {},
    modeSwitch: true,
    networkRecovery: true,
    bleFragmentationV1: true,
    wifiApStaConcurrency: false,
    apBand24Ghz: true,
    apBand5Ghz: false,
  ),
);
