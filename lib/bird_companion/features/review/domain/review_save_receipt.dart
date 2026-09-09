import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';

/// App-only result for callers that need the authoritative photo version
/// returned by the frozen decision POST. The wire contract is unchanged.
class ReviewSaveReceipt {
  const ReviewSaveReceipt({
    this.result = const ReviewSaveResult(),
    this.authoritativeDecision,
    this.authoritativePhoto,
  });

  final ReviewSaveResult result;
  final UserDecision? authoritativeDecision;
  final PhotoSummary? authoritativePhoto;

  bool get queued => result.queued;
  bool get conflict => result.conflict;
  String? get message => result.message;

  factory ReviewSaveReceipt.fromLegacy(ReviewSaveResult result) => ReviewSaveReceipt(result: result);
}

/// Additive capability. Existing ReviewRepository.save callers remain valid.
abstract interface class AuthoritativeReviewWriter {
  Future<ReviewSaveReceipt> saveAuthoritative(
    UserDecision value, {
    String? projectId,
  });
}

/// Receives a frozen PhotoResponse after an offline decision replay succeeds.
abstract interface class SyncedReviewReceiptConsumer {
  Future<void> acceptSyncedPhoto(PhotoSummary photo);
}
