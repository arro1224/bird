import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active-box media uses current token, signed and foreign URLs do not', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String?>[];
    server.listen((request) async {
      seen.add(request.headers.value('Authorization'));
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final api = ApiClient()
      ..configure(base)
      ..setSession(accessToken: 'test-one');
    final media = MediaAssetHttpClient(headersForUri: api.mediaHeaders);
    try {
      final uri = base.resolve('/api/v1/files/photo-1/thumbnail');
      expect((await media.fetch(uri)).bytes, [1, 2, 3]);
      api.setSession(accessToken: 'test-two');
      await media.fetch(uri);
      await media.fetch(uri.replace(query: 'sig=signed'));
      await media.fetch(uri.replace(host: 'localhost'));
      api.clearSession();
      await media.fetch(uri);
      expect(seen, ['Bearer test-one', 'Bearer test-two', null, null, null]);
    } finally {
      media.dispose();
      await api.dispose();
      await server.close(force: true);
    }
  });

  test('authenticated media does not forward a token through redirects', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirected = false;
    server.listen((request) async {
      if (request.uri.path == '/other') redirected = true;
      request.response.statusCode = 302;
      request.response.headers.set('Location', '/other');
      await request.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final api = ApiClient()
      ..configure(base)
      ..setSession(accessToken: 'test-token');
    final media = MediaAssetHttpClient(headersForUri: api.mediaHeaders);
    try {
      await expectLater(media.fetch(base.resolve('/api/v1/files/photo-1/preview')), throwsA(isA<MediaAssetFailure>()));
      expect(redirected, isFalse);
    } finally {
      media.dispose();
      await api.dispose();
      await server.close(force: true);
    }
  });
}
