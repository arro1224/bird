import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_local_filter_engine.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B10 filter progress, cancellation and candidate cache', () {
    test('reports scan progress for every server page and completion', () async {
      final progress = <PhotoQueryProgress>[];
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          final page = query.cursor == null ? 0 : int.parse(query.cursor!);
          return PhotoPage(
            items: [
              _photo('egret-${page * 2}', '白鹭'),
              _photo('egret-${page * 2 + 1}', '白鹭'),
            ],
            hasMore: page < 2,
            nextCursor: page < 2 ? '${page + 1}' : null,
          );
        },
        (query) async => const [],
      );

      final result = await executor.page(
        'project-1',
        const PhotoQuery(search: '白鹭'),
        onProgress: progress.add,
      );

      expect(progress.map((value) => value.scannedCount), [0, 2, 4, 6, 6]);
      expect(progress.last.complete, isTrue);
      expect(progress.last.matchedCount, 6);
      expect(result.scannedCount, 6);
      expect(result.matchedCount, 6);
      expect(result.resultComplete, isTrue);
    });

    test('cancels before requesting another server page', () async {
      var requests = 0;
      final token = PhotoQueryCancellationToken();
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          requests += 1;
          return PhotoPage(
            items: [_photo('egret-1', '白鹭')],
            hasMore: true,
            nextCursor: 'page-2',
          );
        },
        (query) async => const [],
      );

      final future = executor.page(
        'project-1',
        const PhotoQuery(search: '白鹭'),
        cancellationToken: token,
        onProgress: (value) {
          if (value.scannedCount == 1) token.cancel();
        },
      );

      await expectLater(future, throwsA(isA<PhotoQueryCancelled>()));
      expect(requests, 1);
    });

    test('reuses a complete candidate snapshot across local filter changes', () async {
      PhotoCandidateSnapshot? snapshot;
      var serverRequests = 0;
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          serverRequests += 1;
          return PhotoPage(
            items: [
              _photo('egret', '白鹭'),
              _photo('sparrow', '麻雀'),
            ],
            hasMore: false,
          );
        },
        (query) async => const [],
        const PhotoLocalFilterEngine(),
        (batchId, query) => snapshot,
        (batchId, query, value) async => snapshot = value,
      );

      final egret = await executor.page(
        'project-1',
        const PhotoQuery(search: '白鹭'),
      );
      final sparrow = await executor.page(
        'project-1',
        const PhotoQuery(search: '麻雀'),
      );

      expect(egret.items.map((item) => item.id), ['egret']);
      expect(sparrow.items.map((item) => item.id), ['sparrow']);
      expect(serverRequests, 1);
      expect(sparrow.fromCache, isTrue);
      expect(sparrow.cacheScope, PhotoCacheScope.complete);
      expect(sparrow.resultComplete, isTrue);
    });

    test('marks a scan interrupted after cached pages as incomplete', () async {
      var requests = 0;
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          requests += 1;
          if (requests == 2) {
            throw const ApiException(
              message: 'offline',
              retryable: true,
            );
          }
          return PhotoPage(
            items: [_photo('egret-cached', '白鹭')],
            hasMore: true,
            nextCursor: 'page-2',
          );
        },
        (query) async => const [],
      );

      final result = await executor.page(
        'project-1',
        const PhotoQuery(search: '白鹭'),
      );

      expect(result.items.map((item) => item.id), ['egret-cached']);
      expect(result.resultComplete, isFalse);
      expect(result.cacheScope, PhotoCacheScope.partial);
      expect(result.fromCache, isTrue);
      expect(result.scannedCount, 1);
    });

    test('keeps existing gallery items visible while filtering and cancels cleanly', () async {
      final repository = _ControllableExecutionRepository();
      final cubit = GalleryCubit(repository, 'project-1');
      addTearDown(cubit.close);

      await cubit.refresh();
      final filtering = cubit.refresh(
        query: const PhotoQuery(search: '白鹭'),
      );
      await repository.filterStarted.future;

      expect(cubit.state.filtering, isTrue);
      expect(cubit.state.items.map((item) => item.id), ['existing']);
      expect(cubit.state.scannedCount, 200);

      cubit.cancelFiltering();
      await filtering;

      expect(cubit.state.filtering, isFalse);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.items.map((item) => item.id), ['existing']);
      expect(cubit.state.error, isNull);
    });

    test('invalidates candidate sessions before a photo data refresh', () async {
      final repository = _ControllableExecutionRepository();
      final changes = AppDataChangeBus();
      final cubit = GalleryCubit(repository, 'project-1', null, changes);
      addTearDown(cubit.close);
      addTearDown(changes.dispose);
      await cubit.refresh();

      changes.publish(
        {AppDataResource.photos},
        reason: 'photo-updated',
      );
      await repository.invalidated.future;

      expect(repository.invalidatedBatchId, 'project-1');
    });

    test('filters ten thousand summaries within the local performance guard', () {
      final photos = List.generate(
        10000,
        (index) => _photo(
          'photo-$index',
          index.isEven ? '白鹭' : '麻雀',
        ),
        growable: false,
      );
      final stopwatch = Stopwatch()..start();

      final result = const PhotoLocalFilterEngine().filterAndSort(
        photos,
        const PhotoQuery(search: '白鹭'),
      );
      stopwatch.stop();

      expect(result, hasLength(5000));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    testWidgets('filter reset clears search and every advanced condition', (
      tester,
    ) async {
      PhotoQuery? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterSheet(
              initial: const PhotoQuery(
                search: '白鹭',
                species: 'little-egret',
                minScore: 4,
                minConfidence: .85,
                tags: ['湿地'],
                keepState: 'keep',
                analysisState: 'completed',
                clarityState: 'clear',
                recognitionState: 'recognized',
                recommendedOnly: true,
                groupId: 'group-1',
                sceneId: 'scene-1',
                sort: 'score_desc',
              ),
              onApply: (query) => applied = query,
            ),
          ),
        ),
      );

      await tester.tap(find.text('重置'));
      await tester.pump();
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied!.search, isNull);
      expect(applied!.species, isNull);
      expect(applied!.minScore, isNull);
      expect(applied!.minConfidence, isNull);
      expect(applied!.tags, isEmpty);
      expect(applied!.keepState, isNull);
      expect(applied!.analysisState, isNull);
      expect(applied!.clarityState, isNull);
      expect(applied!.recognitionState, isNull);
      expect(applied!.recommendedOnly, isFalse);
      expect(applied!.groupId, isNull);
      expect(applied!.sceneId, isNull);
      expect(applied!.sort, 'captured_at_desc');
    });
  });
}

