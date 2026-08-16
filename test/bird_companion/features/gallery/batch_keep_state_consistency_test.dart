import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only succeeded IDs change and survive a failed reconciliation refresh', () async {
    final repository = _ConsistencyPhotoRepository([
      _photo('photo-1'),
      _photo('photo-2'),
    ]);
    final cubit = GalleryCubit(repository, 'project-7');
    addTearDown(cubit.close);
    await cubit.refresh();

    cubit.applyKeepState(const ['photo-1'], KeepState.keep);

    expect(cubit.state.items.firstWhere((photo) => photo.id == 'photo-1').keepState, 'keep');
    expect(cubit.state.items.firstWhere((photo) => photo.id == 'photo-2').keepState, 'pending');

    repository.failReads = true;
    await cubit.refresh();

    expect(cubit.state.items.firstWhere((photo) => photo.id == 'photo-1').keepState, 'keep');
    expect(cubit.state.items.firstWhere((photo) => photo.id == 'photo-2').keepState, 'pending');
    expect(cubit.state.error, isA<StateError>());
  });

  test('a successful state change immediately leaves a mismatched active filter', () async {
    final repository = _ConsistencyPhotoRepository([
      _photo('photo-1'),
      _photo('photo-2'),
    ]);
    final cubit = GalleryCubit(repository, 'project-7');
    addTearDown(cubit.close);
    await cubit.refresh(query: const PhotoQuery(keepState: 'pending'));

    cubit.applyKeepState(const ['photo-1'], KeepState.discard);

    expect(cubit.state.items.map((photo) => photo.id), ['photo-2']);
    expect(cubit.state.matchedCount, 1);
  });

  test('undo can immediately restore the previous keep state', () async {
    final repository = _ConsistencyPhotoRepository([_photo('photo-1')]);
    final cubit = GalleryCubit(repository, 'project-7');
    addTearDown(cubit.close);
    await cubit.refresh();

    cubit.applyKeepState(const ['photo-1'], KeepState.featured);
    expect(cubit.state.items.single.keepState, 'featured');

    cubit.applyKeepState(const ['photo-1'], KeepState.pending);
    expect(cubit.state.items.single.keepState, 'pending');
  });
}

PhotoSummary _photo(String id) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  keepState: 'pending',
  version: 1,
);

class _ConsistencyPhotoRepository implements PhotoRepository {
  _ConsistencyPhotoRepository(this.photos);

  final List<PhotoSummary> photos;
  bool failReads = false;

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async {
    if (failReads) throw StateError('refresh failed');
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
