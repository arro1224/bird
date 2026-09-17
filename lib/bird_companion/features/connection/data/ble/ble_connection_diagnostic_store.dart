import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';

/// Persists a bounded, secret-safe BLE event timeline in the existing cache.
final class BleConnectionDiagnosticStore implements BleConnectionDiagnosticSink {
  BleConnectionDiagnosticStore(
    this._cache, {
    this.maximumEvents = 500,
  });

  static const cacheKey = 'diagnostics:ble_connection_events:v1';

  final LocalCache _cache;
  final int maximumEvents;
  final StreamController<BleConnectionDiagnosticEvent> _records = StreamController.broadcast(sync: true);
  Future<void> _writeQueue = Future.value();

  Stream<BleConnectionDiagnosticEvent> get records => _records.stream;

  List<BleConnectionDiagnosticEvent> readAll({String? traceId}) {
    final stored = _cache.read<List<dynamic>>(cacheKey) ?? const [];
    final events = stored
        .whereType<Map>()
        .map(
          (value) => BleConnectionDiagnosticEvent.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .where((event) => traceId == null || event.traceId == traceId)
        .toList(growable: false);
    return events;
  }

  @override
  Future<void> record(BleConnectionDiagnosticEvent event) {
    final operation = _writeQueue.then((_) async {
      final values = <Map<String, Object?>>[
        event.toJson(),
        ...readAll().map((item) => item.toJson()),
      ];
      if (values.length > maximumEvents) {
        values.removeRange(maximumEvents, values.length);
      }
      await _cache.write(cacheKey, values);
      if (!_records.isClosed) _records.add(event);
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  String exportJson({String? traceId}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert({
        'schema_version': 1,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'trace_id': traceId,
        'events': readAll(
          traceId: traceId,
        ).reversed.map((event) => event.toJson()).toList(growable: false),
      });

  Future<void> clear() => _cache.remove(cacheKey);

  Future<void> dispose() async {
    await _writeQueue;
    await _records.close();
  }
}
