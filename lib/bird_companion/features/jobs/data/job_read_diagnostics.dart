import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';

/// Metadata-only diagnostics. No response bodies, exception messages, URLs,
/// authorization headers or local/board file paths are exported.
class JobReadDiagnostics {
  const JobReadDiagnostics(this.sink);
  final void Function(Map<String, Object?>) sink;
  factory JobReadDiagnostics.forJournal(BleConnectionDiagnosticStore journal) => JobReadDiagnostics((event) {
    unawaited(journal.record(BleConnectionDiagnosticEvent(
      traceId: event['job_id'] as String? ?? 'task-detail', occurredAt: DateTime.now(),
      eventType: 'task_detail_read', source: 'app_tasks', operationName: 'read_task_detail',
      errorCode: event['error_code'] as String?, sanitizedMessage: jsonEncode(event),
    )).catchError((Object _) {}));
  });

  void record(String jobId, {Object? batchId, Object? error, bool responseReceived = false}) {
    String? identifier(Object? value) => value is String && RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value) ? value : null;
    final job = identifier(jobId);
    final api = error is ApiException ? error : null;
    try {
      sink({
        'event': 'task_detail_read', 'job_id': job, 'batch_id': identifier(batchId),
        'endpoint': job == null ? ApiEndpoints.jobDetail : ApiEndpoints.jobDetail.replaceFirst('{jobId}', job),
        'http_status': responseReceived ? 200 : api?.statusCode,
        'error_code': identifier(api?.code), 'error_class': error?.runtimeType.toString(),
        'parse_field': error is ProtocolCompatibilityException ? identifier(error.field) : null,
        'outcome': error == null ? 'ok' : 'failed',
      });
    } catch (_) {
      // A journal error must never block task navigation.
    }
  }
}
