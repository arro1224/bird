import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('并发离线写入不会互相覆盖，且同一照片可只保留最新修改', () async {
    final store = PendingOperationStore.memory();
    await Future.wait([
      for (var index = 0; index < 40; index++) store.save(_operation('op-$index', 'photo-$index')),
    ]);

    expect(store.readAll(), hasLength(40));

    final newest = _operation('newest', 'photo-2');
    await store.save(
      newest,
      supersedes: (existing) => existing.deviceId == newest.deviceId && existing.type == PendingOperationType.updateReview && existing.payload['file_id'] == 'photo-2',
    );

    final photoTwo = store.readAll().where((operation) => operation.payload['file_id'] == 'photo-2');
    expect(photoTwo.single.id, 'newest');
    expect(store.readAll(), hasLength(40));
  });

  test('重连只同步原设备并复用操作编号作为幂等键', () async {
    final store = PendingOperationStore.memory();
    await store.save(_operation('device-a-success', 'photo-1'));
    await store.save(
      _operation(
        'device-a-conflict',
        'photo-2',
      ),
    );
    await store.save(
      _operation(
        'device-b-success',
        'photo-3',
        deviceId: 'box-b',
      ),
    );
    final client = _RecordingApiClient(
      conflictKeys: {'device-a-conflict'},
    );
    String? acceptedRemoteFile;
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-a',
      (fileId) async => acceptedRemoteFile = fileId,
    );

    final result = await service.synchronize();

    expect(result.syncedCount, 1);
    expect(result.conflictCount, 1);
    expect(
      client.idempotencyKeys,
      ['device-a-success', 'device-a-conflict'],
    );
    expect(
      store.readAll().where((operation) => operation.deviceId == 'box-b'),
      hasLength(1),
    );
    expect(
      store.read('device-a-conflict')?.status,
      PendingOperationStatus.conflict,
    );
    expect(
      store.read('device-a-conflict')?.projectId,
      'project-shared',
    );
    expect(store.read('device-a-conflict')?.fileId, 'photo-2');
    expect(
      store.read('device-a-conflict')?.failureReason,
      isNot(contains('ApiException')),
    );

    await service.synchronize();
    expect(
      client.idempotencyKeys,
      ['device-a-success', 'device-a-conflict'],
      reason: '冲突操作必须等待用户处理，不能在每次重连时反复提交',
    );

    expect(await service.acceptRemote('device-a-conflict'), isTrue);
    expect(acceptedRemoteFile, 'photo-2');
    expect(store.read('device-a-conflict'), isNull);
  });

  test('401/403 暂停同步且不增加离线重试次数', () async {
    final store = PendingOperationStore.memory();
    await store.save(_operation('auth-first', 'photo-1'));
    await store.save(_operation('auth-second', 'photo-2'));
    var attempts = 0;

    final result = await SyncCoordinator(store).synchronize((_) async {
      attempts++;
      throw const ApiException(
        message: 'authorization expired',
        statusCode: 401,
      );
    });

    expect(attempts, 1);
    expect(result.failedOperations, isEmpty);
    expect(store.read('auth-first')?.status, PendingOperationStatus.pending);
    expect(store.read('auth-first')?.retryCount, 0);
    expect(store.read('auth-second')?.status, PendingOperationStatus.pending);
  });

  test('legacy batch_id is read compatibly but never sent on the wire', () async {
    final store = PendingOperationStore.memory();
    await store.save(
      PendingOperation(
        id: 'legacy-batch-review',
        type: PendingOperationType.batchReview,
        payload: const {
          'batch_id': 'project-7',
          'file_ids': <String>['photo-1', 'photo-2'],
          'operation': 'keep',
          'value': null,
          'version': 3,
        },
        createdAt: DateTime.utc(2026, 8, 1),
        deviceId: 'box-a',
      ),
    );
    final client = _RecordingApiClient();
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-a',
    );

    final result = await service.synchronize();

    expect(result.syncedCount, 1);
    expect(client.paths, ['/api/v1/projects/project-7/files/actions']);
    expect(client.payloads.single, {
      'file_ids': ['photo-1', 'photo-2'],
      'operation': 'keep',
      'value': null,
      'version': 3,
    });
    expect((client.payloads.single as Map).containsKey('batch_id'), isFalse);
  });

  test('batch replay without a version is retained locally and never sent', () async {
    final store = PendingOperationStore.memory();
    await store.save(
      PendingOperation(
        id: 'invalid-batch-review',
        type: PendingOperationType.batchReview,
        payload: const {
          'project_id': 'project-7',
          'file_ids': <String>['photo-1'],
          'operation': 'keep',
          'value': null,
        },
        createdAt: DateTime.utc(2026, 8, 1),
        deviceId: 'box-a',
        projectId: 'project-7',
      ),
    );
    final client = _RecordingApiClient();
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-a',
    );

    final result = await service.synchronize();

    expect(result.syncedCount, 0);
    expect(result.failedOperations, hasLength(1));
    expect(client.paths, isEmpty);
    expect(store.read('invalid-batch-review')?.status, PendingOperationStatus.failed);
  });

  test('all four retained batch states replay with their original wire operation', () async {
    final store = PendingOperationStore.memory();
    const operations = ['pending', 'keep', 'discard', 'featured'];
    for (final operation in operations) {
      await store.save(
        PendingOperation(
          id: 'batch-$operation',
          type: PendingOperationType.batchReview,
          payload: {
            'file_ids': ['photo-$operation'],
            'operation': operation,
            'value': null,
            'version': 1,
          },
          createdAt: DateTime.utc(2026, 8, 16),
          version: 1,
          deviceId: 'box-a',
          projectId: 'project-7',
        ),
      );
    }
    final client = _RecordingApiClient();
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-a',
    );

    final result = await service.synchronize();

    expect(result.syncedCount, 4);
    expect(
      client.payloads.map((payload) => (payload as Map)['operation']),
      operations,
    );
    expect(store.readAll(), isEmpty);
  });

  test('B6 coalesces concurrent reconnect synchronization requests', () async {
    final store = PendingOperationStore.memory();
    await store.save(_operation('coalesced-1', 'photo-1'));
    await store.save(_operation('coalesced-2', 'photo-2'));
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final client = _RecordingApiClient(
      beforePost: (key) async {
        if (key != 'coalesced-1') return;
        if (!firstStarted.isCompleted) firstStarted.complete();
        await releaseFirst.future;
      },
    );
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => 'box-a',
    );

    final first = service.synchronize();
    await firstStarted.future;
    final concurrent = service.synchronize();
    expect(identical(first, concurrent), isTrue);
    releaseFirst.complete();

    final result = await first;
    expect(result.syncedCount, 2);
    expect(client.idempotencyKeys, ['coalesced-1', 'coalesced-2']);
    expect(store.readAll(), isEmpty);
  });

  test('B6 stops replay before a queued write can cross device identity', () async {
    final store = PendingOperationStore.memory();
    await store.save(_operation('device-switch-1', 'photo-1'));
    await store.save(_operation('device-switch-2', 'photo-2'));
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final client = _RecordingApiClient(
      beforePost: (key) async {
        if (key != 'device-switch-1') return;
        if (!firstStarted.isCompleted) firstStarted.complete();
        await releaseFirst.future;
      },
    );
    var activeDeviceId = 'box-a';
    final service = BirdSyncService(
      ConnectivityMonitor(),
      SyncCoordinator(store),
      client,
      null,
      () => activeDeviceId,
    );

    final synchronization = service.synchronize();
    await firstStarted.future;
    activeDeviceId = 'box-b';
    releaseFirst.complete();
    final result = await synchronization;

    expect(result.syncedCount, 1);
    expect(client.idempotencyKeys, ['device-switch-1']);
    expect(store.read('device-switch-1'), isNull);
    expect(store.read('device-switch-2')?.status, PendingOperationStatus.pending);
  });
}

PendingOperation _operation(
  String id,
  String fileId, {
  String deviceId = 'box-a',
}) => PendingOperation(
  id: id,
  type: PendingOperationType.updateReview,
  payload: {
    'file_id': fileId,
    'keep_state': 'keep',
    'version': 1,
  },
  createdAt: DateTime.utc(2026, 7, 28),
  deviceId: deviceId,
  projectId: 'project-shared',
  fileId: fileId,
);

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient({
    this.conflictKeys = const {},
    this.beforePost,
  });

  final Set<String> conflictKeys;
  final Future<void> Function(String key)? beforePost;
  final List<String> idempotencyKeys = [];
  final List<String> paths = [];
  final List<Object?> payloads = [];

  @override
  Uri? get baseUri => Uri.parse('http://127.0.0.1:8080');

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? '';
    idempotencyKeys.add(key);
    paths.add(path);
    payloads.add(data);
    await beforePost?.call(key);
    if (conflictKeys.contains(idempotencyKey)) {
      throw const ApiException(
        message: 'internal conflict detail',
        statusCode: 409,
      );
    }
    return const {};
  }
}
