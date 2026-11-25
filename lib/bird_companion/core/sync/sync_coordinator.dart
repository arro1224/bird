import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';

class BatchTagSyncFailure implements Exception {
  const BatchTagSyncFailure(this.failed);

  final Map<String, String> failed;
}

class PendingOperationConflict implements Exception {
  const PendingOperationConflict(this.message);
  final String message;
}

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
    bool Function()? canContinue,
  }) async {
    var syncedCount = 0;
    final failed = <PendingOperation>[];
    for (final snapshot in _store.readAll()) {
      final operation = _store.read(snapshot.id);
      if (operation == null) continue;
      if (canSynchronize != null && !canSynchronize(operation)) continue;
      if (canContinue != null && !canContinue()) break;
      if (operation.status == PendingOperationStatus.conflict) continue;
      try {
        // Batch replay shares a project lock with online submissions and reads
        // the latest record inside that lock. Saving this pre-lock snapshot
        // could overwrite an online acknowledgement still being persisted.
        if (operation.type != PendingOperationType.batchReview) {
          await _store.save(
            operation.copyWith(
              status: PendingOperationStatus.syncing,
              clearFailureReason: true,
            ),
          );
        }
        await submit(operation);
        await _store.remove(operation.id);
        syncedCount++;
      } on BatchTagSyncFailure catch (error) {
        final retryCount = operation.retryCount + 1;
        final retry = (_store.read(operation.id) ?? operation).copyWith(
          retryCount: retryCount,
          status: PendingOperationStatus.conflict,
          failureReason: '${error.failed.length} 张照片的标签未同步，请核对后重新确认：${error.failed.values.toSet().join('、')}',
        );
        await _store.save(retry);
        failed.add(retry);
      } catch (error) {
        final authenticationRequired = error is ApiException && (error.statusCode == 401 || error.statusCode == 403);
        if (authenticationRequired) {
          await _store.save(
            (_store.read(operation.id) ?? operation).copyWith(
              status: PendingOperationStatus.pending,
              clearFailureReason: true,
            ),
          );
          break;
        }
        final conflict = error is PendingOperationConflict || error is ApiException && error.statusCode == 409;
        // Submission may have durably saved an acknowledgement or marked the
        // request sent. Never overwrite it with the pre-submit snapshot.
        final retained = _store.read(operation.id) ?? operation;
        final retried = retained.copyWith(
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
    if (error is PendingOperationConflict) return error.message;
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
