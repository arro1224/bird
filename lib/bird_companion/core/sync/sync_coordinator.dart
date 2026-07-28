import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';

class SyncResult {
  const SyncResult({
    required this.syncedCount,
    required this.failedOperations,
    this.remainingOperations = const [],
  });

  final int syncedCount;
  final List<PendingOperation> failedOperations;
  final List<PendingOperation> remainingOperations;

  int get conflictCount => remainingOperations
      .where(
        (operation) => operation.status == PendingOperationStatus.conflict,
      )
      .length;
}

class SyncCoordinator {
  SyncCoordinator(this._store);

  final PendingOperationStore _store;

  PendingOperation? operation(String id) => _store.read(id);

  Future<void> remove(String id) => _store.remove(id);

  Future<SyncResult> synchronize(
    Future<void> Function(PendingOperation operation) submit, {
    bool Function(PendingOperation operation)? canSynchronize,
  }) async {
    var syncedCount = 0;
    final failed = <PendingOperation>[];
    for (final operation in _store.readAll()) {
      if (canSynchronize != null && !canSynchronize(operation)) continue;
      if (operation.status == PendingOperationStatus.conflict) continue;
      try {
        await _store.save(
          operation.copyWith(
            status: PendingOperationStatus.syncing,
            clearFailureReason: true,
          ),
        );
        await submit(operation);
        await _store.remove(operation.id);
        syncedCount++;
      } catch (error) {
        final conflict = error is ApiException && error.statusCode == 409;
        final retried = operation.copyWith(
          retryCount: operation.retryCount + 1,
          status: conflict ? PendingOperationStatus.conflict : PendingOperationStatus.failed,
          failureReason: _failureReason(error),
        );
        await _store.save(retried);
        failed.add(retried);
      }
    }
    final remaining = _store
        .readAll()
        .where(
          (operation) => canSynchronize == null || canSynchronize(operation),
        )
        .toList(growable: false);
    return SyncResult(
      syncedCount: syncedCount,
      failedOperations: failed,
      remainingOperations: remaining,
    );
  }

  String _failureReason(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 409) {
        return '盒子端已有更新，需要选择保留盒子内容或重新确认本机修改。';
      }
      if (error.statusCode != null && error.statusCode! >= 500) {
        return '盒子服务暂时无法处理，重新连接后可再次尝试。';
      }
    }
    return '同步未完成，请检查手机与盒子的连接后重试。';
  }
}
