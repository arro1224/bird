import 'dart:convert';
import 'package:aves/bird_companion/features/connection/data/ble/ble_critical_event_policy.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> record(String flow, String type, {String? error, int? generation, String? request, Map<String, dynamic>? terminal}) => {
  'trace_id': flow,
  'flow_id': flow,
  'attempt_id': flow,
  'event_type': type,
  'error_code': ?error,
  'connection_generation': ?generation,
  'request_id': ?request,
  'first_terminal_error': ?terminal,
};
BleDiagnosticExport export(List<Map<String, dynamic>> records) => BleDiagnosticExport(traceId: 'current', scans: const [], events: records, generatedAt: DateTime.utc(2026, 10, 20));
Map<String, dynamic> root(String attempt, String code) => {'attempt_id': attempt, 'error_code': code, 'runtime_type': 'StateError', 'trigger_method': 'connect'};

void main() {
  test('old retained terminal ledger does not override the current STA root', () {
    final result = export([record('previous', 'attempt_failed', terminal: root('previous', 'old_failure')), record('current', 'network_transport_error', error: 'current_sta_failure')]);
    final summary = jsonDecode(result.summaryJson) as Map;
    expect(summary['first_error']['error_code'], 'current_sta_failure');
    expect(summary['first_error_scope'], 'requested_flow');
    expect(result.fullJson, contains('old_failure'));
  });
  test('current terminal ledger keeps latest secondary evidence while excluding old ledger', () {
    final currentRoot = root('current', 'current_failure');
    final result = export([
      record('previous', 'attempt_failed', terminal: root('previous', 'old_failure')),
      record('current', 'attempt_failed', terminal: currentRoot),
      {
        ...record('current', 'attempt_failure_finalized', terminal: currentRoot),
        'secondary_errors': [
          {'error_code': 'cleanup_failure', 'runtime_type': 'StateError', 'trigger_method': 'release'},
        ],
        'secondary_error_count': 1,
      },
    ]);
    final summary = jsonDecode(result.summaryJson) as Map;
    expect(summary['first_error']['error_code'], 'current_failure');
    expect(summary['first_error_selection'], 'terminal_ledger');
    expect(summary['secondary_errors'].single['error_code'], 'cleanup_failure');
    expect(utf8.encode(result.summaryJson).length, lessThanOrEqualTo(4096));
  });
  test('expected status19 disconnect in an old flow cannot hide a fresh failure', () {
    final result = export([
      record('previous', 'pairing_preflight_expected_disconnect', generation: 1),
      {...record('current', 'gatt_disconnected', generation: 1), 'gatt_status': 19},
    ]);
    expect((jsonDecode(result.summaryJson) as Map)['first_error']['gatt_status'], 19);
  });
  test('old successful request ID cannot suppress a current failure after restart', () {
    final result = export([record('previous', 'command_succeeded', request: 'reused-request'), record('current', 'command_failed', request: 'reused-request', error: 'new_failure')]);
    expect((jsonDecode(result.summaryJson) as Map)['first_error']['error_code'], 'new_failure');
  });
  test('merged retention protects both network handoff and pairing preflight facts', () {
    for (final type in ['sta_endpoint_ready', 'authenticated_http_ws_verified', 'pairing_preflight_expected_disconnect', 'gatt_rebuild_decision', 'attempt_failure_finalized']) {
      expect(BleCriticalEventPolicy.isCritical({'event_type': type}), true, reason: type);
    }
  });
}
