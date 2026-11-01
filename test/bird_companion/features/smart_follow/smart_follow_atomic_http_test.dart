import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysis HTTP preserves both IDs and transmits stable key only as a header', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      requests.add({'path': request.uri.path, 'key': request.headers.value('Idempotency-Key'), 'body': jsonDecode(await utf8.decoder.bind(request).join())});
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': const BirdJobStatus(id: 'rec-1', type: BirdJobType.analysis, state: BirdJobState.running, sourceProjectId: 'batch-1', smartFollowSessionId: 'sf-1').toJson()}));
      await request.response.close();
    });
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    try {
      final api = JobApi(client);
      const follow = SmartFollowStartRequest(targetMediaId: 'target', reviewExportEnabled: true);
      final request = AnalysisJobRequest(smartFollow: follow.toJson(), idempotencyKey: 'sf-atomic-original');
      final first = await api.createAnalysis('batch-1', request);
      await api.createAnalysis('batch-1', request);
      expect(first.id, 'rec-1');
      expect(first.smartFollowSessionId, 'sf-1');
      expect(requests, hasLength(2));
      expect(requests.first, requests.last);
      expect(requests.first['path'], '/api/v1/projects/batch-1/analysis-jobs');
      expect(requests.first['key'], 'sf-atomic-original');
      expect(requests.first['body'], {'mode': 'standard', 'include_grouping': true, 'smart_follow': follow.toJson()});
      await api.createAnalysis('batch-1', const AnalysisJobRequest());
      expect(requests.last['key'], isNot('sf-atomic-original'));
      expect(requests.last['body'], {'mode': 'standard', 'include_grouping': true});
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}
