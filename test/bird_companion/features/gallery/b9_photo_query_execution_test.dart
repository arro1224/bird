import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_local_filter_engine.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query_plan.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B9 frozen-contract local query execution', () {
    test('searches later server pages and resolves Chinese bird aliases', () async {
      final serverQueries = <PhotoQuery>[];
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          serverQueries.add(query);
          if (query.cursor == null) {
            return const PhotoPage(
              items: [],
              hasMore: true,
              nextCursor: 'page-2',
            );
          }
          return PhotoPage(
            items: [
              _photo(
                'egret-page-2',
                speciesName: 'Little Egret',
                englishName: 'Little Egret',
                latinName: 'Egretta garzetta',
              ),
            ],
            hasMore: false,
          );
        },
        (query) async => const [
          SpeciesCandidate(
            name: '白鹭',
            speciesId: 'little-egret',
            englishName: 'Little Egret',
            latinName: 'Egretta garzetta',
            confidence: 1,
          ),
        ],
      );

      final result = await executor.page(
        'project-egret',
        const PhotoQuery(search: '白鹭'),
      );

      expect(result.items.map((photo) => photo.id), ['egret-page-2']);
      expect(serverQueries, hasLength(2));
      expect(serverQueries[0].cursor, isNull);
      expect(serverQueries[1].cursor, 'page-2');
      const localOnlyParameters = <String>{
        'search',
        'species',
        'min_score',
        'min_confidence',
        'tags',
        'clarity_state',
        'recognition_state',
        'recommended_only',
      };
      for (final query in serverQueries) {
        expect(query.pageSize, PhotoQueryPlan.scanPageSize);
        expect(
          query.parameters.keys.toSet().intersection(localOnlyParameters),
          isEmpty,
        );
      }
    });

    test('paginates filtered results with a local cursor without another request', () async {
      final serverQueries = <PhotoQuery>[];
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          serverQueries.add(query);
          return PhotoPage(
            items: [
              _photo('egret-1', speciesName: '白鹭'),
              _photo('egret-2', speciesName: '白鹭'),
              _photo('egret-3', speciesName: '白鹭'),
            ],
            hasMore: false,
          );
        },
        (query) async => const [],
      );
      const query = PhotoQuery(search: '白鹭', pageSize: 2);

      final first = await executor.page('project-egret', query);
      final second = await executor.page(
        'project-egret',
        query.next(first.nextCursor),
      );

      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, startsWith(PhotoQueryPlan.localCursorPrefix));
      expect(second.items.map((photo) => photo.id), ['egret-3']);
      expect(second.hasMore, isFalse);
      expect(serverQueries, hasLength(1));
      expect(
        serverQueries.single.parameters['cursor'],
        isNull,
        reason: 'App-local cursors must never be sent to birdbox-v1.',
      );
    });

    test('applies combined species, score, confidence, tag and state filters', () {
      final photos = [
        _photo(
          'match',
          speciesName: 'Little Egret',
          englishName: 'Little Egret',
          score: 4.7,
          confidence: 0.93,
          tags: const ['湿地', '晨拍'],
          clarity: ClarityState.clear,
          recommended: true,
        ),
        _photo(
          'low-confidence',
          speciesName: 'Little Egret',
          score: 4.8,
          confidence: 0.4,
          tags: const ['湿地', '晨拍'],
          clarity: ClarityState.clear,
          recommended: true,
        ),
        _photo(
          'wrong-tag',
          speciesName: 'Little Egret',
          score: 4.9,
          confidence: 0.99,
          tags: const ['湿地'],
          clarity: ClarityState.clear,
          recommended: true,
        ),
      ];
      const query = PhotoQuery(
        species: '白鹭',
        minScore: 4.5,
        minConfidence: 0.9,
        tags: ['湿地', '晨拍'],
        clarityState: 'clear',
        recognitionState: 'recognized',
        recommendedOnly: true,
        sort: 'score_desc',
      );

      final result = const PhotoLocalFilterEngine().filterAndSort(
        photos,
        query,
        speciesAliases: const {'白鹭', 'little egret', 'egretta garzetta'},
      );

      expect(result.map((photo) => photo.id), ['match']);
    });

    test('keeps search aliases separate from the species condition', () {
      final result = const PhotoLocalFilterEngine().filterAndSort(
        [_photo('sparrow', speciesName: 'Eurasian Tree Sparrow')],
        const PhotoQuery(search: '麻雀', species: '白鹭'),
        searchAliases: const {'麻雀', 'eurasian tree sparrow'},
        speciesAliases: const {'白鹭', 'little egret'},
      );

      expect(result, isEmpty);
    });

    test('preserves frozen server order when a sort cannot be recomputed', () {
      final photos = [
        _photo('server-first', speciesName: '白鹭'),
        _photo('server-second', speciesName: '白鹭'),
      ];

      final result = const PhotoLocalFilterEngine().filterAndSort(
        photos,
        const PhotoQuery(search: '.jpg', sort: 'size_desc'),
      );

      expect(
        result.map((photo) => photo.id),
        ['server-first', 'server-second'],
      );
    });

    test('stops safely when the server repeats a cursor', () async {
      var requestCount = 0;
      final executor = PhotoLocalQueryExecutor(
        (batchId, query) async {
          requestCount += 1;
          return const PhotoPage(
            items: [],
            hasMore: true,
            nextCursor: 'repeated',
          );
        },
        (query) async => const [],
      );

      final result = await executor.page(
        'project-egret',
        const PhotoQuery(search: '白鹭'),
      );

      expect(result.items, isEmpty);
      expect(requestCount, 2);
    });
  });
}

PhotoSummary _photo(
  String id, {
  required String speciesName,
  String? englishName,
  String? latinName,
  double score = 5,
  double confidence = 0.95,
  List<String> tags = const [],
  ClarityState clarity = ClarityState.clear,
  bool recommended = false,
}) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'jpg',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  recognition: RecognitionResult(
    candidates: [
      SpeciesCandidate(
        name: speciesName,
        englishName: englishName,
        latinName: latinName,
        confidence: confidence,
      ),
    ],
  ),
  rating: RatingResult(totalScore: score),
  clarityState: clarity,
  isRecommended: recommended,
  userTags: tags,
  capturedAt: DateTime.utc(2026, 8, 10),
);
