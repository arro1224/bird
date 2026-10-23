import 'dart:convert';
import 'package:aves/bird_companion/features/connection/data/connection_attempt_recorder.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_scan_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ble_diagnostic_snapshot_test.dart' show MemoryStorage, OfflineFiles, scan;

void main() {
  test('AP and cold restore adopt intent ids while late phase callbacks keep the newer intent current', () async {
    final storage = MemoryStorage(), events = BleConnectionDiagnosticStore(MemoryStorage());
    final recorder = ConnectionAttemptRecorder(storage, events);
    recorder.record({'event': 'ap_intent_started', 'attempt_id': 'AP'});
    expect(recorder.activeId, 'AP');
    recorder.record({'event': 'connection_intent_started', 'attempt_id': 'restore', 'intent': 'cold_restore'});
    recorder.record({
      'event': 'connection_phase_finished',
      'attempt_id': 'AP',
      'phase': 'events',
      'phase_elapsed_ms': 5100,
      'elapsed_ms': 6200,
      'outcome': 'ok',
      'saved_device_present': true,
      'has_network': true,
      'endpoint_source': 'saved',
      'final_trigger': 'verified_session',
      'http_status': 200,
      'password': 'never-save-this',
    });
    expect(recorder.activeId, 'restore');
    await events.flush();
    final output = events.exportJson();
    for (final field in ['phase_elapsed_ms', 'elapsed_ms', 'saved_device_present', 'has_network', 'endpoint_source', 'final_trigger', 'http_status']) {
      expect(output, contains(field));
    }
    expect(output, isNot(contains('never-save-this')));
    await events.dispose();
  });

  test('new scan export keeps prior failed intent and current network session evidence after restart', () async {
    final storage = MemoryStorage();
    final scans = BleScanDiagnosticStore(storage), events = BleConnectionDiagnosticStore(storage);
    final recorder = ConnectionAttemptRecorder(storage, events);
    final failed = recorder.begin('ble_connect', scanId: 'scan-before');
    recorder.record({'event': 'network_transport_error', 'attempt_id': failed, 'error_class': 'PlatformException', 'error_code': 'ble_bond_timeout'});
    await scans.record(scan('scan-before', flow: 'ble-before'));
    final current = recorder.begin('ble_connect', scanId: 'scan-after');
    await scans.record(scan('scan-after', flow: 'ble-after', second: 10));
    recorder.record({'event': 'sta_intent_started', 'attempt_id': 'sta-after', 'device_id': 'bbx-0123456789abcdef0123456789abcdef'});
    recorder.record({'event': 'authenticated_http_ws_verified', 'ws_state': 'connected', 'http_result': 'protected_read_ok'});
    await events.flush();
    expect(ConnectionAttemptRecorder(storage, events).activeId, 'sta-after');
    final export = await BleDiagnosticSnapshotService(scans, events, OfflineFiles()).capture('scan-after', includeRetainedHistory: true);
    final full = jsonDecode(export.fullJson) as Map;
    final history = (full['connection_events'] as List).cast<Map>();
    expect(history.any((row) => row['attempt_id'] == failed && row['error_code'] == 'ble_bond_timeout'), true);
    expect(history.any((row) => row['attempt_id'] == current), true);
    expect(history.any((row) => row['attempt_id'] == 'sta-after' && row['event_type'] == 'authenticated_http_ws_verified'), true);
    expect(full['raw_history_complete'], false);
    expect(full['retention']['export_scope'], 'all_locally_retained_attempts_not_unbounded_raw_history');
    await events.dispose();
  });

  test('network diagnostics use allow-list and never retain credentials, raw payload or query secrets', () async {
    final storage = MemoryStorage(), events = BleConnectionDiagnosticStore(MemoryStorage());
    final recorder = ConnectionAttemptRecorder(storage, events);
    recorder.begin('sta_configuration');
    recorder.record({
      'event': 'network_identity_check_started',
      'password': 'secret-password',
      'access_token': 'secret-token',
      'payload': {'secret': true},
      'ssid': 'private-ssid',
      'base_uri': 'http://user:secret@10.0.0.1:8080/?token=secret-query',
      'error_code': 'timeout',
    });
    await events.flush();
    final output = events.exportJson();
    for (final secret in ['secret-password', 'secret-token', 'private-ssid', 'secret-query', 'user:secret']) {
      expect(output, isNot(contains(secret)));
    }
    expect(output, contains('10.0.0.1:8080'));
    await events.dispose();
  });

  test('retention loss on old attempt remains visible when exporting from a new scan', () async {
    final storage = MemoryStorage(), scans = BleScanDiagnosticStore(MemoryStorage());
    final events = BleConnectionDiagnosticStore(storage, maximumEvents: 3);
    final recorder = ConnectionAttemptRecorder(storage, events);
    final old = recorder.begin('old');
    for (var i = 0; i < 9; ++i) {
      recorder.record({'event': 'network_transport_error', 'error_code': 'failure_$i'});
    }
    recorder.begin('new');
    await events.flush();
    final export = await BleDiagnosticSnapshotService(scans, events, OfflineFiles()).capture('new-scan', includeRetainedHistory: true);
    expect(export.retention['per_flow_retention'], contains(old));
    expect(export.truncated, true);
    await events.dispose();
  });
}
