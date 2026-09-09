import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/album_materialization_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-empty project stays preparing until its first photo is readable', () async {
    final bus = AppDataChangeBus();
    final batches = _BatchRepository(_batch('project-1', totalFiles: 4));
    final photos = _PhotoRepository(
      pages: {'project-1': _page()},
    );
    final cubit = AlbumMaterializationCubit(
      batches,
      photos,
      bus,
      activeDeviceId: () => 'box-1',
      timeout: const Duration(seconds: 1),
      initialRetryDelay: const Duration(milliseconds: 500),
    );
    addTearDown(cubit.close);
    addTearDown(bus.dispose);

    cubit.materialize('project-1');
    await _waitUntil(() => photos.calls['project-1'] == 1);

    expect(cubit.state.preparing, isTrue);
    expect(cubit.state.ready, isFalse);

    photos.pages['project-1'] = _page(items: [_photo('photo-1')]);
    bus.publish(
      {AppDataResource.photos},
      reason: 'first_photo_materialized',
    );
    await _waitUntil(() => cubit.state.ready);

    expect(cubit.state.projectId, 'project-1');
    expect(cubit.state.batch?.totalFiles, 4);
    expect(cubit.state.confirmedEmpty, isFalse);
  });

  test('new focus generation rejects a late result from the old project', () async {
    final bus = AppDataChangeBus();
    final batches = _BatchRepository(_batch('project-1', totalFiles: 1));
    final oldPage = Completer<PhotoPage>();
    final photos = _PhotoRepository(
      pendingPages: {'project-1': oldPage},
      pages: {
        'project-2': _page(items: [_photo('photo-2')]),
      },
    );
    final cubit = AlbumMaterializationCubit(
      batches,
      photos,
      bus,
      activeDeviceId: () => 'box-1',
      timeout: const Duration(seconds: 1),
      initialRetryDelay: const Duration(milliseconds: 5),
    );
    addTearDown(cubit.close);
    addTearDown(bus.dispose);

    cubit.materialize('project-1');
    await _waitUntil(() => photos.calls['project-1'] == 1);
    batches.batch = _batch('project-2', totalFiles: 1);
    cubit.materialize('project-2');
    await _waitUntil(() => cubit.state.ready);

    oldPage.complete(_page(items: [_photo('late-photo')]));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.projectId, 'project-2');
    expect(cubit.state.batch?.id, 'project-2');
  });

  test('an explicitly empty project is allowed to reach the real empty album', () async {
    final bus = AppDataChangeBus();
    final cubit = AlbumMaterializationCubit(
      _BatchRepository(_batch('project-empty', totalFiles: 0)),
      _PhotoRepository(pages: {'project-empty': _page()}),
      bus,
      activeDeviceId: () => 'box-1',
      timeout: const Duration(seconds: 1),
    );
    addTearDown(cubit.close);
    addTearDown(bus.dispose);

    cubit.materialize('project-empty');
    await _waitUntil(() => cubit.state.ready);

    expect(cubit.state.confirmedEmpty, isTrue);
    expect(cubit.state.batch?.totalFiles, 0);
  });

  test('timeout is retryable and a device switch cancels the active focus', () async {
    final bus = AppDataChangeBus();
    final deviceChanges = StreamController<String?>.broadcast();
    var deviceId = 'box-1';
    final batches = _BatchRepository(_batch('project-1', totalFiles: 2));
    final photos = _PhotoRepository(
      pages: {'project-1': _page()},
    );
    final cubit = AlbumMaterializationCubit(
      batches,
      photos,
      bus,
      activeDeviceId: () => deviceId,
      deviceChanges: deviceChanges.stream,
      timeout: const Duration(milliseconds: 20),
      initialRetryDelay: const Duration(milliseconds: 4),
      maximumRetryDelay: const Duration(milliseconds: 8),
    );
    addTearDown(cubit.close);
    addTearDown(deviceChanges.close);
    addTearDown(bus.dispose);

    cubit.materialize('project-1');
    await _waitUntil(() => cubit.state.timedOut);
    photos.pages['project-1'] = _page(items: [_photo('photo-1')]);
    cubit.retry();
    await _waitUntil(() => cubit.state.ready);

    photos.pages['project-1'] = _page();
    cubit.materialize('project-1');
    await _waitUntil(() => cubit.state.preparing);
    deviceId = 'box-2';
    deviceChanges.add(deviceId);
    await _waitUntil(
      () => cubit.state.phase == AlbumMaterializationPhase.idle,
    );

    expect(cubit.state.projectId, isNull);
  });
}

class _BatchRepository implements BatchRepository {
  _BatchRepository(this.batch);

  BatchSummary? batch;

  @override
  Future<BatchSummary?> current() async => batch;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoRepository implements PhotoRepository {
  _PhotoRepository({
    Map<String, PhotoPage>? pages,
    Map<String, Completer<PhotoPage>>? pendingPages,
  }) : pages = pages ?? {},
       pendingPages = pendingPages ?? {};

  final Map<String, PhotoPage> pages;
  final Map<String, Completer<PhotoPage>> pendingPages;
  final Map<String, int> calls = {};

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) {
    calls.update(batchId, (value) => value + 1, ifAbsent: () => 1);
    final pending = pendingPages[batchId];
    if (pending != null) return pending.future;
    return Future.value(pages[batchId] ?? _page());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchSummary _batch(String id, {required int totalFiles}) => BatchSummary(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 9, 7),
  totalFiles: totalFiles,
  analyzedCount: totalFiles,
  reviewCount: totalFiles,
  keepCount: 0,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: 'idle',
);

PhotoSummary _photo(String id) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'jpg',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  version: 1,
);

PhotoPage _page({List<PhotoSummary> items = const []}) => PhotoPage(
  items: items,
  hasMore: false,
  resultComplete: true,
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached in time.');
}
