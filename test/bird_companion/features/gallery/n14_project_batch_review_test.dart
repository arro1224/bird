import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
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
import 'package:aves/bird_companion/features/gallery/domain/photo_version_batch_coordinator.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

const project = 'mock-batch-current';
const ids = ['photo-0001', 'photo-0002', 'photo-0003'];

void main() {
  late _Harness h;
  setUp(() async {
    h = _Harness();
    await h.open();
  });
  tearDown(() => h.close());

  test('mixed photo versions submit one project CAS and cache each real photo version', () async {
    await h.single('photo-0002');
    for (var i = 0; i < 3; i++) {
      await h.single('photo-0003');
    }
    final before = await h.photos.page(project, const PhotoQuery());
    final result = await PhotoVersionBatchCoordinator(h.photos, h.reviews).apply(
      projectId: project,
      fileIds: ids,
      currentPhotos: before.items,
      operation: 'keep',
    );
    expect(result.succeededIds, ids);
    expect(h.client.requests, hasLength(1));
    expect(h.client.requests.single.body['version'], 4);
    expect(result.projectVersion, 5);
    final photos = await Future.wait(ids.map((id) => h.reviews.detail(id)));
    expect(photos.map((detail) => detail.decision!.version), [2, 3, 5]);
    h.offline();
    final cached = await h.photos.page(project, const PhotoQuery());
    expect([for (final id in ids) cached.items.firstWhere((photo) => photo.id == id).version], [2, 3, 5]);
    expect(h.pending.readAll(), isEmpty);
  });

  test('an unrelated single edit advances project CAS without changing selected photo versions', () async {
    await h.photos.readProjectVersion(project);
    await h.single('photo-0004');
    final result = await h.photos.reviewBatch(project, ids, 'discard');
    expect(result.failed, isEmpty);
    expect(h.client.requests.single.body['version'], 1);
    final edited = await h.reviews.detail(ids.first);
    final receipt = await h.reviews.saveAuthoritative(UserDecision(fileId: ids.first, keepState: edited.decision!.keepState, userTags: const ['new tag'], version: edited.decision!.version));
    expect(receipt.result.conflict, false);
    expect(receipt.authoritativeDecision!.version, 3);
  });

  for (final action in ['pending', 'keep', 'discard', 'featured', 'add_tags', 'remove_tags']) {
    test('$action uses the current project version and refreshes authoritative details', () async {
      await h.single('photo-0004');
      final result = await h.photos.reviewBatch(project, ids, action, value: action.endsWith('_tags') ? ['wetland'] : null);
      expect(result.succeededIds, ids);
      expect(result.projectVersion, 2);
      expect(h.client.requests.single.body['version'], 1);
      h.offline();
      for (final id in ids) {
        final detail = await h.reviews.detail(id);
        expect(detail.decision!.version, 2);
        if (!action.endsWith('_tags')) expect(detail.photo.summary.keepState, action);
      }
    });
    test('offline $action persists project scope and replays the original operation', () async {
      await h.photos.readProjectVersion(project);
      h.offline();
      final value = action.endsWith('_tags') ? ['wetland'] : null;
      expect((await h.photos.reviewBatch(project, ids, action, value: value)).queued, true);
      final original = h.pending.readAll().single;
      expect(original.schemaVersion, 2);
      expect(original.versionScope, 'project');
      expect(original.requestSent, false);
      h.online();
      expect((await h.sync.synchronize()).syncedCount, 1);
      expect(h.client.requests.single.key, original.id);
      expect(h.client.requests.single.body, original.payload);
      expect(h.pending.readAll(), isEmpty);
    });
  }

  test('missing project read version fails before any mutation or queue record', () async {
    await h.photos.readProjectVersion(project);
    h.client.stripProjectVersion = true;
    await expectLater(h.photos.reviewBatch(project, ids, 'keep'), throwsA(isA<ProtocolCompatibilityException>()));
    expect(h.client.requests, isEmpty);
    expect(h.pending.readAll(), isEmpty);
  });

  test('lost response survives app restart and replays the identical body and key once', () async {
    h.client.loseResponse = true;
    final result = await h.photos.reviewBatch(project, ids, 'keep');
    expect(result.queued, true);
    final original = h.pending.readAll().single;
    expect(original.isProjectVersionBatch, true);
    expect(original.requestSent, true);
    await h.single('photo-0004'); // A later external change must not rebase a sent request.
    await h.reopenApp();
    final sync = await h.sync.synchronize();
    expect(sync.syncedCount, 1);
    expect(h.client.requests, hasLength(2));
    expect(h.client.requests.last.key, h.client.requests.first.key);
    expect(h.client.requests.last.body, h.client.requests.first.body);
    expect(await h.photos.readProjectVersion(project), 2, reason: 'one batch mutation plus one single mutation');
  });

  test('two unsent offline actions advance only from our acknowledged project CAS', () async {
    await h.photos.readProjectVersion(project);
    h.offline();
    await h.photos.reviewBatch(project, [ids[0]], 'keep');
    await h.photos.reviewBatch(project, [ids[1]], 'discard');
    expect(h.pending.readAll().map((op) => op.version), [0, 0]);
    h.online();
    final result = await h.sync.synchronize();
    expect(result.syncedCount, 2);
    expect(h.pending.readAll(), isEmpty);
    expect(h.client.requests.map((request) => request.body['version']), [0, 1]);
  });

  test('legacy ambiguous queues are retained as conflicts and never POSTed', () async {
    final legacy = PendingOperation(
      id: 'legacy-batch-key',
      type: PendingOperationType.batchReview,
      payload: const {'file_ids': ids, 'operation': 'discard', 'value': null, 'version': 1},
      createdAt: DateTime(2026),
      version: 1,
      deviceId: h.device,
      projectId: project,
    );
    await h.pending.save(legacy);
    final result = await h.sync.synchronize();
    expect(result.conflictCount, 1);
    expect(h.client.requests, isEmpty);
    final retained = h.pending.readAll().single;
    expect(retained.id, legacy.id);
    expect(retained.payload, legacy.payload);
    expect(retained.failureReason, contains('旧版'));
    expect(await h.sync.acceptRemote(legacy.id), true);
    expect((await h.photos.reviewBatch(project, ids, 'discard')).failed, isEmpty);
  });

  test('a genuine project conflict preserves the original intent without retry or rebase', () async {
    h.client.beforeBatch = () => h.single('photo-0004');
    final result = await h.photos.reviewBatch(project, ids, 'keep');
    expect(result.conflict, true);
    expect(result.currentProjectVersion, 1);
    expect(result.failed.keys, ids);
    final retained = h.pending.readAll().single;
    expect(retained.status, PendingOperationStatus.conflict);
    expect(retained.payload['version'], 0);
    await h.sync.synchronize();
    expect(h.client.requests, hasLength(1));
  });

  test('partial success preserves the original request and only failed IDs need confirmation', () async {
    final result = await h.photos.reviewBatch(project, [ids[0], 'missing-photo'], 'add_tags', value: ['new tag']);
    expect(result.succeededIds, [ids[0]]);
    expect(result.failed.keys, ['missing-photo']);
    final retained = h.pending.readAll().single;
    expect(retained.payload['file_ids'], [ids[0], 'missing-photo']);
    expect(retained.remainingFileIds, ['missing-photo']);
    expect(retained.batchReceipt?['version'], 1);
    expect(retained.status, PendingOperationStatus.conflict);
    await h.sync.synchronize();
    expect(h.client.requests, hasLength(1));
    h.offline();
    expect((await h.reviews.detail(ids[0])).decision!.version, 2);
  });

  test('acknowledged writes retry cache reconciliation without another POST', () async {
    await h.photos.page(project, const PhotoQuery());
    h.client.failDetails = true;
    final result = await h.photos.reviewBatch(project, ids, 'keep');
    expect(result.succeededIds, ids);
    expect(result.queued, false);
    expect(h.pending.readAll().single.batchReceipt, isNotNull);
    final keys = h.cache.keysWithPrefix('album:photos:${h.device}:$project:');
    expect(keys, isNotEmpty);
    final cached = keys.expand((key) => (h.cache.read<Map>(key)!['items'] as List).whereType<Map>()).where((photo) => ids.contains(photo['file_id']));
    expect(cached, isNotEmpty);
    expect(cached.map((photo) => photo['version']), everyElement(isNull));
    h.client.failDetails = false;
    final synced = await h.sync.synchronize();
    expect(synced.syncedCount, 1);
    expect(h.client.requests, hasLength(1));
    h.offline();
    expect((await h.reviews.detail(ids[1])).decision!.version, 2);
  });

  test('an invalid response retains the exact sent request for safe replay', () async {
    h.client.stripBatchVersion = true;
    expect((await h.photos.reviewBatch(project, ids, 'keep')).queued, true);
    h.client.stripBatchVersion = false;
    expect((await h.sync.synchronize()).syncedCount, 1);
    expect(h.client.requests.last.body, h.client.requests.first.body);
    expect(h.client.requests.last.key, h.client.requests.first.key);
    expect(await h.photos.readProjectVersion(project), 1);
  });

  test('repairing an older receipt never reapplies its action over a newer confirmed cache', () async {
    await h.photos.page(project, const PhotoQuery());
    h.client.failDetails = true;
    expect((await h.photos.reviewBatch(project, ids, 'keep')).queued, false);
    h.client.failDetails = false;
    expect((await h.photos.reviewBatch(project, ids, 'discard')).failed, isEmpty);
    h.client.failDetails = true;
    await h.sync.synchronize();
    h.offline();
    final page = await h.photos.page(project, const PhotoQuery());
    expect(page.items.where((photo) => ids.contains(photo.id)).map((photo) => photo.keepState), everyElement('discard'));
    expect(h.client.requests, hasLength(2));
    h.online();
    h.client.failDetails = false;
    expect((await h.sync.synchronize()).syncedCount, 1);
    expect(h.client.requests, hasLength(2));
    expect((await h.reviews.detail(ids.first)).photo.summary.keepState, 'discard');
  });

  test('online submission and reconnect synchronization share the same durable operation', () async {
    final gate = Completer<void>();
    h.client.batchGate = gate.future;
    final result = h.photos.reviewBatch(project, ids, 'keep');
    await _until(() => h.client.requests.isNotEmpty);
    final sync = h.sync.synchronize();
    gate.complete();
    expect((await result).succeededIds, ids);
    await sync;
    expect(h.client.requests, hasLength(1));
    expect(h.pending.readAll(), isEmpty);
  });

  test('switching devices during the project read prevents a write to the next box', () async {
    h.client.afterProjectRead = () {
      h.device = 'box-b';
    };
    await expectLater(h.photos.reviewBatch(project, ids, 'keep'), throwsStateError);
    expect(h.client.requests, isEmpty);
    expect(h.pending.readAll(), isEmpty);
  });

  test('sync starting while an online receipt is saved cannot overwrite that receipt', () async {
    final savingReceipt = Completer<void>(), releaseReceipt = Completer<void>();
    h.client.failDetails = true;
    h.cache.beforeWrite = (key, value) async {
      if (value is List && value.whereType<Map>().any((item) => item['batch_receipt'] is Map)) {
        h.cache.beforeWrite = null;
        savingReceipt.complete();
        await releaseReceipt.future;
      }
    };
    final online = h.photos.reviewBatch(project, ids, 'keep');
    await savingReceipt.future;
    final syncing = h.sync.synchronize();
    await Future<void>.delayed(Duration.zero);
    releaseReceipt.complete();
    expect((await online).succeededIds, ids);
    await syncing;
    expect(h.pending.readAll().single.batchReceipt, isNotNull);
    expect(h.client.requests, hasLength(1));
    h.client.failDetails = false;
    expect((await h.sync.synchronize()).syncedCount, 1);
    expect(h.client.requests, hasLength(1));
  });

  test('mock rejects photo CAS, changed parameters under one key, and duplicate mutations', () async {
    final api = PhotoApi(h.client);
    await expectLater(api.batchOperation(project, ids, 'keep', version: 1), throwsA(isA<ApiException>().having((error) => error.statusCode, 'status', 409)));
    final first = await api.batchOperation(project, ids, 'keep', version: 0, idempotencyKey: 'n14-fixed-action');
    final replay = await api.batchOperation(project, ids, 'keep', version: 0, idempotencyKey: 'n14-fixed-action');
    expect(replay.projectVersion, first.projectVersion);
    await expectLater(api.batchOperation(project, ids, 'discard', version: 0, idempotencyKey: 'n14-fixed-action'), throwsA(isA<ApiException>().having((error) => error.code, 'code', 'IDEMPOTENCY_CONFLICT')));
    expect(await api.projectVersion(project), 1);
  });

  test('historical project version is read from existing project pagination', () async {
    expect(await h.photos.readProjectVersion('mock-batch-history-01'), 0);
    expect(h.client.requests, isEmpty);
  });

  test('partial failure can adopt box state even when the failed photo no longer exists', () async {
    await h.photos.reviewBatch(project, [ids[0], 'missing-photo'], 'keep');
    final op = h.pending.readAll().single;
    expect(await h.sync.acceptRemote(op.id), true);
    expect(h.pending.readAll(), isEmpty);
    expect(h.client.requests, hasLength(1));
  });

  test('batch diagnostics retain version scope and counts without the tag payload', () async {
    final records = <Map<String, dynamic>>[];
    h.client.httpDiagnostics.record = records.add;
    await h.photos.reviewBatch(project, ids, 'add_tags', value: ['private-tag-value']);
    final row = records.singleWhere((row) => row['event'] == 'batch_review_confirmed');
    expect(row['project_version_sent'], 0);
    expect(row['returned_project_version'], 1);
    expect(row['version_scope'], 'project');
    expect(row['succeeded_count'], 3);
    expect(jsonEncode(records), isNot(contains('private-tag-value')));
  });

  test('mock project CAS and identical batch replay survive a process restart', () async {
    final directory = await Directory('build/f25-b2-20261125').create(recursive: true);
    final state = File('${directory.path}/mock-state-${DateTime.now().microsecondsSinceEpoch}.json');
    var server = MockBoxServer(photoCount: 8, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: state);
    var client = ApiClient();
    addTearDown(() async {
      await client.dispose();
      await server.close();
    });
    client.configure(await server.start());
    final first = await PhotoApi(client).batchOperation(project, ids, 'keep', version: 0, idempotencyKey: 'n14-restart-key');
    await client.dispose();
    await server.close();
    server = MockBoxServer(photoCount: 8, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: state);
    client = ApiClient()..configure(await server.start());
    final replay = await PhotoApi(client).batchOperation(project, ids, 'keep', version: 0, idempotencyKey: 'n14-restart-key');
    expect(replay.projectVersion, first.projectVersion);
    expect(await PhotoApi(client).projectVersion(project), 1);
    expect((await ReviewApi(client).detail(ids.first)).decision!.version, 2);
  });
}

