import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';

abstract interface class BatchRepository {
  Future<BatchPage> page({String? state, String? sort, String? cursor});
  Future<BatchSummary?> current();
  Future<BatchOverview> overview();
  Future<void> resume(String batchId);
}
