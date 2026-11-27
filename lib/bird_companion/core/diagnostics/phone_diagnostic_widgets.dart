import 'dart:async';
import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/diagnostics/app_build_identity.dart';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_recorder.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:flutter/material.dart';

bool _phoneExportOpen = false;

Future<void> showPhoneDiagnostics(BuildContext context, {Future<BleDiagnosticExport> Function()? capture, BirdBoxBleDiagnosticFilePlatform? files}) => guardBirdNavigation<void>(context, () async {
  if (_phoneExportOpen) return;
  _phoneExportOpen = true;
  try {
    final dependencies = BirdCompanionScope.maybeOf(context);
    final export = await (capture?.call() ?? dependencies!.bleDiagnosticSnapshotService.capture(dependencies.connectionAttempts.activeId, includeRetainedHistory: true, includePhone: true));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BleDiagnosticExportDialog(
        title: '导出手机诊断',
        export: export,
        files: files ?? dependencies?.bleDiagnosticFilePlatform ?? const MethodChannelBirdBoxBleDiagnosticFilePlatform(),
      ),
    );
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('暂未能准备手机诊断，请重试。')));
  } finally {
    _phoneExportOpen = false;
  }
});

class PhoneDiagnosticExportButton extends StatefulWidget {
  const PhoneDiagnosticExportButton({super.key, this.compact = false, this.capture, this.files});
  final bool compact;
  final Future<BleDiagnosticExport> Function()? capture;
  final BirdBoxBleDiagnosticFilePlatform? files;
  @override
  State<PhoneDiagnosticExportButton> createState() => _PhoneDiagnosticExportButtonState();
}

class _PhoneDiagnosticExportButtonState extends State<PhoneDiagnosticExportButton> {
  bool _busy = false;
  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showPhoneDiagnostics(context, capture: widget.capture, files: widget.files);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? TextButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.download_outlined), label: Text(_busy ? '正在准备手机诊断' : '导出手机诊断'))
      : OutlinedButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.download_outlined), label: Text(_busy ? '正在准备手机诊断' : '导出手机诊断'));
}

class AppBuildIdentityLabel extends StatefulWidget {
  const AppBuildIdentityLabel({super.key});
  @override
  State<AppBuildIdentityLabel> createState() => _AppBuildIdentityLabelState();
}

class _AppBuildIdentityLabelState extends State<AppBuildIdentityLabel> {
  Future<Map<String, dynamic>>? _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= (BirdCompanionScope.maybeOf(context)?.appBuildIdentity ?? AppBuildIdentity()).read();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (_, snapshot) => Text('应用 ${AppBuildIdentity.version(snapshot.data)}'),
  );
}

class PhoneDiagnosticLifecycle extends StatefulWidget {
  const PhoneDiagnosticLifecycle({super.key, required this.recorder, required this.child});
  final PhoneDiagnosticRecorder recorder;
  final Widget child;
  @override
  State<PhoneDiagnosticLifecycle> createState() => _PhoneDiagnosticLifecycleState();
}

class _PhoneDiagnosticLifecycleState extends State<PhoneDiagnosticLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.recorder.setLifecycle(WidgetsBinding.instance.lifecycleState?.name ?? 'resumed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => widget.recorder.setLifecycle(state.name);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.recorder.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PhoneDiagnosticNavigationObserver extends NavigatorObserver {
  PhoneDiagnosticNavigationObserver(this.recorder, {this.surface = 'root'});
  final PhoneDiagnosticRecorder recorder;
  final String surface;
  // Route arguments (photo IDs, filenames, entered addresses) are never read.
  static const _pages = {
    '/',
    '/connection',
    '/shell',
    '/gallery',
    '/scenes',
    '/group-review',
    '/comparison-review',
    '/photo-detail',
    '/copy-confirmation',
    '/full-backup',
    '/copy-jobs',
    '/copy-job-detail',
    '/smart-follow-run',
    '/smart-follow-completion',
    '/smart-follow-metadata-preview',
    '/smart-follow-metadata-update',
    '/job-detail',
    '/job-center',
    '/batches',
    '/diagnostics',
    '/settings/device-management',
    '/settings/device-details',
    '/settings/display',
    '/settings/photos',
    '/settings/copy-backup',
    '/settings/storage-target',
    '/settings/network-diagnostics',
    '/settings/network',
    '/settings/system-logs',
    '/settings/help',
  };
  void _page(Route<dynamic>? route) => recorder.setPage(
    surface,
    _pages.contains(route?.settings.name)
        ? route!.settings.name!
        : route is PopupRoute
        ? 'dialog'
        : 'unnamed_page',
  );
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _page(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _page(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _page(newRoute);
}
