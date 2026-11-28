import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/copy/data/mock_copy_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/retained_copy_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online retained union includes featured from later exact-filter server pages and freezes every copy member', () async {
    final photos = _Photos();
    final copies = _Copies();
    const query = PhotoQuery(keepState: 'keep', tags: ['trip']);
    final page = await photos.page('project', query);
    expect(page.matchedCount, 247);
    expect(page.items, hasLength(60));
    final selection = await createRetainedCopySelection(batchId: 'project', query: query, photos: photos, copies: copies, isCurrent: () => true);
    expect(selection.assetCount, 247);
    expect(copies.ids, containsAll(['asset-featured-1', 'asset-featured-2']));
    expect(copies.ids, isNot(contains('asset-other-trip')));
    expect(copies.ids, isNot(contains('asset-discard')));
    expect(copies.calls, 1);
    expect(photos.serverQueries.every((q) => q.keepState == null), isTrue);
    // Frozen wire semantics are untouched; only gallery execution forms a union.
    expect(query.parameters['keep_state'], 'keep');
    expect(query.toCopyFilterV1()!['keep_state'], 'keep');
  });

  test('partial results never freeze a silently incomplete copy selection', () async {
    final photos = _Photos()..partial = true;
    final copies = _Copies();
    await expectLater(
      createRetainedCopySelection(
        batchId: 'project',
        query: const PhotoQuery(keepState: 'keep'),
        photos: photos,
        copies: copies,
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(copies.calls, 0);
  });

  test('device change during list read never creates a selection on the new box', () async {
    final photos = _Photos();
    final copies = _Copies();
    var current = true;
    photos.afterPage = () => current = false;
    await expectLater(
      createRetainedCopySelection(
        batchId: 'project',
        query: const PhotoQuery(keepState: 'keep'),
        photos: photos,
        copies: copies,
        isCurrent: () => current,
      ),
      throwsStateError,
    );
    expect(copies.calls, 0);
  });
}

class _Photos implements PhotoRepository {
  bool partial = false;
  void Function()? afterPage;
  final serverQueries = <PhotoQuery>[];
  late final executor = PhotoLocalQueryExecutor((batch, query) async {
    serverQueries.add(query);
    final all = [
      for (var i = 0; i < 245; i++) _photo('$i', 'keep'),
      _photo('featured-1', 'featured'),
      _photo('featured-2', 'featured'),
      _photo('other-trip', 'keep', tags: ['other']),
      _photo('discard', 'discard'),
    ];
    final facts = query.keepState == null ? all : all.where((p) => p.keepState == query.keepState).toList();
    final offset = int.tryParse(query.cursor ?? '') ?? 0;
    final end = (offset + query.pageSize).clamp(0, facts.length);
    return PhotoPage(items: facts.sublist(offset, end), hasMore: end < facts.length, nextCursor: end < facts.length ? '$end' : null);
  }, (_) async => []);
  @override
  Future<PhotoPage> page(String project, PhotoQuery query) async {
    if (partial) return const PhotoPage(items: [], hasMore: false, resultComplete: false);
    final result = await executor.page(project, query);
    afterPage?.call();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Copies extends MockCopyRepository {
  int calls = 0;
  List<String> ids = [];
  @override
  Future<CopySelectionSnapshot> createSelection(String batchId, List<String> assetIds, {int clientRevision = 0}) async {
    calls++;
    ids = List.of(assetIds);
    return CopySelectionSnapshot(selectionId: 'selection', assetCount: ids.length);
  }
}

PhotoSummary _photo(String id, String state, {List<String> tags = const ['trip']}) =>
    PhotoSummary(id: id, assetId: 'asset-$id', filename: '$id.jpg', format: 'jpg', preview: const PreviewRef(), analysisState: AnalysisState.completed, keepState: state, userTags: tags, version: 1);
