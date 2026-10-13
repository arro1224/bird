import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_critical_event_policy.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_snapshot_service.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ble_diagnostic_snapshot_test.dart' show MemoryStorage, OfflineFiles, scan;

const chain = [
  'user_start_pairing', 'bond_receiver_registered', 'create_bond_invoked', 'create_bond_returned',
  'bond_state_changed', 'system_bond_result', 'gatt_rebuild_started', 'gatt_services_discovered',
  'gatt_notification_descriptor_write', 'gatt_rebuild_completed', 'security_write_api_invoked',
  'security_write_callback_timeout', 'security_write_retry_started', 'security_write_retry_result',
  'command_failed', 'security_write_fact_finalized', 'teardown_started',
];
Map<String, Object?> row(String type, {String flow = 'flow', String request = 'request', String? note}) => {
  'flow_id': flow, 'trace_id': 'scan', 'request_id': request, 'attempt_id': '$request:1:1:1000',
  'event_type': type, 'source': 'synthetic_local_test', 'occurred_at': DateTime.utc(2026, 10, 11).toIso8601String(),
  'sanitized_message': ?note,
};
BleDiagnosticJournal journal(MemoryStorage storage, {int max = 500, int bytes = 2 * 1024 * 1024, int requests = 4}) =>
    BleDiagnosticJournal(storage, key: 'journal', legacyKeys: const [], maximumRecords: max, maximumBytes: bytes,
      pinCurrentAttempt: true, maximumProtectedRequests: requests);

