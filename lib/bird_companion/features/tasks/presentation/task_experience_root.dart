import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:flutter/material.dart';

/// Production task tab backed by the box storage, project and job APIs.
class TaskExperienceRoot extends StatefulWidget {
  const TaskExperienceRoot({super.key, required this.onOpenGallery});

  final ValueChanged<GalleryArgs> onOpenGallery;

  @override
  State<TaskExperienceRoot> createState() => _TaskExperienceRootState();
}

class _TaskExperienceRootState extends State<TaskExperienceRoot> {
  RepositoryTaskExperienceController? _controller;
  StreamSubscription<String>? _analysisSubscription;
  StreamSubscription<String>? _copySubscription;
  var _autoOpeningReport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = BirdCompanionScope.of(context);
    final controller = RepositoryTaskExperienceController(
      storageRepository: dependencies.storageRepository,
      batchRepository: dependencies.batchRepository,
      jobRepository: dependencies.jobRepository,
      copyRepository: dependencies.copyRepository,
      eventClient: dependencies.eventClient,
      deviceSessionCubit: dependencies.deviceSessionCubit,
    );
    _controller = controller;
    _analysisSubscription = controller.analysisCompletedProjects.listen(
      (projectId) => widget.onOpenGallery(GalleryArgs(projectId)),
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
    );
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

  void _openTask(String taskId) {
    final controller = _controller!;
    final task = controller.taskById(taskId);
    final sourceProjectId = task.sourceBatch?.trim();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailPage(
          controller: controller,
          taskId: taskId,
          allowDemoCompletion: false,
          onControl: _control,
          onExportLog: _exportTaskLog,
          onShowResult: task.state == TaskRunState.completed && task.type == TaskType.copy
              ? () => unawaited(
                  _openReport(taskId, sourceProjectId),
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _openReport(
    String jobId,
    String? sourceProjectId, {
    bool automatic = false,
  }) async {
    if (automatic) {
      if (_autoOpeningReport) return;
      _autoOpeningReport = true;
    }
    try {
      final report = await _controller!.report(jobId);
      final List<JobFailure> failures = report.failedCount > 0
          ? await BirdCompanionScope.of(
              context,
            ).jobRepository.failures(jobId)
          : const <JobFailure>[];
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProductionTaskResultPage(
            report: report,
            failures: failures,
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
