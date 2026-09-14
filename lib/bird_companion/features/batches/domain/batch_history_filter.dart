import 'package:aves/bird_companion/core/models/batch_models.dart';

/// The user-selectable filters on the past-shoots page.
enum BatchHistoryFilter { all, inProgress, review, failed }

/// A normalized App-side view of a project lifecycle state.
enum BatchHistoryCategory { inProgress, review, failed, completed, unknown }

BatchHistoryFilter batchHistoryFilterFromValue(String? value) => switch (_normalize(value)) {
  'in_progress' => BatchHistoryFilter.inProgress,
  'review' => BatchHistoryFilter.review,
  'failed' => BatchHistoryFilter.failed,
  _ => BatchHistoryFilter.all,
};

String? batchHistoryFilterValue(BatchHistoryFilter filter) => switch (filter) {
  BatchHistoryFilter.all => null,
  BatchHistoryFilter.inProgress => 'in_progress',
  BatchHistoryFilter.review => 'review',
  BatchHistoryFilter.failed => 'failed',
};

BatchHistoryCategory classifyBatchHistory(BatchSummary batch) {
  final projectState = _normalize(batch.state);
  final copyState = _normalize(batch.copyState);

  if (_failedStates.contains(projectState) || _failedStates.contains(copyState)) {
    return BatchHistoryCategory.failed;
  }
  if (_inProgressStates.contains(projectState) || _inProgressCopyStates.contains(copyState)) {
    return BatchHistoryCategory.inProgress;
  }
  if (_reviewStates.contains(projectState)) {
    return BatchHistoryCategory.review;
  }
  if (_completedStates.contains(projectState)) {
    return BatchHistoryCategory.completed;
  }

  // Older boxes may omit the project state. Pending review totals remain a
  // safe fallback after failed and running states have been excluded above.
  if (batch.pendingReviewCount > 0) {
    return BatchHistoryCategory.review;
  }
  if (_completedCopyStates.contains(copyState)) {
    return BatchHistoryCategory.completed;
  }
  return BatchHistoryCategory.unknown;
}

bool matchesBatchHistoryFilter(
  BatchSummary batch,
  BatchHistoryFilter filter,
) => switch (filter) {
  BatchHistoryFilter.all => true,
  BatchHistoryFilter.inProgress => classifyBatchHistory(batch) == BatchHistoryCategory.inProgress,
  BatchHistoryFilter.review => classifyBatchHistory(batch) == BatchHistoryCategory.review,
  BatchHistoryFilter.failed => classifyBatchHistory(batch) == BatchHistoryCategory.failed,
};

const _failedStates = {
  'failed',
  'error',
  'errored',
};

const _inProgressStates = {
  'created',
  'scanning',
  'importing',
  'analyzing',
  'processing',
  'running',
  'resuming',
};

const _inProgressCopyStates = {
  'running',
};

const _reviewStates = {
  'ready_to_review',
  'review',
  'pending_review',
};

const _completedStates = {
  'completed',
  'complete',
  'copied',
  'success',
  'succeeded',
  'archived',
};

const _completedCopyStates = {
  'completed',
  'copied',
  'success',
  'succeeded',
};

String _normalize(String? value) => value?.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_') ?? '';
