import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'completion_fixtures.dart';

void main() {
  test('HTTP C1 reads all child pages and existing reports without mutation; missing wire field stays unknown', () async {
    HttpOverrides.global = null;
    final fixture = CompletionEnvironment();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    var missingField = false;
    final session = {...fixture.backend.data, 'child_job_count': 2, 'eligible_count': 2, 'copied_asset_count': 2, 'copied_file_count': 4};
    Map<String, dynamic> child(String id) => {'copy_job_id': id, 'state': 'completed', 'asset_count': 1, 'file_count': 2, 'copied_file_count': 2, 'skipped_file_count': 0, 'failed_file_count': 0};
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      final path = request.uri.path;
      Object? data;
      if (path == '/api/v1/smart-follow-sessions/sf_fake') {
        data = session;
      } else if (path == '/api/v1/smart-follow-sessions/sf_fake/copy-jobs') {
        final next = request.uri.queryParameters['cursor'] == 'next';
        data = {
          'items': [child('copy-a'), if (next) child('copy-b')],
          'has_more': !next,
          if (!next) 'next_cursor': 'next',
        };
      } else if (path == '/api/v1/jobs/rec_fake') {
        data = const BirdJobStatus(id: 'rec_fake', type: BirdJobType.analysis, state: BirdJobState.completed, totalCount: 5, finishedCount: 5).toJson();
      } else if (path == '/api/v1/jobs/rec_fake/report') {
        data = {'job_id': 'rec_fake', 'result': 'success', 'total_count': 5, 'success_count': 5, 'failed_count': 0, 'skipped_count': 0};
      } else if (path.startsWith('/api/v1/copy-jobs/')) {
        final id = request.uri.pathSegments[3];
        expect(request.headers.value('X-BirdBox-Protocol'), 'birdbox-copy-v1');
        data = path.endsWith('/report') ? {...fixture.report, 'copy_job_id': id} : {...fixture.detail, 'copy_job_id': id};
        if (missingField && path.endsWith('/report')) (data as Map).remove('not_applicable_files');
      }
      request.response.headers.contentType = ContentType.json;
      if (data == null) {
        request.response.statusCode = 404;
      }
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    final repository = SmartFollowRepository(SmartFollowApi(client));
    final copy = CopyApi(client);
    final jobs = JobApi(client);
    final controller = SmartFollowCompletionController(repository: repository, sessionId: 'sf_fake', readChild: copy.getJob, readCopyReport: copy.jobReport, readRecognition: jobs.detail, readRecognitionReport: jobs.report);
    try {
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.result!.summaryComplete, isTrue);
      expect(controller.result!.children, hasLength(2));
      expect(controller.result!.copiedFiles, 4);
      expect(controller.result!.copiedBytes, 256);
      expect(requests.where((r) => r.contains('cursor=next')), hasLength(1));
      missingField = true;
      await controller.refresh();
      expect(controller.result!.notApplicableFiles, isNull);
      expect(controller.result!.summaryComplete, isFalse);
      expect(requests.every((r) => r.startsWith('GET ')), isTrue);
    } finally {
      controller.dispose();
      repository.dispose();
      fixture.dispose();
      await client.dispose();
      await server.close(force: true);
    }
  });
}
