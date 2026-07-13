import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';

/// Replays locally retained writes when the phone regains a network connection.
/// Each request reuses the operation id as its idempotency key, so a reconnect
/// cannot create a duplicate review or batch action on the box.
class BirdSyncService {
  BirdSyncService(this._connectivity, this._coordinator, this._client);
  final ConnectivityMonitor _connectivity;
  final SyncCoordinator _coordinator;
  final ApiClient _client;
  StreamSubscription<bool>? _subscription;

  void start() {
    _subscription ??= _connectivity.onNetworkChanged.where((online) => online).listen((_) => synchronize());
  }

  Future<SyncResult> synchronize() => _coordinator.synchronize((operation) async {
    switch (operation.type) {
      case PendingOperationType.updateReview:
        final id = operation.payload['file_id']?.toString() ?? '';
        await _client.post(ApiEndpoints.photoDecision.replaceFirst('{fileId}', id), data: operation.payload, idempotencyKey: operation.id);
        return;
      case PendingOperationType.batchReview:
        final batchId = operation.payload['batch_id']?.toString() ?? '';
        await _client.post(ApiEndpoints.batchPhotoOperation.replaceFirst('{batchId}', batchId), data: operation.payload, idempotencyKey: operation.id);
        return;
      case PendingOperationType.controlJob:
      case PendingOperationType.createCopyJob:
        // Existing job/copy flows continue to handle their own queued work.
        return;
    }
  });

  Future<void> dispose() async => _subscription?.cancel();
}