Future<void> _until(bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed > const Duration(seconds: 3)) fail('test operation did not start');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Harness {
  final server = MockBoxServer(photoCount: 8, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false);
  final client = _Client();
  final cache = _Cache();
  final network = _Network();
  String device = 'box-a';
  late PendingOperationStore pending;
  late PhotoRepositoryImpl photos;
  late ReviewRepositoryImpl reviews;
  late BirdSyncService sync;

  Future<void> open() async {
    client.configure(await server.start());
    _assemble();
  }

  void _assemble() {
    pending = PendingOperationStore(cache);
    reviews = ReviewRepositoryImpl(ReviewApi(client), network, pending, cache, () => device, () => device);
    photos = PhotoRepositoryImpl(PhotoApi(client), network, pending, cache, () => device, () => device, reviews.invalidateBatchVersions);
    sync = BirdSyncService(network, SyncCoordinator(pending), client, null, () => device, null, null, photos.replayBatchReview, photos.acceptRemoteBatch);
  }

  Future<void> reopenApp() async {
    await sync.dispose();
    await pending.dispose();
    _assemble();
  }

  void offline() {
    network.online = false;
    client.offline = true;
  }

  void online() {
    network.online = true;
    client.offline = false;
  }

  Future<void> single(String id) async {
    final detail = await reviews.detail(id);
    await reviews.save(UserDecision(fileId: id, keepState: KeepState.keep, userTags: [...detail.userTags, 'edit-${detail.decision!.version}'], version: detail.decision!.version));
  }

  Future<void> close() async {
    await sync.dispose();
    await pending.dispose();
    await client.dispose();
    await server.close();
  }
}

