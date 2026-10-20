import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// One user intent spans scan, pairing, network, HTTP, WS and routing. Storage
/// uses the existing bounded journal, including its durable drop accounting.
final class ConnectionAttemptRecorder {
  ConnectionAttemptRecorder(this.store, this.events);
  final DiagnosticStorage store;
  final BleConnectionDiagnosticStore events;
  static const key = 'connection:diagnostic-attempt:v1';
  String? _active;
  String get activeId => _active ??= store.read<String>(key) ?? SecureRequestIdFactory().create();

  String begin(String intent, {String? scanId}) {
    final id = _active = SecureRequestIdFactory().create();
    unawaited(store.write(key, id).catchError((Object _) {}));
    record({'event': 'connection_intent_started', 'intent': intent, 'scan_session_id': scanId, 'attempt_id': id});
    return id;
  }

  void record(Map<String, dynamic> event) {
    final id = event['attempt_id'] as String? ?? activeId;
    final parentId = activeId;
    if (event['event'] == 'sta_intent_started') {
      _active = id;
      unawaited(store.write(key, id).catchError((Object _) {}));
    }
    // Allow-list: never serialize commands, payloads, credentials or arbitrary
    // exception messages. Endpoint is restricted to its public scheme/host/port.
    final safe = <String, dynamic>{};
    if (event['event'] == 'sta_intent_started') safe['parent_attempt_id'] = parentId;
    for (final entry in event.entries) {
      if (const {
        'event',
        'intent',
        'attempt_id',
        'generation',
        'phase',
        'device_id',
        'operation_id',
        'status_operation_id',
        'operation_state',
        'received_operation_id',
        'event_type',
        'busy',
        'error_class',
        'error_code',
        'stack_frames',
        'network_identity_hash',
        'scan_session_id',
        'request_id',
        'gatt_generation',
        'http_result',
        'ws_state',
        'route',
        'classification',
        'transient',
        'first_error',
        'attempt',
        'network_mode',
        'device_id_verified',
      }.contains(entry.key)) {
        safe[entry.key] = entry.value;
      }
    }
    final endpoint = Uri.tryParse(event['base_uri'] as String? ?? '');
    if (endpoint != null && endpoint.host.isNotEmpty) safe['endpoint'] = '${endpoint.scheme}://${endpoint.host}:${endpoint.port}';
    unawaited(
      events
          .record(
            BleConnectionDiagnosticEvent(
              traceId: id,
              flowId: id,
              attemptId: id,
              occurredAt: DateTime.now(),
              eventType: event['event'] as String? ?? 'connection_state',
              source: 'app_connection',
              operationName: event['operation_id'] as String?,
              errorCode: event['error_code'] as String?,
              sanitizedMessage: jsonEncode(safe),
            ),
          )
          .catchError((Object _) {}),
    );
  }
}
