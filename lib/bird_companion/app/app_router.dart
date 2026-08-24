import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/scene_list_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_page.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_page.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_page.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_details_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_management_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/display_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/photo_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/storage_target_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:flutter/material.dart';

abstract final class BirdRoutes {
  static const connection = '/connection';
  // Keep the shell separate from Navigator.defaultRouteName (`/`). MaterialApp
  // reserves `/` for its `home`, which may be the initial connection page.
  // Reusing it here would reopen `home` after a successful first connection.
  static const shell = '/shell';
  static const gallery = '/gallery';
  static const scenes = '/scenes';
  static const groupReview = '/group-review';
  static const comparisonReview = '/comparison-review';
  static const photoDetail = '/photo-detail';
  static const copyConfirmation = '/copy-confirmation';
  static const jobDetail = '/job-detail';
  static const jobCenter = '/job-center';
  static const batches = '/batches';
  static const diagnostics = '/diagnostics';
  static const settingsDeviceManagement = '/settings/device-management';
  static const settingsDeviceDetails = '/settings/device-details';
  static const settingsDisplay = '/settings/display';
  static const settingsPhotos = '/settings/photos';
  static const settingsCopyBackup = '/settings/copy-backup';
  static const settingsStorageTarget = '/settings/storage-target';
  static const settingsNetworkDiagnostics = '/settings/network-diagnostics';
  static const settingsSystemLogs = '/settings/system-logs';
  static const settingsHelp = '/settings/help';
}

/// Opens the canonical connection flow from any reconnect entry.
void openReconnectConnection(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).pushNamed(
    BirdRoutes.connection,
    arguments: const ConnectionArgs(
      entryMode: ConnectionEntryMode.addOrSwitch,
    ),
  );
}

