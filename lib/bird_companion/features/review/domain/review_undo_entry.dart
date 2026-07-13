import 'package:aves/bird_companion/core/models/review_models.dart';

class ReviewUndoEntry {
  const ReviewUndoEntry({required this.before, required this.after});
  final UserDecision before;
  final UserDecision after;
}
