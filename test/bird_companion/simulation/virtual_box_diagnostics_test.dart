import 'dart:io';
import 'dart:convert';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('virtual LAN controls preserve request UUID and redact queries in joined server evidence', () async {
    final rows = <Map<String, dynamic>>[];
    final server = MockBoxServer(
      logRequests: false,
      httpDiagnostic: rows.add,
      requestOverride: (request) async {
        if (request.uri.path != '/api/v1/lab-slow') return false;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        request.response.statusCode = 503;
        request.response.write('{}');
        await request.response.close();
        return true;
      },
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
    final base = await server.start();
    final normal = await (await client.getUrl(base.resolve('/health'))).close();
    expect(normal.statusCode, 200);
    await normal.drain<void>();
    final request = await client.getUrl(base.resolve('/api/v1/lab-slow?token=secret-fixture'));
    const id = '6118b661-18b6-4118-8118-b66118b66118';
    request.headers.set('X-Request-Id', id);
    final response = await request.close();
    expect(response.headers.value('X-Request-Id'), id);
    expect(response.statusCode, 503);
    await response.drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final row = rows.singleWhere((e) => e['request_id'] == id);
    expect(row['status'], 503);
    expect(row['elapsed_ms'], greaterThanOrEqualTo(25));
    expect(jsonEncode(rows), isNot(contains('secret-fixture')));
  });
}
