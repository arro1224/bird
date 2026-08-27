import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/mock_box_server/mock_box_server.dart';

const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
const _pairingSession = 'ps_a7_transient_pairing_session';
const _pairingCode = '8642';
const _dppUri = 'DPP:K:A7_TEST_BOOTSTRAP_KEY;C:81/1;;';

void main() {
  test('request logs omit query strings, headers and request bodies', () async {
    final logs = <String>[];
    final server = MockBoxServer(
      photoCount: 60,
      logRequests: true,
      requestLogSink: logs.add,
      deviceId: _deviceId,
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
    final baseUri = await server.start();
    final request = await client.getUrl(
      baseUri.replace(
        path: '/health',
        queryParameters: {
          'access_token': 'a7-query-token',
          'dpp_uri': _dppUri,
        },
      ),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer a7-header-token',
    );
    request.headers.set('X-Wifi-Passphrase', 'a7-wifi-password');
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final payload = jsonDecode(responseBody) as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.ok);
    expect(payload.keys.toSet(), {
      'status',
      'device_id',
      'protocol_version',
      'api_version',
      'active_mode',
      'server_time',
    });
    expect(payload['device_id'], _deviceId);
    expect(payload['protocol_version'], '1.0-rc4');
    expect(logs, ['GET /health']);
    final output = logs.join('\n');
    for (final secret in const [
      'a7-query-token',
      'a7-header-token',
      'a7-wifi-password',
      _dppUri,
    ]) {
      expect(output, isNot(contains(secret)));
    }
  });

  test('persistent mock state excludes rc4 pairing credentials', () async {
    final directory = Directory.systemTemp.createTempSync(
      'birdbox-a7-security-',
    );
    final stateFile = File('${directory.path}/state.json');
    final server = MockBoxServer(
      photoCount: 60,
      logRequests: false,
      requireAuthentication: true,
      deviceId: _deviceId,
      pairingCode: _pairingCode,
      pairingSessionId: _pairingSession,
      stateFile: stateFile,
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final baseUri = await server.start();
    final request = await client.postUrl(
      baseUri.resolve('/api/v1/pairing'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Idempotency-Key', 'a7-pairing-0001');
    request.write(
      jsonEncode({
        'device_id': _deviceId,
        'client_id': _clientId,
        'client_name': 'A7 security audit',
        'pairing_session_id': _pairingSession,
      }),
    );
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final payload = jsonDecode(responseBody) as Map<String, dynamic>;
    final accessToken = payload['access_token'] as String;

    expect(response.statusCode, HttpStatus.created);
    expect(stateFile.existsSync(), isTrue);
    final persisted = stateFile.readAsStringSync();
    for (final secret in [
      _pairingCode,
      _pairingSession,
      accessToken,
      _dppUri,
    ]) {
      expect(persisted, isNot(contains(secret)));
    }
    final state = jsonDecode(persisted) as Map<String, dynamic>;
    final idempotent = Map<String, dynamic>.from(
      state['idempotent_responses'] as Map,
    );
    expect(
      idempotent.keys,
      everyElement(isNot(contains('/api/v1/pairing'))),
    );
  });
}
