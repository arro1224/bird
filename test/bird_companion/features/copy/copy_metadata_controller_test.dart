import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_metadata_page.dart';
import 'package:flutter_test/flutter_test.dart';
import '../smart_follow/finish/metadata_fixtures.dart';

void main() {
  test('ordinary metadata: explicit opt-in, persistent same-key recovery, device isolation', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final creates = <Map<String, dynamic>>[];
    final store = MetadataStore();
    var key = 'box-a', failFirst = true;
    final preview = {
      'preview_id': 'pv-1',
      'preview_token': 'token-1',
      'expires_at': '2099-01-01T00:00:00Z',
      'target_media_id': 'usb-1',
      'target_display_name': '摄影备份盘',
      'state': 'ready',
      'child_job_count': 1,
      'updatable_asset_count': 1,
      'updatable_file_count': 1,
      'unchanged_count': 0,
      'blocked_count': 0,
      'conflict_count': 0,
      'estimated_bytes': 4096,
      'write_mode': 'xmp_csv',
      'requires_partial_confirmation': false,
      'blocked_reasons': <String>[],
    };
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      Object? data;
      final path = request.uri.path;
      if (path == '/api/v1/copy-capabilities') data = {'metadata_export_ready': true};
      if (path.endsWith('/metadata-update-context')) data = {'context_type': 'copy_job', 'copy_job_id': 'copy-1', 'active_metadata_update_id': null};
      if (path.endsWith('/metadata-update-availability')) data = {'available': true, 'updatable_asset_count': 1};
      if (path.endsWith('/metadata-updates/preview')) {
        expect(jsonDecode(body)['explicit_export_opt_in'], isTrue);
        expect(request.headers.value('X-BirdBox-Protocol'), 'birdbox-copy-v1');
        data = preview;
      }
      if (path.contains('/metadata-update-previews/')) data = preview;
      if (path.endsWith('/metadata-updates')) {
        creates.add({'body': jsonDecode(body), 'key': request.headers.value('Idempotency-Key')});
        if (failFirst) {
          failFirst = false;
          request.response.statusCode = 503;
        } else {
          data = {'update_id': 'update-1', 'state': 'queued'};
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          data == null
              ? {
                  'error': {'code': 'pending', 'message': 'pending'},
                }
              : {'data': data},
        ),
      );
      await request.response.close();
    });
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${server.port}'));
    CopyMetadataController controller() => CopyMetadataController(client: client, storage: store, copyJobId: 'copy-1', deviceKey: key, currentKey: () => key);
    final first = controller();
    try {
      await first.refresh();
      await first.prepare();
      expect(first.canConfirm, isTrue);
      await first.confirm();
      expect(first.pending, isTrue);
      expect(first.canConfirm, isFalse);
      first.dispose();
      final restored = controller();
      await restored.refresh();
      expect(restored.update?.updateId, 'update-1');
      expect(creates, hasLength(2));
      expect(creates[1], creates[0]);
      expect((creates.first['body'] as Map)['explicit_export_opt_in'], isTrue);
      key = 'box-b';
      await restored.prepare();
      expect(restored.current, isFalse);
      expect(restored.canConfirm, isFalse);
      restored.dispose();
    } finally {
      if (!first.disposed) first.dispose();
      await client.dispose();
      await server.close(force: true);
    }
  });
}
