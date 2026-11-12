import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  test('离线批量标签重连后仅确认成功的照片，并只重试失败的照片', () async {
    final server = MockBoxServer(photoCount: 12, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false);
    final client = _SwitchableClient()..configure(await server.start());
    addTearDown(server.close);
    final connectivity = _Online();
    final pending = PendingOperationStore.memory();
    addTearDown(pending.dispose);
    final cache = _MemoryCache();
    String deviceId() => 'box-1';
    final photos = PhotoRepositoryImpl(PhotoApi(client), connectivity, pending, cache, deviceId, deviceId);
    final reviews = ReviewRepositoryImpl(ReviewApi(client), connectivity, pending, cache, deviceId, deviceId);
    final sync = BirdSyncService(connectivity, SyncCoordinator(pending), client, null, deviceId, null, null, photos.acceptSyncedBatchTags);
    addTearDown(sync.dispose);
    const batch = 'mock-batch-current';
    const first = 'photo-0001';
    const second = 'photo-0002';
    const tag = '离线新增标签';
    await photos.page(batch, const PhotoQuery());
    final beforeFirst = await reviews.detail(first);
    final beforeSecond = await reviews.detail(second);
    final version = beforeFirst.decision!.version!;
    expect(beforeSecond.decision!.version, version);

    connectivity.online = false;
    client.disconnected = true;
    final queued = await photos.batchOperation(batch, [first, second], 'add_tags', version: version, value: [tag]);
    expect(queued.queued, isTrue);
    expect(client.batchRequests, isEmpty);
    expect((await reviews.detail(first)).userTags, beforeFirst.userTags);
    expect((await photos.page(batch, const PhotoQuery())).items.firstWhere((photo) => photo.id == first).userTags, beforeFirst.userTags);

    connectivity.online = true;
    client.disconnected = false;
    client.rejectPhoto = second;
    final firstSync = await sync.synchronize();
    expect(firstSync.failedOperations.single.status, PendingOperationStatus.failed);
    expect(firstSync.remainingOperations.single.payload['file_ids'], [second]);
    expect(client.batchRequests.single.ids, [first, second]);

    client.disconnected = true;
    expect((await reviews.detail(first)).userTags, [...beforeFirst.userTags, tag]);
    expect((await reviews.detail(second)).userTags, beforeSecond.userTags);
    final cachedPage = await photos.page(batch, const PhotoQuery());
    expect(cachedPage.items.firstWhere((photo) => photo.id == first).userTags, [...beforeFirst.userTags, tag]);
    expect(cachedPage.items.firstWhere((photo) => photo.id == second).userTags, beforeSecond.userTags);

    client.disconnected = false;
    client.rejectPhoto = null;
    final retry = await sync.synchronize();
    expect(retry.syncedCount, 1);
    expect(retry.remainingOperations, isEmpty);
    expect(client.batchRequests.last.ids, [second]);
    expect(client.batchRequests.last.key, isNot(client.batchRequests.first.key));
    final afterFirst = await reviews.detail(first);
    final afterSecond = await reviews.detail(second);
    expect(afterFirst.userTags, [...beforeFirst.userTags, tag]);
    expect(afterFirst.decision!.version, version + 1);
    expect(afterSecond.userTags, [...beforeSecond.userTags, tag]);
    expect(afterSecond.decision!.version, version + 1);
  });

  for (final saveFirst in [false, true]) {
    test('batch tags survive detail/edit/save and removal (previous save: $saveFirst)', () async {
      final server = MockBoxServer(
        photoCount: 12,
        assetDirectory: Directory('tool/mock_box_server/assets'),
        logRequests: false,
      );
      final uri = await server.start();
      addTearDown(server.close);
      final client = ApiClient()..configure(uri);
      final pending = PendingOperationStore.memory();
      addTearDown(pending.dispose);
      final repository = ReviewRepositoryImpl(
        ReviewApi(client),
        _Online(),
        pending,
        _MemoryCache(),
        () => 'box-1',
        () => 'box-1',
      );
      final before = await repository.detail('photo-0001');
      if (saveFirst) {
        await repository.save(
          UserDecision(
            fileId: 'photo-0001',
            keepState: KeepState.keep,
            userTags: before.decision!.userTags,
            version: before.decision!.version,
          ),
        );
      }
      final original = (await repository.detail('photo-0001')).decision!;
      final untouched = await repository.detail('photo-0002');
      final api = PhotoApi(client);
      final added = await api.batchOperation('mock-batch-current', ['photo-0001'], 'add_tags', version: original.version!, value: ['水鸟']);
      expect(added.succeededIds, ['photo-0001']);
      final detail = await repository.detail('photo-0001');
      expect(detail.decision!.userTags, [...original.userTags, '水鸟']);
      expect(detail.photo.summary.userTags, detail.decision!.userTags);
      expect(detail.decision!.version, original.version! + 1);
      expect((await repository.detail('photo-0002')).decision, untouched.decision);

      // Saving another field from the editor must not erase the batch tag.
      await repository.save(
        UserDecision(
          fileId: 'photo-0001',
          keepState: KeepState.featured,
          userTags: detail.decision!.userTags,
          version: detail.decision!.version,
        ),
      );
      final saved = await repository.detail('photo-0001');
      expect(saved.decision!.userTags, contains('水鸟'));
      final removed = await api.batchOperation('mock-batch-current', ['photo-0001'], 'remove_tags', version: saved.decision!.version!, value: ['水鸟']);
      expect(removed.succeededIds, ['photo-0001']);
      final after = await repository.detail('photo-0001');
      expect(after.decision!.userTags, original.userTags);
      expect(after.photo.summary.userTags, original.userTags);
      expect(after.decision!.keepState, KeepState.featured);
    });
  }
}

class _Online extends ConnectivityMonitor {
  bool online = true;

  @override
  Future<bool> get hasNetwork async => online;
}

class _SwitchableClient extends ApiClient {
  bool disconnected = false;
  String? rejectPhoto;
  final batchRequests = <({List<String> ids, String? key})>[];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    if (disconnected) throw const ApiException(message: 'offline', retryable: true);
    return super.get(path, queryParameters: queryParameters, headers: headers);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) async {
    final payload = data as Map<String, dynamic>;
    final ids = (payload['file_ids'] as List).cast<String>();
    batchRequests.add((ids: ids, key: idempotencyKey));
    final rejected = rejectPhoto;
    if (rejected == null || !ids.contains(rejected)) {
      return super.post(path, data: data, idempotencyKey: idempotencyKey, headers: headers);
    }
    final response = await super.post(
      path,
      data: {...payload, 'file_ids': ids.where((id) => id != rejected).toList()},
      idempotencyKey: idempotencyKey,
      headers: headers,
    );
    return {
      ...response,
      'failed': [
        {'file_id': rejected, 'reason': '暂时无法写入'},
      ],
    };
  }
}

class _MemoryCache implements LocalCache {
  final _values = <String, Object?>{};
  @override
  T? read<T>(String key) => _values[key] as T?;
  @override
  List<String> keysWithPrefix(String prefix) => _values.keys.where((key) => key.startsWith(prefix)).toList();
  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
