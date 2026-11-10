import 'dart:async';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only current private transport failures report global unreachability', () async {
    final dio = Dio();
    final client = ApiClient(dio: dio, publicDio: dio);
    final failures = <void>[];
    final subscription = client.connectionFailures.listen(failures.add);
    addTearDown(() async {
      await subscription.cancel();
      await client.dispose();
    });
    client.configure(Uri.parse('http://192.0.2.1:8080'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError)),
      ),
    );
    await expectLater(client.get('/api/v1/storage/devices'), throwsException);
    await Future<void>.delayed(Duration.zero);
    expect(failures.length, 1);
    await expectLater(client.getUri(Uri.parse('http://192.0.2.2:8080/health')), throwsException);
    await Future<void>.delayed(Duration.zero);
    expect(failures.length, 1, reason: 'public candidate checks must not disconnect the active box');
  });

  test('busy/service errors and cancellation do not masquerade as transport loss', () async {
    for (final status in [409, 503, null]) {
      final dio = Dio();
      final client = ApiClient(dio: dio);
      client.configure(Uri.parse('http://192.0.2.1:8080'));
      var failures = 0;
      final subscription = client.connectionFailures.listen((_) => failures++);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: status == null ? DioExceptionType.cancel : DioExceptionType.badResponse,
              response: status == null ? null : Response(requestOptions: options, statusCode: status),
            ),
          ),
        ),
      );
      await expectLater(client.get('/api/v1/storage/devices'), throwsException);
      await Future<void>.delayed(Duration.zero);
      expect(failures, 0);
      await subscription.cancel();
      await client.dispose();
    }
  });

  test('late failure from a replaced address cannot invalidate the new box', () async {
    final dio = Dio();
    final client = ApiClient(dio: dio);
    client.configure(Uri.parse('http://192.0.2.1:8080'));
    var failures = 0;
    final subscription = client.connectionFailures.listen((_) => failures++);
    addTearDown(() async {
      await subscription.cancel();
      await client.dispose();
    });
    final arrived = Completer<void>();
    late RequestOptions request;
    late RequestInterceptorHandler handler;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, next) {
          request = options;
          handler = next;
          arrived.complete();
        },
      ),
    );
    final pending = client.get('/api/v1/device/status');
    final rejected = expectLater(pending, throwsException);
    await arrived.future;
    client.configure(Uri.parse('http://192.0.2.2:8080'));
    handler.reject(DioException(requestOptions: request, type: DioExceptionType.connectionError));
    await rejected;
    await Future<void>.delayed(Duration.zero);
    expect(failures, 0);
  });
}
