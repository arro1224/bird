import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('部分成功、重试和撤销期间相册与拍摄记录计数始终一致', () async {
    final bus = AppDataChangeBus();
    final gallery =
        GalleryCubit(
          _PhotoRepository([
            _photo('photo-1'),
            _photo('photo-2'),
          ]),
          'project-1',
          null,
          bus,
        )..seedReviewCounts(
          pendingCount: 38,
          keepCount: 16,
          discardCount: 6,
        );
    final batches = BatchListCubit(
      _BatchRepository(_batch(pending: 38, kept: 16, discarded: 6)),
      null,
      bus,
      const Duration(hours: 1),
    );
    addTearDown(gallery.close);
    addTearDown(batches.close);
    addTearDown(bus.dispose);
    await gallery.refresh();
    await batches.load();

    // Two photos were attempted, but only photo-1 succeeded initially.
    const firstSuccess = [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.pending,
        after: KeepState.keep,
      ),
    ];
    _applyAndPublish(gallery, bus, firstSuccess);
    await Future<void>.delayed(Duration.zero);

    _expectCounts(gallery, batches, pending: 37, kept: 17, discarded: 6);
    expect(_keepState(gallery, 'photo-1'), 'keep');
    expect(_keepState(gallery, 'photo-2'), 'pending');

    // Retrying the failed photo succeeds with a different target bucket.
    const retrySuccess = [
      ReviewStateTransition(
        fileId: 'photo-2',
        before: KeepState.pending,
        after: KeepState.discard,
      ),
    ];
    _applyAndPublish(gallery, bus, retrySuccess);
    await Future<void>.delayed(Duration.zero);

    _expectCounts(gallery, batches, pending: 36, kept: 17, discarded: 7);
    expect(_keepState(gallery, 'photo-2'), 'discard');

    final undo = [
      firstSuccess.single.reversed(),
      retrySuccess.single.reversed(),
    ];
    _applyAndPublish(gallery, bus, undo);
    await Future<void>.delayed(Duration.zero);

    _expectCounts(gallery, batches, pending: 38, kept: 16, discarded: 6);
    expect(_keepState(gallery, 'photo-1'), 'pending');
    expect(_keepState(gallery, 'photo-2'), 'pending');
  });
}

void _applyAndPublish(
  GalleryCubit gallery,
  AppDataChangeBus bus,
  List<ReviewStateTransition> transitions,
) {
  gallery.applyReviewTransitions(transitions);
  bus.publishChange(
    BatchReviewDecisionChanged(
      deviceId: 'box-1',
      projectId: 'project-1',
      transitions: transitions,
      queued: false,
    ),
  );
}

void _expectCounts(
  GalleryCubit gallery,
  BatchListCubit batches, {
  required int pending,
  required int kept,
  required int discarded,
}) {
  expect(gallery.state.pendingCount, pending);
  expect(gallery.state.keepCount, kept);
  expect(gallery.state.discardCount, discarded);
  expect(batches.state.current?.pendingReviewCount, pending);
  expect(batches.state.current?.keepCount, kept);
  expect(batches.state.current?.discardCount, discarded);
  expect(batches.state.items.single, batches.state.current);
}

String? _keepState(GalleryCubit gallery, String id) => gallery.state.items.singleWhere((photo) => photo.id == id).keepState;

PhotoSummary _photo(String id) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  keepState: 'pending',
  version: 1,
);

BatchSummary _batch({
  required int pending,
  required int kept,
  required int discarded,
}) => BatchSummary(
  id: 'project-1',
  name: '测试拍摄记录',
  createdAt: DateTime.utc(2026, 9, 14),
  totalFiles: pending + kept + discarded,
  analyzedCount: pending + kept + discarded,
  reviewCount: pending,
  keepCount: kept,
  discardCount: discarded,
  pendingCopyCount: 0,
  copyState: 'idle',
  state: 'ready_to_review',
);

class _PhotoRepository implements PhotoRepository {
  _PhotoRepository(this.photos);

  final List<PhotoSummary> photos;

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async => PhotoPage(
    items: photos,
    hasMore: false,
    matchedCount: photos.length,
  );

  @override
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
  }) async => BatchOperationOutcome(succeededIds: ids);

  @override
  Future<List<SceneSummary>> scenes(String batchId) async => const [];

  @override
  Future<List<SpeciesCandidate>> searchSpecies(String query) async => const [];
}

class _BatchRepository implements BatchRepository {
  _BatchRepository(this.batch);

  final BatchSummary batch;

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async => BatchPage(items: [batch], hasMore: false);

  @override
  Future<BatchSummary?> current() async => batch;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
