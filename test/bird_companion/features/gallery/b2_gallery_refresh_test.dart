import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

const _recognized = PhotoQuery(recognitionState: 'recognized');

void main() {
  test('shares an active scan and replays its preview without sharing cancellation', () async {
    final api = _PhotoApi();
    final repository = _repository(api, _Cache(), () => 'box-a');
    final firstToken = PhotoQueryCancellationToken();
    final first = repository.pageWithProgress('trip', _recognized, cancellationToken: firstToken);
    final firstCancelled = expectLater(first, throwsA(isA<PhotoQueryCancelled>()));
    await api.waitForRequests(1);
    api.pages[0].complete(_page(['newest', 'boundary'], next: 'second'));
    await api.waitForRequests(2);

    final replay = Completer<PhotoQueryProgress>();
    final second = repository.pageWithProgress(
      'trip',
      _recognized,
      onProgress: (progress) {
        if (progress.previewItems != null && !replay.isCompleted) replay.complete(progress);
      },
    );
    expect((await replay.future).previewItems!.map((item) => item.id), ['newest']);
    firstToken.cancel();
    await firstCancelled;
    api.pages[1].complete(_page(['oldest'], day: 4));
    final result = await second;

    expect(result.items.map((item) => item.id), ['newest', 'boundary', 'oldest']);
    expect(result.resultComplete, isTrue);
    expect(api.pages, hasLength(2));
    expect((await repository.page('trip', _recognized)).cacheScope, PhotoCacheScope.complete);
    expect(api.pages, hasLength(2));
  });

  test('coalesces recognition and reconnect signals into one follow-up across two galleries', () async {
    final bus = AppDataChangeBus();
    final reconnect = SessionRefreshCoordinator();
    final api = _PhotoApi();
    final repository = _repository(api, _Cache(), () => 'box-a');
    final first = GalleryCubit(repository, 'trip', reconnect, bus, null, null, () => 'box-a');
    final second = GalleryCubit(repository, 'trip', reconnect, bus, null, null, () => 'box-a');
    addTearDown(first.close);
    addTearDown(second.close);
    addTearDown(bus.dispose);
    addTearDown(reconnect.dispose);

    final scans = Future.wait([
      first.refresh(query: _recognized),
      second.refresh(query: _recognized),
    ]);
    await api.waitForRequests(1);
    expect(first.refresh(query: _recognized), same(first.refresh(query: _recognized)));
    api.pages[0].complete(_page(['old', 'boundary'], next: 'second'));
    await api.waitForRequests(2);

    reconnect.requestRefresh();
    reconnect.requestRefresh();
    bus.publishChange(const RecognitionFactsChanged(deviceId: 'box-a', projectId: 'trip', fileIds: {'old'}));
    bus.publishChange(const RecognitionFactsChanged(deviceId: 'box-a', projectId: 'trip', fileIds: {'new'}));
    bus.publishChange(const RecognitionFactsChanged(deviceId: 'box-b', projectId: 'trip', fileIds: {'foreign'}));
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(api.pages, hasLength(2));
    expect(first.state.scannedCount, 2);
    expect(second.state.items.single.id, 'old');

    final updated = Future.wait([
      first.stream.firstWhere((state) => state.resultComplete && state.items.firstOrNull?.id == 'new'),
      second.stream.firstWhere((state) => state.resultComplete && state.items.firstOrNull?.id == 'new'),
    ]);
    api.pages[1].complete(_page(['last'], day: 4));
    await scans;
    await api.waitForRequests(3);
    api.pages[2].complete(_page(['new']));
    await updated;
    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(api.pages, hasLength(3));
  });

  test('late replies after invalidation and a box switch cannot write obsolete pages', () async {
    final api = _PhotoApi();
    final cache = _Cache();
    var device = 'box-a';
    final repository = _repository(api, cache, () => device);
    final old = repository.page('trip', _recognized);
    final oldCancelled = expectLater(old, throwsA(isA<PhotoQueryCancelled>()));
    await api.waitForRequests(1);
    await repository.invalidateLocalQueries('trip');
    await oldCancelled;

    final replaced = repository.page('trip', _recognized);
    final replacedCancelled = expectLater(replaced, throwsA(isA<PhotoQueryCancelled>()));
    await api.waitForRequests(2);
    device = 'box-b';
    final current = repository.page('trip', _recognized);
    await replacedCancelled;
    await api.waitForRequests(3);
    api.pages[2].complete(_page(['current']));
    expect((await current).items.single.id, 'current');
    api.pages[0].complete(_page(['invalidated']));
    api.pages[1].complete(_page(['other-box']));
    await Future<void>.delayed(Duration.zero);
    expect(cache.values.keys, everyElement(contains(':box-b:trip:')));
    expect((await repository.page('trip', _recognized)).items.single.id, 'current');
    expect(api.pages, hasLength(3));
  });

  test('a cancelled filter cannot replace the new filter’s offline candidates', () async {
    final api = _PhotoApi();
    final repository = _repository(api, _Cache(), () => 'box-a');
    final cubit = GalleryCubit(repository, 'trip', null, null, null, null, () => 'box-a');
    addTearDown(cubit.close);
    const unknown = PhotoQuery(recognitionState: 'unknown');

    final old = cubit.refresh(query: _recognized);
    await api.waitForRequests(1);
    final next = cubit.refresh(query: unknown);
    await api.waitForRequests(2);
    api.pages[1].complete(_page(['current'], recognized: false));
    await next;
    api.pages[0].complete(_page(['obsolete'], recognized: false));
    await old;
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.items.single.id, 'current');

    await repository.invalidateLocalQueries('trip');
    final offline = repository.page('trip', unknown);
    await api.waitForRequests(3);
    api.pages[2].completeError(const ApiException(message: 'offline', retryable: true));
    final page = await offline;
    expect(page.items.single.id, 'current');
    expect(page.cacheScope, PhotoCacheScope.partial);
    expect(page.resultComplete, isFalse);
  });
}

PhotoRepositoryImpl _repository(_PhotoApi api, _Cache cache, String Function() device) =>
    PhotoRepositoryImpl(api, _UnusedConnectivity(), PendingOperationStore.memory(), cache, device, device);

PhotoPage _page(List<String> ids, {int day = 10, String? next, bool recognized = true}) => PhotoPage(
  items: [
    for (final (index, id) in ids.indexed)
      PhotoSummary(
        id: id,
        filename: '$id.jpg',
        format: 'jpg',
        preview: const PreviewRef(),
        analysisState: AnalysisState.completed,
        recognition: recognized ? const RecognitionResult(candidates: [SpeciesCandidate(name: '白鹭', confidence: .95)]) : null,
        capturedAt: DateTime.utc(2026, 8, day, 12 - index),
      ),
  ],
  hasMore: next != null,
  nextCursor: next,
);

class _PhotoApi implements PhotoApi {
  final pages = <Completer<PhotoPage>>[];

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery q) {
    final response = Completer<PhotoPage>();
    pages.add(response);
    return response.future;
  }

  Future<void> waitForRequests(int count) async {
    for (var attempts = 0; pages.length < count && attempts < 1500; attempts++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(pages, hasLength(count));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalCache {
  final values = <String, Object?>{};

  @override
  T? read<T>(String key) => values[key] as T?;

  @override
  List<String> keysWithPrefix(String prefix) => values.keys.where((key) => key.startsWith(prefix)).toList();

  @override
  Future<void> write(String key, Object? value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedConnectivity implements ConnectivityMonitor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
