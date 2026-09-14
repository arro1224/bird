import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_history_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch history filter values', () {
    test('maps the existing UI values without changing the API vocabulary', () {
      expect(batchHistoryFilterFromValue(null), BatchHistoryFilter.all);
      expect(batchHistoryFilterFromValue('in_progress'), BatchHistoryFilter.inProgress);
      expect(batchHistoryFilterFromValue('review'), BatchHistoryFilter.review);
      expect(batchHistoryFilterFromValue('failed'), BatchHistoryFilter.failed);
      expect(batchHistoryFilterValue(BatchHistoryFilter.all), isNull);
      expect(batchHistoryFilterValue(BatchHistoryFilter.inProgress), 'in_progress');
      expect(batchHistoryFilterValue(BatchHistoryFilter.review), 'review');
      expect(batchHistoryFilterValue(BatchHistoryFilter.failed), 'failed');
    });
  });

  group('batch history classification', () {
    test('uses failure before running and review fallbacks', () {
      expect(
        classifyBatchHistory(
          _batch(
            state: 'processing',
            copyState: 'failed',
            pending: 8,
          ),
        ),
        BatchHistoryCategory.failed,
      );
    });

    test('normalizes project lifecycle aliases', () {
      expect(
        classifyBatchHistory(_batch(state: 'Ready-To-Review', pending: 8)),
        BatchHistoryCategory.review,
      );
      expect(
        classifyBatchHistory(_batch(state: ' analyzing ', pending: 8)),
        BatchHistoryCategory.inProgress,
      );
      expect(
        classifyBatchHistory(_batch(state: 'completed')),
        BatchHistoryCategory.completed,
      );
    });

    test('uses pending totals only as an old-box fallback', () {
      expect(
        classifyBatchHistory(_batch(pending: 8)),
        BatchHistoryCategory.review,
      );
      expect(
        classifyBatchHistory(_batch(copyState: 'running', pending: 8)),
        BatchHistoryCategory.inProgress,
      );
    });

    test('keeps unknown records distinct from completed records', () {
      expect(
        classifyBatchHistory(_batch()),
        BatchHistoryCategory.unknown,
      );
      expect(
        classifyBatchHistory(_batch(copyState: 'success')),
        BatchHistoryCategory.completed,
      );
    });

    test('matches all four selectable filters', () {
      final running = _batch(state: 'importing');
      final review = _batch(state: 'ready_to_review', pending: 12);
      final failed = _batch(state: 'failed');
      final completed = _batch(state: 'completed');

      expect(
        [running, review, failed, completed].where(
          (batch) => matchesBatchHistoryFilter(batch, BatchHistoryFilter.all),
        ),
        hasLength(4),
      );
      expect(matchesBatchHistoryFilter(running, BatchHistoryFilter.inProgress), isTrue);
      expect(matchesBatchHistoryFilter(review, BatchHistoryFilter.review), isTrue);
      expect(matchesBatchHistoryFilter(failed, BatchHistoryFilter.failed), isTrue);
      expect(matchesBatchHistoryFilter(completed, BatchHistoryFilter.review), isFalse);
    });
  });
}

BatchSummary _batch({
  String? state,
  String copyState = 'unknown',
  int pending = 0,
}) => BatchSummary(
  id: 'project-${state ?? copyState}-$pending',
  name: '测试拍摄记录',
  createdAt: DateTime.utc(2026, 9, 14),
  totalFiles: 20,
  analyzedCount: 20,
  reviewCount: pending,
  keepCount: 20 - pending,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: copyState,
  state: state,
);
