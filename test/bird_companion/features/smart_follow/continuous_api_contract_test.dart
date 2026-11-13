import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'continuous_summary_contract_test.dart' show envelope;

void main() {
  late HttpServer server;
  late ApiClient client;
  late SmartFollowApi api;
  late List<String> paths;
  late Object? detail;
  late int status;
  late Map<String, dynamic> response;
  late List<String?> keys;
  late List<Uri> uris;
  late List<Object?> bodies;

  setUp(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    paths = [];
    keys = [];
    uris = [];
    bodies = [];
    detail = {'smart_follow_session_id': 'follow-example'};
    status = 200;
    response = envelope();
    server.listen((request) async {
      paths.add(request.uri.path);
      uris.add(request.uri);
      keys.add(request.headers.value('X-Idempotency-Key'));
      final body = await utf8.decoder.bind(request).join();
      bodies.add(body.isEmpty ? null : jsonDecode(body));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v1/jobs/analysis-example') {
        request.response.statusCode = status;
        request.response.write(jsonEncode(status == 200 ? {'data': detail} : {'error': {'code': 'AUTH_REQUIRED', 'message': 'authentication required'}}));
      } else if (request.uri.path.endsWith('/recognition-events')) {
        request.response.write(jsonEncode({'data': {'smart_follow_session_id': 'legacy-follow'}}));
      } else {
        request.response.write(jsonEncode({'data': response}));
      }
      await request.response.close();
    });
    client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    api = SmartFollowApi(client);
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('session and action retain installed envelope summary and stable action header', () async {
    final session = await api.session('follow-example');
    expect(session.summary!.copiedBytes, 61260);
    final updated = await api.act('follow-example', SmartFollowAction.retry, expectedStateVersion: 4, idempotencyKey: 'retry-original');
    expect(updated!.summary!.fileCounts['copied'], 2);
    expect(keys.last, 'retry-original');
  });
  test('job detail supplies association without depending on recognition-events', () async {
    expect(await api.sessionIdForRecognitionJob('analysis-example'), 'follow-example');
    expect(paths, ['/api/v1/jobs/analysis-example']);
  });
  test('explicit null association is authoritative', () async {
    detail = {'smart_follow_session_id': null};
    expect(await api.sessionIdForRecognitionJob('analysis-example'), isNull);
    expect(paths, hasLength(1));
  });
  test('legacy detail without association retains recognition-events discovery', () async {
    detail = {'job_id': 'analysis-example'};
    expect(await api.sessionIdForRecognitionJob('analysis-example'), 'legacy-follow');
    expect(paths.last, '/api/v1/jobs/analysis-example/recognition-events');
  });
  test('authentication failure must not fall back to stale association', () async {
    status = 401;
    await expectLater(api.sessionIdForRecognitionJob('analysis-example'), throwsA(isA<ApiException>()));
    expect(paths, hasLength(1));
  });
  test('grouped history sends grouped true and opaque cursor verbatim', () async {
    response = {'items': [
      {'kind': 'smart_follow', 'session_id': 'follow-example', 'data': envelope()},
      {'kind': 'copy', 'copy_job_id': 'copy-original', 'state': 'completed'},
    ], 'has_more': false, 'next_cursor': null};
    final page = await api.groupedHistory(cursor: 'opaque+/==');
    expect(page.items, hasLength(2));
    expect(page.items.first.session!.sessionId, 'follow-example');
    expect(page.items.last.copy!.copyJobId, 'copy-original');
    expect(uris.single.path, '/api/v1/copy-jobs');
    expect(uris.single.queryParameters, {'grouped': 'true', 'page_size': '30', 'cursor': 'opaque+/=='});
  });
  test('continuous start uses the installed SmartFollowIn boolean export field', () async {
    await api.startOnRecognitionJob('analysis-example', const SmartFollowStartRequest(targetMediaId: 'target', reviewExportEnabled: false, continuousQueue: true), idempotencyKey: 'continuous-original');
    expect(bodies.single, {'target_media_id': 'target', 'eligibility_mode': 'recognized_only_v1', 'pair_policy': 'raw_only', 'conflict_strategy': 'skip', 'review_export_enabled': false});
    expect(keys.single, 'continuous-original');
  });
  test('session list parses envelopes and preserves its keyset cursor', () async {
    response = {'items': [envelope()], 'has_more': true, 'next_cursor': 'follow-page=='};
    final page = await api.sessions(cursor: 'first-bound+/=');
    expect(page.items.single.summary!.copiedBytes, 61260);
    expect(page.nextCursor, 'follow-page==');
    expect(uris.single.path, '/api/v1/smart-follow-sessions');
    expect(uris.single.queryParameters, {'page_size': '30', 'cursor': 'first-bound+/='});
  });
}