abstract final class BirdAppRouter {
  static Route<void> onGenerateRoute(
    RouteSettings settings, {
    ProvisioningRepository? provisioningRepository,
  }) {
    Widget page;
    switch (settings.name) {
      case BirdRoutes.connection:
        final args = settings.arguments;
        page = ConnectionPage(
          entryMode: args is ConnectionArgs ? args.entryMode : ConnectionEntryMode.initialSetup,
          provisioningRepository: provisioningRepository,
        );
      case BirdRoutes.shell:
        final args = settings.arguments;
        page = BirdAppShell(
          initialIndex: args is ShellArgs ? args.initialIndex : 0,
          initialRoute: args is ShellArgs ? args.initialRoute : null,
          onGenerateRoute: (settings) => onGenerateRoute(
            settings,
            provisioningRepository: provisioningRepository,
          ),
        );
      case BirdRoutes.gallery:
        final args = settings.arguments;
        final id = _batchId(args);
        page = id == null
            ? _invalid('相册', '缺少拍摄记录')
            : GalleryPage(
                batchId: id,
                batchName: args is GalleryArgs ? args.batchName : null,
                createdAt: args is GalleryArgs ? args.createdAt : null,
                totalCount: args is GalleryArgs ? args.totalCount : null,
                pendingCount: args is GalleryArgs ? args.pendingCount : null,
                keepCount: args is GalleryArgs ? args.keepCount : null,
                discardCount: args is GalleryArgs ? args.discardCount : null,
                initialQuery: args is GalleryArgs ? args.initialQuery : const PhotoQuery(),
                restoreSavedView: args is GalleryArgs ? args.restoreSavedView : true,
                reviewContext: args is GalleryArgs ? args.context : null,
              );
      case BirdRoutes.scenes:
        final args = settings.arguments;
        page = args is SceneListArgs ? SceneListPage(args: args) : _invalid('拍摄场景', '缺少拍摄记录');
      case BirdRoutes.groupReview:
        final args = settings.arguments;
        final id = _groupBatchId(args);
        page = id == null
            ? _invalid('挑选连拍照片', '缺少拍摄记录')
            : GroupReviewPage(
                batchId: id,
                sceneId: args is GroupReviewArgs ? args.sceneId : null,
                sceneName: args is GroupReviewArgs ? args.sceneName : null,
                reviewContext: args is GroupReviewArgs ? args.context : null,
              );
      case BirdRoutes.comparisonReview:
        final args = settings.arguments;
        page = args is ComparisonReviewArgs && args.fileIds.length >= 2 ? ComparisonReviewPage(args: args) : _invalid('对比审阅', '至少需要两张照片');
      case BirdRoutes.photoDetail:
        final args = settings.arguments;
        final id = _fileId(args);
        page = id == null
            ? _invalid('照片详情', '缺少照片编号')
            : PhotoDetailPage(
                fileId: id,
                displayIndex: args is PhotoDetailArgs ? args.displayIndex : null,
                totalCount: args is PhotoDetailArgs ? args.totalCount : null,
                sequence: args is PhotoDetailArgs ? args.sequence : const [],
                hasMoreSequence: args is PhotoDetailArgs && args.hasMoreSequence,
                loadMoreSequence: args is PhotoDetailArgs ? args.loadMoreSequence : null,
                reviewContext: args is PhotoDetailArgs ? args.reviewContext : null,
              );
      case BirdRoutes.copyConfirmation:
        final id = _copyBatchId(settings.arguments);
        page = id == null ? _invalid('复制确认', '缺少拍摄记录') : CopyConfirmationPage(batchId: id);
      case BirdRoutes.jobDetail:
        final args = settings.arguments;
        final id = _clean(
          args is JobDetailArgs
              ? args.jobId
              : args is String
              ? args
              : null,
        );
        page = id == null
            ? _invalid('处理详情', '缺少任务编号')
            : JobDetailPage(
                jobId: id,
                sourceBatchId: args is JobDetailArgs ? args.sourceBatchId : null,
              );
      case BirdRoutes.jobCenter:
        page = const JobCenterPage();
      case BirdRoutes.batches:
        final args = settings.arguments;
        page = BatchListPage(openMode: args is BatchOpenMode ? args : BatchOpenMode.gallery);
      case BirdRoutes.diagnostics:
        page = const DiagnosticsPage();
      case BirdRoutes.settingsDeviceManagement:
        page = _SettingsControllerRoute(
          builder: (context, controller) => DeviceManagementPage(
            controller: controller,
            onOpenDetails: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DeviceDetailsPage(controller: controller),
              ),
            ),
          ),
        );
      case BirdRoutes.settingsDeviceDetails:
        page = _SettingsControllerRoute(
          builder: (_, controller) => DeviceDetailsPage(controller: controller),
        );
      case BirdRoutes.settingsDisplay:
        page = _SettingsControllerRoute(
          builder: (_, controller) => DisplaySettingsPage(controller: controller),
        );
      case BirdRoutes.settingsPhotos:
        page = _SettingsControllerRoute(
          builder: (_, controller) => PhotoSettingsPage(controller: controller),
        );
      case BirdRoutes.settingsCopyBackup:
        page = _SettingsControllerRoute(
          builder: (_, controller) => CopyBackupSettingsPage(controller: controller),
        );
      case BirdRoutes.settingsStorageTarget:
        page = _SettingsControllerRoute(
          builder: (_, controller) => StorageTargetPage(controller: controller),
        );
      case BirdRoutes.settingsNetworkDiagnostics:
        page = const NetworkDiagnosticsPage();
      case BirdRoutes.settingsSystemLogs:
        page = const SystemLogsPage();
      case BirdRoutes.settingsHelp:
        page = const HelpCenterPage();
      default:
        page = _invalid('页面不存在', '请返回拍鸟伴侣首页后重新选择功能');
    }
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }

  static String? _clean(String? value) => value?.trim().isNotEmpty == true ? value!.trim() : null;
  static String? _batchId(Object? value) => _clean(
    value is GalleryArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _groupBatchId(Object? value) => _clean(
    value is GroupReviewArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _copyBatchId(Object? value) => _clean(
    value is CopyConfirmationArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _fileId(Object? value) => _clean(
    value is PhotoDetailArgs
        ? value.fileId
        : value is String
        ? value
        : null,
  );

  static Widget _invalid(String title, String message) => _RouteErrorPage(title: title, message: message);
}

typedef _SettingsPageBuilder =
    Widget Function(
      BuildContext context,
      BirdSettingsController controller,
    );

class _SettingsControllerRoute extends StatefulWidget {
  const _SettingsControllerRoute({required this.builder});

  final _SettingsPageBuilder builder;

  @override
  State<_SettingsControllerRoute> createState() => _SettingsControllerRouteState();
}

class _SettingsControllerRouteState extends State<_SettingsControllerRoute> {
  BirdSettingsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = context.dependOnInheritedWidgetOfExactType<BirdCompanionScope>()?.dependencies;
    _controller = BirdSettingsController(
      store: dependencies?.settingsStore,
      dataChangeBus: dependencies?.dataChangeBus,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller!);
}

class _RouteErrorPage extends StatelessWidget {
  const _RouteErrorPage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: EmptyState(
        icon: Icons.explore_off_outlined,
        title: title,
        message: message,
        actionLabel: '返回',
        onAction: () {
          final navigator = Navigator.of(context);
          navigator.canPop() ? navigator.pop() : navigator.pushReplacementNamed(BirdRoutes.shell);
        },
      ),
    ),
  );
}
