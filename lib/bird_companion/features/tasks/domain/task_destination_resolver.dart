import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';

enum TaskDestinationKind { detail, album, copyResult }

class TaskDestination {
  const TaskDestination._(this.kind, {this.sourceProjectId});

  const TaskDestination.detail() : this._(TaskDestinationKind.detail);

  const TaskDestination.copyResult() : this._(TaskDestinationKind.copyResult);

  const TaskDestination.album(String sourceProjectId)
    : this._(
        TaskDestinationKind.album,
        sourceProjectId: sourceProjectId,
      );

  final TaskDestinationKind kind;
  final String? sourceProjectId;
}

abstract final class TaskDestinationResolver {
  static TaskDestination resolve(TaskSummary task) {
    if (task.state != TaskRunState.completed) {
      return const TaskDestination.detail();
    }
    return switch (task.type) {
      TaskType.importIndex || TaskType.aiAnalysis => _albumOrDetail(task),
      TaskType.copy => const TaskDestination.copyResult(),
      // The current App has no persisted per-item SyncResult keyed by job ID.
      // Keep the main destination on authoritative task detail until it does.
      TaskType.sync => const TaskDestination.detail(),
    };
  }

  static TaskDestination _albumOrDetail(TaskSummary task) {
    final projectId = task.sourceBatchId?.trim();
    return projectId == null || projectId.isEmpty ? const TaskDestination.detail() : TaskDestination.album(projectId);
  }
}