class _Network extends ConnectivityMonitor {
  bool online = true;
  @override
  Future<bool> get hasNetwork async => online;
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
}

class _Client extends ApiClient {
  bool offline = false, loseResponse = false, stripProjectVersion = false, stripBatchVersion = false, failDetails = false;
  Future<void> Function()? beforeBatch;
  void Function()? afterProjectRead;
  Future<void>? batchGate;
  final requests = <({Map<String, dynamic> body, String? key})>[];
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    if (offline || failDetails && path.startsWith('/api/v1/files/')) throw const ApiException(message: 'test offline', retryable: true);
    final response = await super.get(path, queryParameters: queryParameters, headers: headers);
    if (path == '/api/v1/projects/current') {
      afterProjectRead?.call();
      if (stripProjectVersion) {
        return {
          ...response,
          'batch': {...Map<String, dynamic>.from(response['batch'] as Map)}..remove('version'),
        };
      }
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) async {
    if (offline) throw const ApiException(message: 'test offline', retryable: true);
    if (!path.endsWith('/files/actions')) return super.post(path, data: data, idempotencyKey: idempotencyKey, headers: headers);
    requests.add((body: Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map), key: idempotencyKey));
    final before = beforeBatch;
    beforeBatch = null;
    await before?.call();
    await batchGate;
    final response = await super.post(path, data: data, idempotencyKey: idempotencyKey, headers: headers);
    if (loseResponse) {
      loseResponse = false;
      throw const ApiException(message: 'test response lost', retryable: true);
    }
    return stripBatchVersion ? ({...response}..remove('version')) : response;
  }
}

class _Cache implements LocalCache {
  final values = <String, Object?>{};
  Future<void> Function(String key, Object? value)? beforeWrite;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    await beforeWrite?.call(key, value);
    values[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  List<String> keysWithPrefix(String prefix) => values.keys.where((key) => key.startsWith(prefix)).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
