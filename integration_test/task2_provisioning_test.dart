import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_import.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/wifi_qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'task2_qr_fixtures.dart';

/// On-device evidence for task 2 (加入现有 Wi-Fi 与相册扫码 D1).
///
/// Runs the real Android channel for the phone SSID and the real widget tree for the
/// entry page. The box side is the simulated provisioning repository, so no physical
/// box is required; everything the App owns is the production implementation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('任务2：真机读取手机当前 Wi-Fi 名称', (tester) async {
    final hint = await const MethodChannelPhoneWifiPlatform().currentSsid();
    // Evidence is logged without the SSID itself.
    debugPrint('TASK2_SSID_READABLE=${hint.isReadable} FAILURE=${hint.failure?.name} LENGTH=${hint.ssid?.length ?? 0}');

    // Either a real name or an explicit reason — never a silent empty string.
    expect(hint.isReadable || hint.failure != null, isTrue);
    expect(hint.failure, isNot(PhoneWifiReadFailure.unsupported));
  });

  testWidgets('任务2：配网入口三张卡片，第一张预填手机当前 Wi-Fi 且仍要密码', (tester) async {
    final hint = await const MethodChannelPhoneWifiPlatform().currentSsid();
    final repository = B7SimulatedProvisioningRepository();
    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    expect(find.text('连接手机当前 Wi-Fi'), findsOneWidget);
    expect(find.textContaining('首次连接请填写密码'), findsOneWidget);
    expect(find.text('扫描 Wi-Fi 二维码'), findsOneWidget);
    expect(find.text('选择或手动输入网络'), findsOneWidget);
    // DPP is not part of this round's entry list.
    expect(find.text('使用手机安全共享 Wi-Fi'), findsNothing);
    expect(find.textContaining('安全共享'), findsNothing);

    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    final ssid = tester.widget<TextField>(find.byKey(const ValueKey('wifi-ssid'))).controller?.text;
    final password = tester.widget<TextField>(find.byKey(const ValueKey('wifi-password')));
    expect(ssid, hint.isReadable ? hint.ssid : '');
    expect(password.obscureText, isTrue);
    expect(find.byKey(const ValueKey('wifi-prefill-hint')), hint.isReadable ? findsNothing : findsOneWidget);
    // Nothing was sent to the box just by opening the pre-filled form.
    expect(repository.calls, isNot(contains('setStaConfig')));
    debugPrint('TASK2_PREFILL=${hint.isReadable ? 'filled' : 'explained'}');
  });

  testWidgets('任务2：扫码页同时提供摄像头与相册，取消选图不改状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const WifiQrScannerPage(phoneWifi: _CancellingPhoneWifi()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // The gallery entry must exist even when the camera is unavailable.
    expect(find.text('从相册选择'), findsOneWidget);
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    // Cancelling the picker leaves the page in its initial, selectable state.
    expect(find.text('确认目标网络'), findsNothing);
    expect(find.text('从相册选择'), findsOneWidget);
    debugPrint('TASK2_GALLERY_ENTRY=cancel-safe');
  });

  testWidgets('任务2：真机解码相册图片——单码可确认，双码必须拒绝', (tester) async {
    final singlePath = await _writePng('task2_single.png', task2QrSingle);
    final doublePath = await _writePng('task2_double.png', task2QrDouble);

    final controller = MobileScannerController();
    addTearDown(controller.dispose);

    final single = await controller.analyzeImage(singlePath);
    final singleOutcome = evaluateWifiQrCodes(single?.barcodes.map((barcode) => barcode.rawValue) ?? const <String?>[]);
    debugPrint('TASK2_DECODE_SINGLE=${singleOutcome.isAccepted} codes=${single?.barcodes.length ?? 0}');
    expect(singleOutcome.isAccepted, isTrue);
    expect(singleOutcome.credentials!.ssid, 'Studio');
    expect(singleOutcome.credentials!.security.name, 'wpa2Personal');

    final double = await controller.analyzeImage(doublePath);
    final doubleOutcome = evaluateWifiQrCodes(double?.barcodes.map((barcode) => barcode.rawValue) ?? const <String?>[]);
    debugPrint('TASK2_DECODE_DOUBLE=${doubleOutcome.failure?.name} codes=${double?.barcodes.length ?? 0}');
    expect(doubleOutcome.isAccepted, isFalse);
    expect(doubleOutcome.failure, WifiQrImportFailure.multipleCodes);
  });
  testWidgets('任务2：真机走通首次加入（模拟盒子）——只下发一次并进入成功态', (tester) async {
    final repository = B7SimulatedProvisioningRepository();
    addTearDown(repository.dispose);
    final peer = await repository.discoverDevices().first;
    final info = await repository.connect(peer);
    await repository.openPairing();
    await repository.authorizePairing('123456');

    final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(info);
    addTearDown(cubit.close);
    await tester.pumpWidget(_harness(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接手机当前 Wi-Fi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('wifi-ssid')), 'Studio-Router');
    await tester.enterText(find.byKey(const ValueKey('wifi-password')), 'synthetic-value');
    await tester.tap(find.text('连接此 Wi-Fi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // One confirmation, one command.
    expect(repository.calls.where((call) => call == 'setStaConfig'), hasLength(1));

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('盒子已加入 Wi-Fi'), findsOneWidget);
    // The password typed for this join never appears back on screen.
    expect(find.textContaining('synthetic-value'), findsNothing);
    debugPrint('TASK2_FIRST_JOIN=success commands=${repository.calls.where((call) => call == 'setStaConfig').length}');
  });
}

/// Writes a base64 PNG payload into the app sandbox so the on-device decoder can read it.
Future<String> _writePng(String name, String base64Payload) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(base64Decode(base64Payload), flush: true);
  return file.path;
}

Widget _harness(NetworkProvisioningCubit cubit) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: BlocProvider.value(
      value: cubit,
      child: NetworkProvisioningPage(
        onBack: () {},
        // The permission is granted out-of-band for this run; never block on a system dialog.
        requestLocationPermission: () async => false,
      ),
    ),
  ),
);

/// Cancels immediately, mirroring a user closing the system picker.
final class _CancellingPhoneWifi implements PhoneWifiPlatform {
  const _CancellingPhoneWifi();

  @override
  Future<PhoneWifiSsid> currentSsid() async => const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.unavailable);

  @override
  Future<String?> pickQrImage() async => null;
}

ProvisioningDeviceInfo _deviceInfo() => const ProvisioningDeviceInfo(
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
