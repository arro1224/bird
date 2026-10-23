import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'connection_cancellation.dart';
import 'package:dio/dio.dart';

/// Identity and cancellation belong to an intent, not to a page timeout.
/// Attaching metadata to the token lets lower layers retain the original trace
/// even after another intent becomes current.
final class ConnectionAttempt {
  ConnectionAttempt({required this.id, required this.generation, required this.token, required this.isCurrent, this.deviceId, this.operationId, this.diagnostic, this.onStage}) {
    _tokens[token] = this;
  }

  static final _tokens = Expando<ConnectionAttempt>();
  static ConnectionAttempt? forToken(CancelToken? token) => token == null ? null : _tokens[token];
  final String id;
  final int generation;
  final CancelToken token;
  final bool Function() isCurrent;
  final String? operationId;
  String? deviceId;
  String? stage;
  bool committed = false;
  final void Function(Map<String, dynamic>)? diagnostic;
  final void Function(String stage)? onStage;
  final _clock = Stopwatch()..start();

  void check() {
    token.throwIfCancellationRequested();
    if (!isCurrent()) throw StateError('Connection attempt superseded');
  }

  void record(String event, [Map<String, dynamic> fields = const {}]) {
    try {
      diagnostic?.call({'event': event, 'attempt_id': id, 'generation': generation, 'device_id': deviceId, 'operation_id': operationId, 'phase': stage, 'elapsed_ms': _clock.elapsedMilliseconds, ...fields});
    } catch (_) {
      // Recording cannot change the verification result.
    }
  }

  Future<T> run<T>(String phase, Future<T> Function() request) async {
    check();
    stage = phase;
    onStage?.call(phase);
    final clock = Stopwatch()..start();
    record('connection_phase_started');
    try {
      final result = await request();
      check();
      record('connection_phase_finished', {'phase': phase, 'phase_elapsed_ms': clock.elapsedMilliseconds, 'outcome': 'ok'});
      return result;
    } catch (error) {
      record('connection_phase_finished', {'phase': phase, 'phase_elapsed_ms': clock.elapsedMilliseconds, 'outcome': 'failed', ...errorFields(error)});
      rethrow;
    }
  }

  static Future<T> runFor<T>(CancelToken? token, String stage, Future<T> Function() request) => forToken(token)?.run(stage, request) ?? request();

  static Map<String, Object?> errorFields(Object error) {
    final api = error is ApiException ? error : null;
    final dio = error is DioException
        ? error
        : api?.cause is DioException
        ? api!.cause as DioException
        : null;
    return {
      'error_class': error.runtimeType.toString(),
      'error_code': api?.code ?? dio?.type.name ?? (error is TimeoutException ? 'deadline' : null),
      'http_status': api?.statusCode ?? dio?.response?.statusCode,
    };
  }
}
