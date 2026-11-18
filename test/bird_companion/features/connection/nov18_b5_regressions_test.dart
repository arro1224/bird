import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  for (final change in ['new_address', 'address_round_trip', 'new_token']) {
    for (final status in [401, 403]) {
      test('会话切换$change后旧请求$status不能使当前授权失效', () async {
        final dio = Dio();
        final api = ApiClient(dio: dio);
        final failures = <int>[];
        final subscription = api.authenticationFailures.listen(failures.add);
        addTearDown(() async {
          await subscription.cancel();
          await api.dispose();
        });
        final entered = Completer<void>();
        final release = Completer<void>();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              entered.complete();
              await release.future;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: options, statusCode: status),
                ),
              );
            },
          ),
        );
        api.configure(Uri.parse('http://192.0.2.1:8080'));
        final failed = expectLater(api.get('/api/v1/projects'), throwsException);
        await entered.future;
        if (change == 'new_token') {
          api.setSession(accessToken: 'replacement-synthetic-token');
        } else {
          api.configure(Uri.parse('http://192.0.2.2:8080'));
          if (change == 'address_round_trip') api.configure(Uri.parse('http://192.0.2.1:8080'));
        }
        release.complete();
        await failed;
        await Future<void>.delayed(Duration.zero);
        expect(failures, isEmpty);
      });
    }
  }

  for (final maxAttempts in [1, 5]) {
    test('同一WS的error和done只消耗一次重连尝试，预算$maxAttempts', () async {
      final channels = <_Channel>[];
      final records = <Map<String, dynamic>>[];
      final client = EventClient(
        reconnectPolicy: ReconnectPolicy(maxAttempts: maxAttempts, initialDelay: const Duration(milliseconds: 100)),
        connector: (_, _) {
          final channel = _Channel();
          channels.add(channel);
          return channel;
        },
      )..diagnostic = records.add;
      addTearDown(client.dispose);
      await client.connect(Uri.parse('ws://127.0.0.1/api/v1/events'), accessToken: 'synthetic-only');
      channels.single.messages.addError(StateError('synthetic transport failure'));
      await channels.single.messages.close();
      expect(records.where((e) => e['event'] == 'websocket_retry_wait'), hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channels, hasLength(2));
      expect(client.currentState, EventConnectionState.connected);
    });
  }
}

class _Channel extends Fake implements WebSocketChannel {
  final messages = StreamController<dynamic>();
  @override
  Stream<dynamic> get stream => messages.stream;
  @override
  late final WebSocketSink sink = _Sink(messages);
  @override
  Future<void> get ready async {}
  @override
  int? get closeCode => 1006;
}

class _Sink extends Fake implements WebSocketSink {
  _Sink(this.messages);
  final StreamController<dynamic> messages;
  @override
  Future<void> close([int? closeCode, String? closeReason]) => messages.close();
}
