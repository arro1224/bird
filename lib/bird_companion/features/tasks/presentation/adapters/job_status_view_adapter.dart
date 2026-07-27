import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';

abstract final class JobStatusViewAdapter {
  static TaskSummary? toTaskSummary(
    BirdJobStatus job, {
    String? sourceBatch,
    TaskConnectionState connectionState = TaskConnectionState.connected,
    int remainingMinutes = 0,
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
      remainingMinutes: remainingMinutes,
      state: state,
      sourceBatch: sourceBatch,
      currentFile: job.currentFile,
      speed: _speed(job.speedBytesPerSecond),
      failedCount: job.failedCount,
      failureReason: job.errorMessage ?? job.errorCode,
      connectionState: connectionState,
      availableActions: _actions(state, job.failedCount),
    );
  }

  static TaskType? _type(BirdJobType type) => switch (type) {
    BirdJobType.import => TaskType.importIndex,
    BirdJobType.analysis => TaskType.aiAnalysis,
    BirdJobType.copy => TaskType.copy,
    BirdJobType.sync => TaskType.sync,
    BirdJobType.unknown => null,
  };

  static TaskRunState _state(BirdJobState state) => switch (state) {
    BirdJobState.idle || BirdJobState.unknown => TaskRunState.queued,
    BirdJobState.running => TaskRunState.running,
    BirdJobState.paused => TaskRunState.paused,
    BirdJobState.completed => TaskRunState.completed,
    BirdJobState.failed => TaskRunState.failed,
    BirdJobState.cancelled => TaskRunState.cancelled,
  };

  static Set<TaskAction> _actions(TaskRunState state, int failedCount) => switch (state) {
    TaskRunState.queued => const {TaskAction.cancel, TaskAction.exportLog},
    TaskRunState.running => const {TaskAction.pause, TaskAction.cancel, TaskAction.exportLog},
    TaskRunState.paused => const {TaskAction.resume, TaskAction.cancel, TaskAction.exportLog},
    TaskRunState.failed => {
      TaskAction.retry,
      if (failedCount > 0) TaskAction.skipFailed,
      TaskAction.exportLog,
    },
    TaskRunState.completed || TaskRunState.cancelled => const {TaskAction.exportLog},
  };

  static String? _speed(double? bytesPerSecond) {
    if (bytesPerSecond == null) return null;
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
}
