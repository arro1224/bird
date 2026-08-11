import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/foundation.dart';

abstract final class JobStatusViewAdapter {
  static ValueChanged<BirdJobState>? legacyStateReporter;
  static ValueChanged<String>? unknownWorkflowStageReporter;

  static const _knownWorkflowStages = {
    'scanning',
    'importing',
    'analyzing',
    'awaiting_review',
    'reviewing',
    'awaiting_copy',
    'copying',
    'verifying',
    'exporting_xmp',
    'completed',
  };

  static TaskSummary? toTaskSummary(
    BirdJobStatus job, {
    String? sourceBatch,
    String? sourceBatchId,
    TaskConnectionState connectionState = TaskConnectionState.connected,
    int? remainingMinutes,
  }) {
    final type = _type(job.type);
    if (type == null) return null;
    final state = _state(job.state);
    final rawProgress = job.progress <= 1 ? job.progress * 100 : job.progress;
    final progressPercent = rawProgress.round().clamp(0, 100);
    final workflowStage = job.workflowStage?.trim();
    if (workflowStage?.isNotEmpty == true && !_knownWorkflowStages.contains(workflowStage)) {
      unknownWorkflowStageReporter?.call(workflowStage!);
      debugPrint('Unknown job workflow_stage: $workflowStage');
    }
    return TaskSummary(
      id: job.id,
      type: type,
      title: type.label,
      processed: job.finishedCount,
      total: job.totalCount,
      progressPercent: progressPercent,
      remainingMinutes: remainingMinutes ?? ((job.estimatedRemainingSeconds ?? 0) / 60).ceil(),
      state: state,
      workflowStage: workflowStage,
      sourceBatch: _sourceName(job, sourceBatch),
      sourceBatchId: _nonEmpty(job.sourceProjectId) ?? sourceBatchId,
      currentFile: job.currentFile,
      speed: _speed(job.speedBytesPerSecond),
      failedCount: job.failedCount,
      failureReason: job.errorMessage == null && job.errorCode == null
          ? null
          : UserMessageMapper.fromJobFailure(
              code: job.errorCode,
              message: job.errorMessage,
            ).message,
      connectionState: connectionState,
      availableActions: _actions(job),
    );
  }

  static TaskType? _type(BirdJobType type) => switch (type) {
    BirdJobType.import => TaskType.importIndex,
    BirdJobType.analysis => TaskType.aiAnalysis,
    BirdJobType.copy => TaskType.copy,
    BirdJobType.sync => TaskType.sync,
    BirdJobType.unknown => null,
  };

  static TaskRunState _state(BirdJobState state) {
    if (state == BirdJobState.idle || state == BirdJobState.unknown) {
      legacyStateReporter?.call(state);
      debugPrint(
        'BirdJobStatus compatibility mapping used for ${state.name}; '
        'the box should send queued.',
      );
      return TaskRunState.queued;
    }
    return switch (state) {
      BirdJobState.queued => TaskRunState.queued,
      BirdJobState.running => TaskRunState.running,
      BirdJobState.paused => TaskRunState.paused,
      BirdJobState.completed => TaskRunState.completed,
      BirdJobState.failed => TaskRunState.failed,
      BirdJobState.cancelled => TaskRunState.cancelled,
      BirdJobState.idle || BirdJobState.unknown => TaskRunState.queued,
    };
  }

  static Set<TaskAction> _actions(BirdJobStatus job) => {
    ...job.availableActions.map(_action).whereType<TaskAction>(),
    // Log export is a separate read-only diagnostics endpoint and is not part
    // of the box task-control available_actions contract.
    TaskAction.exportLog,
  };

  static TaskAction? _action(String action) => switch (action) {
    'pause' => TaskAction.pause,
    'resume' => TaskAction.resume,
    'cancel' => TaskAction.cancel,
    'retry' || 'retry_failed' => TaskAction.retry,
    'skip_failed' => TaskAction.skipFailed,
    _ => null,
  };

  static String? _speed(double? bytesPerSecond) {
    if (bytesPerSecond == null) return null;
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  static String? _sourceName(BirdJobStatus job, String? fallback) => _nonEmpty(job.sourceProjectName) ?? _nonEmpty(fallback) ?? _nonEmpty(job.sourceProjectId);

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
