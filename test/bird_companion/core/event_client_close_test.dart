import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'test-token-not-a-real-secret';
const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';

void main() {
  test('disconnect closes the server-side WebSocket', () async {
    final server = await _LoopbackWebSocketServer.start();
    final client = EventClient();
    addTearDown(() async {
      await client.dispose();
      await server.close();
    });
    final accepted = server.nextConnection();

    await client.connect(server.endpoint, accessToken: _token);
    final connection = await accepted;
    await client.disconnect();

    await connection.closed.timeout(const Duration(seconds: 2));
    expect(server.activeConnectionCount, 0);
  });

  test('connect replacement closes the previous WebSocket first', () async {
    final oldServer = await _LoopbackWebSocketServer.start();
    final newServer = await _LoopbackWebSocketServer.start();
    final client = EventClient();
    addTearDown(() async {
      await client.dispose();
      await oldServer.close();
      await newServer.close();
    });
    final oldAccepted = oldServer.nextConnection();
    await client.connect(oldServer.endpoint, accessToken: _token);
    final oldConnection = await oldAccepted;
    final newAccepted = newServer.nextConnection();

    await client.connect(newServer.endpoint, accessToken: _token);
    final newConnection = await newAccepted;

    await oldConnection.closed.timeout(const Duration(seconds: 2));
    expect(oldServer.activeConnectionCount, 0);
    expect(newServer.activeConnectionCount, 1);
    expect(newConnection.authorization, 'Bearer $_token');
  });

  test('repeated session address changes retain one event socket', () async {
    final servers = <_LoopbackWebSocketServer>[
      await _LoopbackWebSocketServer.start(),
      await _LoopbackWebSocketServer.start(),
      await _LoopbackWebSocketServer.start(),
    ];
    final api = ApiClient();
    final events = EventClient();
    final coordinator = SessionCoordinator(
      api,
      events,
      MemorySecureSessionStore(),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await events.dispose();
      await api.dispose();
      for (final server in servers) {
        await server.close();
      }
    });

    _ServerConnection? previous;
    for (final server in servers) {
      final accepted = server.nextConnection();
      await coordinator.activate(_credential(server.baseUri));
      final current = await accepted;
      if (previous != null) {
        await previous.closed.timeout(const Duration(seconds: 2));
      }
      previous = current;
      expect(current.authorization, 'Bearer $_token');
      expect(
        servers.fold<int>(
          0,
          (total, item) => total + item.activeConnectionCount,
        ),
        1,
      );
    }

    expect(api.baseUri, servers.last.baseUri);
    expect(
      servers.last.endpoint.path,
      ApiEndpoints.events,
    );
  });
}

SessionCredential _credential(Uri baseUri) => SessionCredential(
  deviceId: _deviceId,
  baseUri: baseUri,
  accessToken: _token,
  expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
  apiVersion: 'v1',
  clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
);

final class _ServerConnection {
  const _ServerConnection({
    required this.socket,
    required this.closed,
    required this.authorization,
  });

  final WebSocket socket;
  final Future<void> closed;
  final String? authorization;
}

final class _LoopbackWebSocketServer {
  _LoopbackWebSocketServer._(this._server);

  final HttpServer _server;
  final List<_ServerConnection> _active = [];
  final List<_ServerConnection> _queued = [];
  final List<Completer<_ServerConnection>> _waiters = [];

  static Future<_LoopbackWebSocketServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _LoopbackWebSocketServer._(httpServer);
    httpServer.listen(server._accept);
    return server;
  }

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');
  Uri get endpoint => baseUri.replace(
    scheme: 'ws',
    path: ApiEndpoints.events,
  );
  int get activeConnectionCount => _active.length;

  Future<_ServerConnection> nextConnection() {
    if (_queued.isNotEmpty) return Future.value(_queued.removeAt(0));
    final waiter = Completer<_ServerConnection>();
    _waiters.add(waiter);
    return waiter.future.timeout(const Duration(seconds: 2));
  }

  Future<void> _accept(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final closed = Completer<void>();
    late final _ServerConnection connection;
    connection = _ServerConnection(
      socket: socket,
      closed: closed.future,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
    );
    _active.add(connection);
    socket.listen(
      (_) {},
      onError: (_, _) {
        _active.remove(connection);
        if (!closed.isCompleted) closed.complete();
      },
      onDone: () {
        _active.remove(connection);
        if (!closed.isCompleted) closed.complete();
      },
      cancelOnError: false,
    );
    if (_waiters.isEmpty) {
      _queued.add(connection);
    } else {
      _waiters.removeAt(0).complete(connection);
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    final active = _active.toList(growable: false);
    await Future.wait(active.map((connection) => connection.socket.close()));
  }
}
