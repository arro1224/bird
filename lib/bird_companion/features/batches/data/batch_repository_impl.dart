import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';

class BatchRepositoryImpl implements BatchRepository {
  BatchRepositoryImpl(this._api);
  final BatchApi _api;
  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) => _api.page(state: state, sort: sort, cursor: cursor);
  @override
  Future<BatchSummary?> current() => _api.current();
  @override
  Future<void> resume(String batchId) => _api.resume(batchId);
}
