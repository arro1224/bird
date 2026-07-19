import 'dart:async';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/connection/presentation/qr_connection_uri.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_background.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrConnectionScannerPage extends StatefulWidget {
  const QrConnectionScannerPage({super.key});

  @override
  State<QrConnectionScannerPage> createState() => _QrConnectionScannerPageState();
}

class _QrConnectionScannerPageState extends State<QrConnectionScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  bool _invalidCode = false;
  DateTime? _lastInvalidAt;
  Uri? _candidateUri;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final uri = parseBirdBoxConnectionUri(raw);
    if (uri == null) {
      final now = DateTime.now();
      if (_lastInvalidAt == null || now.difference(_lastInvalidAt!) > const Duration(seconds: 1)) {
        _lastInvalidAt = now;
        if (mounted) setState(() => _invalidCode = true);
      }
      return;
    }

    _handled = true;
    await _controller.stop();
    if (mounted) {
      setState(() {
        _candidateUri = uri;
        _invalidCode = false;
      });
    }
  }

  Future<void> _retryScan() async {
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _handled = false;
      _invalidCode = false;
      _lastInvalidAt = null;
      _candidateUri = null;
    });
    await _controller.start();
  }

  void _returnCandidate() {
    final uri = _candidateUri;
    if (uri == null) return;
    Navigator.of(context).pop(QrConnectionResult.connect(uri));
  }

  void _openManualAddress() {
    Navigator.of(context).pop(const QrConnectionResult.manual());
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.light(),
    child: Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: const BirdPageBackButton(fallbackRoute: BirdRoutes.connection),
        title: const Text('扫描设备二维码'),
        actions: [
          IconButton(
            tooltip: '扫码帮助',
            onPressed: () => _showScanHelp(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: ConnectionBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              AppSpacing.md,
              AppSpacing.pageHorizontal,
              AppSpacing.xl,
            ),
            children: [
              AspectRatio(
                aspectRatio: .92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        fit: BoxFit.cover,
                        tapToFocus: true,
                        placeholderBuilder: (_) => const ColoredBox(
                          color: AppColors.brandDark,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorBuilder: (_, error) => _CameraFailure(error: error),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x72000000), Colors.transparent, Color(0x4D000000)],
                            stops: [0, .35, 1],
                          ),
                        ),
                      ),
                      const Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        top: AppSpacing.lg,
                        child: Text(
                          '扫描盒子机身或屏幕上的设备二维码',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                          ),
                        ),
                      ),
                      const Positioned.fill(child: CustomPaint(painter: _ScannerCornerPainter())),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: AppSpacing.md,
                        child: Center(
                          child: ValueListenableBuilder<MobileScannerState>(
                            valueListenable: _controller,
                            builder: (context, state, _) {
                              final available = state.torchState != TorchState.unavailable;
                              final enabled = state.torchState == TorchState.on;
                              return FilledButton.tonalIcon(
                                onPressed: available ? _controller.toggleTorch : null,
                                icon: Icon(enabled ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded),
                                label: Text(enabled ? '关闭手电筒' : '打开手电筒'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  backgroundColor: const Color(0xB30F1710),
                                  foregroundColor: Colors.white,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _candidateUri != null
                    ? _CandidateNotice(
                        key: const ValueKey('candidate'),
                        uri: _candidateUri!,
                        onRescan: _retryScan,
                      )
                    : _invalidCode
                    ? const _InvalidCodeNotice(key: ValueKey('invalid'))
                    : const _SecurityNotice(key: ValueKey('security')),
              ),
              const SizedBox(height: AppSpacing.md),
              BirdButton(
                label: _candidateUri != null
                    ? '使用此地址连接'
                    : _invalidCode
                    ? '重新扫描'
                    : '等待扫码',
                onPressed: _candidateUri != null
                    ? _returnCandidate
                    : _invalidCode
                    ? _retryScan
                    : null,
                icon: Icon(
                  _candidateUri != null
                      ? Icons.link_rounded
                      : _invalidCode
                      ? Icons.refresh_rounded
                      : Icons.qr_code_scanner_rounded,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              BirdButton(
                label: '手动输入地址',
                onPressed: _openManualAddress,
                icon: const Icon(Icons.edit_outlined),
                variant: BirdButtonVariant.outlined,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _showScanHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            AppSpacing.xs,
            AppSpacing.pageHorizontal,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BirdSectionTitle(text: '扫码提示'),
              BirdListItem(
                leading: Icon(Icons.wb_sunny_outlined),
                title: '避免反光',
                subtitle: '调整设备角度，让二维码表面光线均匀。',
              ),
              BirdListItem(
                leading: Icon(Icons.straighten_rounded),
                title: '保持合适距离',
                subtitle: '建议让手机与二维码保持约 10–20 厘米。',
              ),
              BirdListItem(
                leading: Icon(Icons.center_focus_strong_rounded),
                title: '确保二维码完整',
                subtitle: '将二维码完整放入取景框内并保持稳定。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateNotice extends StatelessWidget {
  const _CandidateNotice({
    super.key,
    required this.uri,
    required this.onRescan,
  });

  final Uri uri;
  final Future<void> Function() onRescan;

  @override
  Widget build(BuildContext context) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return BirdCard(
      backgroundColor: AppColors.brandLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.brand,
            foregroundColor: AppColors.cream,
            child: Icon(Icons.check_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已读取设备连接地址',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${uri.scheme}://${uri.host}$port',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton.icon(
                  onPressed: onRescan,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('不是这台设备，重新扫描'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({super.key});

  @override
  Widget build(BuildContext context) => const BirdCard(
    backgroundColor: AppColors.brandLight,
    child: Row(
      children: [
        Icon(Icons.shield_outlined, color: AppColors.brand),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('扫码后会先显示目标地址；请确认二维码来自您面前的可信设备。'),
        ),
      ],
    ),
  );
}

class _InvalidCodeNotice extends StatelessWidget {
  const _InvalidCodeNotice({super.key});

  @override
  Widget build(BuildContext context) => const BirdCard(
    backgroundColor: AppColors.dangerSoft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cancel_outlined, color: AppColors.danger, size: 32),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('未识别到有效的设备二维码', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.xxs),
              Text('请调整角度或距离后重试。'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CameraFailure extends StatelessWidget {
  const _CameraFailure({required this.error});

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
              const Icon(Icons.no_photography_outlined, color: AppColors.cream, size: 52),
              const SizedBox(height: AppSpacing.md),
              Text(
                permissionDenied ? '需要相机权限' : '相机暂时不可用',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.cream),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                permissionDenied ? '请在系统设置中允许拍鸟伴侣使用相机。' : '可以稍后重试，或返回手动输入设备地址。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.brandLight),
              ),
              if (permissionDenied) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: openAppSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.cream,
                    side: const BorderSide(color: AppColors.cream),
                  ),
                  child: const Text('打开系统设置'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerCornerPainter extends CustomPainter {
  const _ScannerCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * .68;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final path = Path();
    const length = 34.0;

    path
      ..moveTo(rect.left, rect.top + length)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + length, rect.top)
      ..moveTo(rect.right - length, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + length)
      ..moveTo(rect.right, rect.bottom - length)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - length, rect.bottom)
      ..moveTo(rect.left + length, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - length);

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.brandLight
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
