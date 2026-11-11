import 'dart:async';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_list_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_child_jobs_view.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_section.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_preview_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_page.dart';
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
import 'package:aves/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
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
  static const fullBackup = '/full-backup';
  static const copyJobs = '/copy-jobs';
  static const copyJobDetail = '/copy-job-detail';
  // SmartFollow 运行页（联合任务书 §9：入口随识别状态变化，运行页独立路由）。
  static const smartFollowRun = '/smart-follow-run';
  static const smartFollowCompletion = '/smart-follow-completion';
  static const smartFollowMetadataPreview = '/smart-follow-metadata-preview';
  static const smartFollowMetadataUpdate = '/smart-follow-metadata-update';
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
  static const settingsNetwork = '/settings/network';
  static const settingsSystemLogs = '/settings/system-logs';
  static const settingsHelp = '/settings/help';
}

/// Opens the canonical connection flow from any reconnect entry.
void openReconnectConnection(BuildContext context) {
  unawaited(() async {
    final dependencies = BirdCompanionScope.maybeOf(context);
    final verification = dependencies?.deviceSessionCubit.verifySavedSession();
    final attemptId = dependencies?.deviceSessionCubit.activeAttemptId;
    if (await verification == true) {
      // 已连接时点击"重新连接"过去会静默返回，用户以为按钮失效；给一次明确反馈。
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('连接正常，已刷新设备状态。')));
      }
      return;
    }
    if (!context.mounted) return;
    if (dependencies != null && (dependencies.deviceSessionCubit.activeAttemptId != attemptId || dependencies.deviceSessionCubit.provisioningHandoffActive)) return;
    // A pending authenticated event gate is retried on the same saved device.
    if (dependencies?.deviceSessionCubit.state.verificationStage == 'events') return;
    unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamed(
        BirdRoutes.connection,
        arguments: const ConnectionArgs(
          entryMode: ConnectionEntryMode.addOrSwitch,
        ),
      ),
    );
  }());
}

