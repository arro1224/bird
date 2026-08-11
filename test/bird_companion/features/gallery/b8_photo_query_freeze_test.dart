import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B8 photo query freeze and defect characterization', () {
    test('online white-egret search stops after an empty first page', () async {
      final client = _PagedRecordingApiClient();

      final page = await PhotoApi(client).page(
        'project-egret',
        const PhotoQuery(search: '白鹭'),
      );

      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'page-2');
      expect(client.requests, hasLength(1));
      expect(
        client.requests.single.path,
        '/api/v1/projects/project-egret/files',
      );
      expect(client.requests.single.queryParameters, isNot(contains('search')));
      expect(client.page2SpeciesNames, contains('白鹭'));

      // PhotoApi intentionally remains a frozen, single-page transport. B9's
      // repository-level executor now supplies the end-to-end cross-page
      // success path while this test keeps guarding the transport boundary.
    });

    test('photo list sends only query parameters declared by frozen OpenAPI', () async {
      final client = _PagedRecordingApiClient();
      const query = PhotoQuery(
        cursor: 'cursor-2',
        pageSize: 200,
        sort: 'score_desc',
        species: 'little-egret',
        search: '白鹭',
        minScore: 4,
        minConfidence: 0.85,
        tags: ['湿地', '晨拍'],
        keepState: 'keep',
        analysisState: 'completed',
        clarityState: 'sharp',
        recognitionState: 'recognized',
        recommendedOnly: true,
        groupId: 'group-7',
        sceneId: 'scene-9',
      );

      await PhotoApi(client).page('project-egret', query);

      final sent = client.requests.single.queryParameters.keys.toSet();
      final declared = _declaredPhotoListQueryParameters();
      expect(sent.difference(declared), isEmpty);
      expect(sent, {
        'page_size',
        'sort',
        'cursor',
        'keep_state',
        'analysis_state',
        'group_id',
        'scene_id',
      });
      expect(
        sent.intersection({
          'search',
          'species',
          'min_score',
          'min_confidence',
          'tags',
          'clarity_state',
          'recognition_state',
          'recommended_only',
        }),
        isEmpty,
      );
    });
  });
}

Set<String> _declaredPhotoListQueryParameters() {
  final document =
      jsonDecode(
            File('docs/contracts/birdbox-v1.openapi.yaml').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final paths = document['paths'] as Map<String, dynamic>;
  final path = paths['/projects/{projectId}/files'] as Map<String, dynamic>;
  final operation = path['get'] as Map<String, dynamic>;
  final parameters = <Object?>[
    ...(path['parameters'] as List? ?? const []),
    ...(operation['parameters'] as List? ?? const []),
  ];

  return parameters.whereType<Map>().map((raw) => _resolveParameter(document, Map<String, dynamic>.from(raw))).where((parameter) => parameter['in'] == 'query').map((parameter) => parameter['name']?.toString()).whereType<String>().toSet();
}

Map<String, dynamic> _resolveParameter(
  Map<String, dynamic> document,
  Map<String, dynamic> parameter,
) {
  final reference = parameter[r'$ref']?.toString();
  if (reference == null) return parameter;
  const prefix = '#/components/parameters/';
  if (!reference.startsWith(prefix)) {
    throw StateError('Unsupported parameter reference: $reference');
  }
  final name = reference.substring(prefix.length);
  final components = document['components'] as Map<String, dynamic>;
  final parameters = components['parameters'] as Map<String, dynamic>;
  return Map<String, dynamic>.from(parameters[name] as Map);
}

class _RecordedGet {
  const _RecordedGet(this.path, this.queryParameters);

  final String path;
  final Map<String, dynamic> queryParameters;
}

class _PagedRecordingApiClient extends ApiClient {
  final List<_RecordedGet> requests = [];

  final Map<String, dynamic> _page2 = const {
    'items': [
      {
        'file_id': 'egret-page-2',
        'filename': 'DSC_2002.ARW',
        'recognition': {
          'candidates': [
            {'name': '白鹭', 'english_name': 'Little Egret'},
          ],
        },
      },
    ],
    'has_more': false,
  };

  Iterable<String> get page2SpeciesNames =>
      (_page2['items'] as List).whereType<Map>().expand((item) => ((item['recognition'] as Map)['candidates'] as List)).whereType<Map>().map((candidate) => candidate['name']?.toString()).whereType<String>();

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final query = Map<String, dynamic>.from(queryParameters ?? const {});
    requests.add(_RecordedGet(path, query));
    if (query['cursor'] == 'page-2') return _page2;
    return const {
      'items': <Map<String, dynamic>>[],
      'has_more': true,
      'next_cursor': 'page-2',
    };
  }
}
