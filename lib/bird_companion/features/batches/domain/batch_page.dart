import 'package:aves/bird_companion/core/models/batch_models.dart';

class BatchPage {
  const BatchPage({required this.items, required this.hasMore, this.nextCursor});
  final List<BatchSummary> items;
  final bool hasMore;
  final String? nextCursor;
}