abstract final class BirdAppRouter {
  static Route<void> onGenerateRoute(
    RouteSettings settings, {
    ProvisioningRepository? provisioningRepository,
    ProvisioningCompletionHandler? onProvisioningCompleted,
  }) {
    Widget page;
    switch (settings.name) {
      case BirdRoutes.connection:
        final args = settings.arguments;
        page = ConnectionPage(
          entryMode: args is ConnectionArgs ? args.entryMode : ConnectionEntryMode.initialSetup,
          provisioningRepository: provisioningRepository,
          onProvisioningCompleted: onProvisioningCompleted,
        );
      case BirdRoutes.shell:
        final args = settings.arguments;
        page = BirdAppShell(
          initialIndex: args is ShellArgs ? args.initialIndex : 0,
          initialRoute: args is ShellArgs ? args.initialRoute : null,
          onGenerateRoute: (settings) => onGenerateRoute(
            settings,
            provisioningRepository: provisioningRepository,
            onProvisioningCompleted: onProvisioningCompleted,
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
                timing: args is GalleryArgs ? args.timing : null,
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
        page = id == null ? _invalid('复制确认', '缺少拍摄记录') : CopyConfirmationPage.fromArgs(args: settings.arguments);
      case BirdRoutes.fullBackup:
        page = const CopyConfirmationPage(
          batchId: null,
          initialScope: 'media_full_backup',
        );
      case BirdRoutes.copyJobs:
        page = const CopyJobListPage();
      case BirdRoutes.smartFollowRun:
        final args = settings.arguments;
        final runArgs = args is SmartFollowRunArgs
            ? args
            : args is String && args.trim().isNotEmpty
            ? SmartFollowRunArgs(args.trim())
            : null;
        page = runArgs == null ? _invalid('边识别边复制', '缺少跟随任务编号') : _SmartFollowRunRoute(args: runArgs);
      case BirdRoutes.smartFollowCompletion:
        final args = settings.arguments;
        page = args is SmartFollowCompletionArgs && args.sessionId.trim().isNotEmpty ? _SmartFollowCompletionRoute(args: args) : _invalid('边识别边复制结果', '缺少跟随任务编号');
      case BirdRoutes.smartFollowMetadataPreview:
        final args = settings.arguments;
        page = args is SmartFollowMetadataPreviewArgs && args.sessionId.trim().isNotEmpty ? _SmartFollowMetadataPreviewRoute(args: args) : _invalid('预览识别信息更新', '缺少跟随任务编号');
      case BirdRoutes.smartFollowMetadataUpdate:
        final args = settings.arguments;
        page = args is SmartFollowMetadataUpdateArgs && args.sessionId.trim().isNotEmpty && (args.updateId == null || args.updateId!.trim().isNotEmpty) ? _SmartFollowMetadataUpdateRoute(args: args) : _invalid('识别信息更新任务', '缺少原任务关联');
      case BirdRoutes.copyJobDetail:
        final args = settings.arguments;
        final id = _clean(
          args is CopyJobDetailArgs
              ? args.copyJobId
              : args is String
              ? args
              : null,
        );
        page = id == null ? _invalid('复制任务详情', '缺少任务编号') : CopyJobDetailPage(copyJobId: id, deviceId: args is CopyJobDetailArgs ? args.deviceId : null, createdJob: args is CopyJobDetailArgs ? args.createdJob : null);
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
        page = provisioningRepository == null
            ? _SettingsControllerRoute(
                builder: (context, controller) => DeviceManagementPage(
                  controller: controller,
                  onOpenDetails: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DeviceDetailsPage(controller: controller),
                    ),
                  ),
                ),
              )
            : ConnectionPage(
                entryMode: ConnectionEntryMode.addOrSwitch,
                provisioningRepository: provisioningRepository,
                onProvisioningCompleted: onProvisioningCompleted,
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
      case BirdRoutes.settingsNetwork:
        page = provisioningRepository == null
            ? _invalid('网络设置', '当前未提供蓝牙配网服务')
            : NetworkSettingsPage(
                repository: provisioningRepository,
                onProvisioningCompleted: onProvisioningCompleted,
              );
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

/// 运行页路由壳：仓储从依赖容器取（页面本身仍接受显式 repository，便于测试），
/// 并把"复制批次"接到 RC3 child CopyJob 详情。
class _SmartFollowRunRoute extends StatefulWidget {
  const _SmartFollowRunRoute({required this.args});

  final SmartFollowRunArgs args;

  @override
  State<_SmartFollowRunRoute> createState() => _SmartFollowRunRouteState();
}

class _SmartFollowRunRouteState extends State<_SmartFollowRunRoute> {
  String? _contextKey;
  int? _deviceGeneration;
  Stream<void>? _signals;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = BirdCompanionScope.of(context);
    _deviceGeneration ??= dependencies.smartFollowRepository.deviceGeneration;
    _contextKey ??= '${dependencies.deviceSessionCubit.state.device?.id}|${dependencies.apiClient.baseUri}';
    _signals ??= Stream<void>.multi((signals) {
      final subscriptions = [
        dependencies.deviceSessionCubit.stream.listen((_) => signals.add(null)),
        dependencies.refreshCoordinator.changes.listen((_) => signals.add(null)),
      ];
      signals.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    final repository = dependencies.smartFollowRepository;
    final args = widget.args;
    bool current() => _deviceGeneration == repository.deviceGeneration && dependencies.deviceSessionCubit.state.isConnected && _contextKey == '${dependencies.deviceSessionCubit.state.device?.id}|${dependencies.apiClient.baseUri}';
    return SmartFollowRunPage(
      repository: repository,
      sessionId: args.sessionId,
      recognitionProcessed: args.recognitionProcessed,
      recognitionTotal: args.recognitionTotal,
      pollInterval: const Duration(seconds: 4),
      readRecognition: dependencies.jobRepository.detail,
      refreshSignals: _signals,
      isCurrent: current,
      metadataSection: _metadataSection(context, dependencies, args.sessionId, current, _signals),
      onOpenCompletion: () {
        if (!current()) return;
        Navigator.of(context).pushNamed(
          BirdRoutes.smartFollowCompletion,
          arguments: SmartFollowCompletionArgs(args.sessionId, deviceId: dependencies.deviceSessionCubit.state.device?.id, deviceGeneration: _deviceGeneration, baseUri: dependencies.apiClient.baseUri.toString()),
        );
      },
      onOpenChildJobs: () => showSmartFollowChildJobsSheet(
        context,
        repository: repository,
        sessionId: args.sessionId,
        onOpenCopyJob: (copyJobId) {
          if (current()) Navigator.of(context).pushNamed(BirdRoutes.copyJobDetail, arguments: CopyJobDetailArgs(copyJobId, deviceId: dependencies.deviceSessionCubit.state.device?.id));
        },
      ),
    );
  }
}

class _SmartFollowCompletionRoute extends StatefulWidget {
  const _SmartFollowCompletionRoute({required this.args});
  final SmartFollowCompletionArgs args;
  @override
  State<_SmartFollowCompletionRoute> createState() => _SmartFollowCompletionRouteState();
}

class _SmartFollowCompletionRouteState extends State<_SmartFollowCompletionRoute> {
  SmartFollowCompletionController? _controller;
  Stream<void>? _signals;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = BirdCompanionScope.of(context);
    final args = widget.args;
    final generation = args.deviceGeneration ?? dependencies.smartFollowRepository.deviceGeneration;
    final deviceId = args.deviceId ?? dependencies.deviceSessionCubit.state.device?.id;
    final baseUri = args.baseUri ?? dependencies.apiClient.baseUri.toString();
    _controller = SmartFollowCompletionController(
      repository: dependencies.smartFollowRepository,
      sessionId: args.sessionId,
      readChild: dependencies.copyJobRepository.getJob,
      readCopyReport: dependencies.copyJobRepository.jobReport,
      readRecognition: dependencies.jobRepository.detail,
      readRecognitionReport: dependencies.jobRepository.report,
      isCurrent: () =>
          generation == dependencies.smartFollowRepository.deviceGeneration &&
          dependencies.deviceSessionCubit.state.isConnected &&
          deviceId == dependencies.deviceSessionCubit.state.device?.id &&
          baseUri == dependencies.apiClient.baseUri.toString(),
    );
    _signals = Stream<void>.multi((signals) {
      final subscriptions = [dependencies.deviceSessionCubit.stream.listen((_) => signals.add(null)), dependencies.refreshCoordinator.changes.listen((_) => signals.add(null))];
      signals.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SmartFollowCompletionPage(
    controller: _controller!,
    refreshSignals: _signals,
    metadataSection: _metadataSection(context, BirdCompanionScope.of(context), widget.args.sessionId, () => _controller!.isCurrent?.call() ?? true, _signals),
    onOpenRun: () {
      if (!(_controller!.isCurrent?.call() ?? true)) return;
      Navigator.of(context).pushReplacementNamed(BirdRoutes.smartFollowRun, arguments: SmartFollowRunArgs(widget.args.sessionId));
    },
    onOpenChild: (id) {
      if (!(_controller!.isCurrent?.call() ?? true)) return;
      Navigator.of(context).pushNamed(BirdRoutes.copyJobDetail, arguments: CopyJobDetailArgs(id, deviceId: BirdCompanionScope.of(context).deviceSessionCubit.state.device?.id));
    },
  );
}

Widget _metadataSection(BuildContext context, BirdCompanionDependencies dependencies, String sessionId, bool Function() current, Stream<void>? signals) => SmartFollowMetadataSection(
  repository: dependencies.smartFollowRepository,
  sessionId: sessionId,
  readRecognition: dependencies.jobRepository.detail,
  isCurrent: current,
  refreshSignals: signals,
  onOpenPreview: () {
    if (!current()) return;
    Navigator.of(context).pushNamed(
      BirdRoutes.smartFollowMetadataPreview,
      arguments: SmartFollowMetadataPreviewArgs(
        sessionId,
        deviceId: dependencies.deviceSessionCubit.state.device?.id,
        deviceGeneration: dependencies.smartFollowRepository.deviceGeneration,
        baseUri: dependencies.apiClient.baseUri.toString(),
      ),
    );
  },
  onOpenUpdate: (id) => _openMetadataUpdate(context, dependencies, sessionId, id, current),
);

class _SmartFollowMetadataPreviewRoute extends StatefulWidget {
  const _SmartFollowMetadataPreviewRoute({required this.args});
  final SmartFollowMetadataPreviewArgs args;
  @override
  State<_SmartFollowMetadataPreviewRoute> createState() => _SmartFollowMetadataPreviewRouteState();
}

class _SmartFollowMetadataPreviewRouteState extends State<_SmartFollowMetadataPreviewRoute> {
  SmartFollowMetadataController? _controller;
  Stream<void>? _signals;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = BirdCompanionScope.of(context);
    final args = widget.args;
    final generation = args.deviceGeneration ?? dependencies.smartFollowRepository.deviceGeneration;
    final deviceId = args.deviceId ?? dependencies.deviceSessionCubit.state.device?.id;
    final baseUri = args.baseUri ?? dependencies.apiClient.baseUri.toString();
    _controller = SmartFollowMetadataController(
      repository: dependencies.smartFollowRepository,
      sessionId: args.sessionId,
      readRecognition: dependencies.jobRepository.detail,
      isCurrent: () =>
          generation == dependencies.smartFollowRepository.deviceGeneration &&
          dependencies.deviceSessionCubit.state.isConnected &&
          deviceId == dependencies.deviceSessionCubit.state.device?.id &&
          baseUri == dependencies.apiClient.baseUri.toString(),
    );
    _signals = Stream<void>.multi((signals) {
      final subscriptions = [dependencies.deviceSessionCubit.stream.listen((_) => signals.add(null)), dependencies.refreshCoordinator.changes.listen((_) => signals.add(null))];
      signals.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SmartFollowMetadataPreviewPage(
    controller: _controller!,
    refreshSignals: _signals,
    onOpenUpdate: (id) => _openMetadataUpdate(context, BirdCompanionScope.of(context), widget.args.sessionId, id, () => _controller!.current),
  );
}

void _openMetadataUpdate(BuildContext context, BirdCompanionDependencies dependencies, String sessionId, String id, bool Function() current) {
  if (!current()) return;
  Navigator.of(context).pushNamed(
    BirdRoutes.smartFollowMetadataUpdate,
    arguments: SmartFollowMetadataUpdateArgs(
      sessionId,
      updateId: id,
      deviceId: dependencies.deviceSessionCubit.state.device?.id,
      deviceGeneration: dependencies.smartFollowRepository.deviceGeneration,
      baseUri: dependencies.apiClient.baseUri.toString(),
    ),
  );
}

class _SmartFollowMetadataUpdateRoute extends StatefulWidget {
  const _SmartFollowMetadataUpdateRoute({required this.args});
  final SmartFollowMetadataUpdateArgs args;
  @override
  State<_SmartFollowMetadataUpdateRoute> createState() => _SmartFollowMetadataUpdateRouteState();
}

class _SmartFollowMetadataUpdateRouteState extends State<_SmartFollowMetadataUpdateRoute> {
  SmartFollowMetadataUpdateController? _controller;
  Stream<void>? _signals;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = BirdCompanionScope.of(context);
    final args = widget.args;
    final generation = args.deviceGeneration ?? dependencies.smartFollowRepository.deviceGeneration;
    final deviceId = args.deviceId ?? dependencies.deviceSessionCubit.state.device?.id;
    final baseUri = args.baseUri ?? dependencies.apiClient.baseUri.toString();
    _controller = SmartFollowMetadataUpdateController(
      repository: dependencies.smartFollowRepository,
      sessionId: args.sessionId,
      updateId: args.updateId,
      isCurrent: () =>
          generation == dependencies.smartFollowRepository.deviceGeneration &&
          dependencies.deviceSessionCubit.state.isConnected &&
          deviceId == dependencies.deviceSessionCubit.state.device?.id &&
          baseUri == dependencies.apiClient.baseUri.toString(),
    );
    _signals = Stream<void>.multi((signals) {
      final subscriptions = [dependencies.deviceSessionCubit.stream.listen((_) => signals.add(null)), dependencies.refreshCoordinator.changes.listen((_) => signals.add(null))];
      signals.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    final state = _controller!;
    return SmartFollowMetadataUpdatePage(
      controller: state,
      refreshSignals: _signals,
      onOpenCopy: (id) {
        if (state.current) Navigator.of(context).pushNamed(BirdRoutes.copyJobDetail, arguments: CopyJobDetailArgs(id, deviceId: dependencies.deviceSessionCubit.state.device?.id));
      },
      onOpenUpdate: (id) => _openMetadataUpdate(context, dependencies, widget.args.sessionId, id, () => state.current),
      onOpenPreview: () {
        if (!state.canPreview) return;
        Navigator.of(context).pushNamed(
          BirdRoutes.smartFollowMetadataPreview,
          arguments: SmartFollowMetadataPreviewArgs(
            widget.args.sessionId,
            deviceId: dependencies.deviceSessionCubit.state.device?.id,
            deviceGeneration: dependencies.smartFollowRepository.deviceGeneration,
            baseUri: dependencies.apiClient.baseUri.toString(),
          ),
        );
      },
    );
  }
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
