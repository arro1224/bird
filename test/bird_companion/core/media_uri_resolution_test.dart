import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API 响应中的相对照片地址统一解析到当前盒子', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': {
            'items': [
              {
                'file_id': 'photo-01',
                'thumb_ref': '/mock/media/kingfisher.png',
                'preview_ref': 'mock/media/kingfisher.png',
              },
            ],
          },
        }),
      );
      request.response.close();
    });

    final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    final client = ApiClient()..configure(baseUri);

    final data = await client.get('/api/v1/projects/mock/files');
    final item = Map<String, dynamic>.from((data['items'] as List).single as Map);

    expect(item['thumb_ref'], '$baseUri/mock/media/kingfisher.png');
    expect(item['preview_ref'], '$baseUri/mock/media/kingfisher.png');
  });

  test('绝对照片地址和无会话地址保持原值', () {
    final client = ApiClient();
    expect(client.resolveMediaReference('/mock/media/photo.png'), '/mock/media/photo.png');

    client.configure(Uri.parse('http://192.168.4.1:8080'));
    expect(
      client.resolveMediaReference('https://cdn.example.com/photo.png'),
      'https://cdn.example.com/photo.png',
    );
  });
}
