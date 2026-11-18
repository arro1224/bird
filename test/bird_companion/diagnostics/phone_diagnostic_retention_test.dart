import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_recorder.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_snapshot_service.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage implements DiagnosticStorage {
  final values = <String, Object?>{};
  int journalWrites = 0;
  Completer<void>? gate;
  bool failNext = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    if (key == PhoneDiagnosticRecorder.journalKey) {
      journalWrites++;
      final wait = gate;
      gate = null;
      if (wait != null) await wait.future;
      if (failNext) {
        failNext = false;
        throw StateError('storage unavailable');
      }
    }
    values[key] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _Files implements BirdBoxBleDiagnosticFilePlatform {
  @override
  Future<Map<String, dynamic>> buildIdentity() async => {'package_id': 'bird', 'build_id': 'new-build', 'version_name': '1.14.11', 'version_code': '176', 'apk_sha256': 'c' * 64};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('busy HTTP traces batch writes, retain failures after successful recovery and survive a new recorder', () async {
    final storage = _Storage();
    final recorder = PhoneDiagnosticRecorder(storage, maximumEvents: 8);
    recorder.record({'event': 'http_request_finished', 'request_id': 'failed-request', 'error_code': 'receiveTimeout', 'outcome': 'failed'});
    recorder.record({'event': 'connection_state_changed', 'next_state': 'connected'});
    for (var i = 0; i < 16; i++) {
      recorder.record({'event': 'http_request_finished', 'outcome': 'ok'});
    }
    final snapshot = await recorder.snapshot();
    expect(storage.journalWrites, 1);
    expect((snapshot['events'] as List).any((e) => e['request_id'] == 'failed-request'), true);
    expect((snapshot['events'] as List).length, lessThanOrEqualTo(8));
    expect(snapshot['retention']['truncated'], true);
    await recorder.dispose();
    final restored = PhoneDiagnosticRecorder(storage, maximumEvents: 8);
    addTearDown(restored.dispose);
    expect(((await restored.snapshot())['events'] as List).any((e) => e['error_code'] == 'receiveTimeout'), true);
  });

  test('blocked persistence does not create an unbounded queue and overflow is counted durably', () async {
    final storage = _Storage();
    final gate = Completer<void>();
    storage.gate = gate;
    final recorder = PhoneDiagnosticRecorder(storage, maximumPending: 12);
    addTearDown(recorder.dispose);
    recorder.record({'event': 'initial'});
    final writing = recorder.flush();
    for (var i = 0; i < 100; i++) {
      recorder.record({'event': 'poll'});
    }
    gate.complete();
    await writing;
    final snapshot = await recorder.snapshot();
    expect(snapshot['retention']['queue_dropped'], 88);
    expect(snapshot['retention']['truncated'], true);
    expect((snapshot['events'] as List).length, 13);
    final restored = PhoneDiagnosticRecorder(storage);
    addTearDown(restored.dispose);
    expect((await restored.snapshot())['retention']['queue_dropped'], 88);
  });

  test('journal write failure is reported and does not prevent the next export', () async {
    final storage = _Storage()..failNext = true;
    final recorder = PhoneDiagnosticRecorder(storage);
    addTearDown(recorder.dispose);
    recorder.record({'event': 'failed-before-recovery', 'error_code': 'receiveTimeout'});
    await recorder.flush();
    recorder.record({'event': 'recovery-succeeded'});
    final snapshot = await recorder.snapshot();
    expect(snapshot['retention']['persistence_write_failures'], 1);
    expect(snapshot['retention']['truncated'], true);
  });

  test('offline phone export includes history and actual exporting build without needing a box log request', () async {
    final storage = _Storage();
    final recorder = PhoneDiagnosticRecorder(storage);
    final scans = BleScanDiagnosticStore(storage), connections = BleConnectionDiagnosticStore(storage);
    addTearDown(() async {
      await recorder.dispose();
      await scans.dispose();
      await connections.dispose();
    });
    recorder.record({'event': 'http_request_finished', 'error_code': 'receiveTimeout', 'request_id': 'previous-failure'});
    recorder.record({'event': 'connection_state_changed', 'next_state': 'connected'});
    final service = BleDiagnosticSnapshotService(scans, connections, _Files(), phoneSnapshot: recorder.snapshot);
    final export = await service.capture('after-recovery', includeRetainedHistory: true, includePhone: true);
    final full = jsonDecode(export.fullJson);
    expect(full['exporting_app_build']['build_id'], 'new-build');
    expect(full['phone_diagnostics']['events'].any((e) => e['request_id'] == 'previous-failure'), true);
    expect(full['phone_diagnostics']['box_logs']['included'], false);
    expect(jsonDecode(export.summaryJson)['phone_diagnostics']['retained_events'], 2);
    expect(export.phoneEventCount, 2);
  });
}
