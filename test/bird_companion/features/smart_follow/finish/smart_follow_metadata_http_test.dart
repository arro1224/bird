import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_fixtures.dart';

void main() {
  test('HTTP preview sends no write until final partial consent, then stable token and target', () async {
    HttpOverrides.global = null;
    final fixture = MetadataEnvironment();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add({'method': request.method, 'path': request.uri.path, 'body': body.isEmpty ? null : jsonDecode(body), 'key': request.headers.value('Idempotency-Key')});
      final path = request.uri.path;
      Object? data;
      if (path == '/api/v1/recognition-capabilities') {
        data = {
          'incremental_recognition_results': {'available': true},
          'smart_follow_copy': {'available': true},
          'smart_follow_metadata_update': {'available': true},
        };
      } else if (path == '/api/v1/smart-follow-sessions/sf_fake') {
        data = fixture.backend.data;
      } else if (path == '/api/v1/jobs/rec_fake') {
        data = const BirdJobStatus(id: 'rec_fake', type: BirdJobType.analysis, state: BirdJobState.completed).toJson();
      } else if (path.endsWith('/metadata-update-availability')) {
        data = {'available': true};
      } else if (path.endsWith('/metadata-updates/preview') || path == '/api/v1/smart-follow-metadata-previews/pv-1') {
        data = {...fixture.backend.previewData, 'blocked_count': 1, 'requires_partial_confirmation': true};
      } else if (path.endsWith('/metadata-updates')) {
        data = {'update_id': 'http-parent', 'state': 'queued'};
      }
      request.response.headers.contentType = ContentType.json;
      if (data == null) request.response.statusCode = 404;
      request.response.write(jsonEncode({'data': data}));
      await request.response.close();
    });
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    final repository = SmartFollowRepository(SmartFollowApi(client));
    final controller = SmartFollowMetadataController(repository: repository, sessionId: 'sf_fake', readRecognition: JobApi(client).detail);
    try {
      await controller.prepare();
      expect(controller.error, isNull);
      expect(controller.preview, isNotNull);
      expect(requests.where((r) => (r['path'] as String).endsWith('/metadata-updates')), isEmpty);
      await controller.confirm();
      expect(requests.where((r) => (r['path'] as String).endsWith('/metadata-updates')), isEmpty);
      controller.setPartialConsent(true);
      await controller.confirm();
      final creates = requests.where((r) => (r['path'] as String).endsWith('/metadata-updates')).toList();
      expect(creates, hasLength(1));
      expect(creates.single['body'], {'preview_token': 'token-1', 'target_media_id': 'media_usb_fake', 'confirm_partial': true});
      expect(creates.single['key'], 'md-create-sf_fake-token-1');
      expect(controller.activeUpdateId, 'http-parent');
      expect(requests.where((r) => (r['path'] as String).contains('/copy-jobs')), isEmpty);
    } finally {
      controller.dispose();
      repository.dispose();
      fixture.dispose();
      await client.dispose();
      await server.close(force: true);
    }
  });
}
