import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

import '../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  late MockBoxServer server;

  tearDown(() async {
    await server.close();
  });

  test('未配对到安全保存、REST、WS、媒体、日志形成同一鉴权链路', () async {
    server = MockBoxServer(
      photoCount: 4,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
    );
    final baseUri = await server.start();
    final store = MemorySecureSessionStore();
    var apiClient = ApiClient();
    var eventClient = EventClient();
    var coordinator = SessionCoordinator(apiClient, eventClient, store);
    var connection = ConnectionApi(
      apiClient,
      PairingApi(apiClient),
      coordinator,
    );

    await expectLater(
      connection.handshake(baseUri, NetworkMode.manual),
      throwsA(isA<PairingRequiredException>()),
    );

    final status = await connection.pair(
      baseUri,
      NetworkMode.manual,
      pairingCode: '2468',
    );
    expect(status.connection.isPaired, isTrue);
    expect(coordinator.activeDeviceId, 'mock-k7-001');
    expect(eventClient.currentState, EventConnectionState.connected);
    expect(await store.read('mock-k7-001'), isNotNull);

    final project = await apiClient.get(ApiEndpoints.currentBatch);
    expect((project['batch'] as Map)['project_id'], 'mock-batch-current');

    final page = await PhotoApi(
      apiClient,
    ).page('mock-batch-current', const PhotoQuery(pageSize: 1));
    final media = await apiClient.downloadSignedBytes(
      page.items.single.preview.previewUri!,
    );
    expect(media.bytes, isNotEmpty);

    final logExport = await apiClient.post(
      ApiEndpoints.logExport,
      data: const {'scope': 'device_and_jobs'},
    );
    final log = await apiClient.downloadSignedBytes(
      baseUri.resolve(logExport['download_url']!.toString()),
    );
    expect(String.fromCharCodes(log.bytes), contains('status=ok'));
    expect(server.lastSignedAssetAuthorizationHeader, isNull);

    await coordinator.clearMemory();
    await coordinator.dispose();
    await eventClient.dispose();
    await apiClient.dispose();

    // App restart: only the encrypted store survives. The coordinator restores
    // the same device-scoped identity before any protected work resumes.
    apiClient = ApiClient();
    eventClient = EventClient();
    coordinator = SessionCoordinator(apiClient, eventClient, store);
    connection = ConnectionApi(
      apiClient,
      PairingApi(apiClient),
      coordinator,
    );
    final restored = await connection.handshake(
      baseUri,
      NetworkMode.manual,
    );
    expect(restored.connection.id, 'mock-k7-001');
    expect(eventClient.currentState, EventConnectionState.connected);

    server.revokeAccessToken();
    await expectLater(
      apiClient.get(ApiEndpoints.currentBatch),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.forbidden,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.activeDeviceId, isNull);
    expect(eventClient.currentState, EventConnectionState.disconnected);
    expect(await store.read('mock-k7-001'), isNull);

    await coordinator.dispose();
    await eventClient.dispose();
    await apiClient.dispose();
  });

  test('REST 严格区分缺失、错误和正确 Token', () async {
    server = MockBoxServer(
      photoCount: 60,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
    );
    final baseUri = await server.start();
    final client = ApiClient()..configure(baseUri);
    addTearDown(client.dispose);

    await _expectStatus(
      client.get(ApiEndpoints.currentBatch),
      HttpStatus.unauthorized,
    );
    client.setSession(accessToken: 'wrong-token', apiVersion: 'v1');
    await _expectStatus(
      client.get(ApiEndpoints.currentBatch),
      HttpStatus.forbidden,
    );

    final credential = await PairingApi(
      client,
    ).pair(baseUri, pairingCode: '2468');
    client.setSession(
      accessToken: credential.accessToken,
      apiVersion: credential.apiVersion,
    );
    final result = await client.get(ApiEndpoints.currentBatch);
    expect((result['batch'] as Map)['project_id'], 'mock-batch-current');
  });

  test('WS 401/403 停止退避重连并触发身份恢复', () async {
    server = MockBoxServer(
      photoCount: 60,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
    );
    var attempts = 0;
    final events = EventClient(
      reconnectPolicy: const ReconnectPolicy(
        maxAttempts: 5,
        initialDelay: Duration(milliseconds: 10),
      ),
      connector: (endpoint, headers) {
        attempts++;
        return IOWebSocketChannel(
          Future<WebSocket>.error(
            const HttpException('HTTP status code: 403'),
          ),
        );
      },
    );
    addTearDown(events.dispose);
    final failure = events.authenticationFailures.first;

    await events.connect(
      Uri.parse('ws://127.0.0.1:8787${ApiEndpoints.events}'),
      accessToken: 'wrong-token',
    );

    expect(await failure.timeout(const Duration(seconds: 1)), 403);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(attempts, 1);
    expect(events.currentState, EventConnectionState.disconnected);
  });

  test('短签名媒体过期后重新读取业务对象可获得新地址', () async {
    var now = DateTime.utc(2026, 7, 29, 8);
    server = MockBoxServer(
      photoCount: 60,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
      signedUrlLifetime: const Duration(seconds: 2),
      clock: () => now,
    );
    final baseUri = await server.start();
    final client = ApiClient()..configure(baseUri);
    addTearDown(client.dispose);
    final credential = await PairingApi(
      client,
    ).pair(baseUri, pairingCode: '2468');
    client.setSession(
      accessToken: credential.accessToken,
      apiVersion: credential.apiVersion,
    );

    final api = PhotoApi(client);
    final first = await api.page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 1),
    );
    final expiredAddress = first.items.single.preview.previewUri!;
    final expiredLogAddress = baseUri.resolve(
      (await client.post(
        ApiEndpoints.logExport,
        data: const {'scope': 'device_and_jobs'},
      ))['download_url']!.toString(),
    );
    now = now.add(const Duration(seconds: 3));

    await expectLater(
      client.downloadSignedBytes(expiredAddress),
      throwsA(
        isA<SignedAssetDownloadException>().having(
          (error) => error.isExpired,
          'isExpired',
          isTrue,
        ),
      ),
    );
    await expectLater(
      client.downloadSignedBytes(expiredLogAddress),
      throwsA(isA<SignedAssetDownloadException>()),
    );

    final refreshed = await api.page(
      'mock-batch-current',
      const PhotoQuery(pageSize: 1),
    );
    expect(
      refreshed.items.single.preview.previewUri,
      isNot(expiredAddress),
    );
    expect(
      (await client.downloadSignedBytes(
        refreshed.items.single.preview.previewUri!,
      )).bytes,
      isNotEmpty,
    );
    final refreshedLogAddress = baseUri.resolve(
      (await client.post(
        ApiEndpoints.logExport,
        data: const {'scope': 'device_and_jobs'},
      ))['download_url']!.toString(),
    );
    expect(refreshedLogAddress, isNot(expiredLogAddress));
    expect(
      (await client.downloadSignedBytes(refreshedLogAddress)).bytes,
      isNotEmpty,
    );
  });

  test('Token 到期返回 401 且不会被标记为可重试网络错误', () async {
    var now = DateTime.utc(2026, 7, 29, 8);
    server = MockBoxServer(
      photoCount: 60,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
      tokenLifetime: const Duration(seconds: 2),
      clock: () => now,
    );
    final baseUri = await server.start();
    final client = ApiClient()..configure(baseUri);
    addTearDown(client.dispose);
    final credential = await PairingApi(
      client,
    ).pair(baseUri, pairingCode: '2468');
    client.setSession(
      accessToken: credential.accessToken,
      apiVersion: credential.apiVersion,
    );
    now = now.add(const Duration(seconds: 3));

    await expectLater(
      client.get(ApiEndpoints.currentBatch),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });

  test('换设备切换内存身份，忘记设备只删除对应安全凭据', () async {
    server = MockBoxServer(
      photoCount: 60,
      deviceId: 'device-a',
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
    );
    final otherServer = MockBoxServer(
      photoCount: 60,
      deviceId: 'device-b',
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
      requireAuthentication: true,
    );
    addTearDown(otherServer.close);
    final baseA = await server.start();
    final baseB = await otherServer.start();
    final store = MemorySecureSessionStore();
    final client = ApiClient();
    final events = EventClient();
    final coordinator = SessionCoordinator(client, events, store);
    final connection = ConnectionApi(
      client,
      PairingApi(client),
      coordinator,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await events.dispose();
      await client.dispose();
    });

    await connection.pair(
      baseA,
      NetworkMode.manual,
      pairingCode: '2468',
    );
    expect(coordinator.activeDeviceId, 'device-a');
    await connection.pair(
      baseB,
      NetworkMode.manual,
      pairingCode: '2468',
    );
    expect(coordinator.activeDeviceId, 'device-b');
    expect(otherServer.lastPairAuthorizationHeader, isNull);
    expect(await store.read('device-a'), isNotNull);
    expect(await store.read('device-b'), isNotNull);

    await coordinator.forget('device-b');
    expect(coordinator.activeDeviceId, isNull);
    expect(await store.read('device-b'), isNull);
    expect(await store.read('device-a'), isNotNull);
  });

  test('凭据恢复为过期和时间偏差预留安全窗口', () async {
    final now = DateTime.utc(2026, 7, 29, 8);
    SessionCredential credential(Duration lifetime) => SessionCredential(
      deviceId: 'device-a',
      baseUri: Uri.parse('http://192.168.4.1:8080'),
      accessToken: 'secret',
      expiresAt: now.add(lifetime),
      apiVersion: 'v1',
    );

    expect(credential(const Duration(seconds: 30)).isUsableAt(now), isFalse);
    expect(credential(const Duration(seconds: 31)).isUsableAt(now), isTrue);
    expect(
      credential(
        const Duration(seconds: 10),
      ).isUsableAt(now, clockSkew: Duration.zero),
      isTrue,
    );
  });

  test('WS 非鉴权故障保持 1/2/4/8/16 秒退避', () {
    const policy = ReconnectPolicy();
    expect(
      [for (var attempt = 0; attempt < 5; attempt++) policy.delayFor(attempt)],
      const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
      ],
    );
  });
}

Future<void> _expectStatus(Future<Object?> request, int statusCode) => expectLater(
  request,
  throwsA(
    isA<ApiException>().having(
      (error) => error.statusCode,
      'statusCode',
      statusCode,
    ),
  ),
);