void main() {
  test('more than 500 observations preserve the entire critical chain and bounded bytes after restart', () async {
    final storage = MemoryStorage();
    final j = journal(storage);
    for (final type in chain) { await j.record(row(type)); }
    for (var i = 0; i < 620; i++) { await j.record(row('observation', note: '鸟🐦 $i')); }
    final snapshot = await journal(storage).snapshot();
    expect(snapshot.records.length, 500);
    expect(snapshot.records.map((r) => r['event_type']), containsAll(chain));
    final retention = snapshot.retentionFor('flow', 500);
    expect(retention['total_observed'], chain.length + 620);
    expect(retention['critical_observed'], chain.length);
    expect(retention['critical_dropped'], 0);
    expect(retention['critical_events_missing'], false);
    expect(retention['dropped'], chain.length + 620 - 500);
    expect(snapshot.retainedBytes, lessThanOrEqualTo(snapshot.maximumBytes));
  });

  test('recent terminal requests survive traffic from a newer request and other flow', () async {
    final storage = MemoryStorage();
    final active = journal(storage, max: 60);
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final type in chain) { await active.record(row(type, request: 'req-$attempt')); }
    }
    for (var i = 0; i < 100; i++) { await active.record(row('observation', request: 'new', flow: 'other')); }
    final restored = await journal(storage, max: 60).snapshot();
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(restored.records.where((r) => r['request_id'] == 'req-$attempt').map((r) => r['event_type']), containsAll(chain));
    }
    expect(restored.retentionFor('flow', 51)['critical_events_missing'], false);
    expect((storage.values['journal'] as Map)['protected_requests'].length, 4);
  });

  test('critical capacity loss and expired request window are explicitly marked', () async {
    final storage = MemoryStorage(), j = journal(storage, max: 5, requests: 1);
    for (final type in chain) { await j.record(row(type, request: 'old')); }
    for (final type in chain.take(4)) { await j.record(row(type, request: 'new')); }
    final info = (await j.snapshot()).retentionFor('flow', 5);
    expect(info['critical_events_missing'], true);
    expect(info['critical_dropped'], greaterThan(0));
    expect(info['critical_missing_reasons'], containsAll(['critical_event_capacity', 'older_request_window']));
    expect(info['critical_observed'], (info['critical_retained'] as int) + (info['critical_dropped'] as int));
  });

  test('UTF8 byte budget includes metadata and oversized critical evidence reports loss', () async {
    final storage = MemoryStorage(), j = journal(storage, bytes: 1400);
    await j.record(row('create_bond_invoked', note: '鸟🐦' * 1000));
    final snapshot = await j.snapshot(), info = snapshot.retentionFor('flow', snapshot.records.length);
    expect(utf8.encode(jsonEncode(storage.values['journal'])).length, lessThanOrEqualTo(1400));
    expect(info['critical_events_missing'], true);
    expect(info['critical_missing_reasons'], contains('byte_capacity'));
  });

  test('failed critical persistence is visible immediately and survives subsequent success and restart', () async {
    final storage = MemoryStorage()..failNext = true;
    final active = journal(storage);
    await expectLater(active.record(row('create_bond_returned')), throwsStateError);
    expect((await active.snapshot()).retentionFor('flow', 0)['critical_missing_reasons'], contains('persistence_write_failure'));
    await active.record(row('observation'));
    final restored = (await journal(storage).snapshot()).retentionFor('flow', 1);
    expect(restored['persistence_write_failures'], 1);
    expect(restored['critical_dropped'], 1);
    expect(restored['critical_events_missing'], true);
  });

  test('old cache with unknown prior critical losses never claims intact evidence', () async {
    final storage = MemoryStorage();
    storage.values['journal'] = {'records': [row('create_bond_invoked')], 'flows': {'flow': {'total': 20, 'dropped': 19, 'history_unknown': false}}, 'next_sequence': 21};
    final active = journal(storage);
    final info = (await active.snapshot()).retentionFor('flow', 1);
    expect(info['critical_history_unknown'], true);
    expect(info['critical_events_missing'], true);
    await active.record(row('command_failed'));
    expect((await journal(storage).snapshot()).retentionFor('flow', 2)['critical_history_unknown'], true);
  });

  test('migration seeds the recent request window before a bounded snapshot trims old records', () async {
    final storage = MemoryStorage();
    final records = [for (var i = 0; i < 100; i++) row('observation', request: 'new'), ...chain.map(row)];
    storage.values['journal'] = {'records': records, 'flows': {'flow': {'total': records.length, 'dropped': 0, 'history_unknown': false}}, 'next_sequence': records.length + 1};
    final snapshot = await journal(storage, max: 20).snapshot();
    expect(snapshot.records.map((record) => record['event_type']), containsAll(chain));
    expect(snapshot.retentionFor('flow', 20)['critical_events_missing'], false);
  });

  test('native counters and failure stage round trip independently', () {
    final event = BleConnectionDiagnosticEvent.fromPlatform({
      'traceId': 'scan', 'eventType': 'security_write_fact_finalized', 'occurredAtMs': 0,
      'createBondCallCount': 1, 'commandAttemptCount': 2, 'attWriteCallCount': 17, 'writeFragmentIndex': 9,
      'preparationStep': 'notification_1', 'failurePhase': 'restoring_notifications',
    });
    final restored = BleConnectionDiagnosticEvent.fromJson(Map<String, dynamic>.from(event.toJson()));
    expect(restored.commandAttemptCount, 2); expect(restored.attWriteCallCount, 17);
    expect(restored.writeFragmentIndex, 9); expect(restored.preparationStep, 'notification_1');
    expect(restored.failurePhase, 'restoring_notifications');
  });

  test('capture exports every retained record and optionally emits marked local JSON samples', () async {
    final storage = MemoryStorage();
    final scanStore = BleScanDiagnosticStore(storage), events = BleConnectionDiagnosticStore(storage);
    await scanStore.record(scan('scan'));
    Future<void> record(String type, int second, String note) => events.record(BleConnectionDiagnosticEvent(
      traceId: 'scan', flowId: 'flow', requestId: 'synthetic-local-request', attemptId: 'synthetic-local-attempt',
      occurredAt: DateTime.utc(2026, 10, 11).add(Duration(seconds: second)), eventType: type, source: 'synthetic_local_test',
      sanitizedMessage: note, createBondCallCount: 1, commandAttemptCount: 2, attWriteCallCount: 8, writeFragmentIndex: 4,
    ));
    for (var i = 0; i < chain.length; i++) { await record(chain[i], i, '本地合成记录，非手机无线实测'); }
    final capture = BleDiagnosticSnapshotService(scanStore, events, OfflineFiles());
    final plain = await capture.capture('scan');
    for (var i = 0; i < 600; i++) { await record('observation', i + 20, '鸟🐦' * 150); }
    final large = await capture.capture('scan');
    final full = jsonDecode(large.fullJson) as Map, retention = full['retention']['connection_events'] as Map;
    expect((full['connection_events'] as List).length, 500);
    expect(retention['critical_events_missing'], false);
    expect((full['connection_events'] as List).cast<Map>().where(BleCriticalEventPolicy.isCritical).length, chain.length);
    expect(utf8.encode(large.fullJson).length, greaterThan(256 * 1024));
    final destination = Platform.environment['BLE19_SAMPLE_DIR'];
    if (destination != null) {
      for (final entry in {'plain': plain, 'zip': large}.entries) {
        final directory = Directory('$destination/${entry.key}')..createSync(recursive: true);
        File('${directory.path}/full_trace.json').writeAsStringSync(entry.value.fullJson, encoding: utf8);
        File('${directory.path}/summary.json').writeAsStringSync(entry.value.summaryJson, encoding: utf8);
      }
    }
    await scanStore.dispose(); await events.dispose();
  });
}
