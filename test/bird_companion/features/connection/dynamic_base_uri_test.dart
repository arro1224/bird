import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('dynamic address relocates REST, WebSocket and relative media', () async {
    final endpoints = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
    });
    final api = ApiClient();
    final events = EventClient(
      connector: (endpoint, headers) {
        endpoints.add(endpoint);
        return IOWebSocketChannel.connect(
          endpoint,
          headers: headers,
          connectTimeout: const Duration(seconds: 2),
        );
      },
    );
    final store = MemorySecureSessionStore();
    final coordinator = SessionCoordinator(api, events, store);
    addTearDown(() async {
      await coordinator.dispose();
      await events.dispose();
      await api.dispose();
      await server.close(force: true);
      await Future.wait(sockets.toList(growable: false).map((socket) => socket.close()));
    });

    final oldBase = Uri.parse('http://127.0.0.1:${server.port}');
    final newBase = Uri.parse('http://localhost:${server.port}');
    final credential = SessionCredential(
      deviceId: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
      baseUri: oldBase,
      accessToken: 'test-token-not-a-real-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      apiVersion: 'v1',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );

    await coordinator.activate(credential);
    final change = coordinator.addressChanges.first;
    await coordinator.activate(
      SessionCredential(
        deviceId: credential.deviceId,
        baseUri: newBase,
        accessToken: credential.accessToken,
        expiresAt: credential.expiresAt,
        apiVersion: credential.apiVersion,
        clientId: credential.clientId,
      ),
    );

    expect((await change).baseUri, newBase);
    expect(api.baseUri, newBase);
    expect(coordinator.activeBaseUri, newBase);
    expect(endpoints.last, newBase.replace(scheme: 'ws', path: ApiEndpoints.events));
    expect(
      api.resolveMediaReference('/media/photo-1/preview'),
      newBase.resolve('/media/photo-1/preview').toString(),
    );
    expect((await store.read(credential.deviceId))?.baseUri, newBase);
  });
}
