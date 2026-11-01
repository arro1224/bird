import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_update_fixtures.dart';

void main() {
  test('HTTP parent report retries same ID and rereads later availability using only existing GET endpoints', () async {
    HttpOverrides.global = null;
    final fixture = MetadataUpdateEnvironment();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    bool failReport = false, available = false;
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      Object? data;
      if (path == '/api/v1/smart-follow-sessions/sf_fake') {
        data = fixture.backend.data;
      } else if (path == '/api/v1/smart-follow-metadata-updates/update-1') {
        if (failReport) {
          request.response.statusCode = 503;
          request.response.write(jsonEncode({'error_message': 'report unavailable'}));
          await request.response.close();
          return;
        }
        data = {...fixture.backend.updateData, 'state': 'completed_partial', 'blocked_count': 1};
      } else if (path == '/api/v1/recognition-capabilities') {
        data = {
          'incremental_recognition_results': {'available': true},
          'smart_follow_copy': {'available': true},
          'smart_follow_metadata_update': {'available': true},
        };
      } else if (path.endsWith('/metadata-update-availability')) {
        data = {'available': available, 'active_update_id': 'update-1'};
      }
      if (data == null) request.response.statusCode = 404;
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    final repository = SmartFollowRepository(SmartFollowApi(client));
    final controller = SmartFollowMetadataUpdateController(repository: repository, sessionId: 'sf_fake', updateId: 'update-1');
    try {
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.report!.title, '识别信息部分更新');
      expect(controller.report!.children.last.copyJobId, 'copy-2');
      failReport = true;
      await controller.refresh();
      expect(controller.error, isNotNull);
      expect(controller.canPreview, isFalse);
      failReport = false;
      available = true;
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.canPreview, isTrue);
      expect(requests.every((path) => path.startsWith('GET ')), isTrue);
      expect(requests.where((path) => path.contains('/smart-follow-metadata-updates/')).toSet(), {'GET /api/v1/smart-follow-metadata-updates/update-1'});
      expect(requests.any((path) => path.contains('/metadata-update-jobs/')), isFalse);
    } finally {
      controller.dispose();
      repository.dispose();
      fixture.dispose();
      await client.dispose();
      await server.close(force: true);
    }
  });
}
