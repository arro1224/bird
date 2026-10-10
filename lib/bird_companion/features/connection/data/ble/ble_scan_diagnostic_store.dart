import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';

final class BleScanDiagnosticStore implements BleScanDiagnosticSink {
  BleScanDiagnosticStore(DiagnosticStorage cache, {this.maximumSessions = 100})
    : _journal = BleDiagnosticJournal(cache, key: cacheKey, legacyKeys: const [v3CacheKey, v2CacheKey, legacyCacheKey], maximumRecords: maximumSessions, pinCurrentAttempt: false);
  static const cacheKey = 'diagnostics:ble_scan_sessions:v4';
  static const v3CacheKey = 'diagnostics:ble_scan_sessions:v3';
  static const v2CacheKey = 'diagnostics:ble_scan_sessions:v2';
  static const legacyCacheKey = 'diagnostics:ble_scan_sessions:v1';
  final int maximumSessions;
  final BleDiagnosticJournal _journal;
  final _records = StreamController<BleScanDiagnosticSession>.broadcast(sync: true);
  Stream<BleScanDiagnosticSession> get records => _records.stream;
  List<BleScanDiagnosticSession> readAll() => _journal.readAll().map(BleScanDiagnosticSession.fromJson).toList();
  @override
  Future<void> record(BleScanDiagnosticSession event) async {
    await _journal.record(event.toJson());
    if (!_records.isClosed) _records.add(event);
  }

  Future<void> flush() => _journal.flush();
  Future<BleDiagnosticJournalSnapshot> snapshot() => _journal.snapshot();
  String exportJson() => jsonEncode({'schema_version': 4, 'sessions': readAll().map((e) => e.toJson()).toList()});
  Future<void> clear() => _journal.clear();
  Future<void> dispose() async {
    await flush();
    await _records.close();
  }
}
