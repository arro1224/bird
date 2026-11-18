import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_recorder.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryDiagnostics implements DiagnosticStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => values[key] = jsonDecode(jsonEncode(value));
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  late HttpServer server;
  late ApiClient client;
  late PhoneDiagnosticRecorder recorder;
  late Uri uri;
  final requests = <Map<String, String?>>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      requests.add({'path': request.uri.path, 'request_id': request.headers.value('x-request-id'), 'key': request.headers.value('x-idempotency-key')});
      await request.drain<void>();
      if (request.uri.path.contains('slow-id')) await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        request.response.statusCode = request.uri.path.endsWith('/busy') ? 503 : 200;
        request.response.headers.contentType = ContentType.json;
        if (request.headers.value('x-request-id') case final id?) request.response.headers.set('X-Request-Id', id.toUpperCase());
        request.response.write('{"data":{"healthy":true,"items":[],"body":"response-secret"}}');
        await request.response.close();
      } catch (_) {
        /* The timed-out client may already have closed. */
      }
    });
    recorder = PhoneDiagnosticRecorder(MemoryDiagnostics());
    client = ApiClient(dio: Dio(BaseOptions(receiveTimeout: const Duration(milliseconds: 80))));
    client.configure(uri);
    client.setSession(accessToken: 'bearer-secret');
    client.httpDiagnostics
      ..record = recorder.record
      ..context = () => {'device_id': 'test-box', 'page': '/copy-confirmation', 'generation': 7};
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
    await recorder.dispose();
  });

  test('real network attempts get distinct UUIDs while write retries keep their idempotency key; no sensitive values are logged', () async {
    for (var i = 0; i < 2; i++) {
      await client.post('/api/v1/files/secret-photo/decision', data: {'wifi_password': 'body-secret'}, idempotencyKey: 'intent-key-secret');
    }
    final ids = requests.map((r) => r['request_id']!).toList();
    expect(ids.every(isUuidV4), true);
    expect(ids.toSet(), hasLength(2));
    expect(requests.map((r) => r['key']), everyElement('intent-key-secret'));
    final snapshot = await recorder.snapshot();
    final finished = (snapshot['events'] as List).where((e) => e['event'] == 'http_request_finished').toList();
    expect(finished, hasLength(2));
    expect(finished.first['response_request_id'], ids.first);
    expect(finished.first['page'], '/copy-confirmation');
    expect(finished.first['route'], '/api/v1/files/{id}/decision');
    expect(finished.first['queue_ms'], isNull);
    expect(finished.first['elapsed_ms'], isNonNegative);
    final exported = jsonEncode(snapshot);
    for (final secret in ['bearer-secret', 'body-secret', 'response-secret', 'secret-photo', 'intent-key-secret']) {
      expect(exported, isNot(contains(secret)));
    }
  });

  test('real timeout joins failed business request to independent health probe without demoting a reachable box', () async {
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(_Repository(uri), _Online(), events, refresh, connectionFailureDetails: client.connectionFailureDetails, probeReachability: client.probeReachability, diagnostic: recorder.record);
    addTearDown(() async {
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });
    await session.setConnectedFromStatus(DeviceStatus(connection: _Repository(uri).device, card: const CardStatus(inserted: true)));
    await expectLater(client.get('/api/v1/smart-follow-sessions/slow-id'), throwsA(isA<ApiException>()));
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final snapshot = await recorder.snapshot();
      if ((snapshot['events'] as List).any((e) => e['event'] == 'business_failure_reachability_checked')) break;
    }
    final records = (await recorder.snapshot())['events'] as List;
    final business = records.singleWhere((e) => e['event'] == 'http_request_finished' && e['timeout'] == true);
    final checked = records.singleWhere((e) => e['event'] == 'business_failure_reachability_checked');
    expect(checked['cause_request_id'], business['request_id']);
    expect(isUuidV4(checked['probe_request_id']), true);
    expect(records.any((e) => e['request_id'] == checked['probe_request_id'] && e['event'] == 'http_request_finished' && e['route'] == '/health'), true);
    expect(checked['outcome'], 'reachable');
    expect(session.state.isConnected, true);
  });

  test('cancellation and HTTP 503 retain error type and status; signed asset URLs are redacted', () async {
    await expectLater(client.get('/api/v1/device/busy?password=query-secret'), throwsA(isA<ApiException>()));
    final cancel = CancelToken();
    final pending = client.getUri(uri.resolve('/api/v1/smart-follow-sessions/slow-id'), cancelToken: cancel);
    final failed = expectLater(pending, throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cancel.cancel('cancel-secret');
    await failed;
    await client.downloadSignedBytes(uri.resolve('/signed/file-secret?signature=signed-secret'));
    final snapshot = await recorder.snapshot();
    final records = snapshot['events'] as List;
    expect(records.any((e) => e['http_status'] == 503 && e['event'] == 'http_request_finished'), true);
    expect(records.any((e) => e['cancelled'] == true && e['error_class'] == 'cancel'), true);
    expect(requests.last['request_id'], isNull, reason: 'signed asset requests do not acquire a new custom header');
    for (final secret in ['query-secret', 'cancel-secret', 'signed-secret', 'file-secret']) {
      expect(jsonEncode(snapshot), isNot(contains(secret)));
    }
  });
  test('progressive preview downloads are observed without changing signed URL authentication', () async {
    final media = MediaAssetHttpClient(diagnostics: client.httpDiagnostics);
    addTearDown(media.dispose);
    await media.fetch(uri.resolve('/api/v1/files/secret-photo/preview?signature=signed-secret'));
    expect(requests.single['request_id'], isNull);
    final snapshot = await recorder.snapshot();
    expect((snapshot['events'] as List).any((e) => e['route'] == '/api/v1/files/{id}/preview' && e['event'] == 'http_request_finished'), true);
    expect(jsonEncode(snapshot), isNot(contains('signed-secret')));
  });
}

class _Online extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
  @override
  Future<bool> get hasNetwork async => true;
}

class _Repository implements ConnectionRepository {
  _Repository(Uri uri) : device = DeviceConnection(id: 'bbx-test', name: 'box', baseUri: uri, networkMode: NetworkMode.infrastructureSta, isPaired: true);
  final DeviceConnection device;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
