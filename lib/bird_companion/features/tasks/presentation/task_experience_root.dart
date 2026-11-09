import 'dart:async';
import 'package:aves/bird_companion/features/recognition/recognition_widgets.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_task_tile.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_section.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/active_copy_jobs_banner.dart';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_destination_resolver.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_result_sheet.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_job_summary_sheet.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:flutter/material.dart';

/// Production task tab backed by the box storage, project and job APIs.
class TaskExperienceRoot extends StatefulWidget {
  const TaskExperienceRoot({
    super.key,
    required this.onOpenGallery,
    this.onAnalysisCompleted,
  });

  final ValueChanged<GalleryArgs> onOpenGallery;
  final ValueChanged<String>? onAnalysisCompleted;

  @override
  State<TaskExperienceRoot> createState() => _TaskExperienceRootState();
}

class _TaskExperienceRootState extends State<TaskExperienceRoot> {
  RepositoryTaskExperienceController? _controller;
  StreamSubscription<String>? _analysisSubscription;
  StreamSubscription<String>? _copySubscription;
  var _autoOpeningReport = false;
  final Set<String> _openingReportJobs = {};
  var _syncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = BirdCompanionScope.of(context);
    final controller = RepositoryTaskExperienceController(
      deviceRepository: dependencies.deviceRepository,
      storageRepository: dependencies.storageRepository,
      batchRepository: dependencies.batchRepository,
      jobRepository: dependencies.jobRepository,
      copyRepository: dependencies.copyRepository,
      copyJobRepository: dependencies.copyJobRepository,
      eventClient: dependencies.eventClient,
      deviceSessionCubit: dependencies.deviceSessionCubit,
      pendingOperationStore: dependencies.pendingOperationStore,
      dataChangeBus: dependencies.dataChangeBus,
      recognitionRepository: dependencies.recognitionRepository,
      smartFollowCreation: dependencies.smartFollowCreation,
      smartFollowConfiguration: (batch) => smartFollowConfigurationReader(dependencies, batch),
    );
    _controller = controller;
    _analysisSubscription = controller.analysisCompletedProjects.listen(
      (projectId) async {
        final device = dependencies.smartFollowCreation.contextKey();
        if (dependencies.smartFollowCreation.hasStaged(projectId) || dependencies.smartFollowCreation.hasPending(projectId)) return;
        try {
          final capabilities = await dependencies.smartFollowRepository.capabilities();
          if (capabilities.canShowEntry) {
            for (final job in controller.jobs.where((job) => job.sourceProjectId == projectId && job.type.name == 'analysis')) {
              if (job.smartFollowSessionId != null || await dependencies.smartFollowRepository.refreshForJob(job.id) != null) return;
            }
          }
        } catch (_) {
          return; // Do not present recognition completion as follow completion.
        }
        if (!mounted || dependencies.smartFollowCreation.contextKey() != device) return;
        final onAnalysisCompleted = widget.onAnalysisCompleted;
        if (onAnalysisCompleted != null) {
          onAnalysisCompleted(projectId);
        } else {
          widget.onOpenGallery(GalleryArgs(projectId));
        }
      },
    );
    _copySubscription = controller.copyCompletedJobs.listen((jobId) {
      if (!mounted || _autoOpeningReport || !dependencies.settingsStore.read().autoOpenReport) {
        return;
      }
      String? sourceProjectId;
      for (final job in controller.jobs) {
        if (job.id == jobId) {
          sourceProjectId = job.sourceProjectId?.trim();
          break;
        }
      }
      unawaited(
        _openReport(
          jobId,
          sourceProjectId,
          automatic: true,
        ),
      );
    });
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    unawaited(_analysisSubscription?.cancel());
    unawaited(_copySubscription?.cancel());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return TaskHomePage(
      controller: controller,
      onOpenSdCard: _openSdCard,
      onOpenTask: _openTask,
      onStartTask: _startTask,
      onOpenCopyJobs: _openCopyJobs,
      copyRecoveryBanner: ActiveCopyJobsBanner(recovery: BirdCompanionScope.of(context).copyJobRecovery),
    );
  }

  /// RC3 复制任务列表（独立于通用任务中心，不含 copy_jobs_v1 任务）。
  Future<void> _openCopyJobs() async {
    await Navigator.of(context).pushNamed<void>(BirdRoutes.copyJobs);
    // 详情页可能已执行取消/重试等动作，返回后刷新任务首页。
    await _controller?.refreshFromBox();
  }

  Future<void> _startTask(TaskType type) async {
    final controller = _controller!;
    try {
      if (!controller.canSubmitTaskWrites) {
        throw StateError('The task home state is refreshing');
      }
      switch (type) {
        case TaskType.importIndex:
          _openSdCard();
          return;
        case TaskType.aiAnalysis:
          final dependencies = BirdCompanionScope.of(context);
          final batchId = controller.activeBatchId;
          if (batchId == null || batchId.trim().isEmpty) throw StateError('当前没有可用批次');
          final choice = await chooseRecognitionMode(
            context,
            dependencies.recognitionRepository,
            entryReader: smartFollowEntryReader(dependencies, batchId),
            configurationReader: smartFollowConfigurationReader(dependencies, batchId),
            creationService: dependencies.smartFollowCreation,
          );
          if (choice == null) return;
          if (choice.existingSessionId != null) {
            if (mounted) await Navigator.of(context).pushNamed<void>(BirdRoutes.smartFollowRun, arguments: SmartFollowRunArgs(choice.existingSessionId!));
            return;
          }
          if (choice.existingRecognitionJobId != null) {
            if (mounted) await _openTask(choice.existingRecognitionJobId!);
            return;
          }
          await dependencies.smartFollowCreation.discardStaged(batchId);
          await dependencies.recognitionRepository.rememberAnalysisOption(batchId, null);
          final jobId = await controller.startAnalysisForActiveProject(smartFollow: choice.config);
          if (mounted) await _openTask(jobId);
          return;
        case TaskType.copy:
          final batchId = controller.activeBatchId?.trim();
          if (batchId == null || batchId.isEmpty) {
            throw StateError('There is no active project to copy');
          }
          if (mounted) {
            await Navigator.of(context).pushNamed<void>(
              BirdRoutes.copyConfirmation,
              arguments: CopyConfirmationArgs(batchId, enableSmartFollow: true),
            );
            await controller.refreshFromBox();
          }
          return;
        case TaskType.fullBackup:
          if (mounted) {
            await Navigator.of(context).pushNamed<void>(BirdRoutes.fullBackup);
            await controller.refreshFromBox();
          }
          return;
        case TaskType.sync:
          if (_syncing) return;
          if (controller.connectionState != TaskConnectionState.connected) {
            throw StateError('The box is not connected');
          }
          _syncing = true;
          try {
            final result = await BirdCompanionScope.of(
              context,
            ).birdSyncService.synchronize();
            await controller.refreshFromBox(includeScan: true);
            if (!mounted) return;
            final firstConflictProjectId = result.remainingOperations
                .where(
                  (operation) => operation.status == PendingOperationStatus.conflict && (operation.projectId?.trim().isNotEmpty ?? false),
                )
                .map((operation) => operation.projectId!.trim())
                .firstOrNull;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              builder: (_) => TaskSyncResultSheet(
                result: result,
                onOpenConflicts: firstConflictProjectId == null
                    ? null
                    : () => widget.onOpenGallery(
                        GalleryArgs(firstConflictProjectId),
                      ),
              ),
            );
            if (!mounted) return;
            final refreshError = controller.error;
            if (refreshError != null) _showError(context, refreshError);
          } finally {
            _syncing = false;
          }
          return;
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  void _openSdCard() {
    final controller = _controller!;
    Map<String, dynamic>? selected;
    SmartFollowConfiguredIntent? selectedIntent;
    final configurationReady = ValueNotifier(true);
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (sdContext) => SdCardFlowPage(
              controller: controller,
              onRescan: controller.rescan,
              onContinue: () {
                selected = null;
                selectedIntent = null;
                configurationReady.value = true;
                unawaited(
                  Navigator.of(sdContext).push<void>(
                    MaterialPageRoute<void>(
                      builder: (batchContext) => ValueListenableBuilder<bool>(
                        valueListenable: configurationReady,
                        builder: (_, ready, _) => BatchSetupPage(
                          controller: controller,
                          canStartImport: ready,
                          analysisOptions: RecognitionOptions(
                            repository: BirdCompanionScope.of(context).recognitionRepository,
                            onChanged: (value) => selected = value,
                            onConfigured: (value) => selectedIntent = value,
                            onReadyChanged: (value) => configurationReady.value = value,
                          ),
                          onStartImport: (batchName) async {
                            try {
                              await controller.startImportBatch(batchName, smartFollow: selected, smartFollowIntent: selectedIntent);
                              if (!batchContext.mounted) return;
                              final jobId = controller.currentJobId;
                              if (jobId == null) return;
                              unawaited(
                                Navigator.of(batchContext).pushReplacement<void, void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TaskDetailPage(
                                      controller: controller,
                                      taskId: jobId,
                                      allowDemoCompletion: false,
                                      onControl: _control,
                                      onExportLog: _exportTaskLog,
                                    ),
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (batchContext.mounted) {
                                _showError(batchContext, error);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        )
        .whenComplete(configurationReady.dispose);
  }

  Future<void> _openTask(String taskId) async {
    final controller = _controller!;
    try {
      await controller.refreshJobDetail(taskId);
    } catch (error) {
      if (mounted) _showError(context, error);
      return;
    }
    if (!mounted) return;
    final refreshedTask = controller.taskByIdOrNull(taskId);
    if (refreshedTask == null) {
      _showError(context, StateError('任务已不在当前列表，请刷新后重试'));
      return;
    }
    final sourceProjectId = refreshedTask.sourceBatchId?.trim();
    final recognition = BirdCompanionScope.of(context).recognitionRepository;
    if (refreshedTask.type == TaskType.aiAnalysis) {
      try {
        final dependencies = BirdCompanionScope.of(context);
        final device = dependencies.smartFollowCreation.contextKey();
        final capabilities = await dependencies.smartFollowRepository.capabilities();
        if (capabilities.canShowEntry) {
          final session = await dependencies.smartFollowRepository.refreshForJob(taskId);
          if (!mounted || dependencies.smartFollowCreation.contextKey() != device) return;
          if (session != null) {
            await Navigator.of(context).pushNamed<void>(BirdRoutes.smartFollowRun, arguments: SmartFollowRunArgs(session.sessionId, recognitionJobId: taskId));
            return;
          }
        }
        await recognition.sync(taskId);
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          if (mounted) _showError(context, error);
          return;
        }
      } catch (error) {
        if (mounted) _showError(context, error);
        return;
      }
      if (!mounted) return;
    }
    final destination = TaskDestinationResolver.resolve(refreshedTask, incrementalRecognition: recognition.snapshot(taskId) != null);
    switch (destination.kind) {
      case TaskDestinationKind.album:
        widget.onOpenGallery(
          GalleryArgs(destination.sourceProjectId!),
        );
        return;
      case TaskDestinationKind.copyResult:
        await _openReport(taskId, sourceProjectId);
        return;
      case TaskDestinationKind.detail:
        break;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TaskDetailPage(
            controller: controller,
            taskId: taskId,
            incrementalPanel: refreshedTask.type == TaskType.aiAnalysis
                ? Column(
                    children: [
                      SmartFollowTaskTile(
                        repository: BirdCompanionScope.of(context).smartFollowRepository,
                        recognitionJobId: taskId,
                        recognitionProcessed: refreshedTask.processed,
                        recognitionTotal: refreshedTask.total,
                        onOpenRun: (sessionId) => unawaited(
                          Navigator.of(context).pushNamed<void>(
                            BirdRoutes.smartFollowRun,
                            arguments: SmartFollowRunArgs(
                              sessionId,
                              recognitionJobId: taskId,
                              recognitionProcessed: refreshedTask.processed,
                              recognitionTotal: refreshedTask.total,
                            ),
                          ),
                        ),
                      ),
                      if (sourceProjectId != null)
                        SmartFollowEntrySection(
                          batchId: sourceProjectId,
                          recognitionJobId: taskId,
                          onModeChanged: (_) {},
                          onSnapshot: () => unawaited(Navigator.of(context).pushNamed<void>(BirdRoutes.copyConfirmation, arguments: CopyConfirmationArgs(sourceProjectId, scope: 'recognized_assets'))),
                          onOpenRecognition: () => controller.refreshJobDetail(taskId),
                        ),
                    ],
                  )
                : null,
            allowDemoCompletion: false,
            onControl: _control,
            onExportLog: _exportTaskLog,
            onShowResult: switch ((refreshedTask.type, refreshedTask.state)) {
              (TaskType.aiAnalysis, TaskRunState.completed) when sourceProjectId != null => () => widget.onOpenGallery(GalleryArgs(sourceProjectId)),
              (TaskType.copy, TaskRunState.completed) => () => unawaited(
                _openReport(taskId, sourceProjectId),
              ),
              (TaskType.sync, TaskRunState.completed) => () => unawaited(
                _showSyncJobSummary(refreshedTask),
              ),
              _ => null,
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showSyncJobSummary(TaskSummary task) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => TaskSyncJobSummarySheet(task: task),
  );

  Future<void> _openReport(
    String jobId,
    String? sourceProjectId, {
    bool automatic = false,
  }) async {
    if (!_openingReportJobs.add(jobId)) return;
    if (automatic) {
      if (_autoOpeningReport) {
        _openingReportJobs.remove(jobId);
        return;
      }
      _autoOpeningReport = true;
    }
    try {
      final jobRepository = BirdCompanionScope.of(context).jobRepository;
      final report = await _controller!.report(jobId);
      var failurePage = const JobFailurePage.empty();
      Object? failureError;
      if (report.failedCount > 0) {
        try {
          failurePage = await jobRepository.failurePage(jobId);
        } catch (error) {
          failureError = error;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProductionTaskResultPage(
            report: report,
            initialFailurePage: failurePage,
            initialFailureError: failureError,
            loadFailurePage: (cursor) => jobRepository.failurePage(
              jobId,
              cursor: cursor,
            ),
            onOpenAlbum: sourceProjectId == null || sourceProjectId.isEmpty
                ? null
                : () => widget.onOpenGallery(
                    GalleryArgs(sourceProjectId),
                  ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (automatic) _autoOpeningReport = false;
      _openingReportJobs.remove(jobId);
    }
  }

  Future<void> _control(String taskId, TaskAction action) async {
    try {
      await _controller!.controlJob(taskId, action);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<String> _exportTaskLog(String taskId) async {
    final dependencies = BirdCompanionScope.of(context);
    final downloaded = await dependencies.logDownloadService.downloadWithRefresh(
      () => dependencies.jobRepository.exportLogs(
        scope: 'jobs',
        jobId: taskId,
      ),
    );
    if (await downloaded.file.length() <= 0) {
      throw StateError('The downloaded task log is empty.');
    }
    return downloaded.file.path;
  }

  void _showError(BuildContext context, Object error) {
    if (error is SmartFollowCreationPending || error is SmartFollowConfirmationRequired) {
      final text = error is SmartFollowConfirmationRequired ? error.message : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    final message = UserMessageMapper.fromError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${message.title}：${message.message}')),
    );
  }
}
