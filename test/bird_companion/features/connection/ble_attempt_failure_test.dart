import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_attempt_failure.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_diagnostic_journal.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ble_diagnostic_snapshot_test.dart' show MemoryStorage;
import 'fakes/fake_provisioning_repository.dart';

const rejected = ProvisioningException(code: ProvisioningErrorCode.blePairingRejected, retryable: false);
void capture(BleAttemptFailure failure, Object error, {String method = 'openPairing'}) =>
    failure.capture(error, StackTrace.fromString('#0 f (package:aves/test.dart:20:4) password=PRIVATE'), method: method, expectedState: 'bonded', currentState: 'not_bonded');
Map<String, dynamic> event(BleAttemptFailure failure, String type) => {'trace_id': 'flow', 'flow_id': 'flow', 'event_type': type, 'source': 'dart', 'occurred_at': '2026-10-20T00:00:00.000Z', 'attempt_id': 'attempt', ...failure.toJson()};
BleDiagnosticExport export(List<Map<String, dynamic>> events) => BleDiagnosticExport(traceId: 'flow', scans: const [], events: events, generatedAt: DateTime.utc(2026, 10, 20));

void main() {
  test('primary rejection survives cleanup, source diagnostics and immutable snapshots', () {
    final failure = BleAttemptFailure(attemptId: 'attempt', requestId: 'request', connectionGeneration: 3);
    capture(failure, rejected);
    final initial = failure.toJson();
    capture(failure, StateError('reset_token=PRIVATE AA:BB:CC:DD:EE:FF password=SECRET'), method: 'failSecurityWrite');
    final restored = BleConnectionDiagnosticEvent.fromJson(event(failure, 'command_failed'));
    expect(failure.exception.code, ProvisioningErrorCode.blePairingRejected);
    expect((initial['secondary_errors'] as List), isEmpty);
    final details = restored.failureDetails!;
    expect((details['first_terminal_error'] as Map)['connection_generation'], 3);
    final secondary = (details['secondary_errors'] as List).single as Map;
    expect(secondary['runtime_type'], 'StateError');
    expect(secondary['to_string'], 'StateError(<redacted>)');
    expect(secondary['stack_trace'], 'test.dart:20:4');
    expect(jsonEncode(restored.toJson()), isNot(contains('PRIVATE')));
    expect(jsonEncode(restored.toJson()), isNot(contains('AA:BB')));
    expect(UserMessageMapper.fromError(failure.exception).title, UserMessageMapper.fromError(rejected).title);
  });

  test('unknown first error is actionable and later rejection cannot silently replace it', () {
    final failure = BleAttemptFailure(attemptId: 'attempt');
    capture(failure, StateError('PRIVATE'));
    capture(failure, rejected);
    expect(failure.exception.code, ProvisioningErrorCode.bleGattOperationFailed);
    expect((failure.toJson()['first_terminal_error'] as Map)['runtime_type'], 'StateError');
    expect(UserMessageMapper.fromError(failure.exception).message, isNot(contains('StateError')));
  });

  test('cross-layer propagation retains the same cause and counts bounded secondary errors', () {
    final source = BleAttemptFailure(attemptId: 'source');
    capture(source, rejected);
    capture(source, StateError('first cleanup'));
    final repository = BleAttemptFailure(attemptId: 'repository');
    capture(repository, source.exception);
    for (var i = 0; i < 50; i++) {
      capture(repository, StateError('cleanup-$i'));
    }
    final details = repository.toJson();
    expect((details['first_terminal_error'] as Map)['attempt_id'], 'source');
    expect((details['secondary_errors'] as List).length, BleAttemptFailure.maximumSecondaryErrors);
    expect(details['secondary_error_count'], 51);
    expect(details['secondary_errors_dropped'], 35);
  });

  test('summary and full export select terminal rejection ahead of recoverable status and cleanup', () {
    final failure = BleAttemptFailure(attemptId: 'attempt');
    capture(failure, rejected);
    final first = event(failure, 'attempt_failed');
    capture(failure, StateError('PRIVATE'));
    final result = export([
      {'event_type': 'pairing_preflight_expected_disconnect', 'gatt_status': 19},
      {'event_type': 'security_write_callback_timeout', 'error_code': 'authentication_required'},
      first,
      {'event_type': 'security_cleanup_failed', 'error_code': 'invalid_state', 'cleanup_outcome': 'failed'},
      event(failure, 'command_failed'),
    ]);
    final summary = jsonDecode(result.summaryJson) as Map;
    final full = jsonDecode(result.fullJson) as Map;
    expect(summary['first_error']['error_code'], 'BLE_PAIRING_REJECTED');
    expect(full['first_terminal_error'], failure.firstTerminalError);
    expect((full['secondary_errors'] as List).single['runtime_type'], 'StateError');
    expect(summary['first_error_selection'], 'terminal_ledger');
    expect(utf8.encode(result.summaryJson).length, lessThanOrEqualTo(4096));
    expect(result.parts.map((p) => (jsonDecode(p) as Map)['payload']).join(), result.fullJson);
  });

  test('expected reset disconnect alone is never a summary error', () {
    final summary =
        jsonDecode(
              export([
                {'event_type': 'gatt_connection_state_changed', 'gatt_status': 19, 'connection_generation': 1},
                {'event_type': 'pairing_preflight_expected_disconnect', 'gatt_status': 19, 'connection_generation': 1},
                {'event_type': 'security_write_callback_timeout', 'request_id': 'succeeded'},
                {'event_type': 'command_succeeded', 'request_id': 'succeeded'},
              ]).summaryJson,
            )
            as Map;
    expect(summary['first_error'], isNull);
    final unexpected =
        jsonDecode(
              export([
                {'event_type': 'gatt_connection_state_changed', 'gatt_status': 19, 'connection_generation': 2},
              ]).summaryJson,
            )
            as Map;
    expect(unexpected['first_error']['gatt_status'], 19);
  });

  testWidgets('failure page displays the original rejection after cleanup throws StateError', (tester) async {
    final failure = BleAttemptFailure(attemptId: 'attempt');
    capture(failure, rejected);
    capture(failure, StateError('password=PRIVATE'));
    final repository = FakeProvisioningRepository(discoverError: failure.exception);
    await tester.pumpWidget(MaterialApp(home: ConnectionPage(provisioningRepository: repository)));
    await tester.pumpAndSettle();
    final message = UserMessageMapper.fromError(rejected);
    expect(find.text(message.message), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('PRIVATE'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await repository.dispose();
  });

  test('17-record pressure retains terminal snapshots and restart exports the original cause', () async {
    final storage = MemoryStorage();
    final store = BleConnectionDiagnosticStore(storage, maximumEvents: 17);
    addTearDown(store.dispose);
    final failure = BleAttemptFailure(attemptId: 'attempt');
    capture(failure, rejected);
    await store.record(BleConnectionDiagnosticEvent.fromJson(event(failure, 'attempt_failed')));
    for (var i = 0; i < 60; i++) {
      await store.record(BleConnectionDiagnosticEvent.fromJson({...event(failure, 'observation'), 'first_terminal_error': null, 'request_id': 'attempt'}));
    }
    capture(failure, StateError('cleanup'));
    await store.record(BleConnectionDiagnosticEvent.fromJson(event(failure, 'command_failed')));
    final restarted = BleConnectionDiagnosticStore(storage, maximumEvents: 17);
    addTearDown(restarted.dispose);
    final records = (await restarted.snapshot()).records.reversed.toList();
    final full = jsonDecode(export(records).fullJson) as Map;
    expect(records.length, 17);
    expect(full['first_terminal_error']['error_code'], 'BLE_PAIRING_REJECTED');
    expect((full['secondary_errors'] as List).single['runtime_type'], 'StateError');
  });

  test('release terminal events survive capacity pressure, restart and cross-attempt export', () async {
    final storage = MemoryStorage();
    final store = BleConnectionDiagnosticStore(storage, maximumEvents: 20);
    addTearDown(store.dispose);
    final types = ['controlled_release_disconnect_confirmed', 'controlled_release_disconnect_timeout', 'controlled_release_immediate', 'controlled_reconnect_already_released', 'pairing_preflight_bond_rejected'];
    for (var attempt = 0; attempt < 2; attempt++) {
      for (final type in types) {
        await store.record(
          BleConnectionDiagnosticEvent(
            traceId: 'trace-$attempt',
            flowId: 'flow',
            occurredAt: DateTime.utc(2026, 10, 21),
            eventType: type,
            source: 'android',
            attemptId: 'release-$attempt',
            connectionGeneration: attempt + 1,
            gattInstanceId: 1,
          ),
        );
      }
    }
    for (var i = 0; i < 100; i++) {
      await store.record(BleConnectionDiagnosticEvent(traceId: 'noise', flowId: 'flow', occurredAt: DateTime.utc(2026, 10, 21), eventType: 'observation', source: 'dart'));
    }
    final restarted = BleConnectionDiagnosticStore(storage, maximumEvents: 20);
    addTearDown(restarted.dispose);
    final records = (await restarted.snapshot()).records.reversed.toList();
    for (final type in types) {
      expect(records.where((e) => e['event_type'] == type), hasLength(2));
    }
    final full = jsonDecode(export(records).fullJson) as Map;
    expect((full['connection_events'] as List).where((e) => types.contains((e as Map)['event_type'])), hasLength(10));
  });

  test('complete preflight transaction exceeds 17 events and remains protected under scan noise', () async {
    final journal = BleDiagnosticJournal(MemoryStorage(), key: 'test', legacyKeys: const [], maximumRecords: 50, pinCurrentAttempt: true);
    final types = ['pairing_preflight_request', 'pairing_preflight_result', 'pairing_preflight_state', 'pairing_preflight_expected_disconnect'];
    for (var i = 0; i < 24; i++) {
      await journal.record({'flow_id': 'flow', 'trace_id': 'flow', 'event_type': types[i % types.length], 'operation_name': 'pairing_preflight', 'attempt_id': 'prepare-transaction', 'request_id': 'request-$i'});
    }
    for (var i = 0; i < 150; i++) {
      await journal.record({'flow_id': 'flow', 'event_type': 'observation'});
    }
    final snapshot = await journal.snapshot();
    expect(snapshot.records.where((r) => r['operation_name'] == 'pairing_preflight').length, 24);
    expect(snapshot.retentionFor('flow', snapshot.records.length)['critical_events_missing'], false);
  });

  test('Cubit retains secondary callbacks, ignores late success, and resets ledger on a new action', () async {
    final repository = _DiscoveryErrors();
    final cubit = ProvisioningCubit(repository);
    addTearDown(cubit.close);
    addTearDown(repository.dispose);
    await cubit.discover();
    repository.stream.addError(rejected, StackTrace.current);
    repository.stream.addError(StateError('PRIVATE'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    final error = cubit.state.error! as ProvisioningException;
    expect(error.code, ProvisioningErrorCode.blePairingRejected);
    expect((error.failureDetails!['secondary_errors'] as List), hasLength(1));
    repository.stream.add(
      ProvisioningDevice(
        scanId: 'late',
        advertisement: BirdBoxAdvertisement(localName: 'BirdBox-TEST', serviceUuids: const [], rssi: -50),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.phase, ProvisioningPhase.failure);
    await cubit.discover();
    repository.stream.addError(StateError('new operation'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect((cubit.state.error as ProvisioningException).code, ProvisioningErrorCode.bleGattOperationFailed);
    expect((cubit.state.error as ProvisioningException).failureDetails!['secondary_errors'], isEmpty);
  });
}

class _DiscoveryErrors extends FakeProvisioningRepository {
  final stream = StreamController<ProvisioningDevice>.broadcast();
  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) => stream.stream;
  @override
  Future<void> dispose() async {
    await stream.close();
    await super.dispose();
  }
}
