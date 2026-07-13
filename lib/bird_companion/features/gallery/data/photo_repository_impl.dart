import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class PhotoRepositoryImpl implements PhotoRepository {
  PhotoRepositoryImpl(this._api, this._connectivity, this._pending);
  final PhotoApi _api;
  final ConnectivityMonitor _connectivity;
  final PendingOperationStore _pending;
  @override
  Future<PhotoPage> page(String id, PhotoQuery q) => _api.page(id, q);
  @override
  Future<BatchOperationOutcome> batchOperation(String id, List<String> ids, String action, {Object? value}) async {
    try {
      if (await _connectivity.hasNetwork) return await _api.batchOperation(id, ids, action, value: value);
    } on ApiException {
      // A failed request is retained below and replayed after a reconnect.
    }
    await _pending.save(
      PendingOperation(id: 'batch-$id-${DateTime.now().microsecondsSinceEpoch}', type: PendingOperationType.batchReview, payload: {'batch_id': id, 'file_ids': ids, 'operation': action, 'value': value}, createdAt: DateTime.now()),
    );
    return BatchOperationOutcome(succeededIds: const [], queued: true);
  }
}
