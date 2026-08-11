import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
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
  Future<SyncResult>? _synchronizing;
  bool _synchronizeAgain = false;

  void start() {
    _subscription ??= _connectivity.onNetworkChanged.where((online) => online).listen((_) => synchronize());
  }

  Future<SyncResult> synchronize() {
    final inFlight = _synchronizing;
    if (inFlight != null) {
      _synchronizeAgain = true;
      return inFlight;
    }
    late final Future<SyncResult> request;
    request = _drainSynchronizationRequests().whenComplete(() {
      if (identical(_synchronizing, request)) _synchronizing = null;
    });
    _synchronizing = request;
    return request;
  }

  Future<SyncResult> _drainSynchronizationRequests() async {
    var syncedCount = 0;
    final failedById = <String, PendingOperation>{};
    var remaining = const <PendingOperation>[];
    do {
      _synchronizeAgain = false;
      final result = await _synchronizeOnce();
      syncedCount += result.syncedCount;
      for (final operation in result.failedOperations) {
        failedById[operation.id] = operation;
      }
      remaining = result.remainingOperations;
    } while (_synchronizeAgain);
    return SyncResult(
      syncedCount: syncedCount,
      failedOperations: failedById.values.toList(growable: false),
      remainingOperations: remaining,
    );
  }

  Future<SyncResult> _synchronizeOnce() async {
    final activeDeviceId = _deviceId()?.trim();
    final activeBaseUri = _client.baseUri;
    if (activeDeviceId == null || activeDeviceId.isEmpty || activeBaseUri == null) {
      return const SyncResult(
        syncedCount: 0,
        failedOperations: [],
      );
    }
    final result = await _coordinator.synchronize(
      (operation) async {
        switch (operation.type) {
          case PendingOperationType.updateReview:
            final id = operation.fileId ?? operation.payload['file_id']?.toString() ?? '';
            if (id.trim().isEmpty) {
              throw StateError('Offline review is missing file_id.');
            }
            await _client.post(
              ApiEndpoints.photoDecision.replaceFirst('{fileId}', id),
              data: _decisionPayload(operation.payload),
              idempotencyKey: operation.id,
            );
            return;
          case PendingOperationType.batchReview:
            final projectId = (operation.projectId ?? operation.payload['project_id']?.toString() ?? operation.payload['batch_id']?.toString() ?? '').trim();
            if (projectId.isEmpty) {
              throw StateError('Offline batch review is missing project_id.');
            }
            await _client.post(
              ApiEndpoints.batchPhotoOperation.replaceFirst('{batchId}', projectId),
              data: _batchPayload(operation.payload),
              idempotencyKey: operation.id,
            );
            return;
          case PendingOperationType.controlJob:
          case PendingOperationType.createCopyJob:
            // These operations are intentionally not queued by the current UI.
            // Never acknowledge an unexpected record, otherwise SyncCoordinator
            // would remove it even though the box did not receive the operation.
            throw StateError('任务控制与复制创建不支持离线重放。');
        }
      },
      canSynchronize: (operation) => operation.deviceId == activeDeviceId,
      canContinue: () => _deviceId()?.trim() == activeDeviceId && _client.baseUri == activeBaseUri,
    );
    if (result.syncedCount > 0 || result.failedOperations.isNotEmpty) {
      _dataChanges?.publish(
        {AppDataResource.photos, AppDataResource.batches, AppDataResource.sync},
        reason: 'offline_changes_synced',
      );
    }
    return result;
  }

  int _requireVersion(Map<String, dynamic> payload) {
    final version = ProtocolValidation.optionalNonNegativeInt(
      payload,
      'version',
    );
    if (version == null) {
      throw const ProtocolCompatibilityException('version', '不能为空');
    }
    return version;
  }

  Map<String, dynamic> _decisionPayload(Map<String, dynamic> source) {
    final payload = <String, dynamic>{
      for (final key in _decisionWireFields)
        if (source.containsKey(key)) key: source[key],
      'version': _requireVersion(source),
    };
    if (!payload.keys.any((key) => key != 'version')) {
      throw const ProtocolCompatibilityException(
        'decision',
        '至少包含一个待修改字段',
      );
    }
    return payload;
  }

  Map<String, dynamic> _batchPayload(Map<String, dynamic> source) {
    final ids = (source['file_ids'] as List? ?? const <Object>[]).map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toSet().toList(growable: false);
    if (ids.isEmpty) {
      throw const ProtocolCompatibilityException('file_ids', '不能为空');
    }
    final operation = source['operation'];
    if (operation is! String || !_batchOperations.contains(operation)) {
      throw const ProtocolCompatibilityException(
        'operation',
        '必须是 birdbox-v1 定义的批量操作',
      );
    }
    return <String, dynamic>{
      'file_ids': ids,
      'operation': operation,
      if (source.containsKey('value')) 'value': source['value'],
      'version': _requireVersion(source),
    };
  }

  Future<bool> acceptRemote(String operationId) async {
    final activeDeviceId = _deviceId()?.trim();
    final operation = _coordinator.operation(operationId);
    if (operation == null || operation.status != PendingOperationStatus.conflict || activeDeviceId == null || activeDeviceId.isEmpty || operation.deviceId != activeDeviceId) {
      return false;
    }
    final fileId = operation.fileId?.trim() ?? operation.payload['file_id']?.toString().trim();
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

const _decisionWireFields = <String>{
  'keep_state',
  'user_score',
  'user_species_id',
  'user_species',
  'user_tags',
};

const _batchOperations = <String>{
  'pending',
  'keep',
  'discard',
  'featured',
  'add_tags',
  'remove_tags',
};
