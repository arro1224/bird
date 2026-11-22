import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_import.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiQrScannerPage extends StatefulWidget {
  const WifiQrScannerPage({super.key, this.phoneWifi, this.imageAnalyzer});

  /// Gallery import channel. Defaults to the app scope, and is injected in tests.
  final PhoneWifiPlatform? phoneWifi;

  /// Decodes a picked image into raw barcode payloads.
  ///
  /// Defaults to the live scanner controller; injected in tests so the gallery
  /// flow is verifiable without a camera or a platform channel.
  final Future<Iterable<String?>> Function(String path)? imageAnalyzer;

  @override
  State<WifiQrScannerPage> createState() => _WifiQrScannerPageState();
}

class _WifiQrScannerPageState extends State<WifiQrScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  PhoneWifiPlatform? _phoneWifi;
  WifiQrCredentials? _candidate;

  /// Set once a target was accepted, so a camera frame cannot re-trigger or double-pop.
  var _handled = false;
  var _importing = false;

  /// Non-null when the last camera/ gallery attempt produced no single usable code.
  String? _problem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phoneWifi = widget.phoneWifi ?? BirdCompanionScope.maybeOf(context)?.phoneWifi ?? const MethodChannelPhoneWifiPlatform();
  }

  @override
  void dispose() {
    _candidate = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || _importing) return;
    final outcome = evaluateWifiQrCodes(capture.barcodes.map((barcode) => barcode.rawValue));
    if (!outcome.isAccepted) {
      // A frame with several codes or a non-Wi-Fi code stops the preview so the user
      // decides what to do instead of the app silently picking one.
      await _controller.stop();
      if (!mounted) return;
      setState(() => _problem = outcome.message);
      return;
    }
    await _accept(outcome.credentials!);
  }

  Future<Iterable<String?>> _decodeImage(String path) async {
    final analyzer = widget.imageAnalyzer;
    if (analyzer != null) return analyzer(path);
    final capture = await _controller.analyzeImage(path);
    return capture?.barcodes.map((barcode) => barcode.rawValue) ?? const <String?>[];
  }

  Future<void> _accept(WifiQrCredentials credentials) async {
    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _candidate = credentials;
      _problem = null;
    });
  }

  /// Imports a photo through the system picker. Works without camera permission.
  Future<void> _pickFromGallery() async {
    if (_handled || _importing) return;
    setState(() {
      _importing = true;
      _problem = null;
    });
    String? path;
    try {
      path = await _phoneWifi?.pickQrImage();
      if (!mounted) return;
      if (path == null) return; // The user cancelled: keep the page as it was.
      final outcome = evaluateWifiQrCodes(await _decodeImage(path));
      if (!outcome.isAccepted) {
        setState(() => _problem = outcome.message);
        return;
      }
      await _accept(outcome.credentials!);
    } on PhoneWifiPickException catch (error) {
      if (!mounted) return;
      setState(() {
        _problem = switch (error.failure) {
          PhoneWifiPickFailure.unavailable => '系统图片选择器打不开，请改用扫描入口。',
          PhoneWifiPickFailure.unreadable => '这张图片读不出来，请重新选择。',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _problem = '这张图片无法识别，请重新选择。');
    } finally {
      if (path != null) {
        // The cache copy exists only for decoding; never keep the photo around.
        unawaited(File(path).delete().then<void>((_) {}, onError: (Object _) {}));
      }
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _rescan() async {
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _candidate = null;
      _handled = false;
      _problem = null;
    });
    await _controller.start();
  }

  void _confirm() {
    final candidate = _candidate;
    if (candidate == null || _handled == false) return;
    // Popping once is what guarantees the caller submits a single provisioning command.
    _candidate = null;
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('扫描 Wi-Fi 二维码')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  fit: BoxFit.cover,
                  tapToFocus: true,
                  placeholderBuilder: (_) => const ColoredBox(
                    color: AppColors.brandDark,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorBuilder: (_, error) => _WifiQrCameraFailure(error: error),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (candidate != null)
              _WifiQrCandidateCard(credentials: candidate)
            else
              BirdCard(
                backgroundColor: _problem != null ? AppColors.dangerSoft : AppColors.brandLight,
                child: Row(
                  children: [
                    Icon(
                      _problem != null ? Icons.error_outline_rounded : Icons.shield_outlined,
                      color: _problem != null ? AppColors.danger : AppColors.brand,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _problem ?? '请扫描路由器或另一台设备提供的标准 Wi-Fi 二维码，或从相册选择二维码图片。密码只用于本次 BLE 配网。',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            BirdButton(
              label: _importing ? '正在识别图片…' : '从相册选择',
              onPressed: candidate == null && !_importing ? () => unawaited(_pickFromGallery()) : null,
              icon: const Icon(Icons.photo_library_outlined),
              variant: BirdButtonVariant.outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            BirdButton(
              label: candidate == null ? (_problem == null ? '等待扫码' : '重新扫描') : '确认连接此 Wi-Fi',
              onPressed: candidate == null ? (_problem == null ? null : _rescan) : _confirm,
              icon: Icon(candidate == null ? Icons.qr_code_scanner_rounded : Icons.wifi_rounded),
            ),
            if (candidate != null) ...[
              const SizedBox(height: AppSpacing.sm),
              BirdButton(
                label: '不是这个网络，重新选择',
                onPressed: _rescan,
                variant: BirdButtonVariant.outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WifiQrCandidateCard extends StatelessWidget {
  const _WifiQrCandidateCard({required this.credentials});

  final WifiQrCredentials credentials;

  @override
  Widget build(BuildContext context) => BirdCard(
    backgroundColor: AppColors.paperStrong,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('确认目标网络', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        BirdListItem(
          leading: const Icon(Icons.wifi_rounded),
          title: credentials.ssid,
          subtitle: _securityLabel(credentials.security),
        ),
        if (credentials.hidden)
          const BirdListItem(
            leading: Icon(Icons.visibility_off_outlined),
            title: '隐藏网络',
            subtitle: '连接时会按二维码声明作为隐藏网络处理。',
          ),
        if (credentials.bssid != null)
          const BirdListItem(
            leading: Icon(Icons.router_outlined),
            title: '已指定接入点',
            subtitle: '二维码包含接入点标识；为保护隐私不在页面展示。',
          ),
        const Text('为保护网络安全，密码不会在确认页显示。'),
      ],
    ),
  );
}

class _WifiQrCameraFailure extends StatelessWidget {
  const _WifiQrCameraFailure({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final permissionDenied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: AppColors.brandDark,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: AppColors.cream,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                permissionDenied ? '需要相机权限' : '相机暂时不可用',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.cream,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                permissionDenied ? '仍可以从相册选择二维码图片。' : '可以改从相册选择二维码图片。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.cream,
                ),
              ),
              if (permissionDenied) ...[
                const SizedBox(height: AppSpacing.md),
                const OutlinedButton(
                  onPressed: openAppSettings,
                  child: Text('打开系统设置'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _securityLabel(WifiSecurity security) => switch (security) {
  WifiSecurity.open => '开放网络',
  WifiSecurity.wpa2Personal => 'WPA2-Personal',
  WifiSecurity.wpa3Personal => 'WPA3-Personal',
  WifiSecurity.wpa2Wpa3Transition => 'WPA2/WPA3-Personal',
};
