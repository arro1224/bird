import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';

/// Compatibility route for callers outside the task tab.
///
/// Copy confirmation, the gallery and the job center still navigate to
/// [BirdRoutes.jobDetail]. The route now renders the same production task
/// controller and [TaskDetailPage] used by the task tab, so there is only one
/// task-detail interaction model.
class JobDetailPage extends StatefulWidget {
  const JobDetailPage({super.key, required this.jobId, this.sourceBatchId});

  final String jobId;
  final String? sourceBatchId;

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  bool _openingReport = false;
  RepositoryTaskExperienceController? _controller;
  var _initialized = false;

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
    );
    _controller = controller;
    unawaited(_initializeController(controller));
  }

  Future<void> _initializeController(
    RepositoryTaskExperienceController controller,
  ) async {
    try {
      await controller.initialize();
      await controller.refreshJobDetail(widget.jobId);
    } catch (_) {
      // The controller retains the error for the unavailable state. Avoid an
      // unhandled route-initialization future while keeping retry semantics
      // explicit.
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const _TaskDetailLoadingPage();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasTask = controller.jobs.any((job) => job.id == widget.jobId);
        if (!hasTask) {
          if (!_initialized || controller.loading) {
            return const _TaskDetailLoadingPage();
          }
          return _TaskDetailUnavailablePage(error: controller.error);
        }
        final task = controller.taskById(widget.jobId);
        final sourceProjectId = _sourceProjectId(controller);
        return TaskDetailPage(
          controller: controller,
          taskId: widget.jobId,
          allowDemoCompletion: false,
          onControl: _control,
          onExportLog: _exportTaskLog,
          onShowResult: task.type == TaskType.copy && task.state == TaskRunState.completed
              ? () => unawaited(
                  _openReport(widget.jobId, sourceProjectId),
                )
              : null,
        );
      },
    );
  }

  String? _sourceProjectId(
    RepositoryTaskExperienceController controller,
  ) {
    final routeValue = widget.sourceBatchId?.trim();
    if (routeValue != null && routeValue.isNotEmpty) return routeValue;
    for (final job in controller.jobs) {
      if (job.id == widget.jobId) {
        final value = job.sourceProjectId?.trim();
        return value == null || value.isEmpty ? null : value;
      }
    }
    return null;
  }

  Future<void> _control(String taskId, TaskAction action) async {
    try {
      await _controller!.controlJob(taskId, action);
    } catch (error) {
      if (mounted) _showError(error);
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

  Future<void> _openReport(
    String jobId,
    String? sourceProjectId,
  ) async {
    if (_openingReport) return;
    _openingReport = true;
    try {
      final dependencies = BirdCompanionScope.of(context);
      final report = await _controller!.report(jobId);
      var failurePage = const JobFailurePage.empty();
      Object? failureError;
      if (report.failedCount > 0) {
        try {
          failurePage = await dependencies.jobRepository.failurePage(jobId);
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
            loadFailurePage: (cursor) => dependencies.jobRepository.failurePage(jobId, cursor: cursor),
            onOpenAlbum: sourceProjectId == null
                ? null
                : () => Navigator.of(context).pushReplacementNamed(
                    BirdRoutes.gallery,
                    arguments: GalleryArgs(sourceProjectId),
                  ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      _openingReport = false;
    }
  }

  void _showError(Object error) {
    final message = UserMessageMapper.fromError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${message.title}：${message.message}')),
    );
  }
}

class _TaskDetailLoadingPage extends StatelessWidget {
  const _TaskDetailLoadingPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        Positioned.fill(child: TaskNatureBackground()),
        Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}

class _TaskDetailUnavailablePage extends StatelessWidget {
  const _TaskDetailUnavailablePage({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final message = error == null ? null : UserMessageMapper.fromError(error!);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('任务详情')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message == null ? '未找到这条任务，请返回任务列表刷新后重试。' : '${message.title}：${message.message}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
