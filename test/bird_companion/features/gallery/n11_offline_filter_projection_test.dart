import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/models/photo_models.dart';
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
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Cache cache;
  late PendingOperationStore pending;
  late _Network network;
  late _Api api;
  late PhotoRepositoryImpl repo;
  var device = 'box-a';
  setUp(() async {
    cache = _Cache();
    pending = PendingOperationStore(cache);
    network = _Network();
    api = _Api();
    device = 'box-a';
    repo = PhotoRepositoryImpl(api, network, pending, cache, () => device, () => device);
    await cache.write('album:photos:box-a:trip:page_size=60', {
      'items': [for (var i = 0; i < 3; i++) _photo('p$i').toJson()],
      'has_more': true,
      'cached_at': '2026-11-25T12:00:00Z',
    });
  });
  tearDown(() => pending.dispose());

  test('45 ordinary retained plus 2 featured stay 47 across refresh, filtering and offline cache', () async {
    final facts = [
      for (var i = 0; i < 48; i++)
        PhotoSummary.fromJson({
          ..._photo('p$i').toJson(),
          'keep_state': i < 45
              ? 'keep'
              : i < 47
              ? 'featured'
              : 'discard',
        }),
    ];
    await cache.write('album:photos:box-a:trip:page_size=60', {'items': facts.map((p) => p.toJson()).toList(), 'has_more': false});
    const retained = PhotoQuery(keepState: 'keep');
    final offline = repo.cachedPage('trip', retained)!;
    expect(offline.items, hasLength(47));
    expect(offline.cachedCounts!.kept, 47);
    expect(offline.resultComplete, false);
    expect(repo.cachedPage('trip', const PhotoQuery(keepState: 'featured'))!.items, hasLength(2));
    expect(repo.cachedPage('trip', const PhotoQuery(keepState: 'discard'))!.items, hasLength(1));
    network.online = true;
    api.gate = Completer<PhotoPage>()..complete(PhotoPage(items: facts, hasMore: false));
    final online = await repo.page('trip', retained);
    expect(online.items, hasLength(47));
    expect(online.resultComplete, true);
    final cubit = GalleryCubit(repo, 'trip', null, null, cache, pending, () => device);
    addTearDown(cubit.close);
    cubit.seedReviewCounts(keepCount: 47);
    await cubit.refresh(query: retained);
    expect(cubit.state.keepCount, 47);
    network.online = false;
    await cubit.refresh(query: retained);
    expect(cubit.state.keepCount, 47);
    expect(cubit.state.items, hasLength(47));
    expect(cubit.state.countsFromLocalCache, true);
  });

  Future<void> save(Map<String, dynamic> payload, {String id = 'draft', String target = 'p0', String box = 'box-a', String project = 'trip', PendingOperationStatus status = PendingOperationStatus.pending}) => pending.save(
    PendingOperation(
      id: id,
      type: PendingOperationType.updateReview,
      payload: {'version': 1, ...payload},
      version: 1,
      deviceId: box,
      projectId: project,
      fileId: target,
      status: status,
      createdAt: DateTime(2026, 11, 25),
    ),
  );

  test('empty cached categories reproject immediately after an offline save, without HTTP', () async {
    for (final state in ['keep', 'discard', 'featured']) {
      await cache.write('album:photos:box-a:trip:keep_state=$state', {'items': [], 'has_more': false});
      expect((await repo.page('trip', PhotoQuery(keepState: state))).items, isEmpty);
    }
    await save({'keep_state': 'keep'});
    final cubit = GalleryCubit(repo, 'trip', null, null, cache, pending, () => device);
    addTearDown(cubit.close);
    final loading = cubit.refresh(query: const PhotoQuery(keepState: 'keep'));
    expect(cubit.state.items.map((p) => p.id), ['p0']);
    expect(cubit.state.query.keepState, 'keep');
    expect(cubit.state.keepCount, 1);
    expect(cubit.state.countsFromLocalCache, true);
    await loading;
    for (final state in ['discard', 'featured']) {
      final next = cubit.refresh(query: PhotoQuery(keepState: state));
      expect(cubit.state.items, isEmpty);
      await next;
    }
    expect(api.requests, 0);
    expect(pending.readAll().single.payload['version'], 1);
  });

  test('search debounce never labels old rows as new query results', () async {
    final cubit = GalleryCubit(repo, 'trip', null, null, cache, pending, () => device);
    addTearDown(cubit.close);
    await cubit.refresh();
    expect(cubit.state.items, hasLength(3));
    cubit.search('absent');
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.query.search, 'absent');
  });

  test('an authenticated local session still reads HTTP when the OS transport hint is false', () async {
    final connected = PhotoRepositoryImpl(api, network, pending, cache, () => device, () => device, null, () => true);
    api.gate = Completer<PhotoPage>()..complete(PhotoPage(items: [_photo('live')], hasMore: false));
    expect((await connected.page('trip', const PhotoQuery())).items.single.id, 'live');
    expect(api.requests, 1);
  });

  test('a disconnected session uses cache immediately even if the OS network hint is true', () async {
    network.online = true;
    final disconnected = PhotoRepositoryImpl(api, network, pending, cache, () => device, () => device, null, () => false);
    expect((await disconnected.page('trip', const PhotoQuery())).items, hasLength(3));
    expect(api.requests, 0);
  });

  test('a query with no cache clears previous rows before a slow request', () async {
    final cubit = GalleryCubit(repo, 'trip', null, null, cache, pending, () => device);
    addTearDown(cubit.close);
    await cubit.refresh();
    cache.values.clear();
    network.online = true;
    api.gate = Completer<PhotoPage>();
    final request = cubit.refresh(query: const PhotoQuery(keepState: 'discard'));
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.loading, true);
    api.gate!.complete(const PhotoPage(items: [], hasMore: false));
    await request;
    expect(cubit.state.items, isEmpty);
  });

  test('projection is scoped to device and project and ignores conflict intents', () async {
    await save({'keep_state': 'keep'}, id: 'foreign-box', box: 'box-b');
    await save({'keep_state': 'keep'}, id: 'foreign-project', project: 'other');
    await save({'keep_state': 'keep'}, id: 'conflict', status: PendingOperationStatus.conflict);
    expect(repo.cachedPage('trip', const PhotoQuery(keepState: 'keep'))!.items, isEmpty);
    device = 'box-b';
    expect(repo.cachedPage('trip', const PhotoQuery()), isNull);
  });

  for (final action in ['keep', 'discard', 'pending', 'featured', 'add_tags', 'remove_tags']) {
    test('pending $action is projected before filtering without copying project CAS to photos', () async {
      if (action == 'remove_tags') {
        await cache.write('album:photos:box-a:trip:page_size=60', {
          'items': [
            {
              ..._photo('p0').toJson(),
              'user_tags': ['wetland'],
            },
            _photo('p1').toJson(),
            _photo('p2').toJson(),
          ],
          'has_more': true,
        });
      }
      await pending.save(
        PendingOperation(
          id: action,
          type: PendingOperationType.batchReview,
          payload: {
            'file_ids': const ['p0'],
            'operation': action,
            'value': const ['wetland'],
            'version': 17,
          },
          version: 17,
          schemaVersion: 2,
          versionScope: 'project',
          deviceId: device,
          projectId: 'trip',
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      final query = action.endsWith('_tags') ? const PhotoQuery(tags: ['wetland']) : PhotoQuery(keepState: action);
      final result = repo.cachedPage('trip', query)!;
      final expected = action == 'remove_tags'
          ? <String>[]
          : action == 'pending'
          ? ['p0', 'p1', 'p2']
          : ['p0'];
      expect(result.items.map((p) => p.id), expected);
      expect(result.items.map((p) => p.version), everyElement(1));
      expect(cache.read<Map>('album:photos:box-a:trip:page_size=60')!['items'][0]['keep_state'], 'pending');
    });
  }

  test('cache pagination is local, stable, and keeps partial counts honest', () async {
    final cubit = GalleryCubit(repo, 'trip', null, null, cache, pending, () => device);
    addTearDown(cubit.close);
    await cubit.refresh(query: const PhotoQuery(pageSize: 1));
    expect(cubit.state.query.cursor, startsWith('cache-v1-'));
    await cubit.loadMore();
    await cubit.loadMore();
    expect(cubit.state.items.map((p) => p.id), ['p0', 'p1', 'p2']);
    expect(cubit.state.hasMore, false);
    expect(cubit.state.resultComplete, false);
    expect(cubit.state.cacheScope, PhotoCacheScope.partial);
    expect(cubit.state.scannedCount, 3);
    expect(api.requests, 0);
  });

  test('newer photo detail and serialized pending intent beat an old query page after restart', () async {
    await cache.write('album:detail:box-a:p0', {
      'file': {
        ..._photo('p0').toJson(),
        'version': 4,
        'user_tags': ['new'],
      },
    });
    await save({
      'keep_state': 'keep',
      'user_tags': ['new', 'wetland'],
    });
    final reopened = PendingOperationStore(cache);
    addTearDown(reopened.dispose);
    final restored = PhotoRepositoryImpl(api, network, reopened, cache, () => device, () => device);
    final page = restored.cachedPage('trip', const PhotoQuery(keepState: 'keep', tags: ['wetland']))!;
    expect(page.items.single.id, 'p0');
    expect(page.items.single.version, 4);
  });

  test('an old acknowledged batch receipt is never projected as a new intent', () async {
    await pending.save(
      PendingOperation(
        id: 'receipt',
        type: PendingOperationType.batchReview,
        payload: const {
          'file_ids': ['p0'],
          'operation': 'discard',
          'version': 8,
        },
        version: 8,
        schemaVersion: 2,
        versionScope: 'project',
        batchReceipt: const {
          'version': 9,
          'succeeded_ids': ['p0'],
          'failed': [],
        },
        deviceId: device,
        projectId: 'trip',
        createdAt: DateTime(2026, 11, 25),
      ),
    );
    expect(repo.cachedPage('trip', const PhotoQuery(keepState: 'discard'))!.items, isEmpty);
  });

  test('real offline single save survives empty query caches and reconnect writes once', () async {
    final server = MockBoxServer(photoCount: 8, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false);
    final client = _Client()..configure(await server.start());
    addTearDown(server.close);
    addTearDown(client.dispose);
    network.online = true;
    final photos = PhotoRepositoryImpl(PhotoApi(client), network, pending, cache, () => device, () => device);
    final reviews = ReviewRepositoryImpl(ReviewApi(client), network, pending, cache, () => device, () => device);
    const project = 'mock-batch-current';
    await photos.page(project, const PhotoQuery());
    const filter = PhotoQuery(keepState: 'keep', tags: ['n11-new']);
    expect((await photos.page(project, filter)).items, isEmpty);
    final before = await reviews.detail('photo-0001');
    network.online = false;
    client.offline = true;
    expect(
      (await reviews.save(
        UserDecision(fileId: 'photo-0001', keepState: KeepState.keep, userTags: [...before.userTags, 'n11-new'], version: before.decision!.version),
        projectId: project,
      )).queued,
      true,
    );
    expect((await photos.page(project, filter)).items.single.id, 'photo-0001');
    network.online = true;
    client.offline = false;
    final sync = BirdSyncService(network, SyncCoordinator(pending), client, null, () => device, null, reviews.acceptSyncedPhoto, photos.replayBatchReview, photos.acceptRemoteBatch);
    addTearDown(sync.dispose);
    expect((await sync.synchronize()).syncedCount, 1);
    await sync.synchronize();
    expect(client.decisionWrites, 1);
    expect(pending.readAll(), isEmpty);
    expect((await photos.page(project, filter)).items.single.id, 'photo-0001');
  });
}

PhotoSummary _photo(String id) => PhotoSummary(id: id, filename: '$id.jpg', format: 'jpg', preview: const PreviewRef(), analysisState: AnalysisState.completed, keepState: 'pending', version: 1);

class _Cache implements LocalCache {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
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

class _Network extends ConnectivityMonitor {
  bool online = false;
  @override
  Future<bool> get hasNetwork async => online;
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
}

class _Api implements PhotoApi {
  int requests = 0;
  Completer<PhotoPage>? gate;
  @override
  Future<PhotoPage> page(String id, PhotoQuery query) {
    requests++;
    return gate?.future ?? Future.error(const ApiException(message: 'offline', retryable: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends ApiClient {
  bool offline = false;
  int decisionWrites = 0;
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) {
    if (offline) throw const ApiException(message: 'offline', retryable: true);
    return super.get(path, queryParameters: queryParameters, headers: headers);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) {
    if (offline) throw const ApiException(message: 'offline', retryable: true);
    if (path.endsWith('/decision')) decisionWrites++;
    return super.post(path, data: data, idempotencyKey: idempotencyKey, headers: headers);
  }
}
