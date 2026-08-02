import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/foundation.dart';

abstract final class JobStatusViewAdapter {
  static ValueChanged<BirdJobState>? legacyStateReporter;

  static TaskSummary? toTaskSummary(
    BirdJobStatus job, {
    String? sourceBatch,
    TaskConnectionState connectionState = TaskConnectionState.connected,
    int? remainingMinutes,
  }) {
    final type = _type(job.type);
    if (type == null) return null;
    final state = _state(job.state);
    final rawProgress = job.progress <= 1 ? job.progress * 100 : job.progress;
    final progressPercent = rawProgress.round().clamp(0, 100);
    return TaskSummary(
      id: job.id,
      type: type,
      title: type.label,
      processed: job.finishedCount,
      total: job.totalCount,
      progressPercent: progressPercent,
      remainingMinutes: remainingMinutes ?? ((job.estimatedRemainingSeconds ?? 0) / 60).ceil(),
      state: state,
      sourceBatch: sourceBatch,
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
      availableActions: _actions(job, state),
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

  static Set<TaskAction> _actions(
    BirdJobStatus job,
    TaskRunState state,
  ) {
    if (job.availableActions.isNotEmpty) {
      return job.availableActions.map(_action).whereType<TaskAction>().toSet();
    }
    return switch (state) {
      TaskRunState.queued => const {TaskAction.cancel, TaskAction.exportLog},
      TaskRunState.running => const {TaskAction.pause, TaskAction.cancel, TaskAction.exportLog},
      TaskRunState.paused => const {TaskAction.resume, TaskAction.cancel, TaskAction.exportLog},
      TaskRunState.failed => {
        TaskAction.retry,
        if (job.failedCount > 0) TaskAction.skipFailed,
        TaskAction.exportLog,
      },
      TaskRunState.completed || TaskRunState.cancelled => const {TaskAction.exportLog},
    };
  }

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
}
