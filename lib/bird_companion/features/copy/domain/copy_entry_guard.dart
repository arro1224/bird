import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';

class CopyEntryDecision {
  const CopyEntryDecision._({required this.enabled, this.batchId, this.reason});

  const CopyEntryDecision.allowed(String batchId) : this._(enabled: true, batchId: batchId);

  const CopyEntryDecision.blocked(String reason) : this._(enabled: false, reason: reason);

  final bool enabled;
  final String? batchId;
  final String? reason;
}

/// Revalidates the album shortcut against the same box-authoritative project
/// and running-job facts used by the task home before copy navigation.
CopyEntryDecision resolveCurrentCopyEntry({
  required String displayedBatchId,
  required BatchSummary? currentProject,
  required Iterable<BirdJobStatus> jobs,
}) {
  final currentId = currentProject?.id.trim();
  if (currentId == null || currentId.isEmpty) {
    return const CopyEntryDecision.blocked('当前没有可复制的批次');
  }
  if (currentId != displayedBatchId.trim()) {
    return const CopyEntryDecision.blocked('当前批次已更新，正在刷新相册，请稍后重试');
  }
  if (currentProject!.totalFiles <= 0) {
    return const CopyEntryDecision.blocked('当前批次没有可复制的照片');
  }

  final pipelineBusy = jobs.any(
    (job) => _blocksNewWork(job) && (job.type == BirdJobType.import || job.type == BirdJobType.analysis || job.type == BirdJobType.copy) && _belongsToProject(job, currentId),
  );
  if (pipelineBusy) {
    return const CopyEntryDecision.blocked('当前批次已有任务正在执行');
  }
  return CopyEntryDecision.allowed(currentId);
}

bool _belongsToProject(BirdJobStatus job, String projectId) {
  final sourceProjectId = job.sourceProjectId?.trim();
  return sourceProjectId == null || sourceProjectId.isEmpty || sourceProjectId == projectId;
}

bool _blocksNewWork(BirdJobStatus job) => switch (job.state) {
  BirdJobState.queued || BirdJobState.idle || BirdJobState.running || BirdJobState.paused || BirdJobState.unknown => true,
  BirdJobState.failed => job.availableActions.any(
    const {'retry', 'retry_failed', 'skip_failed', 'cancel'}.contains,
  ),
  BirdJobState.completed || BirdJobState.cancelled => false,
};
