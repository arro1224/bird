import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';

/// Keeps the latest secret-safe BLE scan sessions in the existing App cache.
final class BleScanDiagnosticStore implements BleScanDiagnosticSink {
  BleScanDiagnosticStore(
    this._cache, {
    this.maximumSessions = 100,
  });

  static const cacheKey = 'diagnostics:ble_scan_sessions:v1';

  final LocalCache _cache;
  final int maximumSessions;
  final StreamController<BleScanDiagnosticSession> _records = StreamController.broadcast(sync: true);

  Stream<BleScanDiagnosticSession> get records => _records.stream;

  List<BleScanDiagnosticSession> readAll() {
    final stored = _cache.read<List<dynamic>>(cacheKey) ?? const [];
    return stored
        .whereType<Map>()
        .map((value) => BleScanDiagnosticSession.fromJson(Map<String, dynamic>.from(value)))
        .toList(growable: false);
  }

  @override
  Future<void> record(BleScanDiagnosticSession session) async {
    final values = <Map<String, Object?>>[
      session.toJson(),
      ...readAll().map((item) => item.toJson()),
    ];
    if (values.length > maximumSessions) {
      values.removeRange(maximumSessions, values.length);
    }
    await _cache.write(cacheKey, values);
    if (!_records.isClosed) _records.add(session);
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'sessions': readAll().map((session) => session.toJson()).toList(growable: false),
  });

  Future<void> clear() => _cache.remove(cacheKey);

  Future<void> dispose() => _records.close();
}
