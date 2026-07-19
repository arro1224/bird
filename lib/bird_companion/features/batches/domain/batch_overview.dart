import 'package:aves/bird_companion/core/models/batch_models.dart';

class BatchOverview {
  const BatchOverview({this.active, this.latest});

  final BatchSummary? active;
  final BatchSummary? latest;

  BatchSummary? get primary => active ?? latest;
  bool get primaryIsActive => active != null;
}
