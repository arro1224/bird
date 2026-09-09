import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
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
      eventClient: dependencies.eventClient,
      deviceSessionCubit: dependencies.deviceSessionCubit,
      pendingOperationStore: dependencies.pendingOperationStore,
      dataChangeBus: dependencies.dataChangeBus,
    );
    _controller = controller;
    _analysisSubscription = controller.analysisCompletedProjects.listen(
      (projectId) {
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
    );
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
          final jobId = await controller.startAnalysisForActiveProject();
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
              arguments: batchId,
            );
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
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (sdContext) => SdCardFlowPage(
          controller: controller,
          onRescan: controller.rescan,
          onContinue: () => Navigator.of(sdContext).push<void>(
            MaterialPageRoute<void>(
              builder: (batchContext) => BatchSetupPage(
                controller: controller,
                onStartImport: (batchName) async {
                  try {
                    await controller.startImportBatch(batchName);
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
      ),
    );
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
    final refreshedTask = controller.taskById(taskId);
    final sourceProjectId = refreshedTask.sourceBatchId?.trim();
    final destination = TaskDestinationResolver.resolve(refreshedTask);
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
            allowDemoCompletion: false,
            onControl: _control,
            onExportLog: _exportTaskLog,
            onShowResult: switch ((refreshedTask.type, refreshedTask.state)) {
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
    final message = UserMessageMapper.fromError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${message.title}：${message.message}')),
    );
  }
}
