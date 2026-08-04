import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('album view cache is isolated by device namespace and project id', () {
    expect(
      albumViewCacheKey(
        deviceNamespace: 'box-a',
        projectId: 'project-7',
      ),
      'album:view:box-a:project-7',
    );
    expect(
      albumViewCacheKey(
        deviceNamespace: 'box-b',
        projectId: 'project-7',
      ),
      isNot('album:view:box-a:project-7'),
    );
  });

  test('gallery only counts pending reviews for its device and project', () async {
    final pending = PendingOperationStore.memory();
    await pending.save(
      _reviewOperation(
        'matching',
        deviceId: 'box-a',
        projectId: 'project-7',
      ),
    );
    await pending.save(
      _reviewOperation(
        'other-project',
        deviceId: 'box-a',
        projectId: 'project-8',
      ),
    );
    await pending.save(
      _reviewOperation(
        'other-device',
        deviceId: 'box-b',
        projectId: 'project-7',
      ),
    );
    final cubit = GalleryCubit(
      _EmptyPhotoRepository(),
      'project-7',
      null,
      null,
      null,
      pending,
      () => 'box-a',
    );
    addTearDown(cubit.close);

    await cubit.refresh();

    expect(cubit.state.pendingOperationCount, 1);
    expect(cubit.state.conflictOperationCount, 0);
  });

  test('gallery exposes the first conflicted photo for direct handling', () async {
    final pending = PendingOperationStore.memory();
    await pending.save(
      _reviewOperation(
        'single-conflict',
        deviceId: 'box-a',
        projectId: 'project-7',
        fileId: 'photo-conflict-1',
        status: PendingOperationStatus.conflict,
      ),
    );
    await pending.save(
      PendingOperation(
        id: 'batch-conflict',
        type: PendingOperationType.batchReview,
        payload: const {
          'project_id': 'project-7',
          'file_ids': ['photo-conflict-2', 'photo-conflict-3'],
        },
        createdAt: DateTime.utc(2026, 7, 29),
        deviceId: 'box-a',
        projectId: 'project-7',
        status: PendingOperationStatus.conflict,
      ),
    );
    final cubit = GalleryCubit(
      _EmptyPhotoRepository(),
      'project-7',
      null,
      null,
      null,
      pending,
      () => 'box-a',
    );
    addTearDown(cubit.close);

    await cubit.refresh();

    expect(cubit.state.conflictOperationCount, 2);
    expect(cubit.state.firstConflictFileId, 'photo-conflict-1');
    expect(
      cubit.state.conflictFileIds,
      ['photo-conflict-1', 'photo-conflict-2', 'photo-conflict-3'],
    );
  });

  test('persisted display preferences drive the real gallery query and grid', () async {
    final bus = AppDataChangeBus();
    final store = _MemorySettingsStore(
      const BirdSettingsSnapshot(
        gridColumns: 5,
        showRatingOverlay: false,
        sortOrder: 'oldest',
        birdPhotosOnly: true,
        defaultPhotoFilter: 'pendingReview',
      ),
    );
    final cubit = GalleryCubit(
      _EmptyPhotoRepository(),
      'project-7',
      null,
      bus,
      null,
      null,
      null,
      null,
      store,
    );
    addTearDown(cubit.close);
    addTearDown(bus.dispose);

    await cubit.restoreAndRefresh(const PhotoQuery());

    expect(cubit.state.gridColumns, 5);
    expect(cubit.state.showRatingOverlay, isFalse);
    expect(cubit.state.query.sort, 'captured_at_asc');
    expect(cubit.state.query.keepState, 'pending');
    expect(cubit.state.query.recognitionState, 'recognized');

    store.snapshot = const BirdSettingsSnapshot(
      gridColumns: 4,
      showRatingOverlay: true,
      sortOrder: 'newest',
      birdPhotosOnly: false,
    );
    final updated = cubit.stream.firstWhere(
      (state) => state.gridColumns == 4 && state.showRatingOverlay && state.query.sort == 'captured_at_desc' && !state.loading,
    );
    bus.publish(
      {AppDataResource.photoPreferences},
      reason: 'test',
    );
    await updated;
  });
}

PendingOperation _reviewOperation(
  String id, {
  required String deviceId,
  required String projectId,
  String fileId = 'photo-1',
  PendingOperationStatus status = PendingOperationStatus.pending,
}) => PendingOperation(
  id: id,
  type: PendingOperationType.updateReview,
  payload: const {'keep_state': 'keep', 'version': 1},
  createdAt: DateTime.utc(2026, 7, 29),
  version: 1,
  deviceId: deviceId,
  projectId: projectId,
  fileId: fileId,
  status: status,
);

class _EmptyPhotoRepository implements PhotoRepository {
  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async => const PhotoPage(items: [], hasMore: false);

  @override
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    Object? value,
  }) async => const BatchOperationOutcome(succeededIds: []);

  @override
  Future<List<SceneSummary>> scenes(String batchId) async => const [];

  @override
  Future<List<SpeciesCandidate>> searchSpecies(String query) async => const [];
}

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore(this.snapshot);

  BirdSettingsSnapshot snapshot;

  @override
  BirdSettingsSnapshot read() => snapshot;

  @override
  Future<void> write(BirdSettingsSnapshot value) async {
    snapshot = value;
  }
}
