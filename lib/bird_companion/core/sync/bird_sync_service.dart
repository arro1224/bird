import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';

/// Replays locally retained writes when the phone regains a network connection.
/// Each request reuses the operation id as its idempotency key, so a reconnect
/// cannot create a duplicate review or batch action on the box.
class BirdSyncService {
  BirdSyncService(
    this._connectivity,
    this._coordinator,
    this._client, [
    this._dataChanges,
    String? Function()? deviceId,
    this._acceptRemoteReview,
  ]) : _deviceId = deviceId ?? (() => null);
  final ConnectivityMonitor _connectivity;
  final SyncCoordinator _coordinator;
  final ApiClient _client;
  final AppDataChangeBus? _dataChanges;
  final String? Function() _deviceId;
  final Future<void> Function(String fileId)? _acceptRemoteReview;
  StreamSubscription<bool>? _subscription;

  void start() {
    _subscription ??= _connectivity.onNetworkChanged.where((online) => online).listen((_) => synchronize());
  }

  Future<SyncResult> synchronize() async {
    final activeDeviceId = _deviceId()?.trim();
    if (activeDeviceId == null || activeDeviceId.isEmpty || _client.baseUri == null) {
      return const SyncResult(
        syncedCount: 0,
        failedOperations: [],
      );
    }
    final result = await _coordinator.synchronize((operation) async {
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
          // These operations are intentionally not queued by the current UI.
          // Never acknowledge an unexpected record, otherwise SyncCoordinator
          // would remove it even though the box did not receive the operation.
          throw StateError('任务控制与复制创建不支持离线重放。');
      }
    }, canSynchronize: (operation) => operation.deviceId == activeDeviceId);
    if (result.syncedCount > 0 || result.failedOperations.isNotEmpty) {
      _dataChanges?.publish(
        {AppDataResource.photos, AppDataResource.batches, AppDataResource.sync},
        reason: 'offline_changes_synced',
      );
    }
    return result;
  }

  Future<bool> acceptRemote(String operationId) async {
    final activeDeviceId = _deviceId()?.trim();
    final operation = _coordinator.operation(operationId);
    if (operation == null || operation.status != PendingOperationStatus.conflict || activeDeviceId == null || activeDeviceId.isEmpty || operation.deviceId != activeDeviceId) {
      return false;
    }
    final fileId = operation.payload['file_id']?.toString().trim();
    if (operation.type == PendingOperationType.updateReview && fileId != null && fileId.isNotEmpty && _acceptRemoteReview != null) {
      try {
        await _acceptRemoteReview(fileId);
      } catch (_) {
        return false;
      }
    }
    await _coordinator.remove(operationId);
    _dataChanges?.publish(
      {AppDataResource.photos, AppDataResource.batches, AppDataResource.sync},
      reason: 'offline_conflict_remote_accepted',
    );
    return true;
  }

  Future<void> dispose() async => _subscription?.cancel();
}
