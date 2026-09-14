import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:equatable/equatable.dart';

/// The batch-level counters displayed by the gallery quick filters.
class GalleryReviewCounts extends Equatable {
  const GalleryReviewCounts({
    required this.pending,
    required this.kept,
    required this.discarded,
  }) : assert(pending >= 0),
       assert(kept >= 0),
       assert(discarded >= 0);

  final int pending;
  final int kept;
  final int discarded;

  @override
  List<Object> get props => [pending, kept, discarded];
}

/// Applies only confirmed transitions to an existing counter snapshot.
///
/// [KeepState.keep] and [KeepState.featured] share the retained bucket, so a
/// transition between them does not change any counter. Defensive clamping
/// prevents a stale source snapshot from producing negative UI values.
GalleryReviewCounts applyReviewStateTransitions(
  GalleryReviewCounts source,
  Iterable<ReviewStateTransition> transitions,
) {
  var pending = source.pending;
  var kept = source.kept;
  var discarded = source.discarded;

  for (final transition in transitions) {
    final before = _bucketFor(transition.before);
    final after = _bucketFor(transition.after);
    if (before == after) continue;

    switch (before) {
      case _ReviewCountBucket.pending:
        pending = _decrement(pending);
        break;
      case _ReviewCountBucket.kept:
        kept = _decrement(kept);
        break;
      case _ReviewCountBucket.discarded:
        discarded = _decrement(discarded);
        break;
    }
    switch (after) {
      case _ReviewCountBucket.pending:
        pending += 1;
        break;
      case _ReviewCountBucket.kept:
        kept += 1;
        break;
      case _ReviewCountBucket.discarded:
        discarded += 1;
        break;
    }
  }

  return GalleryReviewCounts(
    pending: pending,
    kept: kept,
    discarded: discarded,
  );
}

enum _ReviewCountBucket { pending, kept, discarded }

_ReviewCountBucket _bucketFor(KeepState state) => switch (state) {
  KeepState.pending => _ReviewCountBucket.pending,
  KeepState.keep || KeepState.featured => _ReviewCountBucket.kept,
  KeepState.discard => _ReviewCountBucket.discarded,
};

int _decrement(int value) => value > 0 ? value - 1 : 0;
