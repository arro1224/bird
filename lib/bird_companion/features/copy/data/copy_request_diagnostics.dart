import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:dio/dio.dart';

typedef CopyDiagnosticSink = void Function(Map<String, Object?> event);

/// Only explicitly selected metadata is emitted. Exception messages, payloads,
/// credentials, URLs and file paths must never enter the journal.
class CopyRequestDiagnostics {
  const CopyRequestDiagnostics(this.sink);
  factory CopyRequestDiagnostics.forJournal(BleConnectionDiagnosticStore journal) => CopyRequestDiagnostics((event) {
    unawaited(
      journal
          .record(
            BleConnectionDiagnosticEvent(
              traceId: event['job_id'] as String? ?? 'copy',
              occurredAt: DateTime.now(),
              eventType: 'copy_request_result',
              source: 'app_copy',
              operationName: event['endpoint'] as String?,
              errorCode: event['error_code'] as String?,
              requestId: event['request_id'] as String?,
              sanitizedMessage: jsonEncode(event),
            ),
          )
          .catchError((Object _) {}),
    );
  });
  final CopyDiagnosticSink sink;

  Future<T> request<T>(String endpoint, String jobId, Future<T> Function() request, {String? deviceId, String trigger = 'poll'}) async {
    final clock = Stopwatch()..start();
    Object? failure;
    try {
      return await request();
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      record(endpoint, jobId, deviceId: deviceId, trigger: trigger, elapsedMs: clock.elapsedMilliseconds, error: failure);
    }
  }

  void record(String endpoint, String jobId, {String? deviceId, String trigger = 'storage', int elapsedMs = 0, Object? error}) {
    final api = error is ApiException ? error : null;
    final cause = api?.cause;
    final dio = error is DioException
        ? error
        : cause is DioException
        ? cause
        : null;
    final data = dio?.response?.data;
    final requestId = (data is Map ? data['request_id'] : null) ?? dio?.response?.headers.map['x-request-id']?.firstOrNull;
    String? identifier(Object? value) => value is String && RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value) ? value : null;
    try {
      sink({
        'event': 'copy_request_result',
        'endpoint': endpoint,
        'job_id': identifier(jobId),
        'device_id': identifier(deviceId),
        'trigger': trigger,
        'elapsed_ms': elapsedMs,
        'http_status': api?.statusCode ?? dio?.response?.statusCode,
        'request_id': identifier(requestId),
        'error_code': identifier(api?.code),
        'error_class': error?.runtimeType.toString(),
        'platform_error': dio?.type.name,
        'protocol_error': error is ProtocolCompatibilityException,
        'outcome': error == null ? 'ok' : 'failed',
      });
    } catch (_) {
      // Diagnostics must not change the outcome of a request or a successful POST.
    }
  }
}
