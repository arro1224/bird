import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('全新打开批次照片主页时忽略本地保存的旧筛选', () {
    final query = resolveInitialPhotoQuery(
      fallback: const PhotoQuery(),
      savedView: const {
        'search': '白鹭',
        'min_score': 4,
        'keep_state': 'pending',
      },
      restoreSavedView: false,
    );

    expect(query.search, isNull);
    expect(query.minScore, isNull);
    expect(query.keepState, isNull);
    expect(query.activeLabels, isEmpty);
  });

  test('慢筛选响应不会覆盖较新的筛选结果', () async {
    final repository = _ControlledPhotoRepository();
    final cubit = GalleryCubit(repository, 'batch-1');
    addTearDown(cubit.close);

    final oldRequest = cubit.refresh(
      query: const PhotoQuery(search: '旧结果'),
    );
    await Future<void>.delayed(Duration.zero);
    final newRequest = cubit.refresh(
      query: const PhotoQuery(search: '新结果'),
    );
    await Future<void>.delayed(Duration.zero);

    repository.complete(
      '新结果',
      PhotoPage(
        items: [_photo('new')],
        hasMore: false,
      ),
    );
    await newRequest;
    repository.complete(
      '旧结果',
      PhotoPage(
        items: [_photo('old')],
        hasMore: false,
      ),
    );
    await oldRequest;

    expect(cubit.state.items.map((photo) => photo.id), ['new']);
    expect(cubit.state.query.search, '新结果');
  });

  test('服务端返回重复游标时停止继续分页并去重照片', () async {
    final repository = _RepeatingCursorPhotoRepository();
    final cubit = GalleryCubit(repository, 'batch-1');
    addTearDown(cubit.close);

    await cubit.refresh();
    expect(cubit.state.hasMore, isTrue);
    await cubit.loadMore();

    expect(cubit.state.items.map((photo) => photo.id), ['first']);
    expect(cubit.state.hasMore, isFalse);
    expect(repository.callCount, 2);
    await cubit.loadMore();
    expect(repository.callCount, 2);
  });
}

PhotoSummary _photo(String id) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
);

class _ControlledPhotoRepository implements PhotoRepository {
  final Map<String, Completer<PhotoPage>> _requests = {};

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) {
    final completer = Completer<PhotoPage>();
    _requests[query.search ?? ''] = completer;
    return completer.future;
  }

  void complete(String search, PhotoPage page) => _requests[search]!.complete(page);

  @override
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
  }) => throw UnimplementedError();

  @override
  Future<List<SceneSummary>> scenes(String batchId) => throw UnimplementedError();

  @override
  Future<List<SpeciesCandidate>> searchSpecies(String query) => throw UnimplementedError();
}

class _RepeatingCursorPhotoRepository implements PhotoRepository {
  var callCount = 0;

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) async {
    callCount++;
    return PhotoPage(
      items: [_photo('first')],
      hasMore: true,
      nextCursor: 'same',
    );
  }

  @override
  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
  }) => throw UnimplementedError();

  @override
  Future<List<SceneSummary>> scenes(String batchId) => throw UnimplementedError();

  @override
  Future<List<SpeciesCandidate>> searchSpecies(String query) => throw UnimplementedError();
}
