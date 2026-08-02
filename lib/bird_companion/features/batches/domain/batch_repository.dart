import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';

abstract interface class BatchRepository {
  Future<BatchSummary> create(ProjectCreateRequest request);
  Future<BatchPage> page({String? state, String? sort, String? cursor});
  Future<BatchSummary?> current();
  Future<BatchOverview> overview();
  Future<void> resume(String batchId);
}
