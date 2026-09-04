import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_parser.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiQrScannerPage extends StatefulWidget {
  const WifiQrScannerPage({super.key});

  @override
  State<WifiQrScannerPage> createState() => _WifiQrScannerPageState();
}

class _WifiQrScannerPageState extends State<WifiQrScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  WifiQrCredentials? _candidate;
  var _handled = false;
  var _invalid = false;

  @override
  void dispose() {
    _candidate = null;
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final credentials = tryParseWifiQrCredentials(
      capture.barcodes.firstOrNull?.rawValue,
    );
    if (credentials == null) {
      if (mounted) setState(() => _invalid = true);
      return;
    }
    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _candidate = credentials;
      _invalid = false;
    });
  }

  Future<void> _rescan() async {
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _candidate = null;
      _handled = false;
      _invalid = false;
    });
    await _controller.start();
  }

  void _confirm() {
    final candidate = _candidate;
    if (candidate == null) return;
    _candidate = null;
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
          if (_candidate case final candidate?)
            _WifiQrCandidateCard(credentials: candidate)
          else
            BirdCard(
              backgroundColor: _invalid ? AppColors.dangerSoft : AppColors.brandLight,
              child: Row(
                children: [
                  Icon(
                    _invalid ? Icons.qr_code_scanner_rounded : Icons.shield_outlined,
                    color: _invalid ? AppColors.danger : AppColors.brand,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _invalid ? '这不是受支持的标准 Wi-Fi 二维码，请重新扫描。' : '请扫描路由器或另一台设备提供的标准 Wi-Fi 二维码。密码只用于本次 BLE 配网。',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          BirdButton(
            label: _candidate == null ? (_invalid ? '重新扫描' : '等待扫码') : '确认连接此 Wi-Fi',
            onPressed: _candidate == null ? (_invalid ? _rescan : null) : _confirm,
            icon: Icon(_candidate == null ? Icons.qr_code_scanner_rounded : Icons.wifi_rounded),
          ),
          if (_candidate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BirdButton(
              label: '不是这个网络，重新扫描',
              onPressed: _rescan,
              variant: BirdButtonVariant.outlined,
            ),
          ],
        ],
      ),
    ),
  );
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
