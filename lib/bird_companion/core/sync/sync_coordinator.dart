import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';

class SyncResult {
  const SyncResult({required this.syncedCount, required this.failedOperations});

  final int syncedCount;
  final List<PendingOperation> failedOperations;
}

class SyncCoordinator {
  SyncCoordinator(this._store);

  final PendingOperationStore _store;

  Future<SyncResult> synchronize(
    Future<void> Function(PendingOperation operation) submit, {
    bool Function(PendingOperation operation)? canSynchronize,
  }) async {
    var syncedCount = 0;
    final failed = <PendingOperation>[];
    for (final operation in _store.readAll()) {
      if (canSynchronize != null && !canSynchronize(operation)) continue;
      try {
        await submit(operation);
        await _store.remove(operation.id);
        syncedCount++;
      } catch (error) {
        final conflict = error is ApiException && error.statusCode == 409;
        final retried = operation.copyWith(
          retryCount: operation.retryCount + 1,
          status: conflict ? PendingOperationStatus.conflict : PendingOperationStatus.failed,
          failureReason: error.toString(),
        );
        await _store.save(retried);
        failed.add(retried);
      }
    }
    return SyncResult(syncedCount: syncedCount, failedOperations: failed);
  }
}
