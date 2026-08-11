import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('B6 ignores a late REST authentication failure from an old session', () async {
    final requestArrived = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((request) async {
      if (!requestArrived.isCompleted) requestArrived.complete();
      await releaseResponse.future;
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error_code': 'token_expired',
            'error_message': 'old session expired',
            'retryable': false,
          }),
        );
      await request.response.close();
    });
    final client = ApiClient()
      ..configure(Uri.parse('http://127.0.0.1:${server.port}'))
      ..setSession(accessToken: 'old-token');
    final failures = <int>[];
    final failureSubscription = client.authenticationFailures.listen(failures.add);
    addTearDown(() async {
      await failureSubscription.cancel();
      await client.dispose();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    final oldRequest = client.get('/protected');
    await requestArrived.future;
    client.setSession(accessToken: 'new-token');
    releaseResponse.complete();

    await expectLater(
      oldRequest,
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(failures, isEmpty);
  });

  test('B6 ignores a late WS failure after switching event sessions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final serverSubscription = server.transform(WebSocketTransformer()).listen(sockets.add);
    final staleReady = Completer<void>();
    final staleUnderlyingSocket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/api/v1/events',
    );
    final staleConnectorStarted = Completer<void>();
    final currentConnectorStarted = Completer<void>();
    var attempts = 0;
    final events = EventClient(
      reconnectPolicy: const ReconnectPolicy(
        maxAttempts: 1,
        initialDelay: Duration(milliseconds: 10),
      ),
      connector: (endpoint, headers) {
        attempts++;
        if (attempts == 1) {
          staleConnectorStarted.complete();
          return _DeferredReadyIoWebSocketChannel(
            staleUnderlyingSocket,
            staleReady.future,
          );
        }
        currentConnectorStarted.complete();
        return IOWebSocketChannel.connect(endpoint, headers: headers);
      },
    );
    final failures = <int>[];
    final failureSubscription = events.authenticationFailures.listen(failures.add);
    addTearDown(() async {
      await failureSubscription.cancel();
      await events.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    final staleConnect = events.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/api/v1/events'),
      accessToken: 'old-token',
    );
    await staleConnectorStarted.future;
    final currentConnect = events.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/api/v1/events'),
      accessToken: 'new-token',
    );
    await currentConnectorStarted.future;
    staleReady.completeError(
      const HttpException('HTTP status code: 403'),
    );

    await Future.wait([staleConnect, currentConnect]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events.currentState, EventConnectionState.connected);
    expect(failures, isEmpty);
    expect(attempts, 2);
  });
}

class _DeferredReadyIoWebSocketChannel extends IOWebSocketChannel {
  _DeferredReadyIoWebSocketChannel(super.socket, this.ready);

  @override
  final Future<void> ready;
}