PhotoSummary _photo(String id, String species) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'jpg',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  recognition: RecognitionResult(
    candidates: [
      SpeciesCandidate(name: species, confidence: .95),
    ],
  ),
  capturedAt: DateTime.utc(2026, 8, 10),
);

class _ControllableExecutionRepository implements PhotoRepository, PhotoQueryExecutionRepository {
  final filterStarted = Completer<void>();
  final invalidated = Completer<void>();
  String? invalidatedBatchId;

  @override
  Future<PhotoPage> page(String batchId, PhotoQuery query) => pageWithProgress(batchId, query);

  @override
  Future<PhotoPage> pageWithProgress(
    String batchId,
    PhotoQuery query, {
    PhotoQueryProgressCallback? onProgress,
    PhotoQueryCancellationToken? cancellationToken,
  }) async {
    if (query.search == null || query.search!.isEmpty) {
      return PhotoPage(
        items: [_photo('existing', '麻雀')],
        hasMore: false,
      );
    }
    onProgress?.call(
      const PhotoQueryProgress(scannedCount: 200, matchedCount: 3),
    );
    if (!filterStarted.isCompleted) filterStarted.complete();
    while (cancellationToken?.isCancelled != true) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    cancellationToken?.throwIfCancelled();
    throw StateError('unreachable');
  }

  @override
  Future<void> invalidateLocalQueries(String batchId) async {
    invalidatedBatchId = batchId;
    if (!invalidated.isCompleted) invalidated.complete();
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
