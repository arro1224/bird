import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network change replaces live API and media sockets without disposing their clients', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ports = <String, List<int>>{};
    server.listen((request) async {
      ports.putIfAbsent(request.uri.path, () => []).add(request.connectionInfo!.remotePort);
      if (request.uri.path == '/photo') {
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([1, 2, 3]);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true}');
      }
      await request.response.close();
    });
    final api = ApiClient();
    final media = MediaAssetHttpClient();
    addTearDown(() async {
      await api.dispose();
      media.dispose();
      await server.close(force: true);
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    await api.getUri(base.resolve('/health'));
    await media.fetch(base.resolve('/photo'));
    api.resetNetworkConnections();
    media.resetNetworkConnections();
    expect(await api.getUri(base.resolve('/health')), {'ok': true});
    expect((await media.fetch(base.resolve('/photo'))).bytes, [1, 2, 3]);
    expect(ports['/health']!.toSet().length, 2);
    expect(ports['/photo']!.toSet().length, 2);
  });
}
