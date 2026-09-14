import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('batch summary preserves project lifecycle fields through cache JSON', () {
    final source = BatchSummary.fromJson(const {
      'project_id': 'project-1',
      'name': '崇明东滩',
      'state': 'ready_to_review',
      'active_job_id': 'job-analysis-1',
      'created_at': '2026-09-14T06:00:00Z',
      'total_files': 60,
      'analyzed_count': 60,
      'pending_review_count': 38,
      'keep_count': 16,
      'discard_count': 6,
      'pending_copy_count': 16,
      'copy_state': 'pending',
    });

    expect(source.state, 'ready_to_review');
    expect(source.activeJobId, 'job-analysis-1');

    final restored = BatchSummary.fromJson(source.toJson());
    expect(restored, source);
    expect(restored.state, 'ready_to_review');
    expect(restored.activeJobId, 'job-analysis-1');

    final updated = source.copyWith(reviewCount: 36, keepCount: 18);
    expect(updated.state, 'ready_to_review');
    expect(updated.activeJobId, 'job-analysis-1');
  });

  test('blank optional lifecycle fields normalize to null', () {
    final batch = BatchSummary.fromJson(const {
      'project_id': 'project-1',
      'name': '崇明东滩',
      'state': '  ',
      'active_job_id': '',
      'created_at': '2026-09-14T06:00:00Z',
      'total_files': 0,
      'analyzed_count': 0,
      'pending_review_count': 0,
      'keep_count': 0,
      'discard_count': 0,
      'pending_copy_count': 0,
      'copy_state': 'unknown',
    });

    expect(batch.state, isNull);
    expect(batch.activeJobId, isNull);
    expect(batch.toJson(), isNot(contains('state')));
    expect(batch.toJson(), isNot(contains('active_job_id')));
  });
}
