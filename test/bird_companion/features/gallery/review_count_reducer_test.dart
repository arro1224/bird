import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/review_count_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves confirmed photos between pending, retained and discarded buckets', () {
    const source = GalleryReviewCounts(
      pending: 38,
      kept: 16,
      discarded: 6,
    );

    final updated = applyReviewStateTransitions(source, const [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.pending,
        after: KeepState.keep,
      ),
      ReviewStateTransition(
        fileId: 'photo-2',
        before: KeepState.pending,
        after: KeepState.keep,
      ),
    ]);

    expect(
      updated,
      const GalleryReviewCounts(
        pending: 36,
        kept: 18,
        discarded: 6,
      ),
    );
  });

  test('keep and featured share one retained bucket', () {
    const source = GalleryReviewCounts(
      pending: 4,
      kept: 3,
      discarded: 2,
    );

    final updated = applyReviewStateTransitions(source, const [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.keep,
        after: KeepState.featured,
      ),
      ReviewStateTransition(
        fileId: 'photo-2',
        before: KeepState.featured,
        after: KeepState.keep,
      ),
    ]);

    expect(updated, source);
  });

  test('reverse transitions restore counters', () {
    const source = GalleryReviewCounts(
      pending: 1,
      kept: 1,
      discarded: 0,
    );
    const transition = ReviewStateTransition(
      fileId: 'photo-1',
      before: KeepState.pending,
      after: KeepState.discard,
    );

    final changed = applyReviewStateTransitions(source, const [transition]);
    expect(
      changed,
      const GalleryReviewCounts(
        pending: 0,
        kept: 1,
        discarded: 1,
      ),
    );

    final restored = applyReviewStateTransitions(changed, [transition.reversed()]);
    expect(restored, source);
  });

  test('decrements never become negative for a stale source snapshot', () {
    const source = GalleryReviewCounts(
      pending: 0,
      kept: 1,
      discarded: 0,
    );

    final updated = applyReviewStateTransitions(source, const [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.pending,
        after: KeepState.discard,
      ),
    ]);

    expect(updated.pending, 0);
    expect(updated.discarded, 1);
  });
}
