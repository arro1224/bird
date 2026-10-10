import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_snapshot_service.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStorage implements DiagnosticStorage {
  final values = <String, Object?>{};
  Completer<void>? gate;
  bool failNext = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    if (gate != null) {
      final wait = gate!;
      gate = null;
      await wait.future;
    }
    if (failNext) {
      failNext = false;
      throw StateError('disk unavailable');
    }
    values[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class OfflineFiles implements BirdBoxBleDiagnosticFilePlatform {
  @override
  Future<Map<String, dynamic>> buildIdentity() async => {'package_id': 'bird', 'version_name': '1.14.11', 'version_code': '176', 'build_dirty': true, 'build_id': 'build-a', 'source_fingerprint': 'a' * 64};
  @override
  Future<BleDiagnosticFile> prepare(BleDiagnosticExport export) => throw UnimplementedError();
  @override
  Future<String> save(BleDiagnosticFile file) => throw UnimplementedError();
  @override
  Future<String> share(BleDiagnosticFile file) => throw UnimplementedError();
}

BleDiagnosticJournal journal(MemoryStorage s, {int max = 3}) => BleDiagnosticJournal(s, key: 'journal', legacyKeys: const ['legacy'], maximumRecords: max, pinCurrentAttempt: true);
Map<String, Object?> event(int i, {String flow = 'flow', String? type, String? outcome}) => {
  'flow_id': flow,
  'trace_id': 'scan',
  'attempt_id': 'attempt',
  'event_type': type ?? 'event_$i',
  'terminal_outcome': outcome,
  'occurred_at': DateTime.utc(2026, 10, 9, 0, 0, i).toIso8601String(),
};
BleScanDiagnosticSession scan(String id, {String flow = 'flow', int second = 0}) => BleScanDiagnosticSession(
  scanSessionId: id,
  flowId: flow,
  scanTrigger: second == 0 ? 'user_scan' : 'location_settings_return',
  previousScanSessionId: second == 0 ? null : 'before',
  startedAt: DateTime.utc(2026, 10, 9, 0, 0, second),
  endedAt: DateTime.utc(2026, 10, 9, 0, 0, second + 1),
  permissionBefore: BleScanPermissionState.granted,
  permissionAfter: BleScanPermissionState.granted,
  adapterBefore: BleAdapterState.enabled,
  adapterAfter: BleAdapterState.enabled,
  rawResultCount: 0,
  acceptedCount: 0,
  filteredCount: 0,
  reasonCounts: const {},
  endReason: BleScanEndReason.timeout,
);
void main() {
  test('joint queue cutoff waits for queued writes and excludes later callbacks', () async {
    final s = MemoryStorage(), j = journal(MemoryStorage());
    // A blocked first write proves snapshot waits, while the second queued later
    // must remain outside that export, even when both finish before we inspect it.
    final store = journal(s);
    final gate = Completer<void>();
    s.gate = gate;
    final first = store.record(event(0));
    final snapshot = store.snapshot();
    final later = store.record(event(1));
    var complete = false;
    unawaited(snapshot.then((_) => complete = true));
    await Future<void>.delayed(Duration.zero);
    expect(complete, isFalse);
    gate.complete();
    await first;
    expect((await snapshot).records.map((r) => r['event_type']), ['event_0']);
    await later;
    expect(store.readAll().length, 2);
    await j.flush();
  });
  test('current attempt start and terminal survive bounded middle-record trimming', () async {
    final j = journal(MemoryStorage());
    await j.record(event(0, type: 'security_write_begin'));
    await j.record(event(1, type: 'security_write_terminal', outcome: 'failed'));
    for (var i = 2; i < 8; i++) {
      await j.record(event(i));
    }
    final s = await j.snapshot();
    expect(s.records.map((r) => r['event_type']), containsAll(['security_write_begin', 'security_write_terminal', 'event_7']));
    final retention = s.retentionFor('flow', s.records.length);
    expect(retention['total_observed'], 8);
    expect(retention['dropped'], 5);
    expect(retention['truncated'], true);
    expect(s.records.map((r) => r['record_sequence']).toSet().length, 3);
  });
  test('write failure does not poison queue and survives next successful persistence', () async {
    final storage = MemoryStorage(), j = journal(MemoryStorage());
    final active = journal(storage);
    storage.failNext = true;
    await expectLater(active.record(event(0)), throwsStateError);
    await active.record(event(1));
    final restored = await journal(storage).snapshot();
    expect(restored.writeFailures, 1);
    expect(restored.retentionFor('flow', 1)['total_observed'], 2);
    expect(restored.retentionFor('flow', 1)['dropped'], 1);
    expect(restored.retentionFor('flow', 1)['truncated'], true);
    await j.flush();
  });
  test('legacy history and evicted flow counters are never advertised as complete', () async {
    final storage = MemoryStorage();
    storage.values['legacy'] = [event(0)];
    final j = journal(storage, max: 1);
    expect((await j.snapshot()).retentionFor('flow', 1)['history_unknown'], true);
    await j.clear();
    for (var i = 0; i < 130; i++) {
      await j.record(event(i, flow: 'flow_$i'));
    }
    await j.record(event(1, flow: 'flow_0'));
    expect((await j.snapshot()).retentionFor('flow_0', 1)['history_unknown'], true);
  });
  test('flow export joins both settings scans, keeps root error and excludes other flow', () async {
    final storage = MemoryStorage();
    final scans = BleScanDiagnosticStore(storage), events = BleConnectionDiagnosticStore(storage);
    final writes = [
      scans.record(scan('before')),
      scans.record(scan('after', second: 2)),
      scans.record(scan('unrelated', flow: 'other')),
      events.record(BleConnectionDiagnosticEvent(traceId: 'before', flowId: 'flow', occurredAt: DateTime.utc(2026, 10, 9), eventType: 'write_failed', source: 'native', errorCode: 'root_error')),
      events.record(BleConnectionDiagnosticEvent(traceId: 'after', flowId: 'flow', occurredAt: DateTime.utc(2026, 10, 9, 0, 0, 3), eventType: 'completed', source: 'native')),
    ];
    final export = await BleDiagnosticSnapshotService(scans, events, OfflineFiles()).capture('after');
    await Future.wait(writes);
    final full = jsonDecode(export.fullJson) as Map, summary = jsonDecode(export.summaryJson) as Map;
    expect(full['trace_id'], 'flow');
    expect((full['scan_sessions'] as List).map((r) => r['scan_session_id']), ['before', 'after']);
    expect((full['connection_events'] as List).length, 2);
    expect(summary['first_error']['error_code'], 'root_error');
    expect(summary['build'], full['build']);
    expect(full['build']['build_dirty'], true);
    expect(export.truncated, false);
    expect(full['raw_history_complete'], false);
    expect(full['retained_records_complete'], true);
    expect(scans.readAll().first.recordSequence, isNotNull);
    await scans.dispose();
    await events.dispose();
  });
  test('an old package cannot inherit the current APK build identity', () {
    final export = BleDiagnosticExport(
      traceId: 'old',
      scans: const [
        {'package_id': 'old', 'app_version_code': '175'},
      ],
      events: const [],
      generatedAt: DateTime.utc(2026),
      exporterBuild: {'package_id': 'new', 'version_code': '176', 'build_id': 'current'},
    );
    final full = jsonDecode(export.fullJson) as Map;
    expect(full['build']['build_id'], isNull);
    expect(full['exporting_app_build']['build_id'], 'current');
  });
}
