import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';

class ReviewDetail {
  const ReviewDetail({required this.photo, this.decision, this.history = const []});
  final PhotoDetail photo;
  final UserDecision? decision;
  final List<VersionHistory> history;
}

class ReviewSaveResult {
  const ReviewSaveResult({this.queued = false, this.conflict = false, this.message});
  final bool queued;
  final bool conflict;
  final String? message;
}

abstract interface class ReviewRepository {
  Future<List<BirdGroup>> groups(String batchId);
  Future<ReviewDetail> detail(String fileId);
  Future<ReviewSaveResult> save(UserDecision value);
}
