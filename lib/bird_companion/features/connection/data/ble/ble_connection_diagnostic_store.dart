import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';

final class BleConnectionDiagnosticStore implements BleConnectionDiagnosticSink {
  BleConnectionDiagnosticStore(DiagnosticStorage cache, {this.maximumEvents = 500})
    : _journal = BleDiagnosticJournal(cache, key: cacheKey, legacyKeys: const [v2CacheKey, legacyCacheKey], maximumRecords: maximumEvents, pinCurrentAttempt: true);
  static const cacheKey = 'diagnostics:ble_connection_events:v4';
  static const v2CacheKey = 'diagnostics:ble_connection_events:v2';
  static const legacyCacheKey = 'diagnostics:ble_connection_events:v1';
  final int maximumEvents;
  final BleDiagnosticJournal _journal;
  final _records = StreamController<BleConnectionDiagnosticEvent>.broadcast(sync: true);
  Stream<BleConnectionDiagnosticEvent> get records => _records.stream;
  List<BleConnectionDiagnosticEvent> readAll({String? traceId}) => _journal.readAll().map(BleConnectionDiagnosticEvent.fromJson).where((e) => traceId == null || e.traceId == traceId).toList();
  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async {
    await _journal.record(event.toJson());
    if (!_records.isClosed) _records.add(event);
  }

  Future<void> flush() => _journal.flush();
  Future<BleDiagnosticJournalSnapshot> snapshot() => _journal.snapshot();
  String exportJson({String? traceId}) => jsonEncode({'schema_version': 4, 'trace_id': traceId, 'events': readAll(traceId: traceId).reversed.map((e) => e.toJson()).toList()});
  Future<void> clear() => _journal.clear();
  Future<void> dispose() async {
    await flush();
    await _records.close();
  }
}
