import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only confirmed transitions update photos and route-seeded counters', () async {
    final repository = _PhotoRepository([
      _photo('photo-1'),
      _photo('photo-2'),
    ]);
    final cubit = GalleryCubit(repository, 'project-1')
      ..seedReviewCounts(
        pendingCount: 38,
        keepCount: 16,
        discardCount: 6,
      );
    addTearDown(cubit.close);
    await cubit.refresh();

    // photo-2 represents a failed batch item and is deliberately absent.
    cubit.applyReviewTransitions(const [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.pending,
        after: KeepState.keep,
      ),
    ]);

    expect(cubit.state.pendingCount, 37);
    expect(cubit.state.keepCount, 17);
    expect(cubit.state.discardCount, 6);
    expect(_stateOf(cubit, 'photo-1'), 'keep');
    expect(_stateOf(cubit, 'photo-2'), 'pending');
  });

  test('same retained bucket is stable and reverse transitions restore counts', () async {
    final repository = _PhotoRepository([
      _photo('photo-1', keepState: 'keep'),
    ]);
    final cubit = GalleryCubit(repository, 'project-1')
      ..seedReviewCounts(
        pendingCount: 3,
        keepCount: 2,
        discardCount: 1,
      );
    addTearDown(cubit.close);
    await cubit.refresh();

    const retainedTransition = ReviewStateTransition(
      fileId: 'photo-1',
      before: KeepState.keep,
      after: KeepState.featured,
    );
    cubit.applyReviewTransitions(const [retainedTransition]);
    expect(cubit.state.pendingCount, 3);
    expect(cubit.state.keepCount, 2);
    expect(_stateOf(cubit, 'photo-1'), 'featured');

    cubit.applyReviewTransitions([retainedTransition.reversed()]);
    expect(cubit.state.pendingCount, 3);
    expect(cubit.state.keepCount, 2);
    expect(_stateOf(cubit, 'photo-1'), 'keep');

    const pendingTransition = ReviewStateTransition(
      fileId: 'photo-1',
      before: KeepState.keep,
      after: KeepState.pending,
    );
    cubit.applyReviewTransitions(const [pendingTransition]);
    expect(cubit.state.pendingCount, 4);
    expect(cubit.state.keepCount, 1);

    cubit.applyReviewTransitions([pendingTransition.reversed()]);
    expect(cubit.state.pendingCount, 3);
    expect(cubit.state.keepCount, 2);
    expect(_stateOf(cubit, 'photo-1'), 'keep');
  });

  test('aggregate event does not apply the originating gallery delta twice', () async {
    final bus = AppDataChangeBus();
    final repository = _PhotoRepository([_photo('photo-1')]);
    final cubit = GalleryCubit(repository, 'project-1', null, bus)
      ..seedReviewCounts(
        pendingCount: 38,
        keepCount: 16,
        discardCount: 6,
      );
    addTearDown(cubit.close);
    addTearDown(bus.dispose);
    await cubit.refresh();
    const transitions = [
      ReviewStateTransition(
        fileId: 'photo-1',
        before: KeepState.pending,
        after: KeepState.keep,
      ),
    ];

    cubit.applyReviewTransitions(transitions);
    bus.publishChange(
      const BatchReviewDecisionChanged(
        deviceId: 'box-1',
        projectId: 'project-1',
        transitions: transitions,
        queued: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.pendingCount, 37);
    expect(cubit.state.keepCount, 17);
    expect(repository.pageCalls, 1);
  });
}

String? _stateOf(GalleryCubit cubit, String id) => cubit.state.items.firstWhere((photo) => photo.id == id).keepState;

PhotoSummary _photo(String id, {String keepState = 'pending'}) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  keepState: keepState,
  version: 1,
);

class _PhotoRepository implements PhotoRepository {
  _PhotoRepository(this.photos);

  final List<PhotoSummary> photos;
  int pageCalls = 0;

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async {
    pageCalls += 1;
    return PhotoPage(
      items: photos,
      hasMore: false,
      matchedCount: photos.length,
    );
  }

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
